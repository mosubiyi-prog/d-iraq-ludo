# DEDA 100436 — نقطة استئناف الاسترجاع / 2026-11-05

## المرجع المحمي والعمل الحالي
- مستودع: `mosubiyi-prog/d-iraq-ludo`.
- النسخة المحمية 100436 عند `fea54d7db2e8a24a74267f04a14c9572bcb408ee`؛ **لا تُعدّل**.
- فرع استكمال التطبيق الكامل: `deda-100436-stage2-recovery-buildable-integration-qa-2026-11-05`.
- آخر Commit تنفيذي مفحوص عند إعداد هذه الملاحظة: `cd6b4ac5e4fc146f2237614afb0d175727d63f2b`.
- GitHub Actions: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/42079911046 — **success** على Commit المذكور (Node/Functions + Flutter analyzer + source unit/widget regression).
- يجب إعادة قراءة رأس الفرع HEAD عند الاستئناف؛ هذه الوثيقة نفسها تضيف Commit توثيقياً فقط.

## ما تم إغلاقه عند هذه النقطة
- سلوك ربط حساب قديم مع UID الأصلي، الحارس، الجلسة وفصل الإدارة تحت فحوص المصدر والمحاكي السابقة، **ولا يعني هذا تفعيل الإنتاج**.
- مسار تدقيق مالي للماسات القديمة: قراءة أرشيف الهاتف الأصلي والمصادر المتاحة دون إصدار رصيد/جائزة. نقص تاريخ إعلانات AdMob القديم يظل HOLD، ولا يمنع متابعة التحقق المستقل من المجالات الآمنة.
- إصلاح الحارس في `f0070939...` يضع الماسات غير المثبتة في مراجعة، حتى لو تطابق مصدر أرشيف.
- إصلاح التزامن في `a94b3bfd...` والاختبارات في `1b2afcf4...` ثم الحفاظ على عقد أخطاء Future في `cd6b4ac5...`: لا يمكن لطلبين متزامنين في عملية Flutter واحدة إنشاء معرفي Journal مختلفين لنفس الحساب؛ تم اختبار التكرار والبيانات المحلية المعطوبة، ونجح CI الأخير.
- النسخة المحمية وخزان الأكواد الـ12 لم يُمسّا؛ لا APK/AAB ولا نشر Play بهذا العمل.

## حقيقة الجاهزية وما يليها داخل نفس المرحلة (بدون إعادة البداية)
- **الاسترجاع الكامل لم يكتمل وليس جاهزاً لبناء نسخة مكتملة**. `DedaStep2CompletionReport.canPrepareFullRecoveryApk` و `fullAccountRestored` ما زالا false قصداً. لا تُرفع الحواجز بشيفرة شكلية.
- `lib/main.dart` يضم شاشة «لدي حساب» ووصلة `DedaLinkedOwnerGuardianAssembly.prepare()` لكن flags معطلة افتراضياً حتى يُثبت المسار الحقيقي، ولا ينتقل إلى HomePage إلا بعد `fullAccountRestored`.
- لا تزال هناك بيانات تتطلب استرجاعاً حقيقياً وقراءة تحقق بعد الكتابة: أرصدة الماسات القديمة/دفتر الإنفاق، الهدايا والأصول المملوكة، المهام/أسئلة المرور التاريخية، الأصدقاء والمحفوظات والإعدادات والـ100340 القديمة، وصلاحيات الإنتاج/اختبار هاتفين.
- **الخطوة التالية:** استكمال ربط مصادر/استعادة المجالات الناقصة بالعمال الموجودين بدل إضافة أنظمة موازية؛ اجعل كل مجال ذا إثبات خادم/UID ورصيد قبل/بعد، واختبر فشل وسط العملية ومنع الازدواج. راجع `functions/index.js` ومفكرة فكشن فكرة في الخزان قبل أي تفعيل.
- لا تعديل على Firebase الحقيقي ولا تغييرات مالية فعلية ولا بناء نسخة موصوفة بأنها كاملة إلا بعد استيفاء مصادر البيانات والفحوص والموافقة اللازمة.

