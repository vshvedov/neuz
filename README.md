# Neuz

<img width="1617" height="1203" alt="Screenshot 2026-05-22 at 12 52 52 PM" src="https://github.com/user-attachments/assets/0e825e11-a858-4679-bcbb-6d2f56eefee3" />


A self-hosted, single-user news dashboard whose content is curated by an **AI assistant of your choice** on a schedule you control. No ads. No tracking. No external telemetry. Runs as one tiny container on your laptop, a Pi, or a VPS.

Under the hood Neuz is just an authenticated ingest API (`POST /api/items`) plus a clean reader UI — it doesn't care *what* fills it. **Claude Routines** is the turnkey, scheduled curator (its prompts ship in the box); a new **[Open WebUI tool](integrations/openwebui/)** lets any tool-calling model — self-hosted (Qwen, Llama, …) or Claude — publish on demand from a chat; and you can always point your own script or cron at the API.

```
docker compose up -d
docker compose exec neuz bin/neuz setup         # prints API key + Claude prompts
docker compose exec neuz bin/neuz acknowledge   # after you've copied the key
```

That's the install: the CLI mints a single bearer API key on first boot, prints it once along with the two Claude prompts, and you `acknowledge` to delete the on-disk raw copy. From then on Claude pushes JSON news items to `POST /api/items` on whatever cadence you set.

---

## Curation options

Neuz's only ingest contract is `POST /api/items` (bearer auth, JSON below). Pick whatever curator fits — they're not mutually exclusive:

| Curator | Cadence | Best for |
|---|---|---|
| **Claude Routines / Cowork** | scheduled (cron) | hands-off, always-on curation — prompts ship with Neuz (see *How it works*) |
| **[Open WebUI tool](integrations/openwebui/)** | on-demand **or** scheduled | steer a self-hosted model (or Claude) in a chat and say "publish to Neuz" — or run the same tool unattended on a cron-like schedule via Open WebUI **Automations** |
| **Your own script** | anything | curl / cron / n8n / a routine in another tool — just POST the JSON shape below |

The rest of this README walks through the Claude Routines path (the turnkey option) and then the API contract every curator targets.

## How it works

*The Claude Routines path, step by step:*

```
┌────────────────────┐       POST /api/items
│  Claude Routines   ├───────────────────────────┐
│  / Cowork (cron)   │   Authorization: Bearer   │
└─────────▲──────────┘                           │
          │                               ┌──────▼───────┐
          │ recurring prompt              │              │
          │ (Neuz substitutes URL + key)  │  Neuz (you)  │
┌─────────┴──────────┐                    │  Roda+SQLite │
│  Claude Code       │  interview once    │              │
│  (one-time)        ├───────────────────►│              │
└────────────────────┘                    │              │
                                          │  /  /day/    │
                                          │  /month/...  │
                                          └──────────────┘
```

1. `docker compose up` boots Neuz. On first boot, it mints a single bearer API key (stored hashed; raw key cached at `data/first_boot_key.txt`, chmod 600 in a 700 dir).
2. Run `docker compose exec neuz bin/neuz setup` (or locally `bin/neuz setup`). The CLI prints the raw key and the **interview prompt** (the only prompt Neuz ships), with your URL and key already substituted.
3. Run `bin/neuz acknowledge` (or pass `--acknowledge` / `-y` to `setup`). Neuz deletes the raw-key file. From here on the raw key only exists wherever you pasted it.
4. Paste the **interview prompt** into Claude Code. Claude interviews you with `AskUserQuestion` (4-7 questions about interests, sources, cadence, tone) and then prints a complete, personalized **recurring prompt** in the chat — that's the prompt you schedule.
5. Paste the recurring prompt into Claude Routines / Cowork (schedule whatever cadence you like — hourly, daily, etc.).
6. Each run, Claude does the web research, picks items, dedupes against the trailing 14 days, and POSTs a JSON batch to `/api/items`.
7. You read at `/` (today) and `/month/YYYY-MM` (calendar) and `/day/YYYY-MM-DD` (a single day).

If you lose the key, `bin/neuz rotate` mints a new one and invalidates the old. The old Claude Routine will start returning 401 until you update the prompt with the new key.

## API

This is the universal contract — Claude Routines, the [Open WebUI tool](integrations/openwebui/), and any script you write all just POST this same shape.

`POST /api/items` — `Authorization: Bearer <key>`, JSON body:

