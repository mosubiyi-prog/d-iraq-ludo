# DEDA Point 1 — production Google same-UID login: exact deployment blocker
Date: 2026-11-14 (Iraq). READ ONLY findings, no live deploy.

## Verified in the actual Firebase project `deda-25b88`
- Existing GitHub Secrets primary DEDA Firebase service-account JSON authenticates to the correct project.
- Cloud Functions v2 API **lists** functions and permits `cloudfunctions.functions.create` and `cloudfunctions.functions.update`. The new required callable `dedaGoogleExistingUidTokenV1` is **NOT deployed**.
- Primary service account has `iam.serviceAccounts.actAs = false` at project scope. Specific runtime service-account `deda-recovery-runtime@deda-25b88.iam.gserviceaccount.com` test returned HTTP 403, no grant proven. Default compute runtime test HTTP 404, no grant proven. Without a verified exact runtime identity and deployer `roles/iam.serviceAccountUser`, DO NOT deploy.
- Second service-account secret `FIREBASE_SERVICE_ACCOUNT` is **missing**. Prior Firebase CLI login secret `FIREBASE_TOKEN` is **missing**. No alternate authorized deploy path is available.
- Billing GET returned **HTTP 403**: status UNKNOWN, NOT proof enabled or disabled. AppCheck app metadata returned **HTTP 404**: registration/Play Integrity not verified, NOT proof present or absent. The Google Android OAuth config has one Web client and Android client but **Play app-signing SHA-1/SHA-256 is NOT proven** (QA APK signer is not a Play signature).
- Function Auth Google provider config endpoint is readable but production Google/Play-Integrity eligibility needs direct confirmation from the owner/admin console.
- **No Production Firebase user records, service accounts, IAM roles, Cloud Function, Firestore rule, account session, Play app, diamond or original phone data were modified**.

## Evidence
1. [Github Actions 43513733998](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/43513733998): original exact project permission, billing and functions READ ONLY.
2. [Github Actions 43514129698](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/43514129698): primary and fallback IAM, specific runtime actAs checks READ ONLY.
3. [Github Actions 43514392790](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/43514392790): no alternate Firebase CLI token, READ ONLY.
4. [GitHub Actions 43512207413](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/43512207413): server Google signed-identity/UID guard unit tests SUCCESS (not production deploy).
5. [GitHub Actions 43511855387](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/43511855387): Flutter full assembled source/emulator QA SUCCESS (not replacement phone acceptance).

## Precise unblock, requiring project-owner action
- Via the owner's Google Cloud account, confirm existence of runtime service account `deda-recovery-runtime@deda-25b88.iam.gserviceaccount.com` and, **only if it is the reviewed function runtime**, grant `roles/iam.serviceAccountUser` **on that service account** to the CI deployer `firebase-adminsdk-fbsvc@deda-25b88.iam.gserviceaccount.com`. Do not grant broad Owner or Service Account Token Creator roles, and do not touch user accounts.
- Confirm authorized billing/pricing and Cloud Functions deployment availability. Cloud billing status is NOT established by existing CI permissions.
- Confirm Firebase AppCheck Play Integrity for `com.diraq.ludo.d_iraq_ludo` with the actual Play app-signing certificate, and Google provider/Web OAuth client for the same production Firebase project.
- Then re-run read-only deploy preflight, deploy **exactly one** server callable after reviewing function runtime/region/secrets, and test **one consenting healthy existing Google-linked account** on two phones with the original UID and server records. Until then, keep replacement Google flag OFF and do NOT give it a completed APK.
- Account conflicts A/B/C remain on hold; never delete, merge, or pay historical assets.

## Release truth
Point 1 source/QA: completed. Production activation and two-phone UID acceptance: **BLOCKED BY REAL IAM / APP CHECK / SIGNING PROOF**. Point 1 itself is NOT closed, and no claimed restored profile or financial data is valid.
