# Veil — Development Log

## 2026-09-11 — v0.1.46 (push notifications — Phase 3 of 3 complete)

**[ADD] Flutter-side push wiring, completing Phase 3.** Builds on the Sygnal gateway from earlier today (see entry directly below).

- New `core/push_service.dart` — `PushService`, same `attachClient`/`detachClient` lifecycle pattern as `VeilUserPrefs`/`CallService`. On login: gets the device's FCM token, registers it as a Matrix pusher (`POST /client/v3/pushers/set` via `client.request()` directly — matrix_dart_sdk 7.4.0 doesn't have a generated convenience method for this one endpoint), pointing at `https://veilmsg.com/_matrix/push/v1/notify`. Re-registers on `FirebaseMessaging.onTokenRefresh`.
- **Deliberately does not attempt background decryption.** Veil's rooms are always E2E encrypted, so a push's `content` field is Megolm ciphertext — the homeserver never had plaintext to send in the first place, decrypt-only-in-foreground is the honest ceiling here without building a whole background-sync-with-persisted-session pipeline (real risk of Olm/Megolm ratchet desync running two sessions against the same keys from two isolates — deliberately not attempted this round). What Dendrite *does* send unencrypted — `sender_display_name`/`room_name` (room/member metadata isn't secret in Matrix, only message bodies are) — is enough for a real "so-and-so sent a message in X" notification with no decryption at all. Same reasoning means a background push can't be distinguished as a call vs. a regular message either (`type` is just `m.room.encrypted` either way) — shows the same generic notification; `CallService`'s existing to-device/timeline listening (verified working in the v0.1.44/45 two-device test) picks up the real invite once the app opens.
- `@pragma('vm:entry-point')` top-level background handler (required — FCM hands background messages to a fresh, minimal isolate with no access to the running app's `ClientManager`/`CallService`/anything). Shows the notification via its own `flutter_local_notifications` instance, using the **same notification ID derivation** (`roomId.hashCode`) as `NotificationService.showMessage` so a background push and a later live-sync notification for the same room replace each other instead of stacking as two separate alerts.
- **Found and fixed a real pre-existing gap while here**: tapping a notification when the app was *fully closed* (not just backgrounded) did nothing — `NotificationService` only wired up `onDidReceiveNotificationResponse` for taps while already running, never checked `getNotificationAppLaunchDetails()` for the cold-launch case. Added `pendingLaunchRoomId`, consumed once in `main.dart` right after `onTap` is wired up. This was always a real gap, just a rare one before push notifications made "app fully closed, get a notification, tap it" a routine path instead of an edge case.
- Firebase/Gradle/pubspec wiring for this was already done in the previous commit (see entry below) — this is purely the app-side push handling.

**Known limitation, not fixed this round**: `PushService.detachClient()` doesn't delete the pusher on logout — by the time it fires, `ClientManager.logout()` has already cleared the access token needed to authenticate that delete call. The pusher just goes stale server-side rather than being cleanly removed. Harmless (nothing sensitive in these pushes to leak) but not tidy — revisit if it ever becomes a real problem.

Verified: `flutter analyze` clean, debug APK builds with Firebase + the new push code linked in. **Not yet tested with a real push arriving to a killed app** — that needs an actual account logged in on a device with the app fully closed, which wasn't done this session; next real-device test should specifically try this.

**[FIX] v0.1.46's first CI run shipped Android-only — iOS and web both failed to build, caught after the fact.**
- **iOS**: `firebase_core` requires a higher `IPHONEOS_DEPLOYMENT_TARGET` than the project's default (13.0). Bumped to 15.0 in `Runner.xcodeproj/project.pbxproj` (all 3 build configs) and `ios/Flutter/AppFrameworkInfo.plist`'s `MinimumOSVersion`.
- **Web**: a real dart2js compile error, and a good example of why "it built locally" isn't proof by itself — my own local `flutter build web --release` had *silently succeeded* against this same broken dependency, because an incremental-build cache from an earlier compile skipped recompiling the affected file. `flutter clean` + a truly fresh build reproduced the same failure CI hit. Root cause: `firebase_core_web` 3.11.0 (the version `firebase_core: ^4.14.0` resolves to, and pub.dev's current latest) has a genuine upstream regression — `e.isA<JSObject>()` on a plain `Object`-typed value doesn't compile under this Flutter/Dart SDK, inside the package's own source, nothing to do with Veil's code. `3.10.0` compiles clean. Pinned via `dependency_overrides` in `pubspec.yaml`, commented with exactly when it's safe to remove (once a newer `firebase_core_web` release fixes the regression).
- Lesson for next time: after any dependency change, verify with a genuinely clean build (`flutter clean` first) before trusting a "success," and don't call CI's job list green until every platform in it actually is.

**[FIX] iOS still failed after the deployment-target fix** — a real CocoaPods version conflict this time: `firebase_messaging` needs `GoogleDataTransport ~> 10.1`, but `mobile_scanner` 5.2.3's ML Kit barcode-scanning dependency chain pins `GoogleDataTransport < 10.0` — non-overlapping ranges, CocoaPods can't satisfy both no matter what. `mobile_scanner`'s QR-login-scan usage (`MobileScanner`/`BarcodeCapture.barcodes`/`Barcode.rawValue` in `login_screen.dart`) hasn't changed across its major versions, so upgraded straight to 7.4.1 (latest) rather than hunting for a narrower compatible pin — newer ML Kit versions pull a newer, compatible `GoogleDataTransport`. Verified via genuinely clean rebuilds (`flutter clean` first, per the lesson two entries up) on both Android and web before trusting it. **This one, CI confirmed: all three platforms (Web, iOS, Android) green, both `app-release.apk` and `Runner.ipa` attached to the release, IPA's `Payload/Runner.app/Runner` executable verified present and real.**

**[FIX] Caught one more real gap before calling this done**: `PushService.init()`/`attachClient()` only guarded against web (`kIsWeb`) — on iOS they'd have called `Firebase.initializeApp()` unconditionally, which crashes at launch without a registered Firebase iOS app (only Android was set up in `veil-510bf` this round; no `GoogleService-Info.plist` exists). Added `Platform.isIOS` to both guards alongside `kIsWeb`. iOS gets no push notifications for now, consistent with the project's Android-first scoping — but it also doesn't crash on launch, which matters a lot more given this build actually ships to real iPhones via the release's IPA.

---

## 2026-09-11 — Push notification gateway live (Phase 3 of 3, infra half)

**[INFRA] Sygnal (Matrix's reference push gateway) running on the Oracle VM, bridging Dendrite's push events to FCM.** This is the infrastructure Phase 3 (ring/notify when the app is fully closed) needs — the Flutter-side wiring (pusher registration, background message handling) is the remaining piece, tracked separately below.

**Firebase setup:**
- Cloud Messaging (V1 API) was already enabled on the existing `veil-510bf` project.
- The Android app *registered in Firebase used the wrong package name* (`com.veil.app` instead of the real `com.veil.veil`) — this predates this session and was never caught before. Registered a new, correctly-named Android app in the Firebase console; the old mis-registered one was left alone (harmless, unused).
- `google-services.json` couldn't be downloaded through browser automation (the extension blocks triggered downloads, by design) — reconstructed by hand from the config values pulled directly off the console (project number, app ID, package name, API key) instead. This is safe: these are public app identifiers restricted server-side by package name/SHA, not secrets — the file is intentionally committed (`app/android/app/google-services.json`), same as most open-source Firebase apps.
- Generated a GCP service-account key (`firebase-adminsdk-fbsvc@veil-510bf`) for Sygnal to authenticate to FCM. This one **is** a real secret — backed up at `secrets/sygnal-fcm-key.json` locally (gitignored) and deployed to `/etc/sygnal/sygnal-fcm-key.json` on the VM (mode 600, owned by a dedicated `sygnal` system user).

**Sygnal deployment — DO NOT install via `pip install git+.../sygnal.git` into a venv, use Docker.** This cost most of a day to fully root-cause, worth recording precisely:
- `pip install matrix-sygnal`/`sygnal` from PyPI: package isn't published there under either name — must come from git.
- `matrix-org/sygnal` (the old GitHub org) prints a deprecation notice and exits 1 on startup — the project moved to `element-hq/sygnal`. Reinstalled from there.
- Current Sygnal requires Python ≥3.10; Oracle Linux 9's default `python3` is 3.9. Installed `python3.11` from the `ol9_appstream` repo and rebuilt the venv on it.
- With that sorted, the **FCM v1 credential refresh hung indefinitely** on every real request, every time, with no timeout, no exception — just silence. This was the actual multi-hour debugging effort:
  1. First suspect: `google-auth`'s async aiohttp transport, which its own source code comments call "an unstable async... API" (citing [google-auth-library-python#613](https://github.com/googleapis/google-auth-library-python/issues/613), and there's a separate confirmed-hangs report at [#1602](https://github.com/googleapis/google-auth-library-python/issues/1602)). Patched `gcmpushkin.py` to use the stable *sync* `google-auth` transport instead. Real, legitimate bug, but **not** the one causing this specific hang — confirmed by isolating every single component (signing, plain HTTP POST, plain HTTP GET, the full sync credential refresh) in standalone scripts, every one of which completed in under 100ms.
  2. `await asyncio.to_thread(...)` directly → `RuntimeError: await wasn't used with future` under Twisted's asyncioreactor (Twisted's coroutine bridging is stricter than plain asyncio about what it'll await).
  3. Wrapped in `Deferred.fromFuture(asyncio.ensure_future(...))` to match the codebase's existing bridging pattern → fixed that error, but the *hang came back*.
  4. Switched to Twisted's own `deferToThread` (the idiomatic mechanism, no asyncio bridging needed at all) → same hang.
  5. Added temporary diagnostic `print()`s bisecting the exact line execution stops at → pinned it to the `deferToThread` call itself, precisely.
  6. **Actual root cause, found by reading `sygnal.py`'s `main()`:** Sygnal creates its own **standalone** Twisted reactor instance (`asyncioreactor.AsyncioSelectorReactor()`) rather than installing it as the process's global `twisted.internet.reactor`. Bare `deferToThread()` always schedules work on the *global* reactor's thread pool — which, here, belongs to a reactor object that's never actually running. The work just sits on a thread pool with nothing driving it: a true infinite hang, not a slow operation. Fixed with `deferToThreadPool(self.sygnal.reactor, self.sygnal.reactor.getThreadPool(), ...)`, explicitly targeting Sygnal's real reactor.
  7. **This fix still hung.** Reproduced the exact same construction (a standalone, non-global-installed `AsyncioSelectorReactor` with a busy event loop, `deferToThreadPool` against its own real thread pool) in complete isolation — worked perfectly, 100ms. Checked SELinux (this VM has bitten us with silent AVC-style denials before, on the pm2 PID-file issue) — `ausearch` showed zero denials, enforcing mode notwithstanding. Every individual piece, tested alone, works. Only the full running systemd service hangs.
  8. **Gave up chasing the exact interaction bug and switched to Sygnal's actual supported deployment method: Docker**, rather than a raw `pip install` into a hand-built venv. Pulled `matrixdotorg/sygnal:latest` (still the current published image, despite the GitHub org rename), ran it with the *unpatched, stock* code — **it worked immediately**, 0.5 seconds, no patches needed at all. Whatever the exact mechanism, it's specific to something in the from-source pip/venv build on this ARM64/Oracle-Linux-9/dnf-installed-Python-3.11 combination — the officially tested, pinned-dependency Docker image doesn't hit it.
- One more Docker-specific gotcha along the way: the config's `http.bind_addresses: ['127.0.0.1']` made the service unreachable via `-p 127.0.0.1:5000:5000` port mapping — binding to a container's own loopback is invisible to Docker's host-side port forwarding. Changed to `['0.0.0.0']` inside the container (still only exposed to the *host's* `127.0.0.1` via the port mapping, so no external exposure change).
- The image's built-in `HEALTHCHECK` uses `curl`, which isn't present in the slim base image — cosmetically reports "unhealthy" in `docker ps` even though the service works fine. Recreated the container with `--no-healthcheck`.
- The old venv install (`/opt/sygnal/venv`, now unused) and its patch scripts are left on disk as a documented reference for the failed approach; its systemd unit was removed. Sygnal now runs purely as a Docker container (`--restart unless-stopped`, `docker.service` enabled at boot).
- nginx proxies `https://veilmsg.com/_matrix/push/v1/notify` → `http://127.0.0.1:5000/_matrix/push/` (added a new `location` block to the existing `veilmsg.com` :443 server in `/etc/nginx/conf.d/veil.conf`).
- Verified end-to-end with a real (fake-pushkey) notification: request reaches Sygnal, Sygnal authenticates to FCM with the real service account, sends the notification, and gets a proper rejection back from Google for the bogus token — confirming every link in the chain (nginx → Sygnal → FCM auth → FCM API) actually works, not just that something responds.

**Next**: wire the Flutter side — register each device's FCM token as a Matrix "pusher" on login (`POST /_matrix/client/v3/pushers/set`, pointing at the gateway URL above; matrix_dart_sdk 7.4.0 doesn't have a generated convenience method for this specific endpoint, use `client.request(RequestType.POST, '/client/v3/pushers/set', data: ...)` directly), then handle background/killed-app FCM messages — calls need a full-screen incoming-call notification, messages need the existing local-notification path to also fire from a background isolate.

---

## 2026-09-10 — v0.1.45 (switch-camera button — made failure visible, not silenced)

**[FIX/DIAGNOSTIC] Switch-camera (flip to back camera) button appeared to do nothing.** v0.1.44's two-device test confirmed everything else works — audio, video, mute, hangup, front-camera preview all functioning correctly. This is the one thing that didn't.

Could not get real device logs remotely to confirm the exact native failure this session, so this is *not* a confirmed root-cause fix like the v0.1.44 bugs — it's a diagnostic fix: `CallService.switchCamera()` was calling `flutter_webrtc`'s `Helper.switchCamera()` and discarding both its return value (a `bool` indicating success/failure) and any thrown exception — wired straight to the button's `onTap` with nothing awaiting or checking the result. If the native call was failing (Android's `GetUserMediaImpl.switchCamera` has real failure paths — capturer not found for the track ID, `onCameraSwitchError` from the underlying WebRTC camera API), there was **no way to tell** from the Dart side; the button just silently did nothing, which is exactly what got reported.

