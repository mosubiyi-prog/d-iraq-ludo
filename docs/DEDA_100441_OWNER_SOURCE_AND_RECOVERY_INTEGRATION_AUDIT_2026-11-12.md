# DEDA — تدقيق أساس 100441 والربط الآمن للاسترجاع — 2026-11-12

## قرار التنفيذ ومصدر النسخة
- موافقة صاحب المشروع في المحادثة: أخذ نسخة من النسخة الحالية 100441 والعمل في فرع منعزل، بعد المراجعة، مع حفظ كل الوظائف وعدم تكرار الشيفرة.
- الفرع الجديد: `deda-100441-source-audit-isolated-recovery-2026-11-12`، أُنشئ من مصدر بناء APK 100441 المثبت في GitHub، عند commit `308a846ef0c44169929a2908adb0457b4b028672`. **هذا هو أصل البناء المقروء، وليس الادعاء بأن SHA التطبيق المثبت على الهاتف قد فُحص محلياً**.
- سير البناء: GitHub Actions `42413686506` نتيجة `completed/success` وhead_sha مطابق للـcommit أعلاه. وثيقة البناء `docs/DEDA_100441_SIGNED_OWNER_SESSION_DIAGNOSTIC_PHONE_QA_CHECKPOINT_2026-11-07.md` تسجل APK `DEDA-100441-COMPLETE-SESSION-RESCUE-DIAGNOSTIC-SIGNED.apk`، بصمة SHA256 `d7829013df4c493e90bab1b953472c8ab5240479de6211d84f96801464d99ddb` وشهادة التوقيع الأصلية.
- المرجع الناجح الأقدم 100436 مثبت عند المصدر `fea54d7db2e8a24a74267f04a14c9572bcb408ee` ومقبول على الهاتف كمرجع واجهة، **ليس بديلاً تلقائياً عن نسخة 100441**.
- فرع البحث والتطوير السابق `deda-100441-step1-legacy-google-proof-gate-isolated-no-deploy-2026-11-09` صار عند نقطة التوقف الوثائقية `9b57c7d2663eb4637eb40f08da9bd21795cdb64b`، بعد مصدر APK بـ216 commit (GitHub compare)، فلا يجوز دمجه بالكامل.
- سلسلة بناء 100441 تجمع التطبيق كاملاً داخل workspace مؤقت بواسطة `.github/workflows/deda-100441-complete-signed-session-diagnostic-no-play.yml` وأدوات `tools/app_stability/app_package/`. ملفات `lib/main.dart` الخام وحدها **لا تمثل بالضرورة** ملف التطبيق النهائي بعد تطبيق أدوات البناء.
- أعراض المستخدم المثبتة من الصور/الفيديو في المحادثة: تشخيص جلسة مجهولة، اختلاف UID الآيدي ودليل الرقم، عدم تأكد ربط Google، تعذر الأصدقاء، وعدم ظهور مدخل الإدارة. هذه أعراض جهاز، وليست فحص هوية مستقل.

## مصفوفة القرار — لا كود مكرر ولا تجاوز للصلاحيات

