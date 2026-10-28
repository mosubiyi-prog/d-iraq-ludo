# DEDA Weekly Stage45 — private top-ten gift inbox and once-only mock redemption (NO DEPLOY)

Date: 2026-10-28
Stage45 branch: `deda-weekly-stage45-private-top10-gifts-inbox-atomic-no-deploy-2026-10-28`
Verified Stage44 starting SHA `3d1c9285c56e4d81a36ca7869ac6ffdeadf0b6c6`, successful parent run https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/40704645345
Stage45 first passing after enhanced anti-tampering: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/40706538705 (SHA `91c6506ee8d0fa0e498277a41ead57b91fd46646`), 10/10 new Stage45, 9/9 Stage44, 21/21 Stage43 and 123 passed other executed regressions with 1 pre-existing skip, **zero failures**.

## Implemented on PRIVATE Firestore Emulator only
1. `functions/deda_weekly_stage45_private_gifts_inbox_atomic_NOT_EXPORTED.js`: translates the Stage44 *local emulator* applied-XP Top 10 into a privately HMAC-sealed closed-week demo record. Requires **at/after 06:00 Baghdad on week release day**; before that, neither gifts nor credits are possible. Account identities are recovered only from private Stage43 ledger receipts and checked against derived opaque HMAC participant IDs. Cannot accept client-provided ranks, payout sizes, balances, or IDs.
2. A Firestore transaction creates EXACTLY one private `pending` gift-inbox entry per eligible rank, **150 diamonds first, 100 second, 50 third, 10 each fourth–tenth**, total **370 pending mock diamonds** with 10 winners. No private shadow wallet credit occurs merely by creating a pending gift.
3. A separate transaction models the user opening «هداياي» and receiving that gift **once**. Fake app/account/unknown second phone/replayed request cannot access or redeem another account's prize. Two concurrent phones requesting the same prize result in ONE credit to a **private stage45 shadow wallet** and the other call returns `already_received` with **zero** additional diamonds. Shadow HMAC wallet addresses are never original DEDA wallets.
4. Re-issuing the same week validates every existing gift receipt, amount, participant, rank and frozen snapshot. **Missing or altered gift = conflict, not silent success**, and no duplicate grant. Changed snapshot HMAC, false final result and improper week time are rejected.
5. `functions/tests/deda_weekly_stage45_private_gifts_inbox_atomic.test.js`: ten actual Firestore Emulator cases, using original applied-XP style receipts for **12 synthetic accounts**, issuer/source and cutover fixtures. Covers week freeze, after 06:00 release, 10 gifts/370 total, 11th/12th exclusion, first and second prize, wallet preservation, two concurrent phones, account binding, forged App Check-shaped context, tampering, partial missing gift, no live Firebase.
6. `.github/workflows/qa-deda-weekly-stage45-private-gift-inbox-no-deploy.yml`: stops any changes to prior original Android app, archive, Firebase Rules, functions/index.js, account progress/migration engine, original wallets, pubspec and Play deployment; runs Stage45+44+43 local emulator and existing calendar, migration, monthly history regressions.

## Strict boundaries / NOT an operational gift launch
- The HMAC, authenticated identity attestation, source share receipt, migration review, cutover epoch, enrolled phones and account profiles in these tests are **synthetic QA fixtures**. They do **not** prove real production account authority. `request.app.appId` shape checks are not production App Check verification; every Stage45 module remains explicitly `NOT_EXPORTED`.
- The frozen ranking projection is a **non-transactional read-only QA snapshot**. Production must atomically seal/version standings against a trustworthy real server issuer and updated application writes; this module is not a deployable finalizer.
- **Real «هداياي» is NOT integrated. Real diamonds, user wallets, premium IDs, frames, manager balance, XP, original tasks, Firebase and Google Play have NOT been modified or credited.** No actual signed new APK/AAB has been prepared.
- The old installed apps' local XP writers still cannot be stopped by this mock server epoch. A real reviewed cross-device migration, trusted task receipt issuer, authenticated client version and App Check/Roles enforcement, rollback and production Rules validation are outstanding.
- Calendar and approved winner-card original image/text are inherited from Stage31 and must not be changed, no name or ID on winner card. Real user-visible frame/profile click, manager monthly permanent archive and actual winner card remain future integration.

## Mandatory owner gate before any new APK
The owner explicitly requires a **short, copyable all-additions summary and mutual review before any APK or AAB preparation**. See `docs/DEDA_WEEKLY_OWNER_PREBUILD_ADDITIONS_REVIEW_GATE_2026-10-28.md`. Never begin building an APK merely because these QA tests passed. No real Firebase/Play deployment without a separate explicit owner authorization.

Future Stage46 should prioritize independently trustworthy original task completion/migration issuer and old-client server cutover. A real account cannot safely redeem earned XP or prize from purely client-authored evidence.

CI must be verified SUCCESS on this final checkpoint commit before recording Stage45 complete.