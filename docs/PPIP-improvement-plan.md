# PPIP Improvement Plan — 4 Sprints

Scope reviewed: `backend/` (FastAPI + SQLModel), `database/`, `frontend/PlacementPrep` (SwiftUI). Assumes 2-week sprints, one small team. Each item is tagged with the file(s) that show the issue today.

---

## Sprint 1: Fix what's broken or unfinished

Nothing after this sprint should be a dead code path.

- **Wire up `/api/quiz/questions`** — currently `raise NotImplementedError("Wire up the question bank data source here")` (`backend/app/content/quiz_routes.py:22`). Either implement it against the bundled JSON quiz sets or remove the endpoint if quizzes are meant to stay client-side only; right now it's a 500 waiting to happen if anything calls it.
- **Finish or remove `company_data_service.py`** — both functions are stubs that raise `NotImplementedError` (`backend/app/content/company_data_service.py:11,15`). Since company DSA data actually ships as CSVs read by the frontend, decide whether this backend service is dead code and delete it, or finish it if a server-side company API is planned.
- **Replace the ad-hoc column migration with Alembic** — `database/db.py` hand-rolls schema changes via a `_ADDED_COLUMNS` dict and raw `ALTER TABLE` calls, and only for SQLite (`_add_missing_columns` no-ops on any other `DATABASE_URL`). This will silently fail to evolve the schema on Postgres/MySQL and is fragile even on SQLite. Introduce Alembic migrations now, before the schema grows further.
- **Fix CORS configuration** — `cors_origins` defaults to `["*"]` while `allow_credentials=True` (`backend/app/core/config.py:59`, `backend/app/main.py:24`). Browsers reject wildcard-plus-credentials combinations outright, and for a production API it's an insecure default regardless. Set an explicit allow-list per environment.
- **Add rate limiting on auth endpoints.** No rate limiting exists anywhere in the backend (confirmed by search). `/api/auth/signup`, `/verify`, and login are open to brute-force and OTP-guessing. Add `slowapi` or a reverse-proxy-level limit as a baseline.
- **Audit every other stub/TODO** — do a project-wide sweep (`grep -rn "NotImplementedError\|TODO\|FIXME"`) as a first sprint task and log the rest as tickets, since this review only sampled the codebase.

### Sprint 1 status (2026-09-29, uncommitted)

| Item | Verified? | Outcome |
|---|---|---|
| `/api/quiz/questions` | Yes. Its only caller, `QuizViewModel.swift`, was used by no view; quizzes come from the bundled `QuizBank` | **Removed**: the endpoint, its schemas, the unused Python `QuizTopic`/`QuizDifficulty` enums, and the dead Swift view model and models |
| `company_data_service.py` | Yes. `/api/companies` returned 500, `backend/data/companies/` was empty, and the only caller, `CompanyDSAViewModel`, was unused | **Removed**: the service, routes and schemas, the data dir, the dead Swift view model, `DSAQuestion` and its sample data; `/api/companies` also dropped from the architecture diagram |
| Alembic | Yes | **Done**: `database/migrations/` has a baseline revision. `init_db()` runs `upgrade head`; legacy databases are brought up to the baseline and stamped. Checked on copies of both local databases with no row changes |
| CORS | Partly. Starlette 0.38.6 doesn't reject `*` + credentials; it echoes back any origin, which is worse | **Done**: no origins by default, credentials off, and startup fails on `*` + credentials |
| Rate limiting | Yes | **Done**: slowapi on login, signup, verify, resend and OAuth, keyed by `Fly-Client-IP` or user id; a 429 returns JSON `detail` + `Retry-After`, and OAuth redirects back to the app with `error=rate_limited` |
| Stub sweep | Done | Tickets S1-T1 and S1-T2 below |

Checks: backend 37/37 tests pass, `alembic check` reports no drift, and the iOS build succeeds.

### Sprints 2–4 status (2026-09-29, uncommitted)

