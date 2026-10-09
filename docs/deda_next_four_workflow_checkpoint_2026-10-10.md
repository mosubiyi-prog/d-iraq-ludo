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

## Owner scope correction — 2026-10-10 (supersedes cumbersome approvals)

The owner explicitly wants TWO simple manager ON/OFF automation switches, NO added forms, no staff approvals, and no manual review of new place requests:
A) New place creation submissions after enabling ON -> auto-approved/published after a short 10-to-30-second delay (use 30 seconds as provisional default), without employee review or content/duplicate screening. Existing pending requests must stay untouched. OFF -> existing manual approval.
B) Existing forgotten user PIN recovery requests -> issue a replacement PIN after 10 seconds while ON, to the requesting user in the existing in-app channel, without SMS, staff review, or extra user-facing verification steps. OFF -> existing manual recovery.

MANDATORY invisible security boundary: an arbitrary anonymous requester must never be able to reset a different account just by knowing its name/phone. The current Firestore recovery request creation path is not sufficient evidence of account ownership (requesterUid/name/phone/installId can be self asserted). Trusted ownership binding or equivalent proof must exist BEFORE automatic issuance; otherwise default safely to manual and be transparent with the owner. Basic schema/identity validation and atomic server writes are implementation safeguards, not the owner-facing manual review he rejects. Do not expose the PIN to a different requester. 10-30 second scheduling itself requires a real trusted execution mechanism; client timers and security rules do not run server jobs.

NOTE: Prior strict place duplicate checks and manual suspicious screening are NOT the desired business workflow; revise place automation to eliminate human/content screening once basic authenticated owner and valid request information are guaranteed. Do not silently override the owner's requested approval behavior, and do not pretend unsafe PIN reset is acceptable.

Keep one combined APK release only after working end-to-end. DO NOT deploy or build now.

## Owner clarification on launch phase — 2026-10-10

- Originally DEDA had convenient user self-service forgotten-PIN recovery before administrative review was added. The owner's priority is restoring that self-service convenience, not expanding bureaucracy.
- Owner explicitly postpones phone-number ownership OTP verification through WhatsApp/SMS to a LATER SCALE-OUT phase once DEDA has significant real downloads; this is not being abandoned and should not be presented as a mandatory user-facing feature for the upcoming APK.
- The immediate UX should be: user selects Forgot PIN -> receives newly issued 6-digit PIN automatically within ~10s INSIDE DEDA without a staff member, no extra form/OTP/SMS. Place owner is a DEDA user eligible for the same recovery experience.
- For verified previously registered installations, use pre-existing DEDA trusted-session recovery capability to establish account access invisibly; do not pretend that simply providing a phone + name proves ownership. If secure same-account proof is unavailable, do NOT issue that account's secret to an unrelated requester. Use manual exception/fallback, explain candidly; this boundary cannot be postponed to the SMS rollout.
- Separate place OWNER requests should be automatically approved/published after ~30s when manager toggle ON, with no manual review of their content, and OFF restores manual. Existing pending requests unaffected.
- Existing secure channel checks occur in background and are not new user-facing verification steps. Backend deploy limitations still require resolution. No client-only PIN reset, no APK until full test.

## Implementation follow-up — after owner confirmed launch-first simplicity

Latest work on this branch only:
- Place request server trigger: when GM ON before request creation, delay ~30 seconds, then atomic prepare/publish including existing approval counter, status and audit. OFF/new older-than-toggle remain manual. Removed earlier proposed duplicate/content moderation contrary to owner request. Backend still NOT deployed.
- Trusted-device PIN recovery trigger: after 10s of newly-created request, server checks the existing 48-hex installation secret against protected known account profile and account name; issues fresh six-digit credential and requester-visible new PIN in one server transaction with one-hour issuance throttle and immutable audit. Missing old trusted device -> manual, never resets from phone/name alone. No SMS and no extra user-facing step. Backend still NOT deployed.
- Manager controls: when owner opens place/recovery admin screens, client checks manager-only callable readiness automatically. On/Off remains protected/disabled unless these server workers are REALLY deployed. No live business behavior changes.
- Compact administration cards from previous stage unchanged; responsive Flutter widget test and Firestore emulator guard runs previously passed.
- Telegram social cryptographic ID and member policy remains **policy only**. No live payout, no Bot Token in source, no credits to any wallet.

Node stage1+2+Telegram policy/syntax suite verified passing at https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/38000722815
Manager UI / rules security QA https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/38000741467 (verify finished run status before claiming pass).

IMPORTANT: NO NEW APK, NO LIVE FIREBASE CHANGES, NO GOOGLE PLAY ACTION.
All four owner requests remain under active development. Backend deployment Cloud Build restriction, bot admin/setup and live wallet verification remain to be resolved before integrated APK.

## Verified reward-wallet architecture (release warning)

The accepted build reconstructs personal diamonds through legacy scripts at APK build time:
- tools/add_diamonds_reward_100259_2026_10_04.py defines a local SharedPreferences-based DedaDiamondsWallet (ad earnings).
- tools/admin_diamond_backend_100270_2026_10_04.py defines the separate Firestore admin gift wallet and deda_diamond_gift_balances (gift portion of personal diamonds).
- tools/style_wallet_sync_100275_2026_10_05.py preserves isolated manager personal wallet.
This means a real Telegram follow reward CANNOT be implemented by merely creating a new server balance not read by the user UI, and MUST NOT reduce or write the manager gift budget. Need a protected one-time social ledger AND a compatible personal-balance presentation/spending path; otherwise claim would falsely appear successful while the user sees zero diamonds.
The signed 100327 build reconstructs main.dart through tools/build_100318_user_heading_camera.sh with scripts; validate future UI patch on that resulting build workspace, not just the checked-in lib/main.dart. Preserve all accepted navigation checks.

FINAL QA AT THIS CHECKPOINT: Firestore emulator strict manager-toggle tests plus Flutter analyzer and compact-card widget tests passed on https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/38000741467 . Node auto-place/auto-PIN/Telegram-policy and JavaScript syntax checks passed on https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/38000722815 . These are source/policy tests, NOT live backend integration or a completed four-feature APK.
