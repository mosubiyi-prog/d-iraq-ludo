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

## OWNER-OBSERVED RELEASE-BLOCKING REGRESSION — rewarded-ad diamonds profile display (2026-10-10)

Owner attached BEFORE still photo (profile diamonds **999600**) and an AFTER 58s phone screen recording. Recording clearly shows real rewarded advertisement, DEDA return, toast **"تم منحك 3 ماسات بنجاح 💎"** around 52 seconds, but profile diamonds STILL **999600** at 56 seconds. Not a Telegram social-task payout; this is the already-existing three-diamonds-per-rewarded-ad feature.

Source cause found in PROVEN BUILD RECONSTRUCTION SCRIPT tools/style_purchase_separation_100272_2026_10_05.py (profile diamond block):
`${DedaDiamondsWallet.hasGeneralManagerPersonalWallet ? managerDiamonds : normalDiamonds}`
For manager's personal 1,000,000-diamond testing wallet, this conditional HIDES the separate earned-ad/gifted pool, even when DedaDiamondsWallet.claimReward() shows success. Do NOT assume the 3 earned diamonds disappeared; the original rewarded-wallet code adds 3 to an independent per-account SharedPreferences balance and notifies normalDiamonds. The original manager-personal wallet remains at 999600, explaining the static display.

Owner expects rewarded earned diamonds to be VISIBLE. Source-only fix drafted:
- lib/deda_profile_visible_diamonds.dart: display-only sum of authorized manager-personal balance and ordinary earned/gifted balance, no movement/minting.
- tools/fix_profile_rewarded_diamond_display_next_release.py: safe fail-closed post-golden-reconstruction patch of ONLY one profile stat expression; old 100327 code unchanged.
- test/deda_profile_visible_diamonds_test.dart and tests/stage14/test_profile_diamonds_patch.py: regression tests cover example 999600 + 3 -> 999603 WHEN PREVIOUS ordinary earned pool = 0, normal users unaffected.
- Profile display total may be ABOVE 999603 if the owner already has other stored ordinary ad diamonds. Do not erase accumulated balances to force an expected number.
- Award claim success shown by video, but persistence on owner's particular phone has NOT been directly inspected. Future signed APK and owner-device test must check actual wallet component balances and usable spending, without any manager administrative gift budget debit.
- ALWAYS apply the post-reconstruction patch in the eventual single integrated APK pipeline; just creating the patch file does NOT change 100327 or future builds by itself.
- This defect fix is added to release regression checklist, on top of the FOUR approved features, and is NOT grounds for an intermediate APK.

No production Firestore changes, no user data modifications, no APK yet.


## 2026-10-10 — Telegram actual verification/payout source implemented (NO DEPLOY)

A substantial server and client milestone for point 4 on NEXT-FOUR branch ONLY:
- `functions/deda_telegram_bot_binding.js`: authenticated DEDA user requests a 15-minute, high-entropy /start token. Server resolves actual bot username from Telegram getMe and returns a real deep link dynamically, with per-account one-minute new-link throttle.
- `functions/index.js`: `dedaStartTelegramVerification` callable, secret-token-protected `dedaTelegramBotWebhook` HTTP receiver, `dedaClaimVerifiedTelegramFollow` callable, GM-only `dedaManageTelegramVerifiedReward` and `dedaTelegramVerifiedRewardReadiness`. All secrets managed by Firebase Functions secrets, NOT mobile APK, GitHub source or Firestore readable data.
- Webhook accepts a private Telegram /start from the real Telegram user ONLY if the request contains the server-configured Telegram webhook secret and the one-time nonce is unused/not expired. Telegram IDs are never accepted from the Android client's input. Account/Telegram ID binding documents prevent cross-account reuse. User gets a Telegram bot reply after authentic binding.
- `functions/deda_telegram_verified_claim.js`: membership MUST be proven by live Telegram Bot API `getChatMember` for @DEDA_Iraq; actor must have real authenticated DEDA session and registered owned personal DEDA ID. Exact current Baghdad daily task must be explicitly active in trusted mode and worth EXACTLY 10 diamonds. One atomic Admin SDK transaction adds +10 to EXISTING personal spendable `deda_diamond_gift_balances/{publicId}` and creates unique DEDA account + Telegram ID once-ever claims and audit documents. Never writes/consumes `deda_admin_diamond_wallets`.
- `functions/deda_telegram_reward_activation.js`: only verified active general manager can switch real reward ON for today's scheduled 10-diamond Telegram task, and only if the bot itself is actually an administrator of the channel; GM can switch OFF immediately even if Telegram API is down. Standard 100327 day documents continue `rewardsEnabled: false` until explicit activation.
- `lib/deda_telegram_verified_reward_service.dart`, `lib/deda_social_task_preview.dart`: separate "ربط حسابك مع بوت تليجرام" and "تحقق واستلم 10 ماسات" buttons ONLY for server-activated reward task; all preexisting nonpaying published preview behavior remains, no local wallet edits.
- `lib/deda_admin_social_task_preview_page.dart`: GM's real reward ON/OFF buttons disabled when server/Bot API readiness cannot be verified.
- `tools/inject_social_task_golden_preview_2026_10_09.py`: future golden APK will refresh actual existing DedaDiamondsWallet after credited claim, avoiding a misleading success message.
- `firestore.rules`: server-only confidential nonce/binding/claim/audit records, restrict read of active task to exactly the verified 10-diamond state. Changes NOT deployed; live rules must be backed up and surgically merged.
- Regression tests: `tests/stage14/deda_telegram_verified_claim.test.cjs`, `deda_telegram_bot_binding.test.cjs`, `deda_telegram_reward_activation.test.cjs`; negative tests cover unsigned Telegram payload, no membership, identity reuse, replay, expiry, not GM, Bot not channel administrator, prior payout, wallet ownership mismatch and zero manager-wallet debit.
- Verified Node backend unit suite passing: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/38005496420 (readiness and deployment NOT proven by unit tests).
- Flutter social UI and client helper analysis passing on earlier snapshot: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/38005294122 . Latest enhanced GM buttons and Firestore rules changes have additional QA runs; CHECK final status before claiming complete.

