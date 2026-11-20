# DEDA — Director directive 01 — isolated owner/admin session safety repair
Date: 2026-11-20 (Iraq)
Status: **PARTIAL SOURCE REPAIR / NOT APPROVED FOR INSTALLATION**
Branch: `deda-100451-owner-admin-session-safe-repair-2026-11-20`
Protected source baseline: `3ef175a780d9cffd93cfe1ef79ebfd21880acfe5` (100451 signed CI source on 100450 working branch).
CI evidence: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/44624706099 — **success**.
No production deployment, Firebase write, Google Play release or replacement APK was performed.

## Original job
Restore stable DEDA login/owner UID and general-manager access without account identity churn, data loss, removal of existing app features, or changing approved UI placements. Complete historical asset recovery only with independently verified provenance. The older 100451 signed APK is **not** an approved owner-device upgrade.

## What was changed (in this isolated branch only)
- `lib/deda_100431_linked_owner_session_policy.dart`: In owner-protected builds, admin sign-out now requires explicit *fresh-server evidence that the current principal has no public DEDA owner session*. Missing evidence fails closed. The published non-pilot behavior is unchanged.
- `lib/deda_backend.dart`: Before admin sign-out, check the active administrator document and the server-side `deda_sessions/{uid}` owner record, reject owner collisions, and recheck the same principal before sign-out. Only read operations; no UID rewrite, deletion, asset movement or owner logout.
- `test/deda_owner_session_compat_private_test.dart`: Add regression cases for dual-role admin/owner UID and missing fresh owner proof, retain old published-path assertions.
- `.github/workflows/deda-100452-owner-admin-session-repair-qa-no-deploy.yml`: Test source guard, Flutter focused tests, legacy auth-conflict merge, full protected source assembly and merged-backend analyzer. **No APK**.

## 15 mandatory oversight areas
| # | Area | Result |
|---|---|---|
| 01 | Repo / protected branches | New isolated branch from verified 100451 source; originals not changed |
| 02 | Duplicate / conflicting source | CI source-merge and reconciliation regression passed |
| 03 | UID / sessions | New owner-session sign-out block passed Flutter policy tests and assembled code |
| 04 | Restoration / Google | **NOT COMPLETE** — historical owner and data recovery not established; removed Google card not reintroduced |
| 05 | Profile | Source-only patch does not edit profile; full behavioral QA not run |
| 06 | Friends / weekly league | Source-only patch does not edit their files; full behavioral QA not run |
| 07 | Diamonds / frames / premium IDs / gifts | No balances or user data touched; full readback/restoration not verified |
| 08 | Daily tasks / quizzes | Not edited; behavioral QA not run |
| 09 | Administration | Logout owner-protection tests passed. **Admin simultaneous access still blocked on shared Auth** |
| 10 | UI placement / feature preservation | No UI file changed. Full feature device check not run |
| 11 | Startup / performance | No device test run |
| 12 | Firebase | No production writes/deploy; checks use `Source.server` |
| 13 | Package / signing | **NO NEW APK BUILT**; previous 100451 remains QA-only |
| 14 | Tests | CI run 44624706099 successful; physical-device test not run |
| 15 | Manager instructions | Directive 01 read and safety stop maintained |

## Hard stops before final approved upgrade
The source still intentionally refuses administrator sign-in when the owner's UID occupies shared `FirebaseAuth.instance`, because a separate full administrator Auth/Firestore lane has **not** been safely wired through every admin data access. The account recovery completion gate remains false; historical assets and conflicted A/B/C/D identities have not been restored or merged. The existing encrypted Firebase read-only backup does not include device-local data or Firebase Storage binaries. Do not install any new QA build over the sole original owner device without verified backup and end-to-end non-destructive device QA.

This is **not** a claim that the user's requested complete APK has been delivered. No manual phone test, full-data restoration, or final release evidence exists as of this record.

