# Alert Manager — configuration

How to set credentials and API keys for the alert manager service.

## Where to put values

Docker Compose reads variables from:

1. **Your shell** (exported before `docker compose`)
2. **A `.env` file** in the same directory as the compose file: `docker/.env`

Create `docker/.env` (it is ignored by git via root `.gitignore` patterns—do not commit real secrets):

```env
ALERTMANAGER_API_KEYS=your-long-random-key-1,your-long-random-key-2
TELEGRAM_BOT_TOKEN=123456789:AAH...
TELEGRAM_DEFAULT_CHAT_ID=123456789
PUSHOVER_APP_TOKEN=your_pushover_application_token
PUSHOVER_DEFAULT_USER_KEY=your_pushover_user_key
ALERTMANAGER_LOG_LEVEL=INFO
```

Restart after changes:

```bash
cd docker
docker compose -f docker-compose.infra-platform.yml up -d --build alertmanager
```

---

## `ALERTMANAGER_API_KEYS`

- **Purpose:** Secret(s) that callers must send so only your projects can post alerts.
- **Format:** One or more keys separated by commas (no spaces required, but trim any accidental spaces in the key strings).
- **How to generate:** For example:

  ```bash
  openssl rand -hex 32
  ```

- **How clients send it:**
  - Header `X-API-Key: <key>`, or
  - Header `Authorization: Bearer <key>`
- **If unset or empty:** Protected routes treat the API as open (see logs: a warning is emitted). Set at least one key in production.

---

## `TELEGRAM_BOT_TOKEN`

1. In Telegram, open a chat with **@BotFather**.
2. Run `/newbot` (or manage an existing bot).
3. Copy the **HTTP API token** (format like `123456789:AAH...`).

Set:

```env
TELEGRAM_BOT_TOKEN=<that token>
```

---

## `TELEGRAM_DEFAULT_CHAT_ID`

- **Purpose:** The chat where messages are delivered (your private chat with the bot, or a group).
- **Steps:**
  1. Open your bot in Telegram and press **Start** (or send any message).
  2. In a browser, open:

     `https://api.telegram.org/bot<TELEGRAM_BOT_TOKEN>/getUpdates`

  3. In the JSON, find `message.chat.id` (or `my_chat_member` / similar). That number is the chat id (groups are often negative).

Set:

```env
TELEGRAM_DEFAULT_CHAT_ID=<that id>
```

Optional: per-request override is supported in the API body as `telegram_chat_id` (see `README.md`).

---

## `PUSHOVER_APP_TOKEN`

1. Sign in at [https://pushover.net](https://pushover.net).
2. Under **Your Applications**, register an application (e.g. “Infra alerts”).
3. Copy the application’s **API Token / Application Key**.

Set:

```env
PUSHOVER_APP_TOKEN=<that token>
```

---

## `PUSHOVER_DEFAULT_USER_KEY`

1. On the Pushover dashboard, find **Your User Key** (one per account/device setup).
2. That value is the default recipient for notifications.

Set:

```env
PUSHOVER_DEFAULT_USER_KEY=<your user key>
```

Optional: per-request override is supported in the API body as `pushover_user_key` (see `README.md`).

---

## `ALERTMANAGER_LOG_LEVEL`

- **Default:** `INFO`
- **Examples:** `DEBUG`, `WARNING`, `ERROR`

---

## Verify configuration

**Health (no API key):**

```bash
curl -s http://localhost:8090/health
```

The JSON includes `configured_channels` (e.g. `telegram`, `pushover` when both are fully configured).

**Send a test alert:**

```bash
curl -s -X POST http://localhost:8090/api/v1/alerts \
  -H "Content-Type: application/json" \
  -H "X-API-Key: your-long-random-key-1" \
  -d '{"title":"Test","message":"Alert manager OK","severity":"info","source":"manual"}'
```

---

## Security notes

- Never commit `docker/.env` or real tokens to git.
- Rotate `ALERTMANAGER_API_KEYS` if a key leaks; use multiple keys to revoke one project without affecting others.
- Prefer TLS and a reverse proxy in production; do not expose `8090` publicly without authentication and network controls.

For API shapes and examples, see [README.md](README.md).