## إضافة مثبتة بعد النقطة السابقة — حارس المجالات المستقلة
- Commit مفحوص: `ad2d1162b3df6c2c03d70870e474cd5007c18e11`.
- فحص GitHub Actions: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/42084769534 — **success** على الـCommit المذكور: تدقيق Dart للتطبيق والملفات المستوردة، اختبارات Flutter، وNode/Functions.
- `DedaVaultPreflightAdapter` صار يراجع أهلية كل مجال مدعوم **بعد إثبات UID الأصلي وقبل حجز Journal**. أي تحايل بالهوية أو غياب الخادم الفعلي يوقف الفحص؛ لا تسامح فيه.
- إذا غاب أرشيف شراء قديم أو تلفت صيغته المحلية، يوضع مجال الشراء في `needsReview` بدون منح ماسات أو شراء وهمي، وتستمر المجالات المستقلة (المستوى والمكان). لا تُنشأ عملية Journal مدفوعة لهذه الحالة.
- إن أثبت الخادم أنه لا يوجد مكان **منشور** للحساب، تصبح خطوة المكان `notApplicable`، دون إنجاز وهمي أو أي كتابة محلية، ولا يمنع ذلك سريان المجالات الأخرى؛ وجود مسودات ومكان محفوظ ما زال يحتاج سياسة مستقلة.
- إذا ظهر مكان منشور، تبقى شروط المطابقة الصارمة: UID صاحب المكان الأصلي ورقم الموافقة والبيانات من الخادم نفسه. وجود مكان بمالك غريب أو استجابة كاش لا يُعد حالة عدم انطباق.
- أضيفت اختبارات تكرار الاسترجاع، انفصال المجالات، عدم وجود مكان، مصدر شراء مفقود، مصدر أجنبي، وحالة الاكتمال. جميعها ضمن CI الأخير.
- **هذه خطوة ربط وتشغيل معزولة ومفحوصة، وليست اكتمال الاسترجاع.** بقيت مفاتيح تشغيل الإنتاج وإطلاق وظائف الخادم وقرار `fullAccountRestored` مغلقة؛ لا APK/AAB ولا Play بهذا التغيير. لا تغيّر هذه الحواجز دون استكمال بيانات الحساب الأساسية وفحص أجهزة حقيقية.

## 2026-11-05 — تكامل أرشيف الأماكن والإعدادات القديمة (حماية نفس الـ UID)
- آخر Commit تنفيذي مفحوص: `98ea9535f7cc84df8d1f1b050cfb60f955190067`.
- فحص CI الأخضر: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/42089748269 — نجاح Node/Functions وفحص Flutter وDart واختبارات الواجهة والتكامل، متضمناً الاختبارات الجديدة.
- تم ربط خطوة حفظ الأماكن المحفوظة والإعدادات القديمة بواجهة تأكيد الحساب على **الهاتف الأصلي بعد الربط**؛ لا تحفظ بيانات مشتركة على الجهاز بدون موافقة صريحة، ولا تكتب على مصدر قديم أو رصيد.
- `lib/deda_step2_global_places_settings_restore.dart`: استرجاع بيانات العرض القديمة من أرشيف Firestore الموثوق بنفس UID إلى جهاز جديد مع التحقق من المصدر، فحص كامل القيم أولاً، رفض أي بيانات محلية مختلفة، كتابة القيم الغائبة فقط، والقراءة اللاحقة؛ إعادة المحاولة لا تنسخ مكرراً.
- وصلة `DedaLinkedOwnerGuardianAssembly` و`Bridge` تتيح الخدمة **عند طلب استرجاع صريح فقط**، ومفاتيح الميزة OFF افتراضياً. غياب الأرشيف المثبت يأخذ HOLD مستقل؛ محتوى مزور/كاش/هوية مختلفة يوقف العملية. لا تُفسر نجاح هذه الخطوة بأنه اكتمال كل إعدادات الحساب أو أصوله.
- الاختبارات المضافة: `test/deda_step2_global_places_settings_restore_private_test.dart` وتوسعة اختبار الحارس. QA يشمل المصدر والرجوع عند تباين UID ومنع استبدال تفضيلات هاتف مستخدم آخر.
- **مهم: النسخة ما زالت غير جاهزة كبناء استرجاع كامل.** `DedaStep2CompletionReport.canPrepareFullRecoveryApk` مغلقة حسب التصميم، وهناك مصادر تاريخية لا يمكن اختلاقها ولا يعدلها هذا الإصلاح، وخدمات/قواعد Firebase للإنتاج تحتاج موافقة وتفعيل وفحص هاتفين حقيقيين. لا تجعلها true أو تنشر Firebase فقط لتجاوز الإغلاق.
- لا APK/AAB، لا Play، لا Firebase إنتاج، لا تعديل على المرجع المحمي `fea54d7db2e8a24a74267f04a14c9572bcb408ee` ولا خزان الأكواد الـ12. مواصلة العمل من HEAD الحالي، لا إعادة ترتيب الخزان.

## 2026-11-05 — تشخيص Firebase الإنتاجي الحقيقي، قراءة فقط

**سبب استمرار منع الإعلان عن النسخة الكاملة أصبح مُثبتاً:** الاختبارات المحلية الخضراء لا تساوي تفعيل Firebase. لم تُحذف أي بيانات حساب أو تُغيّر صلاحيات إنتاجية بهذه الجولة.

- مشروع الإنتاج المثبت: `deda-25b88`. `Firestore Rules API` أعاد استجابة GET 200 للـrelease والقواعد. فحص 2026-11-05: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/42092615340
- SHA256 القواعد النشطة المُثبت: `9f237713945c454dcfe474a33aa6ca748ef1e7a534ac92ef6f9928e1001f923c`؛ لا يطابق `firestore.rules` بالمستودع. لا تنشر الملف المحلي على الإنتاج لأنه سيستبدل قواعد غير مطابقة.
- وجود المسارات في القواعد المنشورة (فحص `match` فقط، **ليس** فحص سماح API الفعلي):
  - `deda_progress_evidence` و`deda_purchase_evidence`: موجودة.
  - `deda_recovery_journals`: غير موجود.
  - `deda_step2_global_place_archives`: غير موجود.
  - `deda_profile_ui_migration` و`deda_quiz_ui_snapshots`: غير موجودة.
  - `deda_stage66_card_receipts` و`deda_stage66_owned_cards`: غير موجودة.
  - `deda_friendships`, `deda_diamond_gifts`, `deda_stage71_granted_registry`, `deda_stage74_id_gift_receipts`: موجودة.
- ثلاث Functions اللازمة للدخول والحارس (في `us-central1`) **لم توجد** عند طلب GET المباشر: `dedaVerifyExistingOwnerPin` و`dedaIssueLinkedOriginalUidDeviceGrant` و`dedaRecoveryJournalComplete`.
- تأكيد الدفع/خطة Firebase عبر Cloud Billing API لم ينجح: `HTTP 403`. **مجهول** هل الحساب يسمح بنشر Functions؛ لا تدّع Spark أو Blaze دون إثبات. تشغيل فحص القراءة الموسع: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/42092854002
- خطوات التنفيذ لتصفية العائق ضمن نفس نقطة الاسترجاع: مطابقة القواعد الحية وإضافات المجالات الناقصة داخل محاكي واحد مع منع UID غريب واشتراط مصادر الهاتف القديم؛ التحقق من صلاحيات نشر Functions والخطة الفعلية على المشروع؛ نشر باعتماد محدد للقواعد والـFunctions إذا أظهرت نتائج الاختبارات عدم وجود اختراق أو تعارض مع Play 100340؛ ثم اختبارات جهازين وثالث **فعلياً**، واسترجاع مصادر البيانات القديمة الموثقة.
- مصدر محفظة إعلانات 100340 المحلي لا يحتوي تاريخاً خادمياً موقعاً لكل عملية كسب/صرف. هذا لا يُحل بإضافة rule أو نشر Function. لا يمكن المطالبة برصيد مطابق 100% من مصدر غير موجود؛ يحتاج الحفاظ على الهاتف القديم والحالة الأصلية ومطابقة مصدر موثوق قبل أي نقل مالي أو إعلان اكتمال.
- **قرار ما قبل البناء:** لا تُفتح بوابة `fullAccountRestored` و`canPrepareFullRecoveryApk` لتجاوز غياب الأدلة. لا APK/AAB ولا Play ولا تشغيل إنتاجي، ولا تغيّر مرجع 100436 المحمي؛ أبقِ الفرع الحالي نقطة استئناف. لم تُنفّذ تغييرات Firebase حيّة بهذه الجولة.

