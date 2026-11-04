# DEDA — FlutterFire Stage 1 Integration QA (isolated, no deployment)

**Source:** owner-approved 100436 reference commit `40936af117d662f975a67cac4e21eab5f84e9ec2`, with selected QA-only files under this directory.

**Governance:** `خزان العمل المنعزل قيد الاكمال/00_فكشن فكرة 💭أساس العمل 💪👷💪.md` reviewed; only user-requested original account login, not recovery adapters or new feature branches. All 12 original vault codes stay unchanged.

**Test scope:** actual FlutterFire web SDK connected to local Firebase Auth/Functions/Firestore emulators; original UID is seeded by a local-only Admin SDK; two separate Firebase apps represent two devices. Flutter owner handoff must require server proof, a **demo-only QA callable** for issuer (NOT genuine App Check), session write/readback, and independent Auth sessions. Wrong PIN and unauthenticated reads must fail. No APK/AAB.

**Critical concurrency finding:** before hardening, two distinct devices could both receive grant while the server rate count stayed at one. The candidate issuer now requires an **existing server-only per-UID ledger** and updates it in a Firestore transaction. Missing ledger must fail closed; separate tests assert exact count two under parallel grants, no double count on same install and max three per hour. This ledger is not yet automatically provisioned in production; no deployment is authorized.

**Release blockers:** genuine Android Play Integrity/App Check, six-digit PIN abuse controls, integration into approved source app `lib/`, validation of recovery assets and all 12 adapters, Android physical-device QA, and owner approval. This work does not change `firestore.rules`, live Firebase, 100436, Play or user-facing app.

**Latest QA run:** inspect GitHub Actions for this branch; DO NOT write PASS until successful final run appears. Intermediate queued or canceled SHA runs are not evidence of complete FlutterFire integration.
