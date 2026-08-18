# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

"AI 공감 다이어리" (AI Empathy Diary) — a shared, one-line-a-day emotion diary. A member logs in, writes one line about their day, and gets an AI-generated emotion tag + empathetic Korean response. All logged-in members see each other's entries in a shared feed (not a private diary).

Live site: https://emotion-diary-horimi.vercel.app/
GitHub: https://github.com/horimi71/emotion_diary

## Architecture

Two deployed pieces, no build step:

- **`index.html`** — the entire frontend. Single static file: inline `<style>`, a local rule-based Korean emotion engine, and app logic, all in plain ES5-style JS (`var`, function expressions — no bundler, no framework). Hosted on **Vercel** as a static file.
- **`api/analyze.js`** — one Vercel serverless function (CommonJS, `module.exports = async function handler(req, res)`). Proxies emotion analysis to OpenRouter so the API key never reaches the browser.
- **Supabase** (project ref `vlfcssavypbwrtrjhxln`) — Postgres + Auth + Storage + Realtime. All data access from the browser goes through `@supabase/supabase-js` (loaded via CDN `<script>` tag) using the public anon key, gated by Row Level Security policies (see `supabase-setup.sql`).

There is no local dev server and no `npm install` — edit `index.html` / `api/analyze.js` directly and redeploy.

### Why a single HTML file + one API route

The app must be viewable by non-technical members with zero setup, so everything client-side lives in `index.html`. The one exception is `api/analyze.js`: it exists only because the OpenRouter API key can't be embedded in client JS (it's a real secret, unlike the Supabase anon key which is meant to be public and is protected by RLS instead).

## Auth model

Passwordless was tried and abandoned. Current scheme: **phone number + shared fixed password for all members**.

- The login field collects a **phone number** (digits only, e.g. `01012345678`), not an email — this app's members think in phone numbers, not emails. Supabase Auth is still email-based under the hood, so the client builds a synthetic address `<digits>@phone.emotiondiary.local` (`phoneToAuthEmail` in `index.html`) and signs in/up with that + the fixed password `260821` (same password for everyone — this is a private/trusted-group app, not a security boundary).
- Client tries `signInWithPassword` first; on failure, falls back to `signUp` (auto-registers new members). See the `email-form` submit handler in `index.html`.
- `phoneFromUser(user)` strips the `@phone.emotiondiary.local` suffix back off `user.email` to get the displayable/storable phone number — used for the user-bar label and the `user_phone` column on insert.
- Supabase project setting **Confirm email must be OFF** (Authentication → Providers → Email) or new signups won't get a session back.
- `sb.auth.onAuthStateChange` can fire more than once per real sign-in (`INITIAL_SESSION`, `SIGNED_IN`, etc.). `loadedForUserId` guards `loadEntries()`/`subscribeRealtime()` from double-running — **don't remove this guard**, it previously caused the per-photo view counter to burn through its budget twice as fast.
- If a logged-in user's `auth.users` row gets deleted (e.g. manual cleanup) while their browser still holds a valid session, inserts fail with a Postgres FK violation (`23503`). The submit handler catches this, force-signs-out, and shows a friendly message instead of the raw Postgres error.
- Accounts created before this change used real email addresses as the Supabase identity; those rows still display fine (their `user_phone` value is just an email string, cosmetically odd but harmless) but that person can no longer sign back into the *same* auth identity via the phone field — they'll end up as a new account if they log in again with a phone number.

### Admin account

- `01095306933` is the hardcoded admin phone number (`ADMIN_PHONE_EMAIL` in `index.html`, matched against `currentUser.email`). Logging in as this number shows "(관리자)" next to the phone in the user bar and adds 수정/삭제 (edit/delete) buttons to **every** diary entry, not just the admin's own.
- Enforced at the DB layer too, not just hidden UI: `admin_update_entries` / `admin_delete_entries` / `admin_update_photos` / `admin_delete_photos` RLS policies on `diary_entries` and `diary_photos` check `auth.jwt() ->> 'email' = '01095306933@phone.emotiondiary.local'`. Without these, admin update/delete calls would silently no-op under RLS (there was previously no update/delete policy at all — only select-all and insert-own).
- Edit uses a plain `prompt()`, delete uses `confirm()` — matches the app's existing minimal-UI conventions (alerts elsewhere for photo actions), not a design choice to revisit lightly.

## Database (see `supabase-setup.sql` — apply via Supabase SQL Editor or the Supabase MCP)

