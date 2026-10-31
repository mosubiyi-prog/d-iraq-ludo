# DEDA 100401 — Firebase launch requirements, exact read-only audit

Owner intent: finish a simple weekly level-XP league for ~20 actual DEDA accounts. No Pay/Play publishing, no changing original task points or accounts. Project: deda-25b88.

## Verified by successful GitHub Actions 41147895530 (read-only)
- Firestore API ENABLED, Cloud Functions API ENABLED, Service Usage API ENABLED.
- Cloud Build API DISABLED, Artifact Registry API DISABLED, Cloud Run API DISABLED.
- Service account can list/get/create/update Cloud Functions in project.
- Missing at *project scope*: serviceusage.services.enable, iam.serviceAccounts.actAs, cloudbuild.builds.create, artifactregistry.repositories.create. run.services.create is allowed.
- Execution service accounts actAs at specific account resources was NOT verified (compute default 404; App Engine default 403): do NOT claim the permission conclusively absent at the execution service-account scope without checking target.
- Billing status returned HTTP 403. This is UNKNOWN, not proof of Spark nor Blaze.
- Both community score functions are absent from us-central1 function listing: dedaWeeklyCommunityClaimV1 and dedaWeeklyCommunityStandingsV1. Listing complete.

## Exactly one owner-side decision first
View project billing/plan WITHOUT enrolling in billing or selecting a different country:
https://console.cloud.google.com/billing/linkedaccount?project=deda-25b88
Report the displayed project-billing link/plan status. Do not enter payment details without explicit approval. Firebase Functions gen2 generally requires Blaze billing; zero-charge usage is possible with free tiers but is not guaranteed.

## After owner authorization and verified billing readiness
1. Enable Cloud Build, Artifact Registry, and Cloud Run APIs on project deda-25b88 (do not create a new project). The owner can do this using Cloud Console if CI serviceaccount lacks serviceusage.services.enable.
2. Identify actual Gen2 execution runtime service account and grant only scoped roles required for a targeted deployment; currently IAM is insufficient in the project audit. Avoid granting Owner/editor to arbitrary principals.
3. Confirm Firebase App Check and auth, and deploy ONLY the two specified community callables in us-central1 after owner approval.
4. Provision deda_weekly_community_config/active with confirmed week start and grants disabled; prove two real accounts can see the same leaderboard and prevent duplicate points.
5. Leave weekly diamond award writer OFF until independent real tasks and wallet exact-once settlement are verified.

## Current delivery status
100400 code, retry journal, and tests pass; no Firebase deploy and no live 20-account scores. No cloud service, billing, user data, Firebase rules, APK or Play was modified by this audit.