**ملاحظة تنفيذية:** فحوص GET-only لم تطلع على وثائق المستخدمين الخاصة ولا تغير قواعد Firebase. وجود مسار match لا يكفي لتأكيد السماح الفعلي؛ يلزم اختبار SDK/Auth/AppCheck على القواعد نفسها قبل النشر.

## أرشيف الأماكن — مرشح الصلاحيات الحية فقط (2026-11-05 مساءً)
- **محفوظ فعلياً على نفس فرع التجهيز:** `qa/stage2/deda_stage2_global_places_live_additive_candidate.fragment.rules`، ومعه `tools/deda_stage2_preview_global_places_actual_live_rules.py`، واختبار `qa/stage2/deda_global_places_actual_rules_candidate_private.test.cjs`، وworkflow `qa-deda-100436-global-places-live-candidate-emulator-no-deploy.yml`.
- القاعدة الأصلية الحية `deda-25b88` SHA256 `9f237713945c454dcfe474a33aa6ca748ef1e7a534ac92ef6f9928e1001f923c` تُجلب GET-only ويُرفض تغييرها عن هذه البصمة؛ الإضافة تخص match `deda_step2_global_place_archives` وحده ولا تمس قواعد الخادم الأصلية الأخرى.
- **نتيجة CI:** https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/42096067451، نجاح مقارنة القواعد الحية وإضافتها مؤقتاً، ثم Firebase Emulator SDK لاختبار صاحب الحساب الأصلي/هوية أخرى: إنشاء وحيد وقراءة صاحب الحساب، منع enumerate/overwrite/delete ورفض UID الغريب.
- **لم يحصل نشر إنتاجي:** التطوير حتى هذا التاريخ Additive Preview + CI، وليس Firebase deployment. لا تغيّر `firestore.rules` بالمستودع ولا مرجع 100436 ولا قواعد Firebase الحقيقية.
- **حدود الإثبات:** النجاح يثبت انضباط match لأرشيف الأماكن داخل المحاكي، وليس إثبات مصدر هاتف قديم غير قابل للتلاعب أو استرجاع كل المجالات. قبل أي نشر يلزم إعادة تأكيد SHA الحي والاعتماد الصريح للتغيير الحي، ثم قراءة الخادم بعد النشر وتجربة هاتفين.
- لا APK/AAB، لا Play. فتح الحارس أو full-account cutover ما زال يحتاج تغطية بقية مجالات الاسترجاع.

## 2026-11-05 — تفعيل صلاحيات أرشيف الأماكن الحقيقي ✅