- `diary_entries` — one row per diary entry (`text`, `emotion`, `intensity`, `emoji`, `message`, `user_id`, `user_phone` denormalized for display/filtering — holds the phone number since the auth-model change, previously named `user_email`, `created_at`). RLS: any authenticated member can `select` all rows; `insert` only your own; `update`/`delete` restricted to the admin account (see above).
- `diary_photos` — photos belong to an entry (`entry_id` FK), uploaded to the `diary-photos` Storage bucket, with `url` (full-size) and `thumb_url` (small list-view thumbnail) both stored per photo. Legacy entries from before this table existed may still carry a `photo_urls text[]` array column — `index.html` falls back to rendering those as plain images (`photo.id === null`) without the like/download/thumbnail features.
- `photo_reactions` — per-(photo, user) like/dislike toggle, shown both under each thumbnail (compact) and under the expanded full-size photo.
- `photo_views`, `photo_downloads` tables still exist in the schema but are **no longer used** — the view-count limit and the one-download-per-photo limit were both removed; downloads are now unlimited and views aren't tracked (the thumbnail-first UI made per-view bandwidth limiting unnecessary).
- Daily upload cap: **5 photos per account per day** total, checked client-side by counting today's `diary_photos` rows for that user before upload (not DB-enforced). A "*주의사항*" (notice) button below the entry form surfaces this as a tooltip (click-to-toggle, since hover doesn't work on mobile).
- Two image variants are generated client-side before upload (canvas, JPEG): a **Full HD (1920×1080)** cap for the full-size image (quality 0.85) and a **320×320** thumbnail (quality 0.6) used in the list view's 5-per-row thumbnail grid. Tapping a thumbnail loads/shows the full-size image inline, fit to width. (Was QHD 2560×1440 before — lowered to Full HD.)

## Emotion analysis

Two layers, in order:

1. **Local crisis check** (`analyzeEmotion` in `index.html`) — keyword match for self-harm/suicide language. If matched, the API is skipped entirely and a hotline message (1393 / 1577-0199) is shown immediately. This is deliberate: don't send self-harm text to a third-party model, and don't depend on it being up for the safety-critical path.
2. **OpenRouter** (`api/analyze.js`, model `openai/gpt-oss-20b:free`) for everything else — returns `{emotion, intensity, message}` as JSON. If the call fails, times out, or returns something unparseable, the client transparently falls back to the local rule-based engine (`analyzeEmotion` + `generateEmpathyResponse`) so the app still works with OpenRouter down/rate-limited.

`openai/gpt-oss-20b:free` is a reasoning model — it spends completion tokens on an internal reasoning trace before the actual answer. This requires `max_tokens: 800` and `response_format: {type: 'json_object'}` in the OpenRouter request; without both, `choices[0].message.content` comes back empty even though the request "succeeds." If you swap models, re-check whether this still applies.

## Environment variables

- `OPENROUTER_API_KEY` — required by `api/analyze.js`. Set in **Vercel → Project Settings → Environment Variables** (Production, and Preview if you deploy previews). A local `.env` also exists for running quick `curl` tests against OpenRouter directly — it is gitignored and Vercel does not read it.
- The Supabase URL and anon key are hardcoded in `index.html` (`SUPABASE_URL`, `SUPABASE_ANON_KEY`) — this is intentional and safe; the anon key is public-by-design and RLS is the real access control.

## Deployment

No CI — deploys are manual:

1. `git add`/`commit`/`push` to `master` (GitHub is the source of truth / backup, and is git-linked to the Vercel project).
2. Push does *not* reliably trigger a fresh Vercel production deploy on its own (observed to sometimes lag or not fire). To guarantee the live site matches `master`, redeploy explicitly with the Vercel MCP `deploy_to_vercel` tool (`target: "production"`, project name `emotion-diary`), passing the current contents of `index.html` and `api/analyze.js`.
3. Vercel Authentication (team SSO gate) was on by default for this project and blocked all non-team visitors on the `*.vercel.app` URL — it's been turned off (`update_project_deployment_protection`, `ssoProtection.enabled: false`). If the site starts 401/redirecting for outside users, check this setting first.

Supabase schema changes: apply directly via the Supabase MCP (`apply_migration` / `execute_sql`) or paste `supabase-setup.sql` into the Supabase SQL Editor — keep that file in sync with whatever you actually ran.

## Testing

No automated test suite. Verify changes by driving the live Vercel URL with the browser tool (or a local file:// open of `index.html` for logic that doesn't need the API route) — log in with a throwaway phone number (e.g. `0100000099`) and password `260821`, exercise the flow, then delete the throwaway `auth.users` row (`email = '<digits>@phone.emotiondiary.local'`) and any rows it created via the Supabase MCP so test data doesn't pollute the real members' shared feed. Never delete the `01095306933` admin account.

## History / abandoned approaches (don't redo these)

- **Email magic-link / OTP auth** — abandoned. Supabase's default mailer is capped at a handful of emails/hour, and once a custom SMTP (Resend) was wired up, Resend's sandbox mode refused to send to anyone but the Resend account owner without a verified sending domain. Replaced with the shared fixed-password scheme above.
- **GitHub Pages hosting** — the app was briefly hosted on GitHub Pages before moving to Vercel (for the serverless function). GitHub Pages is no longer used for serving the app; GitHub remains only as the git remote.
- Subagent role docs live in `.claude/agents/` (`product-planner`, `frontend-developer`, `backend-developer`, `qa-engineer`, `ai-integration-expert`) from early planning — informative context on intended roles, not wired into any tooling.