## 2026-11-20 — B canonical continuation (same task, no new identity path)
**Director instruction:** Resume the five-point original-account consolidation plan, with B as the historical registration target, preserve A original-ID and C social rights, complete the application only after proved safe. No more A/C/D reselection or alternative "room" solution.
**Prior evidence reused:** 2026-11-13 historical read-only run records, 2026-11-19 Firebase encrypted backup and preceding 100451 build. Historical registry `deda_account_directory.createdUid == deda_credentials.createdUid == B`, original personal-ID owner `A`, social-record owner `C`. This establishes lineage, **not** B sign-in or entitlement to transfer other users' sources.
**Changes:** Existing `functions/deda_100441_owner_split_identity_challenge_review_private_v1.js` received `assessBCanonicalConsolidation`: a strictly offline non-authorizing preflight for B registration, explicitly requires independent B-bound auth review, individually reviewed A/C historical rights with exact original-ID/social UID matching, complete Firebase Auth+Firestore, Storage, device-local archive, purchase ledger and rollback readback. Returns HOLD or separate-review candidate with `canMerge=false`, `canAuthenticate=false`, `canTransferAssets=false` and no Firebase writes. Existing public Auth flows are **unchanged**. Companion tests added to `functions/test/deda_100441_owner_split_identity_challenge_review_private_v1.test.js`; CI workflow `.github/workflows/deda-100452-owner-admin-session-repair-qa-no-deploy.yml` now runs them alongside full protected source checks.
**Evidence:** [GitHub Actions 44631324519](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/44631324519) — **SUCCESS** at source SHA `e159731aa1934f0e9762a7382329b4ff20e04875`: 21 Node tests PASS, 0 FAIL; guarded admin signout source checks pass; focused Flutter tests pass; exact full protected source assembly and Dart analysis pass. This is **NOT** an APK or physical-device test.
**Backup fact verified:** The 2026-11-19 archive manifest includes 2,066 Firestore documents and 632 Firebase Auth user metadata records; Firebase Storage included=false, Auth credential secrets included=false. The encrypted cloud snapshot is not a verified on-device archive of historical purchases, XP, diamond receipts, quizzes or settings.
**Directive 01 oversight 01-15:** (01) isolated version-controlled branch preserved; (02) existing 100441 reviewer reused, no duplicate deployed auth path; (03) B, A and C preserved, no UID mutation; (04) owner restoration and Google **not completed**; (05) profile source protected, no runtime verification; (06) friends/league source rights require separate evidence, no runtime verification; (07) no wallet, ID, frame, gift, or receipt transfer; (08) local tasks, quizzes not available in cloud backup; (09) protected admin code source tests pass but actual parallel admin login remains blocked; (10) no UI or feature position changed; (11) no phone startup/performance test; (12) no Firebase writes/rule deploy/billing; (13) **no new signed APK**; (14) Node 21/21 and focused Flutter+assembly CI successful, not a real-phone pass; (15) instruction 01 and terms read, unsafe claims withheld.
**Status:** PARTIAL SOURCE REPAIR. **Remaining safety gates:** independently authenticated B with provenance for A/C rights, complete asset/local/Storage readbacks, server-authorized permission migration or equivalent safe access on Spark, real original-phone + second-phone verification, confirmed admin entry without replacing DEDA Auth, complete signed Android package and no-loss functional check. Do not mark `completeOwnerDelivery=true` or install an interim candidate on the only original phone.


---

## 2026-11-21 — استئناف المهمة المعتمدة: الجزء المتبقي من النقطة 1 (B identity proof)

**أمر الاستئناف:** «باشر بستأناف العمل». الاستئناف محصور في **إثبات صلاحية B وربط أصل حقوق A وC بها**، وليس إعادة جرد الهويات أو استبدال الخطة الخماسية أو معالجة الإدارة كمهمة مستقلة.

**مرجع البداية:** الفرع نفسه `deda-100451-owner-admin-session-safe-repair-2026-11-20`، آخر رأس عند ابتداء المراجعة `856cb8919ee6c1c255a6550aa1ac97428c76d9b7`. قرئت نصوص `AGENTS.md` وتعليمات المدير العام `01` كاملة، وشروط وأحكام العمل على تطبيق DEDA من `main`، ووثيقة التوقف الصحي، وسجل التنفيذ هذا، وتقرير السبب الجذري 18 نوفمبر وتقرير الأدلة التاريخية 13 نوفمبر ودليل المراجعة المستقلة 17 نوفمبر.

