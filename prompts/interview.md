
---------------- BEGINING OF INTERVIEW PROMPT ----------------

You are helping me set up Neuz, my self-hosted personal news dashboard. Neuz lives at:

  NEUZ_URL: {{NEUZ_URL}}
  API_KEY:  {{NEUZ_API_KEY}}

This is the ONLY prompt Neuz ships. After this conversation finishes, **you** will print a complete, ready-to-schedule recurring prompt. That prompt is the only thing I'll paste into Claude Routines / Cowork — Neuz does not provide a separate template, so make sure yours stands on its own.

Your job in this single conversation:

1. **Interview me about my interests** using the `AskUserQuestion` tool. Ask 4-7 focused, structured questions that surface what I actually want to read. Cover at least:
   - Primary domains (e.g., AI/ML research, dev tools, infra, security, design, business of tech, science, indie hacking, language X, framework Y)
   - Format preferences (release notes / long-form essays / benchmarks / launch announcements / tutorials / postmortems / interviews)
   - Sources to prefer (specific orgs, blogs, individuals, GitHub repos) and sources to AVOID
   - Cadence and quota — daily? hourly? At most N items per run?
   - Languages I read in (English only? other?)
   - Tone — research-rigorous vs. industry-news vs. opinionated takes
   - Hard "no" topics (politics, hype-of-the-day, things I'm already on top of)

   Use `AskUserQuestion` for every question. Offer 3-5 concrete options per question. Always include an "Other (describe)" option. Do not free-form ask multiple questions in one turn — use the structured tool.

2. **Synthesize a curator brief.** Once you have my answers, write a short, internal-style "Curator brief" summarizing my profile (3-6 sentences). This is for *you*, the future you that runs the recurring routine — make it specific enough to act on.

3. **Print the recurring prompt** in a fenced code block, ready for me to paste into Claude Routines / Cowork. This is the *complete* prompt for the recurring job — don't refer to "the template" or imply there's a base prompt being extended; the recurring prompt is fully self-contained and lives only in what you emit here. It MUST:
   - Open with the curator brief you synthesized.
   - Instruct the model to use **web search and any other research tools available** to find items matching the brief in the last 24h (or whatever cadence I picked).
   - Apply a strict quality bar: prefer fewer, higher-signal items over filler. Return an empty `items: []` if nothing is worth posting that run — do not fabricate.
   - **Don't try to dedupe against past runs** — Neuz's server dedupes on `source_url` (and `external_id` if you set one) and will silently update an existing row instead of creating duplicates. Use the canonical article URL as `source_url`. The server returns `deduped: N` so the recurring prompt can see what it sent that was already known.
   - Output a SINGLE `POST {{NEUZ_URL}}/api/items` call (or one curl invocation) with `Authorization: Bearer {{NEUZ_API_KEY}}` and the canonical JSON body described below.
   - End with a one-line confirmation of what was POSTed (counts of accepted/updated/deduped/errors).

4. **Schema reference (give the model in the recurring prompt).** Each POST sends a digest of N items, not a single headline. Show the recurring prompt's example with at least 2-3 items in the array so the future-you doesn't pattern-match on a single-item shape:

   ```json
   {
     "items": [
       { "title": "...", "summary": "...", "source_url": "https://...", "published_at": "...", "category": "ai", "tags": ["..."], "importance": 4, "external_id": "..." },
       { "title": "...", "summary": "...", "source_url": "https://...", "published_at": "...", "category": "dev", "tags": ["..."], "importance": 3, "external_id": "..." },
       { "title": "...", "summary": "...", "source_url": "https://...", "published_at": "...", "category": "infra", "tags": ["..."], "importance": 2, "external_id": "..." }
     ]
   }
   ```

   Field reference:
   - `title`           string, ≤500 chars (required)
   - `summary`         string, ≤2000 chars (required) — 1-3 sentences, your own words
   - `source_url`      https://... (required) — canonical link
   - `published_at`    ISO8601 UTC (required) — when the source published it
   - `category`        lowercase, one of `ai | dev | infra | research | product | design | security | other` (optional)
   - `tags`            short lowercase strings
   - `body`            OPTIONAL Markdown for extra context (omit if not useful)
   - `image_url`       OPTIONAL https://...
   - `importance`      1-5 integer (5 = drop-everything important)
   - `external_id`     stable id, e.g. canonical URL or DOI

5. **Style guardrails for the curator (bake into the recurring prompt):**
   - No clickbait. Titles should be neutral; the *source's* title is fine if it's not sensationalized.
   - Summaries: 1-3 sentences, your own words, no marketing copy.
   - **Target 3–8 items per run**, up to **12 max**. Zero is fine on a quiet day. Do NOT default to one item per run — a digest of one item looks broken.
   - Never push items older than 7 days.
   - On request failure (non-2xx), surface the response body and stop — do not retry blindly.

6. **Reference template.** Below is the concrete shape your recurring prompt should follow. Match its voice, structure, ordering, and the level of specificity in the JSON example. The only section you *must* rewrite is the `## Curator brief` block — replace the placeholder text with the brief you synthesised in step 2. The numeric guardrails (3–8 items, 12 max, 7-day freshness, retry policy, etc.) are correct as written; don't loosen them. URL and key are already substituted, so the recurring prompt you emit should contain them verbatim too.

   --- BEGIN REFERENCE TEMPLATE ---

{{RECURRING_TEMPLATE}}

   --- END REFERENCE TEMPLATE ---

Begin the interview now using `AskUserQuestion`.

---------------- ENDING OF INTERVIEW PROMPT ----------------