- **الإجراء المكتمل:** نشر إضافة واحدة فقط في قواعد Firestore الإنتاجية للمشروع `deda-25b88` تخص `match /deda_step2_global_place_archives/{accountKey}`. لا مساس بالقواعد السابقة، ولا كتابة بيانات حسابات أو رصيد أو أصدقاء.
- قبل النشر: active ruleset `projects/deda-25b88/rulesets/f7b8aedb-0d91-4277-99ff-ee94dedbe1a9`، SHA256 `9f237713945c454dcfe474a33aa6ca748ef1e7a534ac92ef6f9928e1001f923c`.
- بعد النشر: active ruleset `projects/deda-25b88/rulesets/3c7f9f3a-74d6-4e17-9e3e-1b923bcdd09f`، SHA256 `345040e09314c67f3aa3d5f6b7fee49102e775bc2c37395058807b9b189fbbda`.
- **الدليل:** GitHub Actions `42096805454` — **success**. اجتاز Git diff لحماية 100436 وبيئة Auth/Firestore Emulator وفحص UID الغريب ومنع المسح والكتابة فوق الأرشيف، ثم نشر الإضافة وفحص قواعد الإنتاج byte-for-byte بعد النشر. https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/42096805454
- **تأكيد مستقل بعد النشر:** GET-only Firebase Rules audit `42097067355` أثبت `LIVE_HAS_ARCHIVE_MATCH_DEDA_STEP2_GLOBAL_PLACE_ARCHIVES True` والبصمة الجديدة نفسها. https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/42097067355
- **التراجع الآمن:** محفوظ Artifact ID `13446409105` باسم `DEDA-100436-GLOBAL-PLACES-ROLLBACK-METADATA`؛ يتضمن مرجع ruleset السابق وبصمته ومرجع الجديد، بدون أسرار أو حسابات مستخدمين.
- **حدود الإنجاز:** صلاحيات أرشيف الأماكن *مفعلة حقيقة*؛ لكن الاسترجاع الكامل ليس مفعلًا ولا مختبراً بين هاتفين حقيقيين. ثلاث Cloud Functions التي فُحصت سابقًا غير منشورة في `us-central1` وبوابة `canPrepareFullRecoveryApk` ما زالت false. لا APK/AAB ولا Play بهذه الخطوة. النسخة المحمية `fea54d7db2e8a24a74267f04a14c9572bcb408ee` لم تتغير.

## 2026-11-05 — قرار التفعيل الكامل المبني على صلاحيات الإنتاج الفعلية

- **أمر المالك:** تشغيل استرجاع الحساب بالكامل داخل فرع تجهيز 100436؛ لا تستبدل طلب الاسترجاع الكامل بمسار جزئي ولا ترفع الحارس شكلياً.
- **ما ثبت في Firebase الحقيقي بعد أرشيف الأماكن:** قواعد `deda_step2_global_place_archives` منشورة وجرى التحقق من SHA بعد التفعيل، لكن `deda_recovery_journals` غير منشورة ضمن match مستقل، ولا يوجد أي من Callables `dedaVerifyExistingOwnerPin` أو `dedaIssueLinkedOriginalUidDeviceGrant` أو `dedaRecoveryJournalComplete` ضمن جرد Cloud Functions v1/v2 **عبر جميع المناطق**. تحقق من https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/42098125328.
- **صلاحيات GitHub للنشر، فحص مباشر بدون تعديلات:** حساب الخدمة الأساسي يملك `cloudfunctions.functions.create/update` و`run.services.create`، ولا يملك `cloudbuild.builds.create` أو `iam.serviceAccounts.actAs` أو `serviceusage.services.enable`. الحساب الاحتياطي `FIREBASE_SERVICE_ACCOUNT` **غير مهيأ**، و`FIREBASE_TOKEN` **غير مهيأ**. أدلة: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/42098455092 وhttps://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/42098598771.
- **Billing:** معلومات تفعيل فوترة المشروع غير قابلة للقراءة من هذا الحساب (`HTTP 403`)، لذلك لا يجوز الاستنتاج أن المشروع Spark أو Blaze؛ يلزم تأكيدها بصلاحية مالك Cloud Billing.
- **قرار التنفيذ:** *لم يتم تفعيل وظائف الاسترجاع الثلاث*؛ نشر وظائف Cloud Functions من GitHub بهذه الهوية غير جاهز. لا تُنشئ callables وهمية، لا تجعل `DedaStep2CompletionReport.canPrepareFullRecoveryApk` أو `DedaVaultRecoveryResult.fullAccountRestored` يساوي true لإخفاء العائق.
- **لإزالة حاجز النشر:** تفويض هوية نشر GitHub بصلاحيات Cloud Build و`iam.serviceAccounts.actAs` على حساب تشغيل Functions المحدد مع التحقق من تفعيل Cloud Billing وواجهات الخدمة، ثم نشر **الوظائف الثلاث فقط** بأعلام السيرفر الافتراضية OFF، وتأكيدها من Cloud Functions API، وإكمال قواعد Journal باختبارات auth/AppCheck ثم مرحلة إثبات استرجاع كل بيانات الحساب. لا تستخدم `firebase deploy --only firestore` من الملف المحلي القديم؛ قواعد الإنتاج الفعلية مختلفة.
- **لا يزال شرط الاسترجاع الكامل الأوسع:** إثبات كافة المجالات الـ23 المرتبطة بالحساب على هاتفين حقيقيين، مع المحافظة على الماسات والشراء والتاريخ القديم دون إنشاء إيصالات مزيفة. يمكن الحفاظ على أدلة 100340 محلياً دون تصفير، لكن لا يجوز اعتبار أي أرشيف غير مثبت مصدر صرف رسمي.
- **هذا الفحص لم يمس بيانات المستخدمين أو Firebase Rules الإنتاجية أو نسخة 100436 المحمية**، ولم يبنِ APK/AAB ولم ينشر Play. احتفظ بالعمل المكتمل والـSHA في HEAD وارجع من هنا دون إعادة الـ12 كوداً.