### فحص الأدلة الموجودة، من دون إعادة فحص إنتاج أو طلب عائدية الخط مجدداً
1. سجلات القراءة السابقة (GitHub Actions `43315261945`, `43316448609`, `43316994541`) تثبت أن `B` أقدم Firebase Auth UID، و`deda_account_directory.createdUid == deda_credentials.createdUid == B`، وأن مسار الآيدي التاريخي يخص `A` والسجل الاجتماعي يشير إلى `C`. العلاقة بين `users/A` و`users/B` عبر installId قرينة تقنية قابلة للنسخ **وليست إثبات حيازة مصادقاً**؛ وتطابق C في `accountKey` لا يثبت جهازها. لم تُعد هذه الفحوص، ولم تُستخرج UIDs أو أرقام أو PIN.
2. فحص 13 نوفمبر سجّل عدم وجود Google أو بريد أو موفر مصادقة تاريخي مرتبط ظاهر لـA/B/C آنذاك؛ ولا تتضمن الأدلة المتاحة جلسة B مستقلة موثّقة الآن. لا يُخلط مختبر Google أو الجلسة D مع B.
3. `functions/deda_owner_pin_verify_private_v1.js::validCanonicalProof` يشترط تطابق `route.ownerUid` مع `directory.createdUid`، وكذلك إثبات Auth المرتبط. حالة A/B التاريخية لا تستوفيه، فلا يكون PIN أو تسجيل دخول على UID آخر تفويضاً لتجاوز حارس الآيدي. **الحارس لا يُخفف.**
4. `functions/deda_100441_owner_split_identity_challenge_review_private_v1.js::reviewReadiness` يشترط PIN خادمي حديثاً وعاملاً مستقلاً موثق المصدر مرتبطاً بـUID تاريخي، ومراجعة مستقلة حقيقية؛ `assessBCanonicalConsolidation` يشترط أن يكون الإثبات مربوطاً تحديداً بـB ثم شهادات نطاق حقوق A/C. كلاهما أداة فحص غير منشورة، وبلا إصدار Auth أو تصاريح.
5. سجل 17 نوفمبر `qa/unified_room_private/DEDA_OWNER_HISTORICAL_SOURCE_AND_INDEPENDENT_EVIDENCE_DECISION_2026-11-17.md` فرّق صراحة بين وجود مستند عائدية خط ذُكر سابقاً وبين **التحقق الرسمي من أصالته وتغطيته تاريخ تسجيل B وربطه بشخص الحساب**. لا يوجد في الأدلة المقروءة قرار مراجعة بشرية مستقلة موثوق مكتمل أو إثبات دخول مصادق أصلي إلى B؛ لا يُطلب من المالك إعادة تقديم وثيقة سبق الحديث عنها لمجرد بدء الاستئناف.

### نتيجة الجزء المستأنف، والشرط المحدد لاستكماله
**الحكم:** `B = HISTORICAL REGISTRATION UID VERIFIED`، أما `B PERSONALLY AUTHENTICATED / A-C RIGHTS RECONCILED = NOT VERIFIED`. السبب ليس نقص بناء APK أو فشل اختبارات؛ بل نقص **إثبات مستقل صادر/متحقق من جهة موثوقة ومربوط بسجل B التاريخي ومجالات A/C، مع مراجعة مخولة**. يمكن الاستفادة من شهادة عائدية الخط التاريخية الموجودة إن جرى التحقق من أصالتها وتواريخها مباشرة لدى مصدرها، مع مطابقة تاريخ DEDA وسجل الحساب، لكن الشهادة أو PIN بمفردهما لا يثبتان إنشاء حساب Auth لأن تسجيل DEDA القديم لم يشترط OTP لدى المشغل.

**حد التنفيذ الحالي:** لا توجد في اتصال GitHub أداة لإثبات جهة إصدار مستند الاتصالات أو إصدار مصادقة Firebase تاريخية؛ ولا يجوز اصطناع نتائج `independentProof` و`reviewRecord` داخل محاكي ثم اعتبارها إنتاجية. لذلك **SAFE HOLD للانتقال إلى نقل A/C أو تفعيل دخول B** حتى توفر تحقق مستقل حقيقي وتصريح محدد. لا تبدأ النقطة الثانية ولا تُقدَّم نسخة 100451 بوصفها علاجاً، ولا يُفعَّل Google.