| مجال | الدليل في مصدر APK 100441 / الفرع اللاحق | قرار آمن |
|---|---|---|
| واجهة DEDA والدوري والإدارة والهدايا والآيدي | بناء 100441 يعيد تركيب 100440 ويختبر parity؛ وجود المصدر ونجاح CI لا يثبت عمل كل API على الجهاز | **محمي**: إبقاء أدوات التركيب وترتيب الواجهة وبطاقة Google في مكانها؛ لا استبدال شامل بـ100436 أو بالـmain الخام |
| فحص الجلسة | `lib/deda_session_diagnostic_readonly_100441.dart` و`bind_session_diagnostic_readonly_100441.py` موجودان في 100441، قراءة فقط | **موجود**: إعادة استخدامهما؛ لا إنشاء فاحص ثان |
| إدارة الدخول | `lib/deda_backend.dart:currentDedaAccountCanSeeAdminEntry` يستلزم جلسة مناسبة أو استعادتها لقراءة `admin_entry_access`؛ `currentUserIsAdmin` يستلزم Firebase Auth غير مجهول و`admins/{uid}` فعّال | **موجود لكن متعثر بالجلسة**: علاج إثبات هوية الحساب أولاً؛ لا إظهار زر إدارة بشكل صوري ولا منح admin |
| جلسة DEDA | `lib/deda_auth_session_runtime.dart`, `lib/deda_session_transition_gate.dart`, `lib/deda_session_recovery_coordinator.dart` | **موجود**: حارس Auth واحد، والمنقذ لا يعطي صلاحيات دخول ولا يعيد ممتلكات |
| Google داخل الإعدادات | `lib/deda_step1_google_settings_link_100439.dart` و`bind_google_account_settings_100439.py` يربطان فقط عندما تثبت هوية UID القديم | **موجود لكنه مقفل بحق**: لا تجاوز الحماية ولا نقل البطاقة |
| Google على هاتف بديل | `lib/deda_step2_google_replacement_login_100439.dart` بفحص `autoCreate:false` ورفض `isNewUser`؛ لم يثبت أن هذا يصلح حساب A/B/C الذي لم يكن مزوده مربوطاً أصلاً | **ناقص للتفعيل الحقيقي**: لا دخول بالحساب القديم دون ربط سابق موثق |
| التحقق الخاص OIDC / nonce / App Check | في الفرع اللاحق `functions/deda_100441_legacy_google_oidc_verifier_PRIVATE_NOT_EXPORTED.js` وFlutter review bridge؛ نجحت فحوص المحاكي/Node وFlutter، لكن الخدمة غير منشورة، وعقد Android/OAuth الحقيقي لم يثبت | **جديد نافع، معزول غير جاهز**: إبقاؤه في مصدر البحث؛ لا نقله إلى runtime أو `functions/index.js` ولا إصدار token |
| Canonical UID | `functions/deda_100441_canonical_uid_anti_split_preflight_PRIVATE_NOT_EXPORTED.js` + adapter + callable خاص في الفرع اللاحق؛ فحص `SPLIT/HOLD` دون اختيار صاحب الحساب | **جديد نافع للمراجعة فقط**: لا تحويل نتيجة الفحص إلى قرار ملكية أو تعديل UID |
| من يملك A/B/C | وثائق 2026-11-08/09 تسجل اختلاف مسار الآيدي ودليل الرقم والبروفايل؛ إثبات الملكية المستقل غير مكتمل | **عائق حقيقي**: HOLD، دون دمج أو حذف أو ترحيل بيانات أو استبدال UID |
| مراجعة التعارض | `inspectCanonicalUid` و`safeEvidenceAssessment` و`ownerDocumentsMatch` أدوارها تتقاطع لكن ليست ثلاثة مصادر تمنح صلاحية | **تداخل منطقي**: سياسة خادمية للمطابقة، حارس مستقل للملكية، ومنع انتقال Flutter؛ لا كود رابع |
| الرقم والرمز | `lib/deda_pin_auth.dart` و`functions/deda_owner_pin_verify_private_v1.js` مع أدوات إصدار الرمز | **موجود**: PIN وحده لا يثبت ملكية الحساب ولا يسمح بإصدار Firebase custom token |
| منظومة 12 كود للممتلكات | `DedaVaultManifest` يسرد 12 كوداً، لكن `DedaLinkedOwnerGuardianAssembly.prepare` يربط 4 adapters (backup/purchases/levels/places) | **ناقص**: لا اعتبار الـ12 مسترجعة؛ يراجع كل مجال ومصدره قبل استكمال العمال |
| الماسات والهدايا والدوري والإطارات والآيدي والأصدقاء والأماكن | فحوص المحاكي تحاكي جزءاً من السجلات؛ لا إثبات لجميع الممتلكات، خاصة ماسات الإعلانات المحلية القديمة | **غير مكتمل**: التوثيق ومطابقة كل أصل قبل الترحيل؛ لا منح أو تصفير أو مضاعفة |
| حسابات الإدارة الثلاثة | سجلات الإدارة `admins/{uid}` منفصلة عن هويات الحساب المتعارضة A/B/C؛ مدخل الإدارة `admin_entry_access` ليس إذناً فعلياً | **محمي**: لا تعديل الإدارة أو منح صلاحيات لتجاوز مشكلة الجلسة |

## قواعد قبل أي دمج أو APK
1. من المصدر `308a846...` فقط، وفحص أدوات إعادة تركيب APK ومطابقة بصمات الـ100441/100436؛ لا نسخ `lib/main.dart` من فرع معزول بشكل شامل.
2. نجاح `117/117` أو `61/61 + 28/28` يعود لاختبارات Node/Emulator/Flutter ولا يثبت استرجاع مستخدم حقيقي.
3. لا تفعيل `DEDA_STEP2_SPARK_LINKED_UID_READ_ONLY` أو أي مسار رابط قبل وثائق هوية أصلية متطابقة وعامل إثبات مستقل. منع `signInWithCredential` الذي قد ينشئ UID أثناء سباق تغيير مزود.
4. لا تعديل ولا نشر Firebase الحقيقي ولا قواعده، لا Play، لا تعويض ماسات ولا تغيير حسابات A/B/C أو ملفات الإدارة.
5. اختبار الهاتف والتابلت لحساب DEDA نفسه وGoogle الحقيقي لا يتم قبل التأكيد الآمن للهوية؛ التابلت حالياً عليه حساب DEDA مختلف، ومختبر QA مستقل عن الإنتاج.
6. الحالة الآن: **مصدر نسخة 100441 محدد ونسخة عمل معزولة محفوظة، لكن الاسترجاع الحقيقي متوقف عند إثبات المالك وتنفيذ ربط Google آمن غير منشئ ثم التحقق الفعلي من الممتلكات**.

## أدلة GitHub
- APK CI: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/42413686506
- CI الخاص بالتحقق المعزول: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/43036400305
- نقطة توقف 11 نوفمبر: https://github.com/mosubiyi-prog/d-iraq-ludo/commit/9b57c7d2663eb4637eb40f08da9bd21795cdb64b
- تدقيق التضارب: `docs/DEDA_RECOVERY_STEP3_EXISTING_CODE_OWNERSHIP_AND_OVERLAP_2026-11-09.md`
- تدقيق الجلسة/الإدارة: `docs/DEDA_100441_OWNER_ADMIN_SEPARATION_AND_TRUSTED_INSTALL_READONLY_2026-11-08.md`

**هذا التقرير أضيف إلى فرع العمل الجديد فقط، بلا تعديل Dart/JS/Functions/Android أو Firebase أو APK.**
