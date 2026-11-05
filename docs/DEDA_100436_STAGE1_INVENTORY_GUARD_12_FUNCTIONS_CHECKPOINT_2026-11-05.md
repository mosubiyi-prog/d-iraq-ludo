# DEDA 100436 — المرحلة رقم 1: جرد التجميع الشامل للحارس والـ12 كود والـFunctions

**التاريخ:** 2026-11-05  
**القرار المنفذ:** جرد ومراجعة وتحديد النواقص الفعلية فقط. لا دمج للأكواد ولا إعادة كتابة المنجز القديم ولا تفعيل ولا بناء APK ولا نشر.  
**التوثيق:** فرع `deda-100436-pin-compat-private-no-deploy-2026-11-05`؛ أخذت القراءة من هذا الفرع، ومن خزان `deda-100436-isolated-recovery-work-vault-five-codes-pending-completion-2026-11-02`.  
**النسخة المرجعية الناجحة المحمية:** 100436؛ لا تغيير على مصدرها ولا على 12 ملفاً أصلياً بالخزان.

## 1) جرد الأكواد الاثني عشر (فحصت وجود كل ملف داخل الخزان بالفعل)

| رقم | ملف الكود الأصلي | وظيفته الحقيقية | هل موجود في المسار التنفيذي الحالي؟ |
|---|---|---|---|
| 1 | `deda_100430_owner_uid_continuity.dart` | تثبيت UID الأصلي وربطه مع إثبات المالك | لا، محفوظ في الخزان فقط |
| 2 | `deda_100433_owner_confirmation_ui.dart` | تأكيد مالك الهاتف الأصلي بواجهة صريحة | لا، محفوظ في الخزان فقط |
| 3 | `deda_step2_level_points_restore.dart` | استعادة المستوى والنقاط من مصدر مثبت | لا، محفوظ في الخزان فقط |
| 4 | `deda_step2_original_backup_readback.dart` | قراءة مصدر النسخة الأصلية/دليلها | لا، محفوظ في الخزان فقط |
| 5 | `deda_linked_pin_reissue.js` | إعادة إصدار PIN خادمياً كإجراء مستقل | لا، محفوظ في الخزان فقط؛ لا يُشغّل من الحارس |
| 6 | `deda_step2_before_uid_link_evidence_checkpoint.dart` | حفظ أدلة الهاتف الأصلي قبل الربط | لا، محفوظ في الخزان فقط |
| 7 | `deda_step2_financial_source_audit.dart` | تدقيق الأدلة المالية؛ لا يمنح رصيداً | لا، محفوظ في الخزان فقط |
| 8 | `deda_legacy_purchase_evidence.dart` | أرشفة دليل الشراء المحلي دون منح ملكية | **نعم** `lib/` بنفس blob SHA `d762a1330a178d01135b318a5fdce3204fc48d32`؛ ليس Adapter استرجاع |
| 9 | `deda_step2_purchase_backup_readback.dart` | قراءة أدلة المشتريات الأصلية ومقارنتها | لا، محفوظ في الخزان فقط |
| 10 | `deda_step2_assets_readback.dart` | جرد الماسات والإطارات والآيدي والهدايا والدوري؛ قراءة لا منح | لا، محفوظ في الخزان فقط |
| 11 | `deda_step2_linked_published_place_recovery.dart` | إعادة ربط المكان المنشور الأصلي ضمن UID | لا، محفوظ في الخزان فقط |
| 12 | `deda_social_service.dart` | خدمات الأصدقاء والعلاقات | **نعم** `lib/` بنفس blob SHA `c2e89079633ebfe4a9ab5939d9d11347b5e55b1c`؛ لا يوجد Adapter استرجاع أصدقاء |

**نتيجة الجرد:** ملفات الخزان **12/12 موجودة**، لكن **10/12 ليست في مجلد التطبيق الجاري، و2/12 موجودتان في `lib/` أصلاً**. وجود الملف لا يعني تشغيله ضمن الاسترجاع. كل الأكواد الأصلية بقيت بلا تعديل.

## 2) الحارس والوصلة والسجل الموجودان فعلياً