**سجل التعليمات 01–15:** (01) الفرع والنسخ محمية؛ (02) أُعيد استعمال كود المراجعة الموجود ولم يُنسخ؛ (03) B/A/C/D بقيت دون تغيير؛ (04) لا استرجاع أو Google أو جلسة حقيقية جديدة؛ (05) الآيدي والملف لم يُعدّلا؛ (06) الأصدقاء والدوري لم يُغيَّرا؛ (07) لا أرصدة/هدايا/إطارات/مشتريات نقلت؛ (08) المهام/الأسئلة والتقدم المحلي لم يُمسا؛ (09) لا تغيير في الإدارة؛ (10) لا ملفات واجهات أو وظائف تغيرت؛ (11) لا ادعاء اختبار أداء هاتف؛ (12) لا كتابة Firebase أو قواعد أو فوترة؛ (13) لا APK/AAB أو توقيع؛ (14) هذه مراجعة مصادر محفوظة فقط، فحوص `44631324519` السابقة ليست نتيجة فحص حي جديد؛ (15) روجعت 01 والشروط وقرارات التوقف، والحارس الأحمر مطبق.

**الملف المعدل:** هذه الإضافة الرقابية لهذا السجل وحدها؛ **لا كود تطبيق ولا قواعد ولا هويات أو بيانات إنتاجية**. **الحالة:** نقطة 1 مستأنفة ومحقَّقة تاريخياً إلى حد الأدلة، لكنها **جزئية / SAFE HOLD بانتظار تحقق مستقل حقيقي**؛ هذا ليس إعلان إكمالها.


---

## 2026-11-21 — B registration / A-C rights challenge replay guard (source-only)
**Scope:** continue original five-point plan, point 1 only. Verified registration lineage B must not be confused with independently authenticated ownership of B, A or C.
**Actual source fix:** existing `assessBCanonicalConsolidation` now preserves `bIsRegistrationUid=true` after validating immutable B registration, even while refusing any rights/auth grant; accepts A/C historical scope review only when its challenge digest matches the current trusted PIN challenge; rejects re-use of a single source receipt across distinct rights domains. Existing reviewer, not a new migration system.
**Regression:** add negative tests for old/wrong/missing challenge, duplicate per-domain receipt, and correct separation between B lineage and B ownership. Workflow already tests both files on push. No Firebase rules or production Auth/Firestore data altered; no APK, Google, balance, ID or administrative privilege changes.
**Protection:** `canAuthenticate=false`, `canMerge=false`, `canTransferAssets=false`, `productionWrites=false` on all paths; evidence source validity remains dependent on an actual independent verifier/reviewer, which is not simulated as production.
**01–15:** branch and protected source unchanged apart from existing private review module/test and this log (01/02); UIDs and sessions never modified (03); no recovery or Google (04); no UI/profile/friends/league/store/tasks/admin/performance alterations (05–11); no Firebase production writes/billing (12); no APK (13); existing source QA to run on push and no phone test claimed (14); mandatory directives reread and safety HOLD preserved (15).
**Status:** point 1 partial; code hardening is not evidence of ownership and does not complete B/A/C unification.


## 2026-11-21 — Point 1 continued: same-source B/A/C snapshot integrity preflight
**Scope:** same point 1, same owner/admin safe-repair branch, same 01 directives (full AGENTS, manager 01 and terms read); existing 13/17/20 Nov evidence reused. No re-selection of B, no reconstruction of the prior emulator room, and no Google.
**Code:** in existing non-exported offline `assessBCanonicalConsolidation`, tie independently reviewed A/C ownership map and archival readback to an identical server-snapshot SHA-256. Bind historical original-ID owner A and friends/social owner C to the reviewed sources; fail closed on missing, old or mismatched evidence, without promoting any real UID. Regression tests added for mismatched/missing digests and changed A/C ownership mapping.
**Security:** The SHA-256 is an integrity pointer only, NOT personal authentication. A trusted server must compute it from authoritative documents with revision preconditions; fabricated or client-provided hashes grant nothing. This private module continues returning `canAuthenticate=false`, `canMerge=false`, `canTransferAssets=false`, `productionWrites=false`.
**15 controls:** (01) same branch and protected baseline; (02) reuse existing reviewer; (03) no UID changes; (04) no Google/recovery; (05) profile & ID unchanged; (06) friends & league unchanged; (07) no financial/gift/store edits; (08) tasks and XP unchanged; (09) admin unchanged; (10) UI unchanged; (11) no device-performance claim; (12) no Firebase production/rules/billing edits; (13) no APK; (14) existing CI on push must verify and phone not tested; (15) instructions 01 and terms respected. Status PARTIAL / production B ownership and A/C reconciliation still unverified.


