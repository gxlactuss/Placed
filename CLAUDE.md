# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository shape

Two independent halves that are **not currently talking to each other** (see "Current wiring state"):

- `backend/` — FastAPI + SQLModel + SQLite, JWT auth, Google Gemini for mock interviews
- `frontend/` — SwiftUI iOS app (iOS 17+), no third-party dependencies

## Commands

### Frontend

The Xcode project is **generated** from `frontend/project.yml` by XcodeGen and is gitignored. Sources are picked up by directory tree, not listed individually.

```bash
# Regenerate after ANY file add/delete/rename — otherwise Xcode won't see it
cd frontend && xcodegen generate

open frontend/PlacementPrep.xcodeproj   # then ⌘R
```

Command-line builds need `DEVELOPER_DIR` set, or a one-time `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`:

```bash
cd frontend
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -project PlacementPrep.xcodeproj -scheme PlacementPrep \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Driving the simulator directly (useful for visual verification):

```bash
xcrun simctl boot "iPhone 17 Pro"
xcrun simctl install "iPhone 17 Pro" <path-to>/PlacementPrep.app
xcrun simctl launch "iPhone 17 Pro" com.placementprep.app
xcrun simctl io "iPhone 17 Pro" screenshot out.png
```

Every file in `DesignSystem/` ships its own `#Preview` covering all component states — the fastest iteration loop, and it needs no backend.

### Backend

No `.env` exists yet; copy `.env.example` and fill in `JWT_SECRET_KEY` and `GEMINI_API_KEY`.

```bash
cd backend
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
uvicorn app.main:app --reload --port 8000
```

Interactive API docs at `http://localhost:8000/docs`.

### Tests

There is no test suite and no test tooling configured in either half.

## Current wiring state (read this first)

**The frontend does not call the backend.** Auth was removed and the app opens straight into `DashboardView`. Every screen reads from `Services/SampleData.swift`, a hand-written local stand-in.

Consequences when working on the frontend:

- `ViewModels/` (`QuizViewModel`, `CompanyDSAViewModel`, `MockInterviewViewModel`, `AuthViewModel`) are **orphaned** — fully written against `NetworkManager`, but no view references them. Don't assume they are live.
- `LoginView` was deleted. `PlacementPrepApp` has a comment marking where to reinstate the auth gate; `AuthViewModel`, `KeychainService`, and `NetworkManager.authTokenProvider` were left intact for that.
- `SpeechRecognizerService` exists but isn't connected; the mic control streams a canned sentence from `SampleData`.

Consequences when working on the backend — these endpoints are `NotImplementedError` stubs:

- `GET /api/quiz/questions` and `POST /api/quiz/submit` — no question bank exists
- `company_data_service.list_companies` / `get_company_questions` — expects ingested JSON at `backend/data/companies/<slug>.json`, sourced from the `leetcode-company-wise-problems` dataset; the directory is empty

Working today: auth routes, `GET /api/quiz/history`, and the interview routes (real Gemini calls).

The intended path back to a live app is to map decoded API models onto the same presentation types `SampleData` vends, so views don't change shape.

## Frontend architecture

### Design system is the styling contract

`DesignSystem/` holds all visual decisions; screens compose `PP*` components and never hardcode colors, fonts, or spacing. A palette or type change is a one-file edit that propagates everywhere — preserve that property.

- `Color+Theme.swift` — the palette. **"Ledger": neutral ink ground, single amber accent, warm off-white text.** Deliberately not purple/gradient/glow — that look was explicitly rejected as generic. Don't reintroduce gradients, glow shadows, or a second accent hue.
- `Typography.swift` — scale mapped onto **semantic text styles** so Dynamic Type works. Display/title/stat faces are `design: .serif` (New York). Never use fixed-size `Font.system(size:)` for body text; `ppStatFixed` is the one intentional exception, for numerals inside the fixed-diameter score ring.
- `Layout.swift` — spacing/radius/size tokens plus `PPMotion`, the app's only two animation curves. Route new animation through these.
- `PPAppearance.swift` — restyles the system `UITabBar`/`UINavigationBar` via UIKit appearance proxies, called from `PlacementPrepApp.init`. Note iOS 26 renders a Liquid Glass tab bar that partly overrides this.

Visual conventions worth keeping: depth comes from hairline borders, not shadows; filled controls are amber with **ink** (`ppGround`) marks rather than white; one loud amber element per screen.

### Navigation

`DashboardView` owns `selectedTab` as state and passes a `Binding` into `HomeView`, so Home's shortcut cards switch tabs rather than pushing duplicate screens. The quiz session is a `fullScreenCover` (it owns the screen and dismisses via its own X), not a navigation push.

### Quiz session model

`QuizSessionModel` is `@MainActor @Observable` and is the one piece of real state logic in the app. Two constraints it encodes:

- Answers commit **once** — `answer(_:)` ignores repeat taps, and `PPOptionRow.State.resolve(optionID:selectedID:correctID:)` derives all four rows' appearance so a resolved question can mark the wrong pick and reveal the right answer simultaneously. This "reveal immediately, no correction" rule is a product decision, not an implementation detail.
- The per-question timer is a cancellable `Task`, **not** a `Timer` — a main-actor-isolated model cannot invalidate a `Timer` from `deinit`, which is a compile error. Don't "simplify" it back.

## Backend architecture

Standard FastAPI layering: `routes/` → `services/` → `models/` (SQLModel tables) with `schemas/` as the Pydantic request/response boundary. `main.py` wires four routers under `/api/*` and calls `init_db()` (`SQLModel.metadata.create_all`) on startup — there are no migrations, so schema changes mean dropping the SQLite file.

- `core/auth.py` — bcrypt hashing plus JWT encode/decode. `get_current_user_id` is the dependency every protected route injects; it returns the user id as a **string** subject, so routes cast with `int(user_id)`.
- `core/config.py` — pydantic-settings reading `.env`. Defaults are dev-only (`jwt_secret_key` literally defaults to `CHANGE_ME_IN_ENV`).
- `database.py` — SQLite with `check_same_thread=False`; `get_session` is the per-request session dependency.
- `services/gemini_service.py` — `gemini-1.5-flash`. Interview completion is currently hardcoded `False`; the TODO notes it should come from a structured JSON signal rather than being inferred from response text.
- Interview transcripts are stored as a JSON string in `transcript_json`, not a relational table.