## 2026-11-05 — الصلاحيات: فحص قدرة الحساب على إصلاح IAM بنفسه

- هوية النشر المستخدمة في GitHub: `firebase-adminsdk-fbsvc@deda-25b88.iam.gserviceaccount.com`؛ تحقق read-only من JSON الحالي دون كشف المفتاح. https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/42100821956
- `resourcemanager.projects.setIamPolicy`: FALSE، وكذلك `getIamPolicy`: FALSE. أي إضافة Role عبر GitHub بهذه الهوية غير مخولة؛ ممنوع محاولة التفاف على IAM.
- `cloudbuild.builds.create`: FALSE. `iam.serviceAccounts.actAs` بمستوى المشروع FALSE، لكن على حساب تشغيل بعينه لم يُثبت لأن APPENGINE أعاد 403 وCOMPUTE أعاد 404.
- حساب النشر الاحتياطي ورمز Firebase البديل غير مهيأين. لا تعُد للفوترة؛ ليست موضوع مهمة IAM الحالية.
- **وثيقة الإجراء الدقيق لمالك المشروع**: [إعداد صلاحيات Cloud Build وService Account User بنطاق محدد](DEDA_100436_STAGE2_IAM_DEPLOY_OWNER_ACTION_2026-11-05.md).
- لا تغيير في بيانات المستخدمين أو Firebase عند هذا الفحص؛ لا APK، ولا نشر Cloud Functions، ولا تعديل النسخة المحمية 100436. تنتظر عمليات النشر هوية موثوقة مُخولة من مالك المشروع، وبعدها يُستأنف فحص الحارس على نفس فرع العمل.

## 2026-11-05 — موافقة المالك على IAM من Cloud Shell

