# Social sign-in setup (Google & GitHub)

Sign-in is **backend-brokered**: the iOS app opens `…/api/auth/oauth/<provider>/login`
in a secure web sheet, the backend runs the whole OAuth flow, and redirects our
own JWT back to the app via the `placementprep://` scheme. **No client IDs or
secrets live in the app** — they all go in `backend/.env`.

Each provider button stays inert (shows "isn't set up yet") until its two keys
are filled in and the backend is restarted.

The redirect URI the backend uses is always:

```
<OAUTH_REDIRECT_BASE>/api/auth/oauth/<provider>/callback
```

`OAUTH_REDIRECT_BASE` defaults to `http://localhost:8000` (local dev). Set it to
your Fly URL in production. Whatever it is, it must **exactly** match the redirect
URI you register in each console below.

---

## Google

1. [console.cloud.google.com](https://console.cloud.google.com) → create/select a project.
2. **APIs & Services → OAuth consent screen** → User type **External** → fill app
   name + support email → Save. While it's in "Testing", add your own Google
   address under **Test users** (only test users can sign in until you publish).
3. **APIs & Services → Credentials → Create credentials → OAuth client ID**.
   - Application type: **Web application** (our redirect is a backend URL, not an
     iOS reverse-scheme).
   - **Authorized redirect URIs** → add both:
     - `http://localhost:8000/api/auth/oauth/google/callback`  (dev)
     - `https://<your-app>.fly.dev/api/auth/oauth/google/callback`  (prod, once deployed)
4. Copy the **Client ID** and **Client secret** into `backend/.env`:
   ```
   GOOGLE_CLIENT_ID=....apps.googleusercontent.com
   GOOGLE_CLIENT_SECRET=....
   ```

## GitHub

1. [github.com](https://github.com) → **Settings → Developer settings → OAuth Apps → New OAuth App**.
2. Homepage URL: anything (e.g. `http://localhost:8000`).
3. **Authorization callback URL**: `http://localhost:8000/api/auth/oauth/github/callback`
   - GitHub OAuth apps allow only **one** callback URL. For production, create a
     second OAuth App with the Fly callback (`https://<app>.fly.dev/api/auth/oauth/github/callback`)
     and swap the keys, or just point `OAUTH_REDIRECT_BASE` at whichever you're testing.
4. Copy the **Client ID**, generate a **Client secret**, into `backend/.env`:
   ```
   GITHUB_CLIENT_ID=....
   GITHUB_CLIENT_SECRET=....
   ```

## Finish

```
# backend/.env — keep this in sync with the consoles
OAUTH_REDIRECT_BASE=http://localhost:8000     # or https://<app>.fly.dev in prod
```

Restart the backend, then in the app tap **Continue with Google / GitHub**. A new
account created this way is pre-verified (the provider vouches for the email) and
lands on onboarding.

**Notes**
- The iOS Simulator's `localhost` maps to your Mac, so the web sheet reaches the
  local backend and the callback works with no extra setup.
- In production, set these as `fly secrets set GOOGLE_CLIENT_ID=… …` (not in the
  repo), and set `OAUTH_REDIRECT_BASE` to the Fly URL in `fly.toml [env]`.
- The app's `placementprep://` callback scheme is already registered in `Info.plist`.
