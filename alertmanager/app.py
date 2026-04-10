import logging
import os
from typing import Any
from typing import Literal

import requests
from fastapi import FastAPI
from fastapi import Header
from fastapi import HTTPException
from pydantic import BaseModel
from pydantic import Field


logger = logging.getLogger("alertmanager")
logging.basicConfig(level=os.getenv("ALERTMANAGER_LOG_LEVEL", "INFO"))

app = FastAPI(title="Project Alert Manager", version="1.0.0")


class AlertRequest(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    message: str = Field(min_length=1, max_length=4000)
    severity: Literal["info", "warning", "error", "critical"] = "info"
    source: str = Field(default="unknown", min_length=1, max_length=120)
    tags: list[str] = Field(default_factory=list)
    channels: list[Literal["telegram", "pushover"]] = Field(default_factory=list)
    telegram_chat_id: str | None = None
    pushover_user_key: str | None = None
    metadata: dict[str, Any] = Field(default_factory=dict)


class ChannelResult(BaseModel):
    sent: bool
    detail: str


class AlertResponse(BaseModel):
    ok: bool
    results: dict[str, ChannelResult]


def _env(name: str) -> str:
    return os.getenv(name, "").strip()


def _configured_channels() -> list[str]:
    channels: list[str] = []
    if _env("TELEGRAM_BOT_TOKEN") and _env("TELEGRAM_DEFAULT_CHAT_ID"):
        channels.append("telegram")
    if _env("PUSHOVER_APP_TOKEN") and _env("PUSHOVER_DEFAULT_USER_KEY"):
        channels.append("pushover")
    return channels


def _api_keys() -> set[str]:
    raw = _env("ALERTMANAGER_API_KEYS")
    if not raw:
        return set()
    return {item.strip() for item in raw.split(",") if item.strip()}


def _authorize(x_api_key: str | None, authorization: str | None) -> None:
    keys = _api_keys()
    if not keys:
        logger.warning("ALERTMANAGER_API_KEYS is empty; API is currently open.")
        return

    token = ""
    if x_api_key:
        token = x_api_key.strip()
    elif authorization and authorization.lower().startswith("bearer "):
        token = authorization[7:].strip()

    if not token or token not in keys:
        raise HTTPException(status_code=401, detail="Unauthorized")


def _send_telegram(req: AlertRequest) -> ChannelResult:
    bot_token = _env("TELEGRAM_BOT_TOKEN")
    chat_id = (req.telegram_chat_id or _env("TELEGRAM_DEFAULT_CHAT_ID")).strip()
    if not bot_token or not chat_id:
        return ChannelResult(sent=False, detail="Telegram not configured")

    text = (
        f"[{req.severity.upper()}] {req.title}\n"
        f"Source: {req.source}\n"
        f"Message: {req.message}"
    )
    if req.tags:
        text += f"\nTags: {', '.join(req.tags)}"

    url = f"https://api.telegram.org/bot{bot_token}/sendMessage"
    payload = {
        "chat_id": chat_id,
        "text": text,
        "disable_web_page_preview": True,
    }

    try:
        response = requests.post(url, json=payload, timeout=10)
        response.raise_for_status()
    except requests.HTTPError as exc:
        detail = f"Telegram HTTP error: {exc}"
        logger.error(detail)
        return ChannelResult(sent=False, detail=detail)
    except requests.RequestException as exc:
        detail = f"Telegram request failed: {exc}"
        logger.error(detail)
        return ChannelResult(sent=False, detail=detail)

    return ChannelResult(sent=True, detail="Telegram notification sent")


def _send_pushover(req: AlertRequest) -> ChannelResult:
    app_token = _env("PUSHOVER_APP_TOKEN")
    user_key = (req.pushover_user_key or _env("PUSHOVER_DEFAULT_USER_KEY")).strip()
    if not app_token or not user_key:
        return ChannelResult(sent=False, detail="Pushover not configured")

    priority_map = {"info": 0, "warning": 0, "error": 1, "critical": 1}
    body = f"{req.message}\nSource: {req.source}"
    if req.tags:
        body += f"\nTags: {', '.join(req.tags)}"

    payload = {
        "token": app_token,
        "user": user_key,
        "title": f"[{req.severity.upper()}] {req.title}",
        "message": body,
        "priority": priority_map.get(req.severity, 0),
    }

    try:
        response = requests.post(
            "https://api.pushover.net/1/messages.json",
            data=payload,
            timeout=10,
        )
        response.raise_for_status()
    except requests.HTTPError as exc:
        detail = f"Pushover HTTP error: {exc}"
        logger.error(detail)
        return ChannelResult(sent=False, detail=detail)
    except requests.RequestException as exc:
        detail = f"Pushover request failed: {exc}"
        logger.error(detail)
        return ChannelResult(sent=False, detail=detail)

    return ChannelResult(sent=True, detail="Pushover notification sent")


@app.get("/health")
def health() -> dict[str, Any]:
    channels = _configured_channels()
    return {
        "ok": True,
        "configured_channels": channels,
        "auth_required": bool(_api_keys()),
    }


@app.get("/api/v1/channels")
def channels(
    x_api_key: str | None = Header(default=None),
    authorization: str | None = Header(default=None),
) -> dict[str, Any]:
    _authorize(x_api_key=x_api_key, authorization=authorization)
    return {"configured_channels": _configured_channels()}


@app.post("/api/v1/alerts", response_model=AlertResponse)
def send_alert(
    req: AlertRequest,
    x_api_key: str | None = Header(default=None),
    authorization: str | None = Header(default=None),
) -> AlertResponse:
    _authorize(x_api_key=x_api_key, authorization=authorization)

    configured = set(_configured_channels())
    requested = set(req.channels) if req.channels else configured
    if not requested:
        raise HTTPException(
            status_code=400,
            detail="No delivery channel configured. Configure Telegram and/or Pushover.",
        )

    results: dict[str, ChannelResult] = {}

    if "telegram" in requested:
        results["telegram"] = _send_telegram(req)
    if "pushover" in requested:
        results["pushover"] = _send_pushover(req)

    unknown = requested - {"telegram", "pushover"}
    if unknown:
        for ch in sorted(unknown):
            results[ch] = ChannelResult(sent=False, detail="Unsupported channel")

    ok = any(item.sent for item in results.values())
    return AlertResponse(ok=ok, results=results)
