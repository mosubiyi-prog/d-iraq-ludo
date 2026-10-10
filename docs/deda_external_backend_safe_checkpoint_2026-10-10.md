# DEDA – secure managed Node alternative checkpoint, 2026-10-10

## Why alternative is considered
The owner has spent ~2 days blocked by Google Cloud's first-use country/TOS form, without Iraq in their dropdown. This is NOT a reason to use a false country, billing workaround or unverified credentials. The actual Firebase project is `deda-25b88`. GitHub read-only Cloud API check, run `38055747567`: Cloud Build DISABLED, Artifact Registry DISABLED, Cloud Run DISABLED, Cloud Functions ENABLED; billing status **UNKNOWN HTTP 403**.

## Safest fallback candidate
**Managed always-on Node.js HTTPS web service** that reuses the EXISTING Firebase Auth, Firestore and Node Firebase Admin transactions. Render or an equivalent supported managed Node host can be assessed with the owner's account. Availability in Iraq, provider terms, uptime and monthly fees are **not yet verified** and require explicit owner action; do not claim free or zero cost. Sleeping/no-cost web dynos and GitHub Actions cron cannot support real 10-second and 30-second automation reliably. A Node host is more compatible with existing Firebase Admin code than rewriting the whole DEDA backend in another datastore or edge runtime.

## Work already completed (DEV ONLY)
- `functions/deda_external_api.js`: bearer Firebase ID token authorization, strict manager checks, private Telegram secret-protected webhook, start/claim + ON/OFF reward interfaces, safe errors and body cap. NEVER trusts user-supplied account UID, raw Telegram IDs or claimed reward amounts.
- `functions/deda_external_server.js`: owner-gated runtime, uses ADC/service account secret from hosted runtime and validates exact `deda-25b88` project. Checks live official channel administrator membership + webhook EXACT match to the configured HTTPS origin before payout activation. Reuses existing atomic personal spendable wallet claim and secure one-use bot account binding. Has no API keys in source.
- `tests/stage14/deda_external_api.test.cjs`, `.github/workflows/qa-deda-external-backend-no-deploy.yml`: source-only CI, negative permission tests. These DO NOT deploy, activate bots, change Firebase, create APK or cost money.
- Admin ON/OFF setting stays OFF because **there is no durable, tested external scheduler** for 10-second trusted-PIN or 30-second new-place approval yet. The external API explicitly answers `ready:false`. This is mandatory, not an issue to bypass.

## Next engineering work before real owner usage
1. Add persistent event/retry mechanism for the original two Firestore listeners. Test restart, duplicate delivery, older requests, permission failures, owner-only opt-in, certificate number collision, PIN theft prevention and delay under load. An always-on production host (not sleeping) is required. Keep cloud runtime OFF until fully tested.
2. Implement/test **one** Flutter transport adapter (HTTPS bearer Firebase ID token) using `--dart-define` configurable HTTPS origin, to replace hard-coded `FirebaseFunctions.instance.httpsCallable` only in the upcoming one integrated build. The installed 100327 never changes.
3. Inspect and BACKUP actual live Firestore rules and merge only required extra rules with emulator validation. Never deploy checked-in old rules wholesale.
4. Choose provider based on verifiable Iraq account eligibility, reliability and fees, only after owner confirms provider account/connection. Store Firebase service-account credentials, Telegram bot token and separate webhook secret in provider secrets UI, never GitHub source or a ChatGPT message/photo.
5. Verify bot is administrator in official `@DEDA_Iraq` channel (owner screenshot did show bot in admin list), set proper Telegram webhook, confirm real /start nonce with DEDA user, getChatMember proof and once-only +10 diamonds with **zero manager gifting wallet debit**.
6. Restore accepted navigation golden app, test login speed, admin cards, diamond display and real mobile flows. Produce **one** signed APK and require owner phone test before any Play Production .aab.

## Current release blockers
- **Not deployed:** no hosted service chosen/connected, secrets/config missing, no live webhook, server-side scheduler not built or active, Flutter origin not wired.
- Google Cloud billing status is unknown; never assert it is ON or OFF.
- Stable `100327` remains untouched, GM auto toggles and Telegram rewards OFF. Google Play Production access granted, but no public release.