```json
{
  "items": [
    {
      "title": "string, <=500 (required)",
      "summary": "string, <=2000 (required)",
      "source_url": "https://... (required)",
      "published_at": "2026-05-22T13:00:00Z (required, ISO8601 UTC)",
      "category": "lowercase, <=50 (optional)",
      "tags": ["short","lowercase","tags"],
      "body": "OPTIONAL Markdown",
      "image_url": "OPTIONAL https://...",
      "importance": 4,
      "external_id": "stable id (optional but recommended)"
    }
  ]
}
```

Responses:

- `200 { accepted, updated, deduped, errors: [{index, field, code, message}], total }` — partial success is fine.
- `400 { error: "invalid_batch" }` — whole body malformed.
- `401 { error: "unauthorized" }` — missing/bad bearer key.
- `413 { error: "batch_too_large", limit: 500 }` — too many items in one request.
- `429 { error: "rate_limited", retry_after_seconds: N }` — token-bucket exhausted (default 60/min, configurable).
- `503 { error: "database_busy", retry_after_seconds: 5 }` — DB locked or disk full.

`GET /healthz` returns `{ status, db, items_total, items_today, version }`. No auth.

## Routes

| Path              | Purpose                                       |
|-------------------|-----------------------------------------------|
| `GET /`           | Today's items (user-TZ via `tz` cookie)       |
| `GET /day/:date`  | Items for a specific YYYY-MM-DD               |
| `GET /month/:ym`  | Calendar grid for YYYY-MM (intensity-tinted)  |
| `POST /api/items` | Ingest endpoint (bearer auth)                 |
| `GET /healthz`    | Health JSON                                   |

There is intentionally no `/setup`, no `/admin`, no login form. Setup happens via the CLI on the host (or `docker compose exec`):

## CLI (`bin/neuz`)

| Command               | What it does                                            |
|-----------------------|---------------------------------------------------------|
| `bin/neuz setup`      | First command. Print API key + Claude prompts.          |
| `bin/neuz setup -y`   | Same, then immediately delete the raw-key file.         |
| `bin/neuz prompts`    | Reprint the Claude prompts. Reads `first_boot_key.txt` if present; else `--key KEY`, `--stdin`, or `NEUZ_KEY` env (key is verified against the stored hash). |
| `bin/neuz rotate`     | Mint a new key, invalidate the old one.                 |
| `bin/neuz acknowledge`| Delete the first-boot key file.                         |
| `bin/neuz status`     | Instance metadata (URL, version, item counts, etc).     |
| `bin/neuz migrate`    | Apply Sequel migrations (mostly auto-run by entrypoint).|

## Configuration

All env vars are optional unless noted. Defaults shown.

