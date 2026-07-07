# Veil — Development Log

**Format**: `[YYYY-MM-DD] TYPE: Description`
**Types**: `DECISION` `ADD` `REMOVE` `FIX` `INFRA` `COST` `LAUNCH` `QUESTION`

Entries are added every session. Nothing gets done without a log entry.

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
