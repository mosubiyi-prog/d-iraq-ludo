# DEDA 100440 — حسم علاقة الآيدي المميز بتعارض هويتَي Firebase

**التاريخ:** 2026-11-07 (العراق).  
**طلب صاحب المشروع:** تحديد ما إذا كان شراء/تفعيل الآيدي المميز بعد الآيدي الأصلي هو سبب ارتباط رقم حساب DEDA بهويتين مختلفتين في Firebase.  
**النتيجة:** لا يوجد دليل أن الآيدي المميز أنشأ UID آخر. الأدلة الخادمية وترتيب السجلات وكود التفعيل الحالي تؤيد بقوة أن السبب هو **انفصال مسار حساب الرقم/الجلسة عن UID صاحب الآيدي الأصلي**، وليس زر «استخدام» للآيدي المميز. تحديد الحدث التاريخي الأول الذي سبب الانفصال يحتاج سجل تدقيق أقدم؛ لا يجوز الادعاء بمعرفته.

## الأدلة الحية — قراءة فقط
GitHub Actions [42411828728](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/42411828728)؛ فرع `deda-100440-session-rescue-isolated-owner-review-2026-11-07`:

- `PREMIUM_ALIAS_CURRENTLY_SELECTED YES`: الحساب لديه الآن آيدي عرض مميز مُفعّل.
- `PREMIUM_PUBLIC_ALIAS_SAME_ORIGINAL YES` و`PREMIUM_PUBLIC_ROUTE_SAME_ORIGINAL YES`: مسارا نشر الآيدي المميز يطابقان الآيدي الأصلي ولا يوجهان إلى هوية حساب جديدة.
- `DIRECTORY_CREATED_BEFORE_ACTIVE_ID_RECORD YES`: إنشاء وثيقة ربط رقم الحساب أسبق من إنشاء وثيقة التفعيل المميز الحالية.
- `ORIGINAL_PERSONAL_ROUTE_CREATED_BEFORE_ACTIVE_ID_RECORD YES`: إنشاء سجل الآيدي الأصلي أسبق كذلك.
- `PHONE_DIRECTORY_CREATOR_MATCHES_ACCOUNT_CREATION YES`: `deda_account_directory.createdUid` يطابق `deda_credentials.createdUid` في سجل إنشاء حساب الرقم؛ لم نقرأ قيمة PIN أو نطبعها.
- `ACCOUNT_DIRECTORY_POINTS_TO_DIFFERENT_UID YES`: UID تسجيل الرقم يختلف عن `deda_share_ids/{originalId}.ownerUid`.
- سجل UID الخاص بالآيدي الأصلي في `users` يملك الآيدي الأصلي، بينما UID الدليل الثاني لديه `users` بنفس `accountKey` لكنه لا يدّعي الآيدي الأصلي.
- لا توجد `deda_sessions` حالية لأي من الاثنين، ولا حساب دخول بالبريد الاصطناعي أو Google وفق فحص Firebase Auth الخادمي.
- `OWNER_SESSION_ACTIVATION_DECISION HOLD_ORIGINAL_AUTH_NOT_LINKED`: لا يجوز تفعيل الدخول المباشر بمجرد تبديل feature flag.

## مراجعة كود «استخدام» الآيدي المميز
- `lib/deda_stage71_free_owned_use_profile.dart`، `DedaStage71OwnedIdentifierService.use(originalId, identifier)`: يتحقق من مالك الآيدي الأصلي على UID المصادق ويكتب فقط `deda_stage71_active_identifier/{originalId}`. بعد القراءة والتحقق من المنحة والإيصال، ينشر مسار العرض عبر `DedaQa32SparkPublicIdentifierDirectory.publishOwnerVerified`.
- `lib/deda_qa32_spark_public_identifier_directory.dart`: يكتب فقط `deda_public_active_aliases/{originalId}` و`deda_public_alias_routes/{premiumId}` لربط العرض بالأصل. لا يستدعي `signInAnonymously` ولا ينشئ Firebase user ولا يكتب `deda_account_directory` أو `deda_credentials`.
- `lib/deda_unified_active_id_100410.dart` و`lib/deda_verified_active_id_store.dart`: ذاكرة وعرض للآيدي النشط بمفتاح `(Firebase UID, originalId)`، وليسا مصدر إنشاء حساب جديد.

## الموضع الأقرب للتعارض
- `lib/deda_pin_auth.dart` في `createAccount` يضع `createdUid` من جلسة Firebase الحالية داخل `deda_account_directory` و`deda_credentials`.
- في `signIn` مسار الـPIN القديم ينفذ `_openSession` عبر `_ensurePinSessionForAccount` وقد يعتمد على جلسة مجهولة مختلفة على جهاز/تسجيل آخر. `lib/deda_backend.dart` لديه `_ensurePublicUser` الذي يمكنه إنشاء جلسة مجهولة عند غيابها، وهذه نقطة مسار دخول لا علاقة لها باستبدال آيدي العرض.
- هذه **فرضية مصدر الانفصال** تدعمها بنية البيانات والكود؛ لا نملك audit log تاريخياً يثبت بالضبط أي عملية أو نسخة/هاتف أحدثت أول تبديل.

## قرار الحماية
- لا نلغي الآيدي المميز ولا نرجع الآيدي القديم للعرض؛ المميز صحيح الربط في سجل الخادم الحالي.
- لا ننقل أو نمسح UID أو حساباً، ولا نغيّر `createdUid` أو sessions أو Auth providers أو جوائز أو هدايا أو ماسات بتخمين. البيانات القديمة يجب أن تبقى مرجعية.
- التفعيل الشامل للمنقذ يبقى **موقوفاً** إلى أن نحدد إجراءً موثقاً لإثبات صاحب الحساب ومصالحة `deda_account_directory` مع `deda_share_ids` وربط وسيلة الدخول بنفس الـUID الصحيح، مع احترام صلاحيات الإدارة المنفصلة.
- هذا الفحص لم يكتب شيئاً إلى Firebase، ولا بُني APK/AAB، ولا نشر Play، ولا غيّر النسخة 100440.

**مستوى الثقة:** عالٍ جداً بأن **ميزة الآيدي المميز الحالية ليست منشئ الـUID الثاني**؛ غير مثبت تاريخياً أي مسار في التطبيق القديم هو الذي أنشأ هذا الانفصال تحديداً.
