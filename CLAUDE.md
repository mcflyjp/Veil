# CLAUDE.md — Veil

## Project overview
Veil is an end-to-end encrypted messaging app (Signal security, AIM aesthetic).
Stack: Flutter (Android-first, also ships web + iOS), Dendrite homeserver on
Oracle VM, matrix-dart-sdk v7.

- App source: `app/`
- Homeserver: `https://matrix.veilmsg.com` (Dendrite on Oracle VM, same VM as
  BitClip — shares only the hardware, not any service, credential, or cloud
  project. Veil's infrastructure is otherwise fully self-contained. Never
  wire Veil into another project's Cloudflare/Vercel/hosting account or
  reuse another project's deploy credentials for it.)
- Web app: `https://veilmsg.com` (apex domain — self-hosted, see below)
- GitHub repo: `mcflyjp/Veil`
- Domain: `veilmsg.com` (owned by the user; always deploy Veil's web build
  here, never to a throwaway `*.pages.dev`/Vercel URL)

## Build & release process

CI (`.github/workflows/build.yml`) builds on every `v*` tag push:
- **Android APK** — built + attached to the GitHub release automatically
- **iOS IPA** — unsigned, built + attached (known bug: currently produces
  zero output despite the job reporting success — see DEVLOG, unresolved)
- **Web** — built and uploaded as a CI artifact only. **CI does NOT deploy
  it anywhere.** Deploying the web build to `veilmsg.com` is a separate,
  currently-manual step — see "Deploy web" below.

### Version bump (do this first)
Update `version: X.Y.Z+N` in `app/pubspec.yaml`. Both the semver and build
number must increment (e.g. `0.1.38+38` → `0.1.39+39`).

### Release checklist (every version bump)
1. Bump `app/pubspec.yaml` version
2. Add a DEVLOG.md entry
3. Commit, `git tag vX.Y.Z`, push commit + tag → CI builds APK/IPA/web
4. **Deploy web** (CI does not do this — see below). Do this for every
   release that touches anything user-visible, not just "web-specific"
   changes — the web build is the same Flutter source as the APK, so any
   UI/feature change reaches web too and should be deployed alongside it.
5. Verify: `curl -s https://veilmsg.com/version.json` should show the new
   version/build number

### Deploy web (manual — do this on every release)
The web build is self-hosted directly on the Oracle VM via nginx, entirely
independent of any other project's hosting:

- nginx config: `/etc/nginx/conf.d/veil.conf` on the VM — serves static
  files from `/var/www/veilmsg` at the `veilmsg.com` apex (SPA routing via
  `try_files $uri $uri/ /index.html`), plus the `.well-known/matrix/*`
  delegation endpoints so the apex domain also asserts `matrix.veilmsg.com`
  as the homeserver.
- SSH key: `~/.ssh/clipforge_oracle` (Windows: `C:\Users\<user>\.ssh\clipforge_oracle`)
- VM: `opc@158.101.106.75`

```bash
# 1. Build
cd app
flutter build web --release

# 2. Package + upload
cd build/web
tar czf /tmp/veil-web.tar.gz .
scp -i ~/.ssh/clipforge_oracle /tmp/veil-web.tar.gz opc@158.101.106.75:/tmp/veil-web.tar.gz

# 3. Deploy on the VM (replaces old contents, fixes ownership)
ssh -i ~/.ssh/clipforge_oracle opc@158.101.106.75 \
  "sudo rm -rf /var/www/veilmsg/* && \
   sudo tar xzf /tmp/veil-web.tar.gz -C /var/www/veilmsg/ && \
   sudo chown -R opc:opc /var/www/veilmsg && \
   rm /tmp/veil-web.tar.gz"

# 4. Verify
curl -s https://veilmsg.com/version.json
```

**Do not** create a Cloudflare Pages / Vercel / Netlify project for this.
`veilmsg.com` already has a working, dedicated deployment — use it.

### Android APK — CI-built only, do not hand-build for releases
CI attaches `app-release.apk` to every tagged GitHub release. Don't rename
it (renaming has historically produced APKs twice the normal size with
runtime bugs) and don't hand-build a debug APK for releases — debug builds
are for local device testing only (`flutter build apk --debug`, output at
`app/build/app/outputs/flutter-apk/app-debug.apk`, install via
`adb install -r`).

## Architecture

- **Navigation**: go_router v17, ShellRoute with `SplitShell` widget
  - Narrow screens: full-screen stack (buddy list → chat as push)
  - Wide screens (≥700px): side-by-side two-panel layout
  - Back from chat: `context.go('/buddylist')` via `PopScope`

- **Timeline caching**: `ClientManager._timelineCache` stores one `Timeline`
  per room ID. `ChatScreen` calls `mgr.getOrCreateTimeline(roomId)` — never
  `room.getTimeline()` directly. This prevents the freeze caused by calling
  `getTimeline()` twice on the same room when re-entering a chat.
  Do NOT call `timeline.cancelSubscriptions()` in `ChatScreen.dispose()`.
  Cleanup happens only in `ClientManager.logout()`.

- **Themes**: 8 modes in `VeilThemeMode` — `modern` (default), `modernDark`,
  `retro` ("AIM Remastered"), `retroDark`, `aim` ("AIM Classic"), `dark`,
  `glass`, `light`. `VeilUserPrefs` drives `MaterialApp` scaffold colors.
  `AimTheme` is only a base; `scaffoldBackgroundColor` is always overridden
  from `tc.scaffold`. Bubble-vs-flat message rendering and other per-theme
  behavior (floating toolbar, pill composer, avatar ring) are driven by
  bool fields on `VeilThemeColors`, not hardcoded per-theme branches — see
  `core/veil_theme.dart`.

## Devlog
All changes are logged in `DEVLOG.md` before committing.