- `lib/deda_step2_recovery_guardian.dart`: حارس فعلي ذو manifest لـ12 عنصراً؛ `DEDA_STEP2_RECOVERY_GUARDIAN=false` افتراضياً. ليس مشغلاً من `main.dart`؛ `fullAccountRestored=false` صراحة.
- `lib/deda_step2_linked_owner_guardian_assembly.dart`: تجميع للـAuth Port + Journal + Guardian، لكنه يمرر `adapters: const <DedaVaultCode, DedaVaultWorkerAdapter>{}` **فارغة**. لا يوجد عامل مجال واحد منفذ عبر هذا التجميع.
- `lib/deda_step2_recovery_journal_firestore.dart`: نقل دائم وذري إلى Firestore، لكن `DEDA_STEP2_RECOVERY_JOURNAL=false` ووظيفة `dedaRecoveryJournalComplete` غير مُصدّرة في Functions؛ القواعد المقترحة في الخزان/QA فقط، لا ضمن `firestore.rules` الحالي.
- `lib/deda_step2_linked_owner_flutter_handoff.dart` و`lib/deda_step2_linked_owner_firebase_port.dart`: وصلة وحارس Auth محفوظان، لكن OFF وغير مستدعيين من `main.dart`. Port الموجود يعتمد `signInWithEmailAndPassword` وبحاجة إلى إذن الجهاز `dedaIssueLinkedOriginalUidDeviceGrant` غير المصدّر.
- `lib/deda_step2_existing_account_signin_page.dart`: واجهة «لدي حساب» موجودة وOFF، `verifiedLogin=null` افتراضياً، وغير مستوردة من `main.dart`.
- `lib/deda_100431_linked_owner_session_policy.dart`، و`lib/deda_pin_auth.dart` و`lib/deda_backend.dart` تحوي حماية جلسة مستخدم مرتبطة بنطاق التجربة، لكنها لا تعني تمكين استرجاع كامل.
- `functions/deda_owner_pin_verify_private_v1.js`: وظيفة تحقق خادمي تحمي UID الأصلي وتتطلب App Check، **غير موصولة/مصدرة في `functions/index.js`**. تختلف عن مسار `signInWithEmailAndPassword` الحالي لأنها تصدر `customToken`؛ تحتاج محول Flutter واحداً واضحاً، لا تشغيل مسارين متعارضين.
- `functions/deda_pin_manual_recovery_compat_private_v1.js` و`functions/deda_pin_auto_recovery_worker.js`: مرشح مزامنة PIN بين Firestore وFirebase Auth ومعالجة فشل العملية موجود، ولكن في `functions/index.js` العلم `dedaPinCompatPilotEnabled=false`، فلا يُستعمل في مسار الاسترجاع اليدوي الحالي.
- `firestore.rules` الحالي لا يتضمن أسماء مجموعات `deda_recovery_journals` أو `deda_pin_recovery_locks`، ولا مصدر إذن الجلسة linked المرتبط المُختبر في QA. لا يجوز افتراض مطابقة الملف للإعدادات المنشورة.
- `deda_sessions/{uid}`: وثيقة واحدة ذات `installId` واحد؛ فحوص Emulator السابقة أثبتت إمكان احتفاظ أكثر من جهاز بنفس UID وصلاحيات محددة، لكنها لا تضمن تزامن كل الأقسام.

## 3) حفظ المنجز السابق وعدم تكراره

- GitHub Actions #41798062528: 33/33 فحص مصدر/قواعد Journal والحارس، كما وثقه سجل الخزان `08`.
- GitHub Actions #41810798354: 68/68 فحص تكامل SDK JS وAuth/Functions/Firestore Emulator عبر هواتف افتراضية وApp Check الرفض، بحسب سجل الخزان `12`.
- GitHub Actions #41817320617: 81/81 (منها 13 فحص Flutter للوصلة بPort وهمي، وتحليل Dart بلا مشاكل)، وفق سجل الخزان `13`. **لا تعيد بناء هذه المنظومة من الصفر.**
- GitHub Actions #41886712266: فحص FlutterFire الحقيقي عبر Chrome **FAILED / Timeout عند `Firebase.initializeApp`** قبل Auth، وفق سجل الخزان `14`. يجب معالجة فجوة اختبار SDK الحقيقي في الرقم 2، ولا يُسوَّق 81/81 بوصفه نجاح Android كامل.
- مرشح التحقق الخادمي/توافق PIN المستحدث في فرع التطوير: فحص V8 بمحاكاة تبعيات **37/37**؛ لا يتكافأ مع نجاح GitHub Actions أو Firebase Emulator للمرشح الجديد، ولم تتوفر نتيجة CI مُثبتة بعد.

