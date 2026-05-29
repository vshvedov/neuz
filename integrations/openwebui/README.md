# Neuz Publisher — Open WebUI tool

A one-file [Open WebUI](https://github.com/open-webui/open-webui) **tool** that lets a
chat model publish the news items it just generated straight into your Neuz
dashboard — the same `POST /api/items` path Claude Routines use. Trigger it
**on demand** from a conversation, or run it **unattended on a schedule** via
Open WebUI **Automations** (an RRULE-based scheduler that runs a model with its
attached tools) — a self-hosted parallel to Claude Routines. Works with any
backend model that supports tool calling (self-hosted Qwen/Llama via Ollama, or
Claude via an API connection).

## Install

**Option A — load by URL (admin):** Workspace → Tools → ➕ → *Import from URL*,
and paste the GitHub URL of the tool file:

```
https://github.com/vshvedov/neuz/blob/main/integrations/openwebui/neuz_publisher.py
```

Open WebUI converts the GitHub URL to raw automatically.

**Option B — paste:** open [`neuz_publisher.py`](./neuz_publisher.py), copy its
contents, and paste into Workspace → Tools → ➕ → *new tool* → Save.

## Configure (Valves)

After importing, open the tool's **Valves** (gear icon) and set:

| Valve | Value |
|---|---|
| `neuz_url` | Base URL of your Neuz instance, no `/api` (e.g. `https://1hr.pw`) |
| `api_key` | Your Neuz bearer key from `bin/neuz setup` |

The key is stored in Open WebUI and **never shown to the model** — the tool does
the authenticated POST server-side.

## Use

1. Enable the tool for a model (Workspace → Models → your model → Tools), or
   toggle it on per-chat with the 🔧 control.
2. Ask the model to curate news, then say **"publish these to Neuz."** The model
   calls `publish_news` with the items; the tool POSTs the batch and reports back
   how many were `accepted` / `updated` / `unchanged` (Neuz dedupes on
   `source_url`).
3. **To run it on a schedule** (hands-off, like a Claude Routine): create an Open
   WebUI **Automation** (Workspace → Automations) with a recurring rule and a
   prompt like *"Research today's AI news and publish it to Neuz."* The
   automation runs the model with this tool attached on your cadence.

For reliable tool calls, set the model's function-calling mode to **Native**
(Workspace → Models → Advanced Params) and use a capable model — small models
are unreliable at multi-item tool calls.

## Item schema

The model fills these per item (mirrors `lib/neuz/validators.rb`):

- **required:** `title`, `summary`, `source_url`, `published_at` (ISO8601 UTC)
- **optional:** `category` (`ai｜dev｜infra｜research｜product｜design｜security｜other`),
  `tags` (string array), `importance` (1–5), `body` (Markdown), `image_url`,
  `external_id`

## Security

The tool only ever POSTs to the single configured `neuz_url` with the configured
key — the model cannot choose arbitrary endpoints or see the key. Keep your Open
WebUI / Ollama on a trusted network (the Ollama API has no auth).
