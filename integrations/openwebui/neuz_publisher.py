"""
title: Neuz Publisher
author: vshvedov
author_url: https://github.com/vshvedov/neuz
funding_url: https://github.com/vshvedov/neuz
version: 0.1.0
license: MIT
description: Publish curated news items from a chat to a Neuz dashboard (POST /api/items). Lets a self-hosted model (or Claude via Open WebUI) push the news blob it just generated, the same way Claude Routines do.
required_open_webui_version: 0.5.0
"""

# How it works:
#   The LLM generates news items in this chat, then CALLS this tool to publish
#   them. The tool — not the model — performs the authenticated POST to
#   <neuz_url>/api/items. The API key lives in the tool's Valves (admin
#   settings) and is never shown to the model.
#
# Neuz's contract (see lib/neuz/validators.rb): the body is {"items": [...]}.
# Required per item: title, summary, source_url, published_at. Dedupe is on
# source_url (and external_id if set) — re-posting the same URL updates the
# existing row instead of duplicating, and the response reports how many were
# accepted / updated / deduped.

import json
import requests
from pydantic import BaseModel, Field

# Mirrors lib/neuz/validators.rb so we can fail fast (and cheaply) before the
# round-trip, and so the error messages match what the model can fix.
REQUIRED = ("title", "summary", "source_url", "published_at")
MAX_LEN = {
    "title": 500,
    "summary": 2000,
    "body": 50_000,
    "category": 50,
    "external_id": 200,
    "image_url": 2000,
    "source_url": 2000,
}
CATEGORIES = {
    "ai", "dev", "infra", "research", "product", "design", "security", "other",
}


class Tools:
    class Valves(BaseModel):
        neuz_url: str = Field(
            default="https://1hr.pw",
            description="Base URL of your Neuz instance (NO trailing /api). e.g. https://1hr.pw",
        )
        api_key: str = Field(
            default="",
            description="Neuz bearer API key from `bin/neuz setup`. Stored here only; never sent to the model.",
        )
        timeout_seconds: int = Field(
            default=20, description="HTTP timeout for the POST to Neuz."
        )

    def __init__(self):
        self.valves = self.Valves()
        # Don't auto-attach citations; this tool returns its own status string.
        self.citation = False

    def publish_news(self, items: list) -> str:
        """
        Publish one or more curated news items to the user's Neuz dashboard.
        Only call this when the user explicitly asks to publish / post / push
        the news. Do NOT invent sources — every item needs a real source_url.

        Each object in `items` has these fields:
          - title        (string, REQUIRED, <=500 chars)
          - summary      (string, REQUIRED, <=2000 chars) 1-3 sentences, your own words, no clickbait
          - source_url   (string, REQUIRED) canonical http(s) article URL
          - published_at (string, REQUIRED) ISO8601 UTC, e.g. "2026-05-29T14:00:00Z"
          - category     (string, optional) one of: ai, dev, infra, research, product, design, security, other
          - tags         (array of short lowercase strings, optional)
          - importance   (integer 1-5, optional; 5 = drop-everything important)
          - body         (string, optional, <=50000) extra Markdown context
          - image_url    (string, optional) http(s) image URL
          - external_id  (string, optional) stable id; defaults to source_url for dedupe

        :param items: list of news item objects as described above.
        :return: a human-readable summary (accepted / updated / unchanged), or a clear error to fix and retry.
        """
        if not self.valves.api_key:
            return (
                "Not published: the Neuz API key isn't configured. "
                "An admin must set `api_key` in this tool's Valves."
            )

        # Be forgiving about what the model hands us: a JSON string, a single
        # item dict, or {"items": [...]} all get normalized to a list.
        if isinstance(items, str):
            try:
                items = json.loads(items)
            except json.JSONDecodeError as e:
                return f"Not published: `items` was a string but not valid JSON ({e})."
        if isinstance(items, dict):
            items = items.get("items", [items]) if "items" in items else [items]
        if not isinstance(items, list) or not items:
            return "Not published: `items` must be a non-empty list of news item objects."

        # Client-side validation mirroring Neuz, so the model gets fast feedback.
        problems = []
        for i, it in enumerate(items):
            if not isinstance(it, dict):
                problems.append(f"item {i}: not an object")
                continue
            for k in REQUIRED:
                if not str(it.get(k, "")).strip():
                    problems.append(f"item {i}: missing required field `{k}`")
            for k, limit in MAX_LEN.items():
                v = it.get(k)
                if isinstance(v, str) and len(v) > limit:
                    problems.append(f"item {i}: `{k}` exceeds {limit} chars")
            cat = it.get("category")
            if cat and str(cat).lower() not in CATEGORIES:
                problems.append(
                    f"item {i}: category `{cat}` not in {sorted(CATEGORIES)}"
                )
            imp = it.get("importance")
            if imp is not None and not (isinstance(imp, int) and 1 <= imp <= 5):
                problems.append(f"item {i}: importance must be an integer 1-5")
        if problems:
            return "Not published — fix these and call again:\n- " + "\n- ".join(problems)

        base = self.valves.neuz_url.rstrip("/")
        url = f"{base}/api/items"
        try:
            resp = requests.post(
                url,
                json={"items": items},
                headers={
                    "Authorization": f"Bearer {self.valves.api_key}",
                    "Content-Type": "application/json",
                },
                timeout=self.valves.timeout_seconds,
            )
        except requests.RequestException as e:
            return f"Not published: could not reach Neuz at {url} ({e})."

        if resp.status_code == 401:
            return "Not published: Neuz rejected the API key (401). Check the `api_key` Valve."
        if resp.status_code == 429:
            return (
                "Not published: rate limited by Neuz (429). "
                f"Retry after {resp.headers.get('Retry-After', '?')}s."
            )
        if resp.status_code == 413:
            return "Not published: batch too large (413). Send fewer items (Neuz default limit is 500)."
        if resp.status_code >= 400:
            return f"Not published: Neuz returned {resp.status_code}: {resp.text[:500]}"

        try:
            s = resp.json()
        except ValueError:
            return f"Sent, but Neuz's response wasn't JSON: {resp.text[:300]}"

        msg = (
            f"Published to Neuz ({base}): "
            f"{s.get('accepted', 0)} new, {s.get('updated', 0)} updated, "
            f"{s.get('deduped', 0)} unchanged — of {s.get('total', len(items))} sent."
        )
        if s.get("errors"):
            shown = s["errors"][:10]
            msg += "\nRejected items:\n- " + "\n- ".join(
                f"item {e.get('index', '?')}: {e.get('field', '')} {e.get('code', '')}"
                f" — {e.get('message', '')}"
                for e in shown
            )
            if len(s["errors"]) > len(shown):
                msg += f"\n(+{len(s['errors']) - len(shown)} more)"
        return msg
