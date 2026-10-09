# DEDA — Agreed next release scope (2026-10-10)

STATUS: OWNER REQUIREMENTS RECORDED, NOT IMPLEMENTED. Do not build an APK or deploy Firebase from this document.

ACCEPTED BASELINE: Internal APK 100327, successful Telegram social-task draft save, schedule for Baghdad midnight, user task appeared after midnight and opened official Telegram channel. 10-diamond reward is CONFIG ONLY, not payable until real subscription verification. Preserve accepted navigation and existing task behavior.

## 1. Auto-approval toggle for place submissions
- Add ON/OFF setting in admin "طلبات الأماكن".
- Only the GENERAL MANAGER may change the setting.
- Applies ONLY to place requests created AFTER toggle was enabled.
- Previously pending requests stay in the manual review queue.
- Automatically approve only valid/complete/eligible submissions; suspicious or duplicate requests remain for manual review.
- Keep existing audit trail, owner notifications, accepted places, and safe disable behavior.
- Do not retroactively apply toggles to existing requests.
- Implementation must enforce permissions and eligibility server-side rather than trusting the Android UI.

## 2. Optional automatic recovery for forgotten login code
- Add GENERAL MANAGER-only ON/OFF setting in admin "استرجاع الدخول".
- When enabled, process eligible NEW forgot-code requests after 10 seconds.
- When disabled, the existing manual approval/reissue workflow stays unchanged.
- Applies only to users who forgot their login code (not general administrative accounts or unrelated user changes).
- DO NOT release/reissue a code before secure identity/ownership verification. No SMS requirement requested.
- The user specifically wants to reduce manual admin workload.
- Ten-second automation needs a trustworthy server-side mechanism. Firestore rules and a handset timer alone CANNOT safely grant timed recovery; do not promise it until feasibility and security are proven (Cloud Build/API blocker exists).
- Ensure one-time issuance or revocation of previous code, anti-abuse/rate limits, protected delivery channel and audit logs. Requests failing verification stay manual.

## 3. Compact administration-card visual layout
- On "إدارة DEDA" dashboard, resize/compact the admin grid cards and the text inside them to resemble the polished, compact home-screen category cards provided in screenshots.
- Every title/subtitle must stay INSIDE its card with no text overflow, cutoff, or unwanted collision.
- Keep good icons, colors, alignment and comfortable click targets.
- Fit both portrait phone and larger tablet, and support Arabic RTL/text scaling. Use flexible/adaptive layout rather than fixed dimensions that clip; avoid reducing font so far it becomes unreadable.
- VISUAL ONLY: no changes to management permissions, navigation routes, actions, or underlying data.

## Delivery rules
- Owner stated these are the final three requests to collect BEFORE another APK.
- DO NOT build another APK yet; wait for owner to confirm final scope.
- Group secure Telegram actual subscription verification and real reward claim/payout with this next release IF technically feasible; do not assume Cloud Functions can deploy under the current Google Cloud country/billing restriction.
- Do not enable payouts or automatic login recovery until tested and authorized.
- Keep stable 100327 separate from future development; work on a new development branch, preserve rollback.
- Test static security boundaries, Firestore backend, responsive admin UI and full field test before requesting owner installation.
