# Veil — Development Log

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