NEW UNRESOLVED DEPENDENCIES:
1. Owner-controlled Telegram bot must actually exist and be added as ADMIN to the official channel @DEDA_Iraq. Username is resolved automatically via Bot API. Never request BotFather token in chat; use Firebase Secrets.
2. Real Firebase Cloud Functions deployment currently BLOCKED by Cloud Build / Artifact Registry and relevant Google Cloud onboarding/billing prerequisites. Need owner cooperation and explicit permission for credentials, secret provisioning, registered Telegram webhook and production changes. The new callables are NOT live.
3. No real Telegram user/owner device claim has been tested end-to-end. Existing 100327 social task remains intentionally nonpaying. Future activated task is a server-controlled state, not client minting.
4. More integration work needed for the one signed owner-test APK built after all four features work, plus ensure exact accepted navigation and ad-earned wallet fixes survive golden reconstruction. No APK, AAB or Play Production upload has been made.
5. New place/recovery Cloud Functions triggers have bounded explicit 120s/90s function timeouts to cover 30-second/10-second waits safely.

OWNER DECISION: pause all other Google Play work until this ONE integrated version is tested and approved; only THEN prepare public Production upload. Granted Production access is not actual publication.


## Follow-up QA checkpoint — full NEXT version code integrated successfully (source only)

**Verified green end-to-end**:
- Reconstructed the genuine accepted 100319/100327 navigation with all patch scripts, restored NEW compact GM admin and auto controls, applied real +3 rewarded-ad diamonds profile display, **injected actual Telegram user card and success wallet refresh inside final lib/main.dart**, and ran Flutter analyze & widget tests. NO APK built: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/38006500534
- Live Firestore Security Rules emulator now passes adversarial tests: deny public/employee/GM direct spoof of private bot start token, Telegram identity, one-time ledgers; only active GM can read audit; legitimate personal wallet may be read by owner with authenticated DEDA session and reserved personal ID; strangers cannot fake a matching sharePersonalId to read/increase another wallet. NO rules deployed: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/38006641128
- Trusted 10-diamond Node bot/user/manager policy and full private Telegram nonce flow pass CI: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/38006720221
- Safety improvements after QA: bot /start handler rechecks currently ACTIVE directory and DEDA session at callback even after link issued; reward ON readiness now also checks deployed Firebase Telegram webhook via Telegram getWebhookInfo (not merely bot admin); automated place certificate dates match Baghdad midnight (UTC+3).
- The next-release checked-in rules source now contains explicit **session-and-reserved-personal-share-ID-bound** `deda_diamond_gift_balances` rule, since old accepted 100270 wallet permissions were historically inserted at build time and had been absent from checked-in `firestore.rules`. Clients cannot mint extra wallet units; trusted Admin SDK can atomically credit +10. The original production wallet rules MUST be inspected/backed up and safely merged with the stronger security helper; do not overwrite deployed rules wholesale.
- CI uses an ephemeral 1-day keystore ONLY to satisfy the historical golden source check; does not sign APK. No real Telegram secret touched or stored.
- Last accepted device-tested 100327 and stable main remain unchanged. Integrated QA success is NOT production Firebase readiness or tested signed release.

**Remaining release blockers**:
1. Real Firebase Cloud Functions environment/build and account prerequisites, then secure secrets `DEDA_TELEGRAM_BOT_TOKEN` + `DEDA_TELEGRAM_WEBHOOK_SECRET` provisioning and Telegram setWebhook to the deployed Firebase URL. Owner consent and provider access needed.
2. The Telegram bot must truly exist, be administrator in @DEDA_Iraq and have a working webhook. Backend stays fail-closed while missing.
3. Test auto-place 30 s and user forgotten public PIN 10 s against Firebase emulators including race/replay/security, then owner device test. The user-facing PIN flow is already in source but must be verified inside actual reconstructed golden main.dart.
4. Generate ONE properly production-signed internal APK with a new code >100327 only after all items pass and with explicit owner agreement; 100327 remains fallback.
5. Final public release only after owner approves that ONE internal APK and Firebase/Play prerequisites. Production access ≠ app already publicly released.

### Final-build build flag and forgot-PIN screen integration gate
- The proven 100327 social compact card is intentionally feature-gated by `DedaSocialTaskPreview.visible` and defaults FALSE at compile time. The ONE upcoming internal test APK must specify `--dart-define=DEDA_SOCIAL_TASKS_UI_PREVIEW=true` to expose it; otherwise backend could be fully working while user sees no Telegram page. Keep the daily task display preview flag FALSE.
- The next-release golden integration QA now explicitly asserts that the **real reconstructed login** retains `DedaPinRecoveryPage`, `DedaPinAuth.recoveryRequest`, and `DedaPinAuth.readRecoveryPin`, ensuring the ready six-digit code can appear on the existing user screen without extra WhatsApp/SMS flow.
- The PIN **backend transaction** regression includes trusted prior installation, >=10-second mandatory delay, switch OFF, older pending requests, mismatch name, inactive accounts, one/hour throttle, duplicate requests, and emergency anti-admin-reset. All branch-only until Firebase deployment and owner device test.