| Var                           | Default         | Purpose                              |
|-------------------------------|-----------------|--------------------------------------|
| `PORT`                        | `9292`          | HTTP port                            |
| `NEUZ_DATA_DIR`               | `/app/data`     | DB + first-boot key + session secret |
| `NEUZ_DB_PATH`                | `$DATA/neuz.db` | SQLite path                          |
| `NEUZ_URL`                    | (request URL)   | Used in prompt substitution          |
| `NEUZ_BRAND`                  | `Neuz`          | Brand text in header, `<title>`, footer |
| `NEUZ_TAGLINE`                | (empty)         | Optional small text after the brand  |
| `NEUZ_REPO_URL`               | `github.com/vshvedov/neuz` | URL behind the footer "GitHub" link |
| `NEUZ_VERSION`                | (built-in)      | Overrides version in /healthz        |
| `NEUZ_PRUNE_DAYS`             | `90`            | `0` to disable auto-prune            |
| `NEUZ_PRUNE_INTERVAL_SECONDS` | `3600`          | Prune scan interval                  |
| `NEUZ_RATE_CAPACITY`          | `60`            | Tokens in bucket                     |
| `NEUZ_RATE_REFILL_PER_MIN`    | `60`            | Refill rate                          |
| `NEUZ_BATCH_LIMIT`            | `500`           | Max items per ingest                 |
| `NEUZ_JOURNAL_MODE`           | `WAL`           | `WAL` or `DELETE` (NFS fallback)     |
| `NEUZ_CACHE_SIZE`             | `-20000`        | SQLite cache_size pragma (KiB neg.)  |
| `NEUZ_MMAP_SIZE`              | `67108864`      | SQLite mmap_size pragma              |
| `NEUZ_WEB_WORKERS`            | `1`             | Puma workers (keep 1 with built-in prune) |
| `NEUZ_WEB_THREADS_MAX`        | `5`             | Puma threads                         |
| `NEUZ_LOG_MAX_SIZE`           | `10m`           | Docker `json-file` `max-size` per log file (e.g. `1m`, `100k`) |
| `NEUZ_LOG_MAX_FILE`           | `3`             | How many rotated log files Docker keeps |
| `NEUZ_THEME`                  | `default`       | Color theme name; see [Theming](#theming) |

## Theming

Neuz ships 8 light/dark theme pairs: `default`, `solarized`, `gruvbox`,
`catppuccin`, `elflord`, `ayu`, `tokyo-night`, `one-dark`. Pick one with the
`NEUZ_THEME` env var (default `default`):

```yaml
# docker-compose.yml
NEUZ_THEME: tokyo-night
```

The header's light / auto / dark toggle switches modes within the active theme.

You can also drop your own `*.css` theme into the `neuz-data` volume at
`/app/data/themes/` (survives upgrades) and select it by name. See
[`themes/README.md`](themes/README.md) for the variable contract and details.

## Updating

**Update the app (one-liner):**

```sh
bin/update
```

That runs `git pull --ff-only` → `docker compose down` → `docker compose up -d --build`, prints the new container status, and probes `/healthz` for liveness. Flags: `--no-pull` (skip git), `--no-cache` (force rebuild), `--logs` (tail logs after up), `--force` (ignore a dirty working tree).

The `neuz-data` volume / `./data` dir survives. Your API key, item history, and existing Claude Routine compatibility are all preserved.

**Manually (equivalent):**

```sh
# Docker:
git pull
docker compose down                  # required because container_name is pinned
docker compose up -d --build         # rebuilds, runs migrations on boot
# (or `docker compose pull && docker compose up -d` if you pull a pre-built image)

# Bare-metal:
git pull
bundle install                       # if Gemfile.lock changed
bin/dev                              # rebuilds CSS, migrates, boots Puma
```

The `neuz-data` volume / `./data` dir survives. Your API key, item history, and Routine compatibility are preserved across updates.

**Update the Claude prompt** (e.g. you want different interests, or Neuz shipped a better template):

```sh
bin/neuz prompts                     # prints the interview + recurring prompts
# → paste the INTERVIEW prompt into Claude Code
# → walk through the AskUserQuestion sequence
# → Claude prints a fresh RECURRING prompt
# → replace the recurring prompt in your Claude Routine
```

If you've already run `bin/neuz acknowledge`, the raw-key file is gone, so pass the key explicitly:

```sh
bin/neuz prompts --key <your-key>
# or
echo "$NEUZ_KEY" | bin/neuz prompts --stdin
# or
NEUZ_KEY=<your-key> bin/neuz prompts
```

The CLI verifies the key against the stored SHA-256 before printing, so a typo refuses cleanly instead of shipping a broken prompt.

If you've lost the key entirely: `bin/neuz rotate` mints a new one (invalidates the old Routine — you'll need to update the prompt in Claude Routines with the new key, which the post-rotate prompt-reprint already gives you).

## Self-hosting checklist

- Mount `/app/data` on a **local** filesystem — SQLite WAL does not work on NFS/CIFS. Neuz logs a warning if it detects a network mount.
- If you must put data on a network share, set `NEUZ_JOURNAL_MODE=DELETE` (slower, but safe).
- Put a reverse proxy (Caddy, nginx) in front for TLS. Neuz speaks plain HTTP.
- Backups: just snapshot `/app/data/neuz.db` (plus its `-wal` / `-shm` siblings) while the container is paused.
- **Logs:** the app writes one common-log line per request plus warnings/errors to stdout/stderr. Docker captures both via its default `json-file` driver. `docker-compose.yml` caps log volume at `NEUZ_LOG_MAX_SIZE` (default `10m`) × `NEUZ_LOG_MAX_FILE` (default `3`), so the running container can hold at most ~30 MiB of rotated logs at a time. Inspect with `docker compose logs neuz` or `docker compose logs -f neuz`. No logrotate / cron config needed — Docker handles rotation.

## Local development

```sh
bundle install
bundle exec rake db:migrate
bundle exec puma -C config/puma.rb
```

CSS:

```sh
# Build CSS once (download tailwindcss standalone for your arch first)
tailwindcss -c config/tailwind.config.js -i config/tailwind.input.css -o public/app.css --minify
```

Tests:

```sh
bundle exec rake test
```

## Privacy posture

- No outbound network calls from the server. Item images are hotlinked from the source URL by your browser only.
- No third-party JS/CSS.
- Stdout logs HTTP method, path, status, ms — no IPs, no PII, no cookies.
- The only client cookie set is `tz` (your offset in minutes — used to render "today" in your local time). No session cookie, no signing key, no CSRF token — there's no login surface, so none of that is needed.
- Bearer keys are stored only as SHA-256 digests; the raw key exists on disk only between first-boot mint and `bin/neuz acknowledge`.

## License

MIT.
