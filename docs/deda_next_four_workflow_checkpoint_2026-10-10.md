# DEDA — Unified next release development checkpoint — 2026-10-10

OWNER DIRECTIVE: Deliver ONE integrated APK only after all four points are implemented, security verified and runtime checks pass. No intermediate APKs. Keep successful internal 100327 untouched as rollback.
Development branch: deda-next-four-items-stage0-2026-10-10. No production Firebase rules, functions, wallet or Google Play changes made by this branch.

STEP 0 — PASS: independent branch from owner-accepted 100327, scope notes recorded.

STEP 1 — PARTIAL / QA only: protected place auto-approval proposed server worker, fail-closed policy and manager-only UI setting.
- Server transaction reads server configuration; only NEW requests after ON can qualify. Existing pending and edited requests remain manual.
- Requires verified owner, complete required data, coordinate checks, and bounded complete same-province duplicate scan; otherwise manual.
- Audit and monotonic approval ID in server transaction; old manual workflow remains.
- Worker is source only until secure backend redeployment. UI ON stays DISABLED without Admin-SDK-backed readiness marker.
- Stage1 Node policy QA: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/37997403490 (6 tests passed).

STEP 2 — SECURITY POLICY ONLY: 10-second forgotten-code auto mode.
- PIN reissue MUST NOT use phone/name/installId as sufficient proof.
- Pure server policy demands verified cryptographic owner proof, 10 elapsed seconds, 1 request per hour, freshness and revoke/replay checks.
- No client timer, no PIN issuance in test code, no auto-issuance enabled. Existing manual recovery continues.
- Strong device / account proof and a timed privileged backend still need implementation and proof before enabling.

STEP 3 — RESPONSIVE ADMIN CARDS (source and tests added):
- Admin dashboard cards use reusable compact widget, smaller icon/title/subtitle, responsive 2/3/4 columns, large text-size height.
- Old navigation callbacks/permission checks retained.
- Flutter widget tests verify Arabic cards at multiple text scales. See manager UI QA workflow.

STEP 4 — TELEGRAM VERIFICATION POLICY ONLY:
- Login Widget HMAC verification with Bot Token (kept out of app), bound to Telegram user ID.
- Trusted Bot API getChatMember membership check for correct user, blocked for left/kicked.
- Once-only reward and wallet ledger MUST be implemented server side.
- User's displayed ten diamonds on 100327 are still NOT payable.

HARD BLOCKERS BEFORE A REAL RELEASE:
1. Google Cloud Build API cannot currently deploy modified Firebase Functions to deda-25b88 (owner's country onboarding blocked). Two automatic systems and Telegram verified payouts need a TRUSTED SERVER; Firestore-only rules cannot replace it.
2. Trusted PIN recovery verification/enrollment is currently not available; user-supplied name/phone/install ID is insufficient to reset an account automatically. Must implement strong cryptographic proof and safe reset first.
3. Telegram membership checks need an owner-controlled bot added as ADMIN to @DEDA_Iraq, secure Bot API credential via GitHub/Firebase Secrets, and an authenticated Telegram-to-DEDA binding, plus a real auditable server wallet credit ledger.
4. End-to-end tests, comprehensive UI regression, actual protected backend activation and owner device test are still pending.

NEVER claim the four additions are complete or issue a new APK prematurely. Work may continue on backend and UI in the dev branch only. Do not deploy old full repository Firestore rules (different from actual published rules).

QA UPDATE:
- Stage1 + Stage2 + Stage4 pure Node policy regression succeeded: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/37997911608
- GM controls Firestore emulator + admin Flutter analyzer + compact responsive Arabic widget test succeeded: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/37997791969
- Current status remains NOT READY FOR APK because the backend trigger is NOT deployed, ten-second cryptographic PIN verification is NOT built, and verified Telegram real-wallet credit is NOT live.
