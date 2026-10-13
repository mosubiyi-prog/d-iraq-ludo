# DEDA ❤️ نبض التطبيق — Stage 1: safety baseline and acceptance gates

**Date:** 2026-10-13  
**Development branch:** `deda-heartbeat-place-stage1-2026-10-13`  
**Frozen source basis:** `owner-place-map-polish-100332-stage-2026-10-13` at `1720983e7711bde676dce84d47fd1a2655642b86`  
**Production:** 100330 — **DO NOT TOUCH**.  
**Owner-entry reference:** 100331 — **DO NOT TOUCH**.  
**100332 private APK:** GitHub Actions 38450192552 succeeded on commit `5dec98f0...`, **earlier** than the current 100332 tip; the two subsequent photo-picker/QA-guard commits are **not** covered by that APK run.

## Owner-approved scope — seven observations

1. **Bell beside envelope**: actual owner/admin place-decision notices, including approval, must be visible inside the existing 🔔 bottom sheet, account-scoped, sorted newest first, safe read/unread. Never fabricate a notice from a status label. Diagnose event production, query scope, rules and historical approved records first.
2. **Approval card**: eliminate duplicate approval number/date between explicit fields and the approval message; keep genuine status, ID, date, decision notes, old request history.
3. **Likes/followers**: real server-confirmed counts; no fake values, no user-list UI, no direct client write to totals. One following/like state per verified account per published place; unlike/unfollow. Unlike/like independent. Owner should see truthful counts and status.
4. **Place palette and input fields**: seven vivid primary colors and seven corresponding pastels. Checked selected swatch; title, input outlines/labels and marker use approved consistent coloring; keep locally preview-only until separately authorized server schema/rules. Verify readable contrast in dark/light and RTL layouts.
5. **Photos**: NO phone gallery picker or profile photo in this phase. Keep category-specific icon; do not upload or publish local preview. Preserve already published compliant assets if any; never delete.
6. **Auto-approval card / scrolling**: reduce oversized explanatory panel to a compact action/control where the owner sees it; no overlay covering the request/status card; preserve security and actual automation toggle authority.
7. **Place-type icons**: correct icon for pharmacy and all supported categories including other/free-text, stable from form to map; no misleading hard-coded payment/pharmacy emblem.

## Confirmed technical baseline

- `lib/deda_place_engagement_service.dart` is fail-closed by default with `DEDA_PLACE_ENGAGEMENT_LIVE=false`.
- `functions/deda_place_engagement.js` contains staged idempotent transaction logic, but `functions/index.js` currently does not export `dedaReadPlaceEngagement` and `dedaSetPlaceEngagement`; no customer-ready endpoint is proven.
- No explicit direct-client-access engagement rules exist in the current staged `firestore.rules` snapshot; **live Firebase rules must be separately audited against deployed rules** before any change.
- `lib/main.dart` owner notification sheet uses `DedaBackend.ownerPlaceNotifications(accountKey)` and read markers. Empty screenshot is a symptom, not proof a notice was written. Do not alter real customer data to test this.
- `_statusCard` displays dedicated approval ID/date and `_approvalMessage`; screenshot demonstrates duplicate content.
- Existing server functions and Firebase rules are **production-sensitive**. No changes to deployed Firebase, Places/owner data, Google Play, or the live account/notification data in this stage.

## Strict no-regression scope

Do not disturb owner entry paths, old drafts, existing place IDs, submission/edit/resubmission/delete requests, manual approval, geolocation, search, navigation, voice, location-sharing, profile identity, rewarded ads, manager permissions, or existing social systems. Keep `main`, 100330, 100331 and 100332 feature branch untouched.

## Non-negotiable security + scalability acceptance gates

- Verify `accountKey` binding server-side using authenticated session; reject impersonation, anonymous mutations, duplicate and automated spoofed actions.
- Atomically bind user reaction and authoritative count. Repeated taps and retries must be idempotent. Recheck a place's published/hidden/deleted state within each transaction.
- Test permission boundaries using **Firestore Emulator**, including real rules compatibility; confirm rejected reads/writes cannot expose account identity. Server owns totals.
- Design for load: a single total-document transaction can become a high-contention hot spot. Benchmark and consider sharded counters/async aggregation if concurrent usage warrants; never assert thousands-of-users capacity without load testing.
- Include rate-limit/abuse controls, request validation, retries, timeouts, offline behavior, and safe numeric bounds. Loading state never masquerades as `0` or `—` when an actual value is available.
- Test Arabic/English, portrait/landscape, phones/tablets, long place names and big counts. No layout overflow or inaccessible touch targets.
- Test account switching, reinstall/login, old approval records, hidden/rejected/deleted places, network interruption, multiple accounts and concurrent reaction requests in a **synthetic** environment.
- Run Node tests, Flutter analyze, widget tests, source reconstruction scripts, Firestore emulator regression tests, then single private signed APK and manual owner QA **only after full review and explicit authorization**.

## Stage 1 changes

The working branch is separated from the original 100332 tip. Only defensive test/QA documents and automation are permitted in this stage. No APK build, no production publish, no Firebase deploy, no feature flag activation, and no live writes.

**Next:** implement each UI fix narrowly on the reconstructed source path, add server/rules tests separately, record pass/fail for every item, and pause at any failing gate.

## Stage 1 root-cause evidence — owner notification bell (no production mutation)

Confirmed on the staged source:
- Owner bell queries `owner_place_notifications` by `accountKey`.
- `DedaBackend.finalizePlaceApproval` creates an owner-bell notice only for `requestType == 'update'` (edit approved); **initial approval writes none**.
- Automatic approval worker commits status + published place + audit but **no owner-bell notice**.
- `functions/index.js/onPlaceRequestUpdated` sends owner push/FCM, **not** the database notice that the bell displays.
- Existing Firestore client rules for `owner_place_notifications` do **not** permit client-written `approved` type. Do not widen client create permissions merely to fix UI.
- The auto-approved message itself repeats number and date, and the card already separately renders these exact fields.

**Safe repair design (not executed yet):** generate a deterministic, idempotent, **server-authored** owner-notification document on a first-time `place_requests` approval transition, using authenticated request ownership and authoritative approved status. Verify both manual and automatic paths, preserved edit notifications, identity binding, repeat event delivery, existing accounts, and Firestore rules in an emulator; no backend deployment without approval. Historical already-approved records need a separately reviewed, authorized one-time backfill and must never be silently modified.

