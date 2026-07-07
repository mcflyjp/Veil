# Veil — Project Plan

**Tagline**: Signal's security. AIM's soul.
**Started**: 2026-05-22
**Stack decision**: Matrix + Dendrite / Flutter / Cloudflare R2 / Firebase Phone Auth

---

## What It Is

Veil is a cross-platform E2E encrypted messaging app. No plaintext fallback, no compromise on privacy. Default theme is a faithful AOL Instant Messenger aesthetic — retro personality, modern encryption.

---

## Tech Stack

| Layer | Technology | Notes |
|---|---|---|
| Protocol | Matrix (Dendrite homeserver) | Self-hosted on Oracle VM |
| Encryption | Olm/Megolm | E2E equivalent to Signal Protocol |
| Database | PostgreSQL | Managed by Dendrite, on Oracle VM |
| Media Storage | Cloudflare R2 | Client-side encrypted before upload |
| Phone Auth | Firebase Phone Auth | OTP, free up to 10K/month |
| Push (Android) | FCM | Free |
| Push (iOS) | APNs | Phase 2, covered by Apple Dev account |
| Mobile | Flutter | Android → iOS → Desktop, same codebase |
| Invite Web | Vercel | WebCrypto guest Matrix sessions |
| Homeserver domain | TBD | e.g. matrix.veil.app |

---

## Phase 1 — Android MVP
**Target**: Month 4 from start

### Infrastructure
- [x] Domain purchased: veilmsg.com (Cloudflare Registrar)
- [x] Oracle VM headroom confirmed (20GB RAM free, 18GB disk free)
- [ ] PostgreSQL installed on Oracle VM (for Dendrite)
- [ ] Dendrite homeserver installed + configured on Oracle VM
- [ ] PostgreSQL config for Dendrite
- [ ] R2 media repo wired to Dendrite
- [x] Firebase project created (veil-510bf)
- [x] Firebase Phone Auth enabled
- [x] Firebase Android app registered (com.veil.app), google-services.json downloaded
- [ ] SSL + domain for homeserver

### Flutter App (Android)
- [ ] Project scaffold + go_router navigation
- [ ] Auth: phone number → OTP → Matrix account creation
- [ ] Contact list (phone number → Matrix ID lookup)
- [ ] 1:1 E2E encrypted chat (Olm)
- [ ] Group chats — E2E (Megolm), 50-person cap
- [ ] FCM push notifications
- [ ] Read receipts + typing indicators
- [ ] Reactions, reply threads, message editing, message deletion
- [ ] Disappearing messages toggle

### AOL AIM Theme
- [ ] Buddy list contact screen (online/away/offline status)
- [ ] Away message → custom status field
- [ ] Retro chat bubble style
- [ ] AIM-inspired color palette + typography
- [ ] Optional door open/close sounds
- [ ] Dark mode toggle

### Media & Files
- [ ] Image sharing (client-side encrypted → R2, 100MB cap)
- [ ] Video sharing (100MB cap)
- [ ] File sharing (100MB cap)
- [ ] In-app media viewer

### Invite System
- [ ] Unique invite link generation per contact
- [ ] Web page (Vercel): non-app user opens link in browser
- [ ] WebCrypto temporary guest Matrix session
- [ ] In-app disclaimer banner when chatting with non-app user
- [ ] "Install Veil" CTA shown to guest users

### Launch
- [ ] Google Play Store submission
- [ ] Play Store listing (screenshots, description, icon)

---

## Phase 2 — iOS
**Target**: Month 7 from start

- [ ] Apple Developer Account ($99/yr)
- [ ] iOS Flutter build target
- [ ] APNs push notification setup
- [ ] iOS-specific permissions (contacts, camera, notifications)
- [ ] TestFlight beta period
- [ ] App Store submission + review

---

## Phase 3 — Desktop
**Target**: Month 9 from start

- [ ] Adaptive layout (sidebar contact list + main chat panel)
- [ ] Keyboard shortcuts
- [ ] System tray (minimize, unread badge)
- [ ] Native drag-and-drop file sharing
- [ ] Desktop OS notifications
- [ ] Windows `.exe` installer
- [ ] macOS `.dmg` (covered by Apple Dev account)
- [ ] Linux AppImage / Flatpak

---

## Post-Launch Backlog

- [ ] Additional themes (beyond AIM default + dark)
- [ ] Custom emoji / sticker packs
- [ ] Voice calls (WebRTC — Matrix built-in)
- [ ] Video calls (WebRTC)
- [ ] Raise media cap (beyond 100MB)
- [ ] Raise group size cap (beyond 50)
- [ ] Message search
- [ ] Pinned messages

---

## Cost Snapshot

| Item | Cost | Frequency |
|---|---|---|
| Google Play Developer | $25 | One-time |
| Apple Developer Account | $99 | Annual (Phase 2) |
| Veil domain | ~$10–15 | Annual |
| Oracle VM | $0 | Monthly (existing) |
| Cloudflare R2 | $0 | Monthly (first 10GB free, then $0.015/GB) |
| Firebase Phone Auth | $0 | Monthly (first 10K OTPs free) |
| FCM / APNs | $0 | Monthly |
| Vercel (invite web page) | $0 | Monthly (free tier) |
| **Phase 1 year-1 total** | **~$40** | |
| **Phase 1+2 year-1 total** | **~$140** | |
| **Phase 1+2+3 year-1 total** | **~$155** | |
| **Scaling (1K DAU)** | **~$15–30/mo** | |

---

## Open Questions

- [ ] Final domain/TLD — `veil.app`, `getveil.app`, `veilmsg.com`?
- [ ] App icon direction — eye? fabric veil? abstract shape?
- [ ] Screen names — do users pick a display name, or phone number only?
- [ ] Group chat terminology — rooms? threads? convos?
- [ ] Username system — `@name:veil.app` or hide Matrix IDs from users entirely?