| Item | Verified? | Outcome |
|---|---|---|
| S1-T1 fixed OTP | Yes | Default is now `""`; startup fails if a dev code is set together with `RESEND_API_KEY` |
| S1-T2 JWT default | Yes | No default; startup refuses a missing, placeholder or short (<32 character) secret; tests supply their own |
| 2.1 Backend route tests | Yes | New tests for auth/OAuth (52), quiz/DSA (20) and the interview flow (23). They surfaced 6 bugs, all fixed: login was case-sensitive on email, `PATCH /me` with a null `onboarded` returned 500, OAuth could take over an unverified account, OAuth didn't require provider-verified emails, a DSA slug could be empty or unbounded, and quiz scores had no bounds |
| 2.2 Swift test target | Yes | `PlacementPrepTests`, 75 tests. They surfaced bugs, all fixed: CSV parsing broke on CRLF and crashed on duplicate headers, and phone redaction missed Indian 5-5, `+91…` and `(555)` formats (the device and server now share one pattern and the same test samples) |
| 2.3 CI | Yes | `.github/workflows/ci.yml` runs backend tests, an Alembic drift check and, when the iOS code changes, the iOS tests |
| 2.4 LLM call handling | Yes (bugs) | Groq timeouts and 5xx now fall back to the next model, Gemini has a timeout; 17 tests |
| 2.5 Logging | Yes | `app/core/logging.py` writes one `key=value` line per record; auth events are logged with an email hash, never the raw email |
| 3.1 Pagination | Partly | `/quiz/history` and `/interview` take `limit`/`offset`, and iOS history loads more on scroll; `/quiz/progress` uses a SQL aggregate; `/dsa/solved` is deliberately left unpaginated because iOS syncs it as a set |
| 3.2 Indexes | Partly | `(user_id, slug)` already existed; migration 0002 adds `(user_id, started_at)` and `(user_id, completed_at)` |
| 3.3 Error shapes | Yes | 422 and 500 now return a string `detail` |
| 3.4 Company pipeline | Mostly documented | `fetch-company-csvs.sh` now takes company names and refuses to overwrite a bundled list; README has an "Add a new company" procedure |
| 3.5 Resume privacy | README claim false; gap real | The server now redacts emails and phone numbers itself; tests confirm nothing is persisted |
| 4.1 Offline | Yes | Offline banner; interview and resume review are disabled offline; GET requests retry with backoff |
| 4.2 Voice errors | Partly | A failed upload keeps the answer so it can be retried; call and headphone interruptions are handled |
| 4.3 Accessibility | Partly | 17 fixed font sizes addressed; VoiceOver pass; all 188 contrast pairs across 4 themes now pass WCAG |
| 4.4 App Store readiness | Yes, plus blockers found | `PrivacyInfo.xcprivacy` added; also added in-app account deletion (guideline 5.1.1(v)) and made Release builds use the Fly URL instead of localhost |
| 4.5 CSV performance | **No** | Parsing is already lazy and off the main thread; nothing to do |

Checks: backend 190/190 tests pass, `alembic check` finds no drift, iOS 75/75 tests pass.

Still open: OAuth claim doesn't revoke a pre-hijacker's existing tokens (needs a token-version column); `lower(email)` lookup has no functional index; untested on a device: audio interruptions, the upload retry flow, VoiceOver/AX5 layouts; App Store Connect privacy labels, privacy policy (name Groq and Gemini), screenshots.

### Sweep results (2026-09-29)

`git grep` for `NotImplementedError|TODO|FIXME|XXX|HACK|fatalError(` across all tracked files found only the three stubs above; no other markers. The sweep did surface these, logged as tickets:

- **S1-T1: OTP is a fixed `123456` unless overridden.** `dev_verification_code` defaults to `"123456"` (`backend/app/core/config.py`), and `_issue_verification_code` uses it whenever it is non-empty, skipping expiry and email entirely. `fly.toml` does not set `DEV_VERIFICATION_CODE`, so production is only safe if it is set to an empty string as a Fly secret — unverified. Fix: default to `""`, enable the dev code only via `.env`, and fail startup if it is set while `RESEND_API_KEY` is set.
- **S1-T2: JWT secret has a public default.** `jwt_secret_key` defaults to `"CHANGE_ME_IN_ENV"`; if the secret is ever missing in an environment, anyone can mint tokens. Fix: no default, and refuse to start with a missing or placeholder secret.

## Sprint 2: Testing and reliability