## 4) قائمة الربط الناقص المثبتة — تنتقل كلها إلى المرحلة رقم 2 فقط

1. اختيار تدفق دخول واحد آمن: إثبات الهاتف والرمز بالخادم مع UID نفسه، والحفاظ على جلسة الجهاز الآخر؛ توحيد Flutter handoff و`customToken` أو المسار المرتبط المعتمد، ومنع فقدان أصل الحساب أو مسار anonymous بديل. يلزم إثبات أن UID الحساب كان مربوطاً أصلاً في Firebase Auth؛ أي حساب غير مرتبط يفشل بأمان ويحتاج معالجة مخولة.
2. توصيل «لدي حساب» و`verifiedLogin` بالتدفق المعتمد في فرع تطوير مشتق من 100436 دون تعديل المرجع الناجح، ومن دون إظهار نجاح محلي قبل قراءة أدلة الخادم.
3. إعداد وإصدار Functions اللازمة (**owner PIN proof، إذن الجهاز، إكمال Journal**) مع قواعد Firestore المقيدة بعد فحوص Emulator وتفويض المالك؛ لا نفعّل طيار PIN sync قبل توافق الرمز القديم/الجديد واستراتيجية التعارض.
4. ملء Adapters الحارس الأربعة المؤهلة (`originalBackupReadback`, `purchaseBackupReadback`, `levelPointsRestore`, `publishedPlaceRecovery`) من الملفات الموجودة واختبار قراءة المصدر وإثباته؛ الأكواد الأخرى وظائف تأكيد/تدقيق/أمان/أصدقاء لا تتحول إلى كتابات مالية تلقائياً. يجب تغطية مصادر الهوية/الآيدي/الماسات/الإطارات/المستوى/المهام/الهدايا/الدوري/الأصدقاء/المكان/الأسئلة والإعدادات قبل إعلان الاسترجاع كاملاً؛ لا يجوز تخمين أو منح رصيد من لقطة محلية بلا مصدر موثوق.
5. إغلاق الفجوات الموثقة في `deda_sessions` و`installId` وFirestore Rules والإدارة، والفشل الجزئي، والتزامن على هاتفين؛ استثمار اختبارات JS/Flutter السابقة وتكملة اختبار FlutterFire الحقيقي على Emulator/Android. قسم «الأجهزة المسجلة» مؤجل صراحةً بقرار المالك.
6. عدم نقل `deda_100430_owner_uid_continuity.dart` كما هو إذا كان سيكتب جلسة مباشرة قبل إذن الخادم. لا نقل شامل لفرع 100434 أو تعديل أكواد الخزان الأصلية، بل نقل التوصيلات المنتقاة بعد مطابقة الاعتماديات واختبارها.

## 5) حكم إغلاق المرحلة رقم 1

**مرحلة الجرد/التجميع التحليلي مكتملة:** تمت مراجعة وجود الملفات 12/12، الحارس، وصلة Flutter، Journal، Functions، قواعد Firestore، فحوص Emulator السابقة، وتحديد كل أنواع الربط المطلوبة. **لكن تفعيل منظومة استرجاع الحساب وتجميعها داخل APK لم يحدث بعد**؛ هذا نطاق المرحلة 2 و3 حسب قرار المالك، وليس نقصاً مخفياً في جرد المرحلة 1.

**المرحلة المقترحة بعد موافقة المالك:** رقم 2 «التفعيل والفحص» فقط: استكمال التوصيلات والـAdapters والصلاحيات على نسخة تطوير منفصلة من 100436 مع نجاح فحوص Functions/Firestore/FlutterFire، ثم تسليم النتيجة قبل إنشاء APK رقم 3. لا نشر Play أو تعديل الإنتاج إلا بأمر مستقل.
