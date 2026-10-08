# PPIP: Placement Preparation Intelligence Platform

[![CI](https://github.com/mohitsamant14/PPIP/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/mohitsamant14/PPIP/actions/workflows/ci.yml)

**PlacementPrep** is an iOS, iPadOS and Mac Catalyst app for campus placement preparation, backed by a FastAPI service. It combines:

- **Topic-wise quizzes**: aptitude, core CS, DSA and role-specific question sets, with an AI-written summary of how you did.
- **Company DSA question banks** for about 40 companies (Google, Amazon, Microsoft, Flipkart, Zomato, Goldman Sachs and others), with solved and saved tracking.
- **AI mock interviews** you can answer by voice. Rounds adapt their difficulty to your answers and end with written feedback.
- **Progress and motivation**: XP levels, daily streaks, a dashboard, and app icons you unlock as you level up.

## Demo

[![Watch the demo video](docs/media/demo-poster.jpg)](docs/media/demo.mp4)

<p align="center">
  <img src="docs/media/01-home.png" alt="Home screen" width="30%">
  &nbsp;
  <img src="docs/media/08-transcript.png" alt="Mock interview feedback" width="30%">
  &nbsp;
  <img src="docs/media/12-resume.png" alt="Resume review score" width="30%">
</p>

## Features

### Quizzes
Bundled JSON quiz sets live in `frontend/PlacementPrep/Resources/Quizzes/`:

| Track | Sets |
| --- | --- |
| Aptitude | Quantitative, logical, verbal |
| Core CS | Operating systems, DBMS, computer networks, system design, general CS |
| DSA | Data structures, algorithms, mixed |
| Roles | Backend/web, frontend, mobile, data/ML, DevOps/cloud, cyber security, embedded, Java/Spring, Python, QA |

Results are stored per user. The backend can also generate an AI summary of a finished quiz.

### Company DSA lists
Per-company CSVs (`Resources/Companies/`) and logos (`Resources/Logos/`) ship with the app. You can search, filter, mark questions solved (synced to the backend) and save questions for later.

### AI mock interviews
- **Six round types**: HR, tech stack, core CS, projects, panel debate, and DSA approach.
- **Adaptive difficulty**: each round opens with calibration questions, then moves up or down a five-level ladder based on how accurate and how fluent your answers are. A round runs for 10 to 50 questions.
- **Company-style rounds**: pick a company (defaults to your target company) and the rounds imitate its interviews. HR questions are aimed at its published values (Amazon's Leadership Principles, for example), DSA draws from its most-asked problems, and the other rounds are pitched at its bar. The feedback judges you against the same values. Company values and interview expectations live in `backend/app/content/data/expected_qualities.json`.
- **Resume-aware**: you can attach a resume (PDF or text) during onboarding. The app extracts the text, and the backend summarizes your projects so questions can be tailored to them.
- **Voice input**: hold to talk. Groq Whisper (`whisper-large-v3-turbo`) transcribes the audio.
- **Feedback and history**: each round ends with a rating, a five-part rubric (correctness, depth, structure, communication, confidence) for the round and for every answer, a chart of your scores across the round, and suggestions. You can reopen past sessions with full transcripts, each answer marked with its score.

### Resume review
- Upload a resume (PDF or image) and get a score out of 100 for your target role, built from five weighted factors: role fit, impact, technical depth, clarity, and format & ATS.
- Screening checks run in code: whether applicant-tracking software can read the file, contact details, length, section headings, numbers in bullets, action verbs and first-person pronouns.
- Improvements are prioritised, and up to three of your weakest bullets are rewritten. A rewrite must quote your resume exactly, and any number it needs is left as a `[placeholder]` for you to fill in.
- The file is read on the device. Email, phone, links and (best effort) your name are removed before the text is sent, the endpoint stores nothing, and review history stays on the phone.

### Progress and personalization
- **XP levels**: Fresher → Shortlisted → Screened → Interviewing → Final Round → Placed. Each level unlocks an alternate app icon.
- Daily streaks and a dashboard.
- **Focus mode**: keeps the screen awake while you practise.
- A theme picker and a custom design system (`PP*` components, including a Metal liquid-wave shader).

### Accounts
Email sign-up with OTP verification (sent through Resend), plus Google and GitHub OAuth. Auth uses JWT bearer tokens, and the app keeps them in the Keychain.

## Tech stack

| Layer | What it uses |
| --- | --- |
| App | SwiftUI (iOS 17+, iPadOS, Mac Catalyst), Observation, Metal. No third-party dependencies. The Xcode project is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen). |
| API | Python 3.10+, FastAPI, Uvicorn, Pydantic Settings |
| Data | SQLModel on SQLite by default (any SQLAlchemy URL works via `DATABASE_URL`) |
| Auth | PyJWT, passlib/bcrypt, Resend (email OTP), Google and GitHub OAuth |
| AI | Groq (default `openai/gpt-oss-120b`, with fallbacks) and/or Google Gemini (`gemini-flash-latest`, with fallbacks); Groq Whisper for speech-to-text |
| Deploy | Docker + Fly.io (`bom` region, persistent volume for SQLite) |

## Repository layout

| Path | What it is |
| --- | --- |
| `frontend/` | SwiftUI app. Source is in `PlacementPrep/` (App, DesignSystem, Models, Services, ViewModels, Views, Resources); `project.yml` is the XcodeGen spec; `Scripts/` holds content and packaging tools. |
| `backend/app/` | FastAPI service: `auth/` (JWT, OTP, OAuth), `ai/` (interview rounds, difficulty, prompts, LLM calls), `content/` (quiz and DSA routes, company interview expectations), `core/config.py` (settings). |
| `backend/scripts/` | Maintenance scripts (`wipe_database.py`). |
| `database/` | SQLModel table models (`user`, `quiz`, `dsa`, `interview`), the engine/session, and Alembic migrations (`alembic.ini`, `migrations/`), shared with the backend. |
| `Dockerfile`, `fly.toml` | Container image and Fly.io config for the backend. |
| `.github/workflows/ci.yml` | CI: on every push to `main` and every pull request, runs the backend tests and the models-vs-migrations check, plus the iOS tests when `frontend/` changes. |

## Running the backend

Requires Python 3.10+. Run these from `backend/`:

```bash
cd backend
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
# Set JWT_SECRET_KEY in .env to the output of:
python -c "import secrets; print(secrets.token_urlsafe(48))"
uvicorn app.main:app --reload --port 8000
```

- Interactive API docs: http://localhost:8000/docs
- Health check: http://localhost:8000/health
- Startup applies any pending database migrations automatically (see below).
- Tests: `PYTHONPATH=..:. python -m unittest discover -s tests -t .` (`-t .` makes `tests/__init__.py` run, which supplies a test-only `JWT_SECRET_KEY`, so no `.env` is needed)

### Database migrations

The schema is managed with Alembic. Migrations live in `database/migrations/versions/`, and the config is `database/alembic.ini`. On startup, `init_db()` runs `alembic upgrade head`, so a fresh database is created from the migrations and an existing one gets any pending ones.

To change the schema, edit the models in `database/models/`, then generate a migration from `backend/`:

```bash
PYTHONPATH=..:. alembic -c ../database/alembic.ini revision --autogenerate -m "add foo to users"
```

Review the generated file before committing it. Autogenerate misses some changes, such as renames, and on SQLite it writes `batch_alter_table` blocks because SQLite cannot alter columns in place. The migration runs the next time the app starts. You can also apply it by hand with `alembic -c ../database/alembic.ini upgrade head`. The CLI uses `DATABASE_URL` from the environment, which defaults to `./placement_prep.db`.

Databases created before Alembic have no `alembic_version` table. On their first boot, the columns the old startup code used to add are added, along with any missing tables or indexes, and the database is stamped at the baseline revision `0001_baseline`. No rows are changed.

### Configuration (`backend/.env`)

| Variable | Purpose |
| --- | --- |
| `DATABASE_URL` | Defaults to `sqlite:///./placement_prep.db` |
| `JWT_SECRET_KEY` | **Required.** Signs access tokens and OAuth state. Startup fails if it is missing, a placeholder, or shorter than 32 characters. Generate one with `python -c "import secrets; print(secrets.token_urlsafe(48))"`. |
| `JWT_ALGORITHM`, `ACCESS_TOKEN_EXPIRE_MINUTES` | Token settings (HS256, 24 h by default) |
| `GROQ_API_KEY`, `GROQ_MODEL`, `GROQ_FALLBACK_MODELS` | Groq LLM, also used for voice transcription |
| `GEMINI_API_KEY`, `GEMINI_MODEL`, `GEMINI_FALLBACK_MODELS` | Gemini LLM |
| `RESEND_API_KEY`, `EMAIL_FROM` | Sends verification emails. If unset, no email is sent. |
| `DEV_VERIFICATION_CODE` | Fixed OTP for local development only (`.env.example` uses `123456`). Defaults to empty, which issues a random code that expires. Must be empty in production; startup fails if it is set together with `RESEND_API_KEY`. |
| `GOOGLE_CLIENT_ID/SECRET`, `GITHUB_CLIENT_ID/SECRET` | OAuth sign-in stays disabled until these are set. |
| `OAUTH_REDIRECT_BASE` | Public base URL used for OAuth callbacks |
| `CORS_ORIGINS` | JSON list of exact browser origins allowed to call the API. Defaults to `[]`; the iOS app does not need it. |
| `CORS_ALLOW_CREDENTIALS` | Defaults to `false`. Cannot be `true` while `CORS_ORIGINS` contains `"*"`. |

Set at least one of `GROQ_API_KEY` or `GEMINI_API_KEY` for the AI features to work. Voice input needs `GROQ_API_KEY`.

### API overview

| Prefix | Endpoints |
| --- | --- |
| `/api/auth` | `signup`, `verify`, `resend-verification`, `login`, `GET`/`PATCH me`, `DELETE me` (deletes the account and all its data; `204`) |
| `/api/auth/oauth` | `{provider}/login`, `{provider}/callback` (`google`, `github`) |
| `/api/quiz` | `questions`, `submit`, `summary`, `history`, `progress` |
| `/api/dsa` | `GET`/`POST solved`, `DELETE solved/{slug}` |
| `/api/interview` | `start`, `respond`, `transcribe`, `resume-summary`, `{id}/feedback`, list, `{id}` |
| `/api/resume` | `review` |

### Rate limits

The auth endpoints are rate limited. Over the limit, they return `429` with a JSON `{"detail": "..."}` message and a `Retry-After` header.

| Endpoint | Default | Keyed by | Setting |
| --- | --- | --- | --- |
| `login` | 5/minute, 30/hour | IP | `RATE_LIMIT_LOGIN` |
| `signup` | 3/minute, 20/hour | IP | `RATE_LIMIT_SIGNUP` |
| `verify` | 5/minute, 20/hour | user | `RATE_LIMIT_VERIFY` |
| `resend-verification` | 1/minute, 5/hour | user | `RATE_LIMIT_RESEND_VERIFICATION` |
| `oauth/{provider}/login`, `callback` | 20/minute | IP | `RATE_LIMIT_OAUTH` |
| `DELETE me` | 5/hour | user | `RATE_LIMIT_DELETE_ACCOUNT` |

The client IP comes from Fly's `Fly-Client-IP` header, or the socket address when that header is absent. `X-Forwarded-For` is ignored. Set `RATE_LIMIT_ENABLED=false` to turn limiting off. Counters are held in memory (`RATE_LIMIT_STORAGE_URI=memory://`), so they reset when the machine restarts and are not shared between machines. Before running more than one machine, point `RATE_LIMIT_STORAGE_URI` at Redis (for example `redis://host:6379`).

### Resetting the database

```bash
python3 scripts/wipe_database.py        # dry run: lists row counts
python3 scripts/wipe_database.py --yes  # deletes every row
```

The `alembic_version` table is left alone, so the schema stays at the same migration.

## Running the app

Requires Xcode 15+ and XcodeGen (`brew install xcodegen`).

```bash
cd frontend
xcodegen generate            # re-run after adding, removing or renaming files
open PlacementPrep.xcodeproj
```

Pick an iPhone or iPad simulator, or **My Mac (Mac Catalyst)**, then run. For a physical device, set your development team in Signing & Capabilities.

The backend URL comes from the `PP_BACKEND_URL` build setting in `project.yml`: Debug builds use `http://localhost:8000`, Release builds (including archives) use `https://placementprep-api.fly.dev`. To use a different backend, set the `PPBackendURL` user default (Release builds ignore a localhost override), for example:

```bash
xcrun simctl spawn booted defaults write com.placementprep.app PPBackendURL http://192.168.1.10:8000
```

### Tests

Unit tests live in `frontend/PlacementPrepTests/` (Swift Testing, Xcode 16+) and run hosted in the app, so bundled quizzes and company CSVs are covered too. Press ⌘U in Xcode, or from `frontend/` (use any simulator from `xcrun simctl list devices available`):

```bash
xcodebuild test -project PlacementPrep.xcodeproj -scheme PlacementPrep \
  -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO
```

### Packaging for macOS

```bash
./Scripts/package-mac.sh
```

This builds a Release Mac Catalyst archive and a `.dmg` in `frontend/build/mac/`. Set `DEVELOPER_ID` (and optionally `NOTARY_PROFILE`) to sign and notarize it. Without them, the app is left unsigned.

### Content scripts

Quiz and company content ships in the app bundle. Regenerate it with the scripts in `frontend/Scripts/`, run from `frontend/`:

```bash
python3 Scripts/validate-quizzes.py              # run after editing any quiz JSON
python3 Scripts/shuffle-quiz-answers.py          # re-deal a quiz's answer key if validation flags a pattern
python3 Scripts/build-company-csvs.py            # refresh every Resources/Companies/*.csv from every public source
python3 Scripts/build-company-csvs.py Deloitte   # refresh just the named companies
python3 Scripts/fetch-company-logos.py Deloitte  # re-fetch one logo (no names re-fetches all of them)
```

#### Add a new company

A company's CSV file name is the name the app shows, and its logo must use the same name. Company
names must match a directory in [liquidslr/leetcode-company-wise-problems](https://github.com/liquidslr/leetcode-company-wise-problems)
(case doesn't matter).

1. Seed its list: `./Scripts/fetch-company-csvs.sh "Jane Street"`. This copies only the named
   companies. It refuses to overwrite a company that is already bundled unless you pass `--force`, and
   suggests close matches for a misspelled name.
2. Fill it in from every source: `python3 Scripts/build-company-csvs.py "Jane Street"`.
3. Add it to `COMPANIES` in `Scripts/fetch-company-logos.py` (`"Jane Street": ("janestreet.com", None),`),
   then `python3 Scripts/fetch-company-logos.py "Jane Street"`. Always pass the name, because running it
   with no names re-downloads every logo.
4. If the company is listed in `Scripts/companies-not-bundled.txt`, delete that line. The file lists the
   companies deliberately left out of the bundle.
5. Run `xcodegen generate`, then build and run the app and check the company's list and logo.

`./Scripts/fetch-company-csvs.sh --all` still copies every upstream company over the bundled lists,
losing the merged sources and the curated KJSIT lists. It asks for confirmation first.

`build-company-csvs.py` merges LeetCode company tags from five public repos, GeeksforGeeks company
tags (mapped through the hand-checked `Scripts/gfg-leetcode-equivalents.json`) and, for companies
with under 100 problems, LeetCode Discuss interview posts. It re-tags every row from LeetCode's live
catalog and never drops a bundled row. Problems with no current LeetCode frequency get `0`, so they
show without a "Freq" badge after the tagged ones. Pass `--dry-run` to see the counts first.

## Deploying the backend

The backend deploys to Fly.io from the **repo root**, because the image needs both `backend/` and `database/`:

```bash
fly volumes create placementprep_data --region bom   # first time only
fly secrets set JWT_SECRET_KEY=... GROQ_API_KEY=... GEMINI_API_KEY=... RESEND_API_KEY=... DEV_VERIFICATION_CODE=
fly deploy
```

SQLite lives on the mounted volume at `/data/placement_prep.db`. The first boot after Alembic was added stamps that existing database at `0001_baseline` and adds the missing `ix_interview_sessions_mode` index. User data is not touched. To check the version, run `fly ssh console -C "alembic -c /app/database/alembic.ini current"`. Machines auto-stop when idle and start on request, and `/health` is used for health checks. Keep secrets in `fly secrets`, never in `fly.toml`.
