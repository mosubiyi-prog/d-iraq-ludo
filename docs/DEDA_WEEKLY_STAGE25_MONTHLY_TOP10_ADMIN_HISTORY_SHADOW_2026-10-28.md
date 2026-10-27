# DEDA Stage25 — Monthly top-ten and top-three weekly history (PRIVATE SHADOW)

Date: 2026-10-28
Parent safe ref: Stage24 `bd3e7087eab05956046b4a9bc820e81eb4dccf19`.
Branch: `deda-weekly-stage25-monthly-top10-admin-history-shadow-no-deploy-2026-10-28`.

## Accepted owner requirement
Keep a month-by-month archive of the leaderboard's **real top 10 of each completed weekly competition**, including clear first, second and third places and each competitor's rank. This stage creates the read-only archive projection/validation with a separate month ID, not a new monthly contest or monthly prizes.

## Implemented now — safe developer/test model, not public feature
- `functions/deda_weekly_monthly_top10_archive_NOT_EXPORTED.js` converts future trusted-shape **final closed-week** snapshots into the month's week-by-week top-ten history and its top-three highlights.
- Privacy-filtered competitor display name, active public DEDA ID, opaque competitor token, verified weekly task XP and rank only. No raw account key, UID, phone number or wallet returns.
- Month assignment uses **the last eligible Baghdad instant `week.endMs-1`**. Weekly start weekday still depends on an approved production server calendar; no calendar or weekday assumed by this module.
- Any incomplete week, duplicated week, overlap, wrong month, forged shape, mismatched final timestamp, extra function arguments or invalid ordering fails closed.
- Digest is a local *change checksum*, NOT an authentication signature. Prior-week snapshots must eventually come from an audited immutable server issuer; fake `issuer` strings are never sufficient.
- Current month may collect completed weeks as they close. Earlier months are represented separately and cannot be reset by a new month in this pure model.
- No new awards or additional monthly rankings: winner prizes remain **weekly 150 / 100 / 50 / 10 each ranks 4–10**, total maximum **370** for a full weekly top ten once a future real wallet issuer is approved.

## Strict stop gate
This is a testable prototype ONLY. Actual owner/general manager-only access, durable Firestore monthly archive, true task +20 level XP issuer across devices, authorized original social profile/friend callbacks, audit of separate spendable earned diamonds and once/week payout, authentic active equipped frames, signed final phone/tablet acceptance and owner's production approval are **not** completed here.

NO changes to `functions/index.js`, `firestore.rules`, original `lib/main.dart`, user/task/manager balances, production Firebase, Google Play, APK/AAB, or old tested branches. Nothing is exported or deployed.

## QA
- Node tests: `functions/tests/deda_weekly_monthly_top10_archive.test.js`.
- CI workflow: `.github/workflows/qa-deda-weekly-stage25-monthly-top10-admin-history-no-deploy.yml`.
- CI green means pure safe archive behavior is correct, NOT real admin-only security or production readiness.