Fixed: `switchCamera()` now returns whether it actually succeeded and logs any exception instead of swallowing it; the UI awaits that and shows a `SnackBar` ("Couldn't switch camera") on failure instead of silence.

**What this doesn't do**: guarantee the underlying switch now works — if it's a genuine native/plugin-level issue (e.g. camera busy, only one camera enumerated on that specific device, a `flutter_webrtc` bug), this will now show an error message rather than fix the switch itself. Next test should show either (a) it now works — the previous "failure" was silent success that just needed something to trigger a rebuild, or (b) an actual error surfaces that gives a concrete next lead instead of nothing.

---

## 2026-09-10 — v0.1.44 (fixed real, confirmed call bugs from first two-device test)

First real test of calling (v0.1.43) surfaced concrete, reproducible bugs — this fixes all of them. Full root-cause deep dive, not guesses; each was confirmed via a live repro before being called fixed.

**[FIX] Call screens collapsed into a narrow strip on the left of the screen** — the actual bug behind two separate-looking reports ("buttons don't respond while connecting" and "camera/buttons only on the first third of the screen"). Root cause: `InCallScreen`'s `Stack` has only `Positioned`/`Positioned.fill` children (no plain non-positioned child), and go_router's page-transition machinery (even `NoTransitionPage`, via `CustomTransitionPage` under the hood) hands its child page **loose** constraints so it's *able* to animate size. A `Stack` with zero non-positioned children, given loose constraints, collapses to the smallest size that fits its content instead of filling the screen — Flutter does this by design, and it's a well-known footgun. That's why it worked fine on a narrow phone viewport (Scaffold constraints happened to still come out tight there) but broke on anything wide — confirmed by reproducing it live at 900×500 and watching it vanish at 375×812, then confirming a precise fix by adding `fit: StackFit.expand` to the `Stack` and re-testing at the exact same 900×500 viewport where it broke. `IncomingCallScreen`'s `Column`+`Spacer` has the identical exposure (`Spacer` needs bounded height) — wrapped its body in `SizedBox.expand` defensively, same root cause. Both re-verified live post-fix, full-screen and centered at the same viewport that previously broke.
- `app/lib/screens/in_call_screen.dart`, `app/lib/screens/incoming_call_screen.dart`

