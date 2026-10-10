# DEDA — Owner-authorized Firebase services activation gate (10 Oct 2026)

Status: **APPROVED TO PREPARE**, no live backend deployed, no automation ON, no Telegram rewards ON, no APK, no Play production upload. User said: «باشر عزيزي بالتجهيز وتشغيل الخدمات». Authorship and admin ownership remain with the DEDA project owner.

## Evidence / known live prerequisite failure

Production Firebase project: `deda-25b88` (not a test project).
Historical guarded 100326 deployment run:
https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/37983045020

**Exact outcome:** Firestore rules only published successfully (later amended for 100327); Cloud Functions creation failed BEFORE functions became live because:
- Cloud Build API `cloudbuild.googleapis.com` disabled.
- Artifact Registry API `artifactregistry.googleapis.com` unavailable / attempted automatic enable by Firebase.
- Deployment service account lacked permission to enable Google Cloud services.
- Billing activation and IAM might also be required for Firebase v2 backend; never assert free tier or auto-enable billing.

OWNER'S MOBILE UI STEPS (only if not already enabled, don't send credentials in chat):
1. Open https://console.cloud.google.com/apis/library/cloudbuild.googleapis.com?project=deda-25b88 and tap **Enable/تفعيل**; if it shows **Manage/إدارة**, API is already enabled.
2. Open https://console.cloud.google.com/apis/library/artifactregistry.googleapis.com?project=deda-25b88 and enable; same Manage rule.
3. If Google Cloud asks to link/create a billing account or warns about charges, PAUSE and ask owner for explicit approval and explain costs. Do NOT enter a payment method or create billing subscriptions without owner action.
4. If owner shares screenshots, only interpret labels/state. Don't ask for payment card, Firebase private JSON key or Telegram BotFather token in the conversation.

## Target release services and deploy order AFTER owner APIs/billing ready

Code branch ONLY: `deda-next-four-items-stage0-2026-10-10`.
Rollback app: installed `100327`, unchanged.
A target-built APK has NOT been produced.

**Before ANY live mutation:**
- Fetch the exact current production Firestore rules, backup it, hash it, surgically merge only the next-release additions (automation settings/status, guarded Telegram task read, wallet owner + private bot ledger), and exercise emulator against EXACT candidate. Never run `firebase deploy --only firestore:rules` with checked-in rules file unmerged or old scripts. Pre-existing 100327 rules and payment/manager permissions are protected.
- Verify Cloud Functions provisioning, required IAM, project billing; verify deployment authorization and current existing functions. Function discovery/deploy has to be explicit, user-approved, targeted: **never** unconditionally deploy all `functions`, replace old functions or modify unrelated collections.
- Deploy `onPlaceRequestCreated` and `onRecoveryRequestCreated` on v2 ONLY after validating backward compatibility of previously used triggers; create the GM `dedaAutomationReadiness` callable LAST, only once both trigger workers actually exist and can be invoked.
- Check two manager toggles remain **OFF** until DEDA owner has separately consented to enabling each; never issue PINs or publish places to real users as a side effect of an infrastructure preflight.
- Owner-tested anonymous trusted-device PIN reset 10-second trigger must not work with just phone and name. Nontrusted device requests stay manual; never expose PIN via public access.
- Real Telegram reward remains **OFF** until owner sets up a BotFather bot and adds it as administrator of official channel `@DEDA_Iraq`, configures Firebase Secret Manager `DEDA_TELEGRAM_BOT_TOKEN` and `DEDA_TELEGRAM_WEBHOOK_SECRET` **directly in secured cloud environment**, and configures a secret-token-protected `setWebhook` to the correct published function URL. NEVER commit or ask for tokens in chat. Verify actual private /start and Bot API member proof, one-time 10-diamond credit to existing spendable personal balance, zero admin gifted wallet debit and cross-account replay prevention.
- Keep old accepted 100327 and base admin/places/manual recovery stable. No app-store/AAB until single integrated owner-test APK + phone tests.

## 2026-10-10 readiness safety bug discovered BEFORE deployment

`exports.dedaAutomationReadiness` was incorrectly checking `actor.data.role` although `requireGeneralManager(request)` returns normalized `actor.role`. This would have thrown on actual manager handshake. Fixed on DEV branch in commit `cbd271a8b112d3b679c634b1fff0c3279b7b9cba`; redundant check removed (authorization happens within `requireGeneralManager`). Added workflow regression check in `.github/workflows/qa-deda-next-four-stage1-place-policy.yml`, run https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/38008850432 (confirm final state, not implied success).

This approval authorizes preparation and prospective activation, but **the app owner must personally enable Cloud APIs and agree to billing if required**. NO operations bypass Google Cloud constraints.
