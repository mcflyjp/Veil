# CLAUDE.md — Veil

## Project overview
Veil is an end-to-end encrypted messaging app (Signal security, AIM aesthetic).
Stack: Flutter (Android-first), Dendrite homeserver on Oracle VM, matrix-dart-sdk v7.

- App source: `app/`
- Homeserver: `https://matrix.veilmsg.com` (Dendrite on Oracle VM alongside BitClip)
- GitHub repo: `mcflyjp/Veil`
- Domain: `veilmsg.com`

## Build & release process

### Build debug APK
```bash
cd app
flutter build apk --debug
```

### APK output — ALWAYS use `veilmsg.apk`
Gradle renames the APK to `veilmsg.apk` via `applicationVariants.all` in
`android/app/build.gradle.kts` and copies it to the flutter-apk dir.

**Release APK path (use this for GitHub releases):**
```
app/build/app/outputs/flutter-apk/veilmsg.apk
```

Never attach `app-debug.apk` to a release. The canonical release filename is
always `veilmsg.apk`.

### Create a GitHub release
```bash
gh release create vX.Y.Z "app/build/app/outputs/flutter-apk/veilmsg.apk" \
  --title "Veil vX.Y.Z" \
  --notes "..."
```

### Version bump
Update `version: X.Y.Z+N` in `app/pubspec.yaml` before building. Both the
semver and build number must increment (e.g. `0.1.25+25` → `0.1.26+26`).

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

- **Themes**: 4 modes in `VeilThemeMode` — `aim`, `dark`, `glass`, `light`.
  `VeilUserPrefs` drives `MaterialApp` scaffold colors. `AimTheme` is only
  a base; `scaffoldBackgroundColor` is always overridden from `tc.scaffold`.

## Devlog
All changes are logged in `DEVLOG.md` before committing.
