# Deploying the backend to Fly.io

The API ships as a Docker image (`Dockerfile`) with a persistent volume for the
SQLite database (`fly.toml`). One-time setup, then `fly deploy` for every push.

**Run every command below from the repo root.** The `Dockerfile`, `fly.toml`,
and `.dockerignore` live at the root because the image needs both `backend/` and
the sibling `database/` package, so the Docker build context is the whole repo.

## Prerequisites

```bash
brew install flyctl          # or: curl -L https://fly.io/install.sh | sh
fly auth login
```

## One-time setup

1. **Pick a unique app name.** Edit `app = "placementprep-api"` in `fly.toml` if
   that name is taken. Whatever you choose, Fly serves it at
   `https://<app>.fly.dev` — put that same URL in the Release branch of
   `frontend/PlacementPrep/Services/NetworkManager.swift`.

2. **Create the app** (skips the interactive builder; keeps our `fly.toml`):

   ```bash
   fly apps create placementprep-api      # use your chosen name
   ```

3. **Create the volume** (holds `placement_prep.db`; region must match
   `primary_region`):

   ```bash
   fly volumes create placementprep_data --region bom --size 1
   ```

4. **Set secrets** (never commit these). Generate a *fresh* JWT secret for prod —
   don't reuse the local-dev one:

   ```bash
   fly secrets set \
     JWT_SECRET_KEY="$(python3 -c 'import secrets; print(secrets.token_urlsafe(48))')" \
     GEMINI_API_KEY="AIza...your-real-key"
   ```

## Deploy

```bash
fly deploy        # from the repo root
```

Then smoke-test the live host:

```bash
BASE=https://placementprep-api.fly.dev
curl -s $BASE/health
curl -s -X POST $BASE/api/auth/signup -H 'Content-Type: application/json' \
  -d '{"email":"you@example.com","password":"testpass123","full_name":"You","target_role":"Backend Engineer"}'
```

## Wiping the database

Empties every table — accounts, interview transcripts, solved problems, quiz
results. **Unrecoverable**, so the script needs `--yes` and prints the row counts
it is about to delete when run without it.

```bash
fly ssh console -a placementprep-api -C "python3 /app/scripts/wipe_database.py"        # dry run: counts only
fly ssh console -a placementprep-api -C "python3 /app/scripts/wipe_database.py --yes"  # wipe
```

`backend/scripts/` is copied into the image by the `Dockerfile`, so a machine
built before that line was added needs a `fly deploy` first. Without one, the
same job runs inline:

```bash
fly ssh console -a placementprep-api -C 'python3 -c "
import sqlite3
c = sqlite3.connect(\"/data/placement_prep.db\")
for (t,) in c.execute(\"SELECT name FROM sqlite_master WHERE type=%s AND name NOT LIKE %s\" % (repr(\"table\"), repr(\"sqlite_%\"))).fetchall():
    c.execute(\"DELETE FROM \\\"%s\\\"\" % t)
c.commit(); c.execute(\"VACUUM\")
"'
```

Rows, not the file: the schema — including the columns `init_db()` bolts on by
`ALTER TABLE` — survives, so the API keeps serving without a restart. Deleting
`/data/placement_prep.db` outright also works but needs a machine restart before
the next request finds a database.

Locally the same script reads `backend/.env`, so no path is needed:

```bash
cd backend && python3 scripts/wipe_database.py --yes
```

## Notes

- **DB migrations**: there are none. `init_db()` runs `create_all` on startup, so
  additive models are fine; a breaking schema change means deleting the volume's
  `.db` file (`fly ssh console` → `rm /data/placement_prep.db`) and redeploying.
- **Gemini model**: `GEMINI_MODEL` is set in `fly.toml` (`gemini-flash-latest`).
  Change it there, or override with `fly secrets set GEMINI_MODEL=<model>`.
- **Cost**: `auto_stop_machines`/`min_machines_running = 0` lets the machine sleep
  when idle, so a demo app costs ~nothing. First request after sleep is slower.
- **CORS** is `["*"]`; tighten it once the client origins are known.