- المالك نفذ من Cloud Shell إضافة `roles/cloudbuild.builds.editor` إلى `firebase-adminsdk-fbsvc@deda-25b88.iam.gserviceaccount.com`؛ وأظهر أمر `gcloud projects get-iam-policy` الدور ضمن عضوية الحساب.
- المالك أنشأ حساب تشغيل منفصل `deda-recovery-runtime@deda-25b88.iam.gserviceaccount.com`؛ وظهر في Cloud Shell `Created service account`.
- المالك نفذ `gcloud iam service-accounts add-iam-policy-binding` على الحساب الجديد ومنح `roles/iam.serviceAccountUser` إلى حساب نشر GitHub. الاستجابة `Updated IAM policy for serviceAccount` وأظهرت ربط الدور والعضوية المستهدفين.
- **تحقق مستقل حقيقي من GitHub:** https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/42106967599 نجح؛ `LIVE_DEPLOY_PRIMARY_CLOUDBUILD_BUILDS_CREATE=True`، `LIVE_DEPLOY_PRIMARY_CLOUDFUNCTIONS_FUNCTIONS_CREATE=True`. محاولة `testIamPermissions` لمورد حساب التشغيل الجديد أعادت `HTTP 403`، وهي نتيجة **غير قابلة للتحقق بهذا الحساب** وليست دليلاً على غياب `Service Account User` الذي أثبتته استجابة المالك.
- **الخطوة القادمة داخل نفس المسار:** التحقق من سياسات حساب التشغيل والـruntime authorization بأمر قراءة فقط من حساب المالك إذا لزم، ثم تجهيز نشر مقيّد للوظائف الثلاث مع تعيين `--service-account=deda-recovery-runtime@deda-25b88.iam.gserviceaccount.com`، واختبارات الأمان والإتاحة قبل الفتح. **هذا ليس دليلاً على اكتمال الاسترجاع بعد.**
- لا تعديل على نسخة 100436 المحمية، ولا APK، ولا إصدار Play، ولا نشر وظائف بهذه الخطوة.

## 2026-11-05 — محاولة نشر وظائف الاسترجاع الثلاث المقفلة

- تم ربط Callables الثلاث بحساب التشغيل المستقل `deda-recovery-runtime@deda-25b88.iam.gserviceaccount.com`، مع `serviceAccount` و`region: us-central1` و`minInstances:0` و`maxInstances:2` وAppCheck. الإنتاج **مغلق افتراضياً** بسبب الحارس `deda_stage2_live_gate.js`.
- تم إغلاق إصدار Custom Token من ستة أرقام PIN في الإنتاج؛ فقط المسار المرتبط بالـUID نفسه يُسمح له بطلب إثبات (بعد تحقق خادم وتزامن رمز). فحص Flutter كامل: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/42112332671 (success). فحص Auth/Firestore/Functions Emulator وثلاثة أجهزة: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/42112281076 (success). تأكد أن QA السابق `42111762423` نجاح بعد إصلاح نسخ الملف إلى المحاكي.
- محاولة محددة لنشر **الوظائف الثلاث فقط** مع الحفاظ على مصدر الاختبار وخلو `firestore.rules` و`firebase.json` من التعديل: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/42112909937. **النتيجة FAILURE BEFORE DEPLOY:** `cloudbuild.googleapis.com` غير مفعّلة؛ حساب GitHub لا يملك `serviceusage.services.enable`، فتوقفت Firebase CLI قبل بناء أي Function. لا يُدّعى أي نشر وظائف.
- **إجراء مالك المشروع المطلوب الآن (Cloud Shell):** `gcloud services enable cloudbuild.googleapis.com --project=deda-25b88`. هذا يفعل الـAPI فقط، ولا يضيف قواعد أو يغير حسابات. لا يلزم إعادة أي كود.
- بعد نجاح الإجراء تُعاد محاولة workflow الثلاث وظائف المقفلة، وتُفحص حالتها في Cloud Functions v2 وهوية حساب التشغيل المستقل. **لا تُفتح flags الحارس** ولا تصدر نسخة APK قبل اكتمال قواعد Journal، صلاحيات تشغيل الخادم واسترجاع المجالات وفحص الهاتف الحقيقي.
- النسخة المرجعية 100436 وبيانات المستخدمين محفوظة؛ لم يصدر APK/AAB ولم ينشر Play. نتيجة الـworkflow ليست نجاح تشغيل الاسترجاع.
