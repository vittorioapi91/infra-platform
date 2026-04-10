# Alert Manager API

Small notification manager service used by other projects to push events to phone channels.

**Setup and credentials:** see [CONFIGURATION.md](CONFIGURATION.md).

## Channels

- Telegram bot
- Pushover notifications

## Endpoints

- `GET /health` - service health + configured channels
- `GET /api/v1/channels` - configured delivery channels (auth required)
- `POST /api/v1/alerts` - send one alert to one/multiple channels (auth required)

## Authentication

Set `ALERTMANAGER_API_KEYS` to one or more comma-separated keys.

Client can authenticate with either:

- `X-API-Key: <key>`
- `Authorization: Bearer <key>`

## Environment Variables

- `ALERTMANAGER_API_KEYS` (required for protected API)
- `TELEGRAM_BOT_TOKEN`
- `TELEGRAM_DEFAULT_CHAT_ID`
- `PUSHOVER_APP_TOKEN`
- `PUSHOVER_DEFAULT_USER_KEY`
- `ALERTMANAGER_LOG_LEVEL` (default `INFO`)

## Request Example

```bash
curl -X POST "http://localhost:8090/api/v1/alerts" \
  -H "Content-Type: application/json" \
  -H "X-API-Key: change-me" \
  -d '{
    "title": "Pipeline failed",
    "message": "Trading pipeline nightly run failed.",
    "severity": "critical",
    "source": "trading-agent",
    "tags": ["airflow", "nightly"],
    "channels": ["telegram", "pushover"]
  }'
```

## Response Example

```json
{
  "ok": true,
  "results": {
    "telegram": {"sent": true, "detail": "Telegram notification sent"},
    "pushover": {"sent": true, "detail": "Pushover notification sent"}
  }
}
```