Backend tests exist (`test_company_style.py`, `test_resume_review.py`, `test_target_company.py`, ~400 lines total) but only cover three narrow areas. Frontend has no test target at all.

- **Add backend test coverage for the untested routers**: auth (signup/verify/login/OAuth), quiz submit/history/progress, DSA solved/saved tracking, and the interview session flow. Target the request/response contract, not just happy paths — expired OTPs, duplicate signups, unauthorized access.
- **Add a Swift test target** for `ViewModels/` and `Services/` (`QuizViewModel`, `CompanyDSAViewModel`, `AuthViewModel`, `NetworkManager`, `ResumeParser`, `CSVParser`). These currently have zero automated coverage; a CSV-parsing or resume-parsing regression would only surface manually.
- **Add CI** (GitHub Actions) running `python -m unittest discover` on push, plus `xcodebuild test` for the Swift target once it exists. There's no CI config in the repo today.
- **Harden the LLM call path** (`backend/app/ai/llm_service.py`): confirm timeout, retry, and fallback-chain behavior (Groq → Groq fallback models → Gemini chain) is covered by tests, since this is the code most likely to fail in ways users notice (AI mock interviews, resume review, quiz summaries all depend on it).
- **Add structured logging** around the AI and auth flows — `llm_service.py` has a `logger` but usage should be checked/extended for production debuggability (quota exhaustion, auth rejection, transcription failures).

## Sprint 3: Data layer and API cleanup

- **Add pagination to list endpoints** that will grow unbounded per user: `/api/quiz/history`, `/api/quiz/progress`, DSA solved lists, interview history. Right now these return full unfiltered result sets (`backend/app/content/quiz_routes.py`).
- **Add composite indexes** for the common query patterns (`user_id` + `quiz_id`, `user_id` + `slug`) once Alembic is in place from Sprint 1 — worth checking whether SQLModel is defining these already; if not, add them.
- **Consolidate error handling** — standardize on FastAPI exception handlers for common cases (404, 401, validation errors) instead of ad-hoc `HTTPException` calls scattered per-route, so error response shape is consistent for the client to parse.
- **Review the company CSV/logo pipeline** (`frontend/Scripts/fetch-company-csvs.sh`, `build-company-csvs.py`, `fetch-company-logos.py`) — confirm there's a repeatable, documented process for adding a new company, and consider whether this should move server-side so app updates aren't required to add a company.
- **Resume review privacy claims** — the README states PII is stripped client-side and nothing is stored server-side; add a test that asserts the resume review endpoint actually rejects/ignores email, phone, and name fields, so this privacy guarantee is enforced in code, not just documentation.

## Sprint 4: Frontend polish and offline resilience

- **Offline/poor-connectivity handling** — `NetworkManager.swift` surfaces `NetworkError` cases but it's worth confirming there's a retry/backoff strategy and a clear offline state in the UI (quizzes are bundled locally, but interview sessions, resume review, and progress sync all require connectivity). Add a visible "offline" banner state where missing today.
- **Voice input error states** — `VoiceService.swift` and the mock interview flow depend on Groq Whisper; verify there's user-facing handling for mic-permission-denied, transcription failure, and network drop mid-recording.
- **Accessibility pass** — check Dynamic Type support, VoiceOver labels on custom `PP*` design-system components and the Metal liquid-wave shader view, and color contrast in the theme picker's alternate themes.
- **App Store readiness checklist** — privacy manifest (`PrivacyInfo.xcprivacy`), App Tracking Transparency if any analytics are added later, and screenshots/metadata, if submission is planned in this window.
- **Performance pass on the DSA company lists** — with ~40 companies' CSVs bundled, confirm `CSVParser.swift` and `CompanyListView`/`CompanyQuestionsView` load and filter lazily rather than parsing everything eagerly at launch.

---

## Notes on scope and confidence

- This plan is based on a static read of the codebase (structure, README, and the files sampled above), not a running instance, load testing, or a security audit — treat sprint estimates as a starting point to adjust once your team sizes the tickets.
- The three `NotImplementedError` stubs and the CORS/rate-limiting gaps are things I found directly in the code and am confident about. The suggestions in Sprints 3–4 are judgment calls about what a placement-prep app at this stage typically needs next; re-prioritize against your actual bug reports and analytics if you have them.