### Verification follow-up — exact CI evidence (2026-11-21 Iraq)
- Initial source SHA `b1c99601438612d4d3d711cffa7fad81f062ae1c`: [run 44824098325](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/44824098325) FAILED at the existing backup-regression fixture: the newly introduced `sourceSnapshotSha256` key was inadvertently included among missing backup *categories*, producing `SOURCE_SNAPSHOT_READBACK_MISMATCH` where the test expected `COMPLETE_LOSSLESS_RECOVERY_SOURCES_MISSING`. No production failure or data mutation occurred.
- Corrected only the test fixture (not the security gate) at `7d3900f8d9cbcdf9abfc9a495145f2b2dce30b69`: missing category cases now exclude the digest, which has separate mismatch tests.
- **Final verification:** [GitHub Actions 44824288873](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/44824288873) **SUCCESS** on SHA `7d3900f8d9cbcdf9abfc9a495145f2b2dce30b69`. B/A/C rights-review regression, protected admin entry/exit source guard, focused Flutter tests, merge-conflict regression, full protected source assembly, analysis of assembled backend/policy, and no-deploy declaration all passed.
- **Evidence limits:** Offline/synthetic evidence only. Snapshot digest equality does **not** authenticate the underlying snapshots; a trusted server source and independent owner verifier must establish authenticity. No real B authentication, A/C rights transfer or Firestore/Rules/Auth production write, actual phone trial, final APK or Google link. **Point 1 remains PARTIAL / SAFE HOLD for production cutover only.**


## 2026-11-21 — B all-eight scope atomic integration; continuity-first
**Goal:** complete the technical unification staging for historical registration B, with A original ID and C friends/social retained. Same existing owner/admin work branch; no new standalone room.
**Code:** `functions/deda_unified_room_grant_issuer_private_v1.js` adds private `issueAllForB`: requires durable authenticated B UID and separate independent review of EVERY one of eight scopes, checks all owner history and session rows, reads 8 projections, and stages exactly 8 scope views + 8 read-only grants + 8 audits inside a single Firestore transaction. Any missing/changed A/C source, revoked/issued scope, absent independent review, or stale B session holds with ZERO writes. Previous single-domain issue and revoke paths remain unchanged.
**Tests:** add a full synthetic B integration through existing readonly guard, assert no UID/financial/admin effects, original A/C rows untouched and no re-issuance; fault-inject one failure among eight and verify no partial issuance. Reuse the existing 100452 source/Flutter merge CI; no APK.
**Instructions 01–15:** source branch and baseline protected; only private issuer, test, CI and this log changed; no UID creation; no Google/recovery; no profile/social/daily task/league/store mutation, no UI moves, no admin access; no device QA; no Firebase production write/rules/billing; no Play. This does not claim to prove historical B ownership.
**Status:** staged atomic all-eight integration test pending CI. Live consolidation remains independently authorized only, as no trusted B ownership/durable Auth proof was provided by this code.


### B eight-scope atomic issue — CI verified 2026-11-21 (Iraq)
- [Actions run 44825650600](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/44825650600) = **SUCCESS**, SHA `c47e35a781e764d6fa07334f0df634599996da13`.
- 24/24 B historical proof/review gate Node tests PASS and 18/18 private grant issuer tests PASS, including atomic all-eight issued versus zero write on wrong historical owner/absent scope/existing grant, followed by independent readonly-guard reads for each synthetic domain. Focused Flutter 13/13 PASS, protected admin guard and assembled 100450 source analysis PASS.
- No existing production Firebase user or DEDA historical account was modified. No UID migration, wallet credit, Google link, full real-data merge, APK or Play deployment. `issueAllForB` remains private, disabled by default, not exported in `functions/index.js`. Cannot be enabled as a real owner grant without durable B Auth and independent source authorization.
- **Point 1 remains PARTIAL on the actual owner account**. This is an implemented, tested atomic staging path only; successful QA is not real historical rights transfer.