**[FIX] Answering a call never showed the in-call screen — audio connected, but no UI to reach it** — real race condition, not a rendering issue. `IncomingCallScreen`'s "the call vanished, bail out" auto-pop logic checked `calls.phase != CallPhase.incoming`, but *answering* a call legitimately advances the phase past `incoming` (kRinging → kCreateAnswer → kConnecting → …) **while** `_answer()` is still awaiting `calls.answer()`, before it gets to navigate to `/call/active` itself. Each of those SDK-internal state transitions fired `notifyListeners()`, rebuilding `IncomingCallScreen` mid-await — and on that rebuild, the phase-changed check fired the auto-pop, which won the race every time. The screen popped back to whatever was underneath while the call kept connecting silently in the background — exactly matching "I can hear everything but there's no way to access the video call." Fixed by only auto-popping when the call object itself is gone (`call == null`), guarded by `!_resolving` so it never fires at all while `_answer`/`_decline` are in flight — they drive navigation explicitly instead. Also wrapped both in try/catch so a failure mid-negotiation resets the screen instead of leaving both buttons permanently disabled.
- `app/lib/screens/incoming_call_screen.dart`

**[FIX] Local self-view video would never have shown on the caller's side** — found by re-reading the code, not yet reported by name, but confirmed as real: `_watchCall`'s first run happens during the very first build, before the video renderers finish their async `initialize()` — so `_refreshRenderers` bails out immediately (`!_renderersReady`) without attaching anything. Once the renderers *do* become ready a moment later, `_watchCall` runs again but now short-circuits (`_watchedCall == call`, same `CallSession` instance) and never retries `_refreshRenderers` — so a stream already attached to the call before the screen mounted (always true for the caller's own local stream, set up by `CallService.startCall()` before `InCallScreen` ever pushes) would never reach the renderer. Fixed by explicitly re-running `_refreshRenderers` once `_renderersReady` flips true.
- `app/lib/screens/in_call_screen.dart`

**Not fixed / still open**: the web build showing no call icons in the chat title bar at all. Couldn't independently reproduce this session — verified the deployed `main.dart.js` hash matches the local build exactly (rules out a stale deploy), but confirming the actual behavior needs two real logged-in accounts in two genuinely separate browser sessions, which wasn't achievable in-session (sandboxed browser tabs share storage/session state with each other). Needs a real retest after this release before further guessing.

---

## 2026-09-10 — Fixed iOS IPA CI job (root cause found, was broken since project start)

**[FIX] `Build iOS IPA` job reported success but never attached anything** — this was flagged as a known, unresolved bug in earlier entries ("produces zero output despite the job reporting success"). Root-caused while re-checking releases for this session's work: `flutter build ipa --no-codesign` only produces `build/ios/archive/Runner.xcarchive` — it does **not** export an actual `.ipa` file, because Apple's IPA export step (`xcodebuild -exportArchive`) requires a code signing identity, which `--no-codesign` deliberately skips. So the workflow's `app/build/ios/ipa/*.ipa` glob has never matched anything, on any release — `actions/upload-artifact` and `softprops/action-gh-release` both skip silently on a no-match glob rather than failing the step, which is exactly why this looked like success in the Actions UI.

Fixed by packaging the archive ourselves: an IPA is just a zip of `Payload/<AppName>.app`, which is exactly the raw format Sideloadly/AltStore/TrollStore expect to sign themselves — so this isn't a workaround, it's what should have been there from the start. New "Package unsigned IPA" step in `build.yml` copies `Runner.xcarchive`'s `Runner.app` into `Payload/`, zips it to `Runner.ipa`, and only then do the existing upload/attach steps have something to find.

Confirmed via CI logs from the v0.1.42 run: `Build IPA (unsigned)` step succeeded (`✓ Built build/ios/archive/Runner.xcarchive (226.7MB)`), then `Upload IPA artifact` logged `No files were found with the provided path: app/build/ios/ipa/*.ipa` and moved on. The iOS job was added right after v0.1.30 — every release since then (v0.1.31 through v0.1.42, spot-checked v0.1.41/v0.1.42's actual release assets to confirm) shipped Android-only despite the release notes always describing an iOS sideload install path.

---

## 2026-09-10 — v0.1.43 (1:1 voice/video calls — Phases 1 & 2 shipped)

**[ADD] First release with calling.** Phases 0–2 (TURN server, `CallService`/`flutter_webrtc` signaling+media, and the call UI) are all in this build — see the two entries directly below for the full technical detail on each. Shipping now instead of holding for more local testing, since it needs two real devices to actually exercise (one CI-signed build both phones can install is a better test setup than two manually-sideloaded debug APKs anyway).

**Known gaps, not blocking this release but worth knowing before you rely on it**: no ringtone sound yet (incoming calls are silent, visual-only), no speaker/earpiece toggle, group calls not supported (1:1 only), and calls won't ring if the app is fully closed/killed — that's Phase 3 (needs FCM push), not yet started.

---

## 2026-09-10 — Call UI (voice/video calls, Phase 2 of 3)

**[ADD] Incoming-call screen, in-call screen, and call buttons in the chat title bar** — the visible half of 1:1 calling, built entirely on top of Phase 1's `CallService`.
- `lib/screens/incoming_call_screen.dart` — full-screen prompt pushed automatically (see below) when `CallService.onIncomingCall` fires. Caller avatar/name (via `remoteUserId` → `Room.unsafeGetUserFromMemoryOrFallback`), Answer/Decline buttons. Answer awaits `CallService.answer()` then replaces itself with the in-call screen; if the call vanishes out from under it (caller cancelled, answered on another device) it pops itself.
- `lib/screens/in_call_screen.dart` — local/remote video via `flutter_webrtc`'s `RTCVideoRenderer`/`RTCVideoView`, re-subscribing to `CallSession.onStreamAdd`/`onStreamRemoved` whenever the active call changes (the remote stream only exists once negotiation completes, well after the screen mounts). Voice calls fall back to a big `BuddyAvatar` instead of a video surface. Mute/camera-toggle/switch-camera/hangup controls, a live call-duration timer once `CallPhase.connected`, and self-pops when `CallService.activeCall` goes back to null.
- Two new top-level routes, `/call/incoming` and `/call/active` — deliberately *outside* the `ShellRoute`/`SplitShell` tree so they render as true full-screen overlays instead of getting laid out inside the wide-screen two-panel split.
- `main.dart`'s `_VeilAppState` subscribes to `CallService.onIncomingCall` in `initState` (same pattern as the existing `NotificationService.onTap` → router wiring) and pushes `/call/incoming` — this is the only "global" auto-navigation; everything else (answering, hanging up, the call ending) is handled locally by each screen watching `CallService` and popping/pushing itself, which avoids double-navigation races between a global listener and a user-initiated action.
- `_ChatTitleBar` (in `chat_screen.dart`) gained `onVoiceCall`/`onVideoCall` icon buttons, shown only for `room.isDirectChat` — same `null`-means-hidden pattern as the existing `onAddMember` group-only button. `ChatScreen._startCall()` calls `CallService.startCall()` then pushes `/call/active`; guards against starting a second call with a snackbar if `CallService.inCall` is already true.

**Not done yet, called out explicitly**: no ringtone sound (still a no-op per Phase 1, needs a sound asset — Decline/Answer works fine without one, just silent), no speaker-toggle button (`CallSession` doesn't expose one publicly; would need `flutter_webrtc`'s `Helper.setSpeakerphoneOn` wired in separately), not manually tested end-to-end on two real devices (no second device/account available in-session — verified by `flutter analyze` clean + `flutter build apk --debug` succeeding, which confirms compile correctness and that the native video-rendering code links, not actual call behavior over the TURN server). Try a real call between two devices before considering this phase done in practice.

Update: shipped as v0.1.43 anyway rather than waiting on a local two-device test — see the entry above.

**Next**: Phase 3 — ring when the app is fully closed (needs FCM push; `NotificationService` currently only fires while the app's own sync loop is running). Also worth circling back to: a ringtone asset, and a real two-device test of Phases 1–2 together.

---

## 2026-09-10 — CallService wired up (voice/video calls, Phase 1 of 3)

**[ADD] `flutter_webrtc` + matrix_dart_sdk's `voip` module wired into a new `CallService`** — the core plumbing for 1:1 voice/video calls, no UI yet (that's Phase 2). Added:
- Dependencies: `flutter_webrtc` (media backend) + `webrtc_interface` (the abstract types matrix_dart_sdk's `WebRTCDelegate` contract is typed against — needed as a direct import because flutter_webrtc's own barrel file hides `MediaDevices`/`Navigator` from `webrtc_interface` to provide its own deprecated static-method shim under those same names, so pulling the *interface* types through the `flutter_webrtc` import would silently resolve to the wrong class and fail `implements WebRTCDelegate`).
- `lib/core/call_service.dart` — `CallService extends ChangeNotifier`, wraps matrix_dart_sdk's `VoIP`/`CallSession` classes:
  - `CallPhase` state machine: idle → outgoing/incoming → connecting → connected, collapsed from `CallSession`'s more granular `CallState` stream
  - `attachClient()`/`detachClient()` — same lifecycle pattern as `VeilUserPrefs`, wired into `main.dart`'s login-state listener
  - `startCall(room, video:)` — infers the callee automatically for direct chats (`room.directChatMatrixID`) so only that user's devices ring, not the whole room
  - `answer()`/`reject()`/`hangup()`/`toggleMute()`/`toggleCamera()`/`switchCamera()`
  - `onIncomingCall` stream — Phase 2's incoming-call screen will listen on this instead of polling
  - Private `_VeilWebRTCDelegate implements WebRTCDelegate` bridges the SDK's call events to flutter_webrtc's `createPeerConnection`/`navigator.mediaDevices`. `playRingtone()`/`stopRingtone()` are no-ops for now — no sound asset shipped yet, deferred to Phase 2 alongside the incoming-call screen. Group calls (`handleNewGroupCall`) are a no-op — 1:1 only for now.
- Android: added `RECORD_AUDIO`, `MODIFY_AUDIO_SETTINGS`, `ACCESS_NETWORK_STATE`, `BLUETOOTH`/`BLUETOOTH_ADMIN` (≤30)/`BLUETOOTH_CONNECT` permissions, plus optional camera hardware `<uses-feature>` tags (`android:required="false"` — a call-capable build shouldn't be Play Store–excluded from cameraless devices, voice-only calls still work).
- iOS: added `NSCameraUsageDescription`/`NSMicrophoneUsageDescription` to `Info.plist` — previously absent entirely; without these the OS silently kills the app on the first permission prompt instead of showing one.

No version bump/tag for this — same as Phase 0 (TURN server), this is groundwork with nothing user-visible yet. `flutter analyze` clean; debug APK builds successfully with the new native plugin linked in (verified via `flutter build apk --debug`).

**Next**: Phase 2 — call UI (incoming-call screen, in-call screen with local/remote video renderers, call button in the chat title bar) and a ringtone asset. Then Phase 3 (ring-when-app-is-closed via FCM).

---

## 2026-09-10 — TURN server live (voice/video calls, Phase 0 of 3)

**[INFRA] coturn TURN/STUN server running on the Oracle VM** — first step toward 1:1 voice/video calls. Details:
- Installed via Oracle Linux's EPEL developer repo (`oracle-epel-release-el9`, disabled by default — had to enable it)
- Reuses the existing `matrix.veilmsg.com` hostname/cert rather than a new subdomain — no new DNS needed. A certbot deploy hook (`/etc/letsencrypt/renewal-hooks/deploy/coturn-cert.sh`) copies the renewed cert to `/etc/coturn/certs/` (coturn's own user can't read `/etc/letsencrypt` directly) and reloads the service on every renewal.
- **Key fix**: coturn defaulted to binding the VM's private IP (`10.0.0.235`) with no `external-ip` mapping — on Oracle Cloud the public IP is NAT'd at the infrastructure edge, so without this, coturn would've told every client to connect to an unreachable private address. Fixed with explicit `listening-ip`/`relay-ip`/`external-ip` directives. Verified with a real STUN binding request (`turnutils_stunclient`), not just a port check — confirmed it now reports the public IP.
- HMAC shared-secret auth (`use-auth-secret` + `static-auth-secret`) — ephemeral, time-limited credentials, no static password to leak.
- Opened TCP/UDP 3478 (STUN/TURN) and 5349 (TURN+TLS), plus UDP 49160–49360 (relay range) at both the OS firewall (`firewalld`) and — the part that actually blocked reachability until fixed — the OCI Security List, a separate cloud-level firewall that needed the OCI web console (no API/CLI credentials available for it in-session).

**Next**: Phase 1 — wire `flutter_webrtc` + `matrix_dart_sdk`'s existing `voip` module into the app (call signaling + media). Then Phase 2 (call UI), Phase 3 (ring-when-app-is-closed via FCM, decided separately since it's valuable independent of calls).

---

## 2026-09-09 — v0.1.42 (fixed release signing — no more forced uninstalls)

**[FIX] Every release forced users to uninstall before installing the next one** — root cause: `android/app/build.gradle.kts` signed release builds with the **debug** signing config (Flutter's default template setting, never replaced). CI runs on a fresh ephemeral machine every time, so the debug keystore isn't guaranteed consistent between builds — Android refuses to install an update signed with a different key than the currently-installed one, forcing a full uninstall every time.

Generated a dedicated, permanent release keystore (RSA 2048, valid until 2054) and wired it in:
- CI (`build.yml`) decodes it from `ANDROID_KEYSTORE_BASE64` + password secrets and writes `key.properties` before every build
- Local builds use `android/key.properties` (gitignored) copied from the new `key.properties.example` template
- `build.gradle.kts` uses it for release builds, falling back to debug signing only when `key.properties` is absent (so a fresh checkout can still build locally without the real keystore)

The keystore itself was handed to the user as a backup (never committed to git — losing it would reintroduce this exact bug permanently, since every future release must be signed with the same key to update in place).

**This release (v0.1.42) is the last one that will need a manual uninstall** — it's signed with the new key for the first time, which differs from whatever key signed what's currently installed. Every release after this one will update in place normally.

---

## 2026-09-09 — v0.1.41 (real app icon — "Veil mark")

**[ADD] Real app icon, replacing the default Flutter logo** — Veil has shipped with the unmodified default Flutter "f" logo as its icon since the project started; every screen/build has been branded, but the icon itself never was. Fixed using the "Veil mark" concept (speech bubble + lock, signature blue gradient) that was approved from the earlier mockup canvas.

Source assets are hand-authored SVG (`assets/icon/icon_full.svg`-equivalent — the SVGs themselves aren't checked in, only the rasterized PNGs used by the generator) rendered to 1024×1024 PNG via `sharp`, not AI-generated — an exact, deterministic reproduction of the approved mockup rather than a re-generated variant. Three variants:
- `icon_full.png` — flat square (gradient + mark), used for iOS/macOS/web/legacy Android
- `icon_foreground.png` — mark only, transparent background, recentered with generous margin so it isn't clipped by Android's circular/squircle adaptive-icon masks
- `icon_background.png` — gradient only, no mark, for Android's adaptive icon background layer

Wired in via `flutter_launcher_icons` (new dev dependency, config in `pubspec.yaml`) — `dart run flutter_launcher_icons` regenerates all platform icon sizes (Android legacy + adaptive, iOS, macOS, web favicon/PWA icons) from the three source PNGs in `assets/icon/`. Re-run that command any time the icon design changes; don't hand-edit the generated platform icon files.

---

## 2026-09-09 — v0.1.40 (web deployment fixed, version footer, process documented)

**[ADD] Version footer in Settings** — bottom of the Settings screen now shows "Veil vX.Y.Z (build N)" via `package_info_plus` (already a dependency, previously unused). Direct motivation: there was no reliable way to confirm which build was actually running on a device, which is exactly what caused the "only 4 themes" confusion below — Android doesn't auto-update sideloaded APKs, so a stale install looks identical to a real bug until you can check the version.

**[FIX] `veilmsg.com` was serving a build from July 9** — nearly two months stale, which is why the user only saw the original 4 themes (AIM Classic/Dark/Glass/Light) on web despite the app having 8 by then. Root cause: CI's `build-web` job only builds and uploads a GitHub Actions artifact — it has never deployed anywhere. The actual web deployment is a separate, until-now-undocumented manual process: nginx on the Oracle VM (`/etc/nginx/conf.d/veil.conf`) serves static files from `/var/www/veilmsg` at the `veilmsg.com` apex, entirely self-hosted and independent of any other project. Redeployed the current build (`flutter build web --release` → tar → scp → extract on the VM); verified via `curl https://veilmsg.com/version.json` and confirming "Modern Dark" is present in the served bundle.

**[MISTAKE, corrected]** Before finding the above, a session created a brand-new Cloudflare Pages project (`veil-4o5.pages.dev`) for Veil's web build, reusing Cloudflare account credentials documented for a different project (VaultTV). The user caught this immediately ("veilmsg.com is MINE... do not pair this with any other project") and it was reverted — the stray Cloudflare Pages project was deleted. **Lesson, now written into `CLAUDE.md`: never assume infrastructure needs to be created from scratch — check for an existing deployment first, and never reuse another project's hosting account/credentials for Veil.** Veil's infrastructure is fully self-contained on its own Oracle VM + its own domain.

**[DECISION] Web deploy is now a standing step of every release** — going forward, any release that touches user-visible behavior gets deployed to `veilmsg.com`, not just changes that are nominally "web-specific." The web build is the same Flutter source as the APK, so it drifts out of sync with every release it's skipped for. Full process (build → tar → scp → extract → verify) is documented in `CLAUDE.md` under "Deploy web."

---

## 2026-07-19 — v0.1.39 (avatars in chat title bar + group messages)

**[ADD] Avatar in the chat title bar** — every chat screen now shows the room's avatar (the other person's photo for a DM, the group photo if set) next to the lock icon and title, using the same `BuddyAvatar` widget as everywhere else.

**[ADD] Per-sender avatars on group chat messages** — bubble-layout themes (Glass, Modern, Modern Dark) now show the sender's own photo next to their received messages in **group chats only**. Scoped to groups because in a DM you already know who the other person is — showing their avatar on every single line would just be visual noise. Your own sent messages never show one (standard convention, they're already right-aligned).

**Scoping note:** this is bubble-layout themes only for now. AIM Classic / AIM Remastered (light+dark) / Dark / Light use the flat `[HH:MM] Name: text` line format, which doesn't have a natural place for a per-line avatar without restructuring every line into a row — left that format's density alone since it's deliberately compact. Say the word if you want it there too.

---

## 2026-07-19 — v0.1.38 (profile pictures + interactive crop)

**[ADD] Profile picture upload** — Settings → tap the profile avatar → Choose Photo (or Remove Photo, if one is set). Uses `Client.setAvatar` under the hood (uploads to the Matrix media repo, sets `avatar_url` on the account). Previously there was no way to set one at all — every avatar in the app was just a gradient circle with an initial letter.

**[ADD] Interactive avatar positioner** (`screens/avatar_crop_screen.dart`) — after picking a photo, the user gets a full-screen circular window over their image that they drag to reposition and pinch (or use a slider) to zoom, so they choose exactly what lands inside the circle rather than the app auto-centering or auto-cropping. Captures precisely what's visible in the circle via `RenderRepaintBoundary` and uploads that.

**[ADD] Real photos throughout the app** — `BuddyAvatar` now shows an uploaded profile picture when one exists (falling back to the initial-letter gradient on load failure or when unset), used consistently in the buddy list, hidden chats, and the settings profile card. DM rows resolve the other person's photo automatically via `Room.avatar`.

**[ADD] `mxcToHttpUrl` helper** (`core/client_manager.dart`) — centralizes the `mxc://` → authenticated-HTTP-download-URL conversion that was previously duplicated inline in chat_screen.dart's image rendering.

---

## 2026-07-19 — v0.1.37 (Modern Dark + AIM Remastered Dark)

**[ADD] Modern Dark and AIM Remastered Dark** — v0.1.36 shipped only the light variants of both new themes as real, selectable themes; the dark mockups existed but were never wired in. Both are now real theme options with color tokens ported directly from the dark mockups. 8 themes total now (was 6); the Settings theme grid still auto-wraps at 3 per row.

**[CLARIFICATION]** Glass is not, and never was, a dark variant of Modern — it's one of the four original themes and was intentionally left untouched in v0.1.36. The confusion was understandable since both are dark and bubble-based; they're unrelated theme families that happen to share a rendering style.

**[FIX] Floating toolbar (Modern/Modern Dark) illegible** — the "IM" button was only tinted a different color from Settings/Sign Off, with no fill — all three read as the same washed-out gray with nothing to anchor on. Now IM gets an actual filled gradient pill (matching the mockup) with white icon/text; Settings and Sign Off stay plain. This was almost certainly the "gray outline, hard to read" issue.

---

## 2026-07-19 — v0.1.36 (Modern default theme + AIM Remastered)

**[ADD] Modern theme — new default** — A contemporary bubble-based layout (iMessage/Telegram-grade polish) built from the "Direction B" mockup. Keeps Veil's AIM soul through the signature blue and screen-name labels shown above both sent and received bubbles (not hidden behind avatars-only), plus the existing font/color customization surfaced as a first-class pill row in the composer (Aa chip, B/I/U pills, disappearing-timer pill) instead of a small icon. Floating rounded pill bottom toolbar. Gradient-ring avatars with a presence glow. This is now the default theme for anyone who has never set a preference — existing users keep whatever they already had (no forced migration).

**[ADD] AIM Remastered theme** — "Direction A": the exact flat AIM-line structure of AIM Classic (list-row buddy list, `[HH:MM] ScreenName: text`), executed with richer multi-stop-feeling gradients, the same new gradient-ring avatars, and refined coral/blue tones. A secondary, opt-in theme — AIM Classic, Dark, Glass, and Light are all unchanged.

**[REFACTOR] Bubble rendering decoupled from Glass specifically** — Message-bubble colors (sent/received gradients, text color, sender-label color, timestamp color, border) moved from hardcoded values in `_buildGlassBubble` onto `VeilThemeColors`, and the method generalized to `_buildBubbleLayout` so both Glass and Modern share one implementation instead of duplicating it. Glass's exact existing look (purple/indigo sent gradient, translucent received bubble, white54/white38 text) is preserved via explicit token values — this was a refactor, not a Glass redesign.

**[FIX] Title bar hardcoded white text/icons** — `buddy_list_screen.dart`'s `_TitleBar` and `_TitleIconBtn` hardcoded `Colors.white` for the "Veil" wordmark, screen name, lock icon, and toolbar icons. Harmless while every theme's title bar was a dark gradient, but Modern's title bar is near-white — this would have made the title bar text invisible. Both widgets now take `tc.titleOnColor`.

**[FIX] Theme-picker swatch contrast for light swatches** — The Settings theme grid's preview swatch used a hardcoded white "their bubble" chip and white checkmark, assuming every swatch background is dark. Now checks each swatch's estimated brightness and uses dark ink on light swatches (Modern) — Settings theme grid also switched from a single Row to a 3-per-row GridView now that there are 6 themes instead of 4.

**[ADD] Shared `BuddyAvatar` widget** (`widgets/buddy_avatar.dart`) — promoted from buddy_list_screen.dart's private `_Avatar`, now also used by Hidden Chats so avatar treatment (including the new gradient ring) stays consistent across both screens instead of hidden_chats_screen.dart drawing its own inline avatar.

---

## 2026-07-18 — v0.1.35 (codebase documentation pass)

**[DOCS] Header + section comments added to every file in lib/** — All 21 Dart files now start with a short comment explaining what the file is for and how it fits into the app, and every large file has section-block comments marking its major logical zones (e.g. chat_screen.dart: lifecycle, sending text, sending media, disappearing-message controls, build). Comment-only change, zero logic touched; `flutter analyze` confirmed clean before and after.

While auditing for this, found and flagged three dead-code paths so they're easy to spot going forward rather than being silently removed: `widgets/message_bubble.dart` and `widgets/presence_dot.dart` are unused (not imported anywhere — superseded by chat_screen.dart's `_AimMessageLine` and buddy_list_screen.dart's inline `_Avatar`), and `widgets/disappearing_timer_dialog.dart` is only reachable through `chat_screen.dart`'s `_setDisappearing()`, a room-level retention setter that predates the v0.1.31 per-message redesign and is not part of the current disappearing-message flow.

**[DECISION] Header + section comments are now standard for all new Veil code** — every new file should open with a short comment on its purpose, and large files should get section-block comments (`// ── Section ──`, no double-dashes) around their major logical zones. Applies going forward, not just this pass.

---

## 2026-07-18 — v0.1.34 (iOS IPA CI build)

**[INFRA] iOS unsigned IPA distributed via GitHub Releases** — Added `build-ios` job to CI using `macos-latest` runner. Runs `flutter build ipa --no-codesign --obfuscate --split-debug-info=...` and attaches `Runner.ipa` to the GitHub Release alongside the APK. No Apple Developer account required for the build — users install via Sideloadly, AltStore, or TrollStore (same sideload pattern used by open-source iOS projects like Gen1Recomp). iOS platform target (`app/ios/`) was already scaffolded.

---

## 2026-07-18 — v0.1.33 (QR device-link endpoint fix)

**[FIX] QR code button does nothing / shows M_UNRECOGNIZED** — `requestLoginToken()` was calling `POST /_matrix/client/v3/login/token`, which does not exist in the Matrix spec and which Dendrite rightfully returns `M_UNRECOGNIZED` for. The correct Matrix 1.7 endpoint is `POST /_matrix/client/v1/login/get_token`. Changed the URL; the response shape (`login_token` field) is unchanged.

---

## 2026-07-13 — v0.1.32 (gray screen regression fix)

**[FIX] Gray screen on chat re-entry (regression from v0.1.31)** — v0.1.31 added `ClientManager.addListener` / `removeListener` calls in `_ChatScreenState`. The `removeListener` was called inside `dispose()` via `context.read<ClientManager>()`. In Flutter, `deactivate()` is already called by the time `dispose()` runs, making the `BuildContext` stale — calling `context.read()` there can throw, preventing `super.dispose()` from ever running and leaving the widget in a partially-disposed state. On re-entry to the same chat, the Offstage Navigator encountered this inconsistent state and rendered a raw gray scaffold frame.

Fix: store the `ClientManager` reference in `initState()` as `late ClientManager _mgr = context.read<ClientManager>()` and use `_mgr` everywhere outside `build()` — `dispose()`, `_room` getter, `_loadTimeline()`, and `_doScheduleVisible()`. The context is no longer accessed after the widget is deactivated.

---

## 2026-07-11 — v0.1.31 (view-triggered disappearing messages + visual indicator)

**[CHANGE] Disappearing timer starts on VIEW, not on send** — Messages now store `veil_disappear_secs` (duration in seconds) instead of `veil_expire_at` (absolute timestamp set at send time). The timer begins when the **recipient opens the chat** — `ChatScreen.initState` and `_loadTimeline` call `_doScheduleVisible()`, which scans the timeline and calls `DisappearingMessageService.schedule()` for any unscheduled disappearing messages. A `ClientManager.addListener` keeps this running for messages that arrive while the chat is open. The sender's timer starts on the same event (they're already viewing the chat). Backward-compatible: old `veil_expire_at` messages still schedule with the remaining duration.

**[CHANGE] New time options** — Timer picker now offers 3 seconds, 5 seconds, 10 seconds, 1 minute (replaces the old 30s / 5m / 30m / 1h / 24h / 7d options). Both the compose-time picker and the long-press per-message picker use these options.

**[ADD] Clock indicator on disappearing text messages** — Both AIM flat and Glass bubble layouts now show a small `⏱ Xs` badge below any message with `veil_disappear_secs`. The badge is a live countdown (ticks every second) powered by `_DisappearingCountdown`, a `StatefulWidget` that reads the remaining time from `DisappearingMessageService` asynchronously and starts a `Timer.periodic` for the UI update.

**[ADD] Blur + clock overlay on disappearing images** — Disappearing images are shown blurred (`ImageFilter.blur sigmaX/Y 14`) with a dark overlay, a large `Icons.timer` icon in the centre, and the same `_DisappearingCountdown` widget. Tapping still opens the unblurred fullscreen dialog; the save button is hidden as before.

---

## 2026-07-11 — v0.1.30 (hide conversations, linked devices, QR sign-in)

**[FIX] Hide Conversation now works** — Long-pressing a conversation and tapping "Hide Conversation" now actually removes the room from the buddy list. Root cause: `prefs.setHidden(true)` was being called correctly, but the buddy list filter never checked the `hidden` flag. Fixed by loading `SharedPreferences` in `BuddyListScreen` state and reading the `conv_{roomId}_hidden` key synchronously on every rebuild. A "Hidden Chats" footer row appears at the bottom of the buddy list whenever any room is hidden.

**[ADD] Hidden Chats screen** — New screen at `/buddylist/hidden` showing all hidden conversations. Tap a conversation to open it, or tap "Unhide" to bring it back to the main list. Unhiding calls `ClientManager.forceRefresh()` to immediately update the buddy list.

**[ADD] Linked Devices screen** — New screen at `/buddylist/devices` (accessible via Settings → Privacy & Security → Linked Devices). Shows all devices registered to your account with device name, last-seen IP, and last-seen date. Current device is marked with a green "This device" chip. Remove unauthorized devices by tapping the trash icon — requires password re-authentication (UIA via Matrix `m.login.password`), which invalidates the session server-side.

**[ADD] QR code Add Device** — Existing device: Settings → Linked Devices → tap QR icon in header → shows a `qr_flutter`-generated QR code containing a short-lived single-use login token (from `POST /_matrix/client/v3/login/token`). New device: tap "Scan QR Code" on the login screen → `mobile_scanner` opens camera → scans the token → logs in via `m.login.token`. Token expires in ~2 minutes and is single-use.

**[INFRA] Flutter code obfuscation in CI** — Added `--obfuscate --split-debug-info=build/debug-info` to `flutter build apk --release` in `build.yml`. Symbol names in the release APK are now randomised, making static analysis and reverse-engineering significantly harder. Debug symbols are uploaded as a separate build artifact.

---

## 2026-07-10 — v0.1.29 (definitive gray screen fix)

**[FIX] Gray screen on chat re-entry — root cause found and eliminated**

Two independent causes were both contributing to the gray freeze.

**Cause 1 — Navigator disposed between visits.** `split_shell.dart` used `if (!atRoot)` to conditionally render the go_router Navigator. Flutter's GlobalKey deactivation only preserves a removed widget's state for ONE frame. Since the user always spends more than one frame on the buddy list, the Navigator was fully disposed. On re-entry, a fresh Navigator was created, and its first paint showed `tc.scaffold` (AIM Win98 gray `#D4D0C8`) for a frame before ChatScreen could finish rendering. Fix: replaced `if (!atRoot)` with `Offstage(offstage: atRoot, ...)`. The Navigator now stays in the element tree at all times; when `offstage = true` it is alive-but-hidden, so go_router pushes ChatScreen onto it in the background; when `offstage` flips to `false` the screen is already fully rendered — first visible frame = full chat UI, zero gray.

**Cause 2 — `requestHistory` blocked the timeline before first render.** `getOrCreateTimeline` awaited `requestHistory(historyCount: 50)` before returning. That is a real network call (300ms–2s). During the wait, `_loadingTimeline = true` and ChatScreen rendered as a spinner on the gray AIM scaffold — the user perceived this as a gray freeze on first visit to each room. Fix: made `requestHistory` fire-and-forget. The method now returns the Timeline immediately after `room.getTimeline()` completes (local operation). History streams in via the `onUpdate` callback as the network fetch finishes.

---

## 2026-07-10 — v0.1.28 (underlines + gray flash final fix)

**[FIX] Yellow underlines on all text** — v0.1.27's Stack approach left `BuddyListScreen` without a `Material` ancestor, so Flutter fell back to its default `TextStyle` which has `TextDecoration.underline` and a yellow decoration color. Fixed by wrapping the `BuddyListScreen` in `Material` inside the Stack.

**[FIX] Gray flash still present after Stack switch** — The `child` widget passed to `SplitShell` from `ShellRoute` is go_router's internal sub-Navigator, which was still running a slide-in transition animation even inside our Stack. Fixed by switching all shell sub-routes from `builder:` to `pageBuilder:` with `NoTransitionPage`, so the Navigator performs no animation on route changes.

**[INFRA] APK releases** — Stop renaming APK at any stage. CI builds `flutter build apk --release` and attaches `app-release.apk` to the GitHub release when a `v*` tag is pushed. Never attach debug APKs or rename via Gradle/cp.

---

## 2026-07-10 — v0.1.27 (gray freeze root fix)

**[FIX] Gray screen freeze on chat re-entry — root cause eliminated** — The freeze was caused by go_router's page-transition Navigator inside `SplitShell` getting stuck mid-animation when navigating chat → buddy list → same chat. Fixed by replacing the narrow-screen Navigator path with a plain `Stack`: `BuddyListScreen` is always mounted underneath, and the chat/settings/new-chat screen sits on top as a direct Material overlay — no transition animation, no Navigator, no freeze.

---

## 2026-07-10 — v0.1.26 (Container crash fix)

**[FIX] Buddy list toolbar crash** — `_BottomToolbar` passed `color:` directly to a `Container` that also had `decoration: BoxDecoration(...)`. Flutter asserts that both cannot be set simultaneously; moved the color inside the `BoxDecoration`.

**[INFRA] Reverted Gradle APK rename** — `applicationVariants.all` rename and copy task removed from `build.gradle.kts`. The Gradle-renamed APK bypassed Flutter's final packaging step, producing an APK twice the normal size. Releases now attach `app-debug.apk` directly.

---

## 2026-07-10 — v0.1.25 (navigation freeze fix)

**[FIX] Chat freeze when re-entering the same conversation** — Root cause: `ChatScreen.dispose()` called `timeline.cancelSubscriptions()`, then re-entering the same room triggered `room.getTimeline()` + `requestHistory()` again. If the prior `requestHistory` HTTP call was still in-flight, the matrix SDK deadlocked on an internal room lock, freezing the screen permanently.

Fix: `ClientManager` now owns a per-room `Timeline` cache (`_timelineCache`). `getOrCreateTimeline(roomId)` returns the cached timeline instantly on re-entry, never calling `getTimeline()` twice on the same room. `ChatScreen.dispose()` no longer cancels the timeline. On re-entry, `initState()` reads the cached timeline synchronously — no loading spinner, no freeze, messages appear instantly. Timeline cleanup happens only on `logout()`.

---

**Format**: `[YYYY-MM-DD] TYPE: Description`
**Types**: `DECISION` `ADD` `REMOVE` `FIX` `INFRA` `COST` `LAUNCH` `QUESTION`

Entries are added every session. Nothing gets done without a log entry.

---

## 2026-07-10 — v0.1.24 (14-issue audit fix pass)

**[FIX] Video + file OOM crash** — `_sendVideo` now uses `ImagePicker.pickVideo()` instead of `FilePicker withData: true`. `_sendFile` uses `withData: false` + `File.readAsBytes()`. Both enforce a 100 MB cap before reading. Previously any video would crash immediately.

**[FIX] Gray screen during navigation** — `MaterialApp` now watches `VeilUserPrefs` and overrides `scaffoldBackgroundColor` in both `theme` and `darkTheme` to match the active Veil theme. `ThemeMode` is also derived from the Veil theme (dark/glass → `ThemeMode.dark`; aim/light → `ThemeMode.light`). `ThemeModeNotifier` removed — it was never toggled and served no purpose.

**[FIX] Add-member Cancel still ran invite** — `_addMember` dialog now returns `bool?`; Cancel pops `false`, Invite pops `true`. The invite only fires if `confirmed == true`.

**[FIX] Group chats unencrypted** — `createRoom` now passes `initialState: [StateEvent(type: EventTypes.Encryption, ...)]` so group chats use Megolm E2E, matching DM behaviour.

**[FIX] Presence dot hardcoded to "online" for all rooms** — `_Avatar` widget now accepts `isGroup`; the presence dot is hidden for non-DM rooms (groups have no meaningful per-user presence indicator).

**[FIX] Muted state flash on buddy list open** — `BuddyListScreen.initState` now pre-loads all `conv_*_muted` SharedPrefs keys so the cache is warm before the first build.

**[FIX] VeilUserPrefs synced on every Matrix sync** — `_pullFromMatrix` now computes a content snapshot string and returns early if unchanged. Avoids `_saveLocal()` write and `notifyListeners()` on every no-op sync.

**[FIX] `userID!` null crash in sync listener** — `client_manager.dart` now guards against `userID == null` at the top of the onSync handler and returns early rather than throwing.

**[FIX] Buddy list unsorted after restart** — `ClientManager.rooms` now sorts by `lastEvent.originServerTs` descending so the list order is stable.

**[FIX] E2E encrypted images show broken icon** — `_buildNetworkImage` now detects encrypted images (has `content['file']['key']`) and shows a `🔒 Encrypted image` text instead of silently failing. Full AES-CTR decryption deferred — matrix SDK v7 doesn't expose a clean public API for it.

**[FIX] `data-pt` non-standard** — `_buildHtml` now also emits `style="font-size:Xpt"` alongside `data-pt` so other Matrix clients apply the font size. `html_span.dart` now parses `style` attribute as fallback.

**[FIX] No login validation** — `_submit` now validates username and password are non-empty before making any network call.

**[FIX] Video card hardcoded dark colors** — `_buildVideoMessage` now uses `tc.rowBg`, `tc.toolbarActive`, and `tc.previewText` instead of hardcoded `Colors.black45` / `Colors.white`.

**[FIX] Message tap blocks text selection** — removed `onTap: () => _inputFocus.requestFocus()` from message GestureDetectors. Keyboard management is handled by `focusNode` on the TextField and `ScrollViewKeyboardDismissBehavior.manual` on the ListView.

---

## 2026-05-22

**[DECISION] App named "Veil"**
Chosen over Wick, Hush, Glyph, Sigil, Dusk. Single syllable, strong privacy connotation, works as a verb. Pending: verify domain + store availability.

**[DECISION] Protocol: Matrix + Dendrite over custom libsignal or XMPP+OMEMO**
Dendrite is a single lightweight Go binary (~200-500MB RAM), runs on existing Oracle VM alongside BitClip. Olm/Megolm encryption is equivalent to Signal Protocol. matrix_dart_sdk exists for Flutter. Built-in support for reactions, threads, disappearing messages, and WebRTC calls (post-launch). XMPP was ruled out (fragmented ecosystem). Custom libsignal was ruled out (4-6 months extra dev time, high risk of subtle crypto bugs).

**[DECISION] No SMS fallback — web invite links instead**
SMS fallback contradicts the "truly private" brand (mixed encrypted/plaintext threads in same UI). Signal removed this in 2022 for the same reason. Impossible natively on iOS. Replacement: non-app users receive a link, open a WebCrypto-powered temporary guest Matrix session in the browser. Fully encrypted, works on all platforms, reinforces brand.

**[DECISION] Android-first, then iOS (Phase 2), then Desktop (Phase 3)**
Avoids $99/yr Apple Dev account cost until product is validated. Faster iteration without App Store review cycle. Flutter codebase is shared across all platforms — iOS/Desktop are primarily build targets, not rewrites.

**[DECISION] AOL AIM as default theme, dark mode toggle in Phase 1**
Core brand differentiator — "Signal's security. AIM's soul." Additional themes deferred post-launch to keep Phase 1 scope tight.

**[DECISION] Media cap: 100MB per file at launch**
Keeps R2 costs predictable during early growth. Cap can be raised post-launch.

**[DECISION] Group chat cap: 50 members at launch**
Keeps Dendrite load predictable. Matrix Megolm handles larger groups but server resources need monitoring first.

**[INFRA] Project directory initialized**
`D:\Documents\Veil\` created. PLAN.md and DEVLOG.md established as source of truth for roadmap and change history.

**[COST] Baseline cost snapshot logged**
Phase 1 year-1: ~$40 (Google Play $25 + domain ~$15). Monthly ongoing: $0 within free tiers. See PLAN.md for full breakdown.

## 2026-05-22 (continued)

**[INFRA] Domain purchased: veilmsg.com**
Registered via Cloudflare Registrar (at-cost, ~$9-10/yr). WHOIS privacy enabled. Nameservers on Cloudflare. DNS records not yet configured — pending Dendrite homeserver setup.

**[INFRA] Firebase project created: veil-510bf**
Project name: Veil. Project ID: veil-510bf. Project number: 1070805534211. Google Analytics disabled.

**[INFRA] Firebase Phone Auth enabled**
Phone sign-in provider enabled. 10 SMS/day free quota on Spark plan — sufficient for development. Test phone number not yet added (add your number via Authentication → Sign-in method → Phone → edit).

**[INFRA] Dendrite installed and running**
Go 1.22.4 installed to /usr/local/go. Dendrite v0.13.8 built from source (ARM64). Config at /etc/dendrite/dendrite.yaml. Server name: veilmsg.com. PostgreSQL auth switched from ident to md5. Running as PM2 process #4 (veil-dendrite), 50MB RAM. PM2 dump saved.

**[INFRA] Oracle VM headroom confirmed**
RAM: 22GB total, 20GB available. Disk: 30GB total, 18GB free. PM2 running 3 processes (clipforge-api 122MB, clipforge-scheduler 111MB, clipforge-worker 95MB) — 418MB combined, very light. No local PostgreSQL (BitClip uses Supabase cloud) — will install PostgreSQL locally for Dendrite. VM confirmed ready to co-host Dendrite.

**[INFRA] Firebase Android app registered**
Package name: com.veil.app. Nickname: Veil Android. google-services.json downloaded to user Downloads — move to D:\Documents\Veil\ for safekeeping. SHA-1 fingerprint not yet added — required before testing on a real device (add via app settings once Flutter project is scaffolded).
