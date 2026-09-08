# Shipping the Mac app as a .dmg

The Mac build is a Mac Catalyst destination on the iOS target (see "The macOS
build" in `CLAUDE.md`). `frontend/Scripts/package-mac.sh` wraps it in a
drag-to-Applications disk image.

```bash
cd frontend
./Scripts/package-mac.sh          # → build/mac/PlacementPrep.dmg  (~7 MB)
```

This app is handed to **two developers**, so it ships **unsigned** and skips
Apple's $99 Developer Program. That is a deliberate trade: it costs about two
minutes per machine, once, and the two minutes are documented below. If this ever
goes to people who aren't going to run a `xattr` command, read
"If you ever do want to notarize" at the bottom instead.

## Installing on a Mac

`build/mac/PlacementPrep.dmg` — copy it over however you like (AirDrop, Drive, a
USB stick). Then on the receiving Mac:

```bash
# 1. Mount it and drag PlacementPrep.app to Applications (or do it in Finder)
hdiutil attach ~/Downloads/PlacementPrep.dmg
cp -R "/Volumes/Placement Prep/PlacementPrep.app" /Applications/
hdiutil detach "/Volumes/Placement Prep"

# 2. Strip the download quarantine. THIS IS THE STEP THAT MATTERS.
xattr -dr com.apple.quarantine /Applications/PlacementPrep.app

# 3. Launch
open /Applications/PlacementPrep.app
```

Step 2 is the whole reason this is a two-minute job rather than a $99 one.
Anything downloaded from a browser, AirDrop or a messaging app is flagged with
`com.apple.quarantine`, and Gatekeeper refuses to launch a quarantined app that
isn't notarized. Since macOS Sequoia the Control-click ▸ Open bypass is **gone**,
so without `xattr -dr` the dialog has no "open anyway" button at all. Deleting the
attribute makes it a local app rather than a downloaded one, and it launches
normally. `-r` matters: the flag is set on files inside the bundle too.

If step 2 is skipped and the app has already been blocked once, System Settings ▸
Privacy & Security shows an "Open Anyway" button near the bottom. That works too;
`xattr` is just faster and doesn't need a failed launch first.

## Pointing the app at a backend

The app needs the API running. There is no hosted backend — it reads
`http://localhost:8000` by default, and `PPBackendURL` overrides that with no
rebuild:

```bash
# Point at another machine on the LAN (e.g. the Mac running the API)
defaults write ~/Library/Preferences/com.placementprep.app \
  PPBackendURL "http://192.168.1.5:8000"

# Back to the default
defaults delete ~/Library/Preferences/com.placementprep.app PPBackendURL
```

**Write the path, not the bundle id.** `defaults write com.placementprep.app …`
looks equivalent and isn't: on a Mac where a *sandboxed* build of the same bundle
id has ever run (i.e. any machine that has built from Xcode), macOS silently
redirects the write into `~/Library/Containers/…/Preferences/`, while the
unsigned `.dmg` build — no entitlements, therefore not sandboxed — keeps reading
the plain path and never sees it. On a clean machine both forms happen to work;
the path form works on both. Quit and relaunch the app for a change to take. If
it doesn't take, `killall cfprefsd` and relaunch.

Two workable topologies:

- **Each runs their own API.** Both clone the repo, `uvicorn app.main:app --port 8000`,
  leave `PPBackendURL` unset. Separate SQLite files, so progress doesn't sync
  between you — fine, since the app is single-user anyway. Each needs their own
  `backend/.env` (Gemini/Groq keys are free to obtain).
- **One API, shared.** One machine runs it with `--host 0.0.0.0`, the other sets
  `PPBackendURL` to `http://<that-mac>.local:8000` or its LAN IP. The host Mac has
  to be awake and on the same network. `NSAllowsLocalNetworking` in `Info.plist`
  already permits cleartext HTTP to private addresses, so no HTTPS is needed.

```bash
cd backend && source .venv/bin/activate
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

## What the unsigned build costs you

- **No Keychain.** This is the one that actually bites. An ad-hoc-signed build
  cannot write to the macOS Keychain at all: a keychain item needs an access
  group, that comes from the signing identity's Team ID, and ad-hoc signing has
  none (`TeamIdentifier=not set`), so `SecItemAdd` fails with
  `errSecMissingEntitlement` (-34018). Confirmed on both the unsigned Release
  build and the sandboxed Debug build, so the sandbox is not the variable — the
  missing Team ID is. `KeychainService` therefore falls back to a `0600` file at
  `~/Library/Application Support/PlacementPrep/session.token`, engaged only by an
  actual `SecItemAdd` failure, so iOS and any signed build are unaffected. The
  token being in a file rather than the Keychain is a real if modest downgrade —
  anything running as that user can read it.
- **Not sandboxed.** It carries no entitlements at all, because the packaging
  script passes `CODE_SIGNING_ALLOWED=NO`. In practice this makes it *more*
  permissive, not less — the microphone and file picker still work through the
  normal TCC prompts.
- **Gatekeeper, once per machine.** The `xattr` step above.
- **No auto-update.** Re-cutting the .dmg and re-copying is the update mechanism.

Two things Catalyst itself costs, signed or not: the XP-tier **alternate app
icons** don't work (no such API on Catalyst — the picker shows its unavailable
state) and **haptics** silently no-op.

## If you ever do want to notarize

Needed only if this goes to people who won't run a terminal command. Requires the
paid membership; there is no free path, since a Personal Team cannot issue a
Developer ID certificate.

```bash
# once
xcrun notarytool store-credentials placementprep \
  --apple-id you@example.com --team-id TEAMID --password <app-specific-password>

# per release
cd frontend
DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE=placementprep \
  ./Scripts/package-mac.sh
```

The script then archives, exports with the `developer-id` method, signs the .dmg,
submits it, waits, and staples the ticket — and prints `Signed and notarized` only
if every step actually succeeded. Verify the way a downloader's Mac will:

```bash
spctl -a -t open --context context:primary-signature -v build/mac/PlacementPrep.dmg
xcrun stapler validate build/mac/PlacementPrep.dmg
```

Note that a signed build **is** sandboxed, which flips three things above: the
entitlements in `Resources/PlacementPrep.entitlements` start applying,
`defaults write` should then target the container path, and the Keychain starts
working — so `KeychainService` stops using its file fallback and deletes any
token the unsigned build left behind.
