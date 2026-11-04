# DEDA — نقطة توقف رقم 10: ربط الرقم والرمز على Auth/Functions وثلاثة هواتف

**التاريخ:** 2026-11-04  
**النتيجة:** **نجاح محدود ومثبت** في Auth + Functions + Firestore Emulator على 3 مثيلات Firebase SDK مستقلة، مع نتائج حماية وضوابط وصول. **لا يعني نجاح استرجاع كل بيانات الحساب أو تجربة 3 هواتف حقيقية.**  
**آخر GitHub Actions:** [#41804177848](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/41804177848) — **SUCCESS**.  
**SHA الفحص:** `4bf2df4b9ab33cdf886c959d9174f99cb050555f`.  
**فرع QA:** `deda-100436-recovery-journal-firestore-emulator-private-qa-no-deploy-2026-11-04`.  
**قاعدة الفرع:** نسخة 100436 المرجعية `deda-100436-owner-confirmed-success-reference-2026-11-02` عند `40936af117d662f975a67cac4e21eab5f84e9ec2`؛ لا مصدر تطوير من فرع 100434.  
**الخزان:** `deda-100436-isolated-recovery-work-vault-five-codes-pending-completion-2026-11-02`.  
**مرجع الفكرة:** `00_فكشن فكرة 💭أساس العمل 💪👷💪.md` + نقاط التوقف 04–09.  
**التزام الحماية:** عدم لمس نسخة التطبيق 100436 أو الأكواد الـ12 الأصلية، وعدم دمج أو توقيع أو APK/AAB أو نشر Firebase أو Play.

## ما جرى اختباره فعلياً

| الفئة | العدد | النتيجة |
|---|---:|---|
| قواعد Firestore الحقيقية داخل Emulator: السجل، الجلسة الأصلية، إصدار الإذن ورفض الهجمات | 33 | **PASS 33/33** |
| منطق الخادم لإكمال سجل الاسترجاع (Node + Firebase mocks) | 9 | **PASS 9/9** |
| حارس الـ12 في Flutter باستخدام Journal/Adapters مزيفة | 11 | **PASS 11/11** |
| **NEW**: Auth Emulator + Functions Emulator + Firestore Emulator مع 3 مثيلات عميل مستقلة | 13 | **PASS 13/13** |
| **مجموع فحوص المسار** | **66** | **PASS 66/66** |
| تحليل Dart للحارس وسجل Firestore وسياسة UID | — | **No issues found** |

**سيناريو الاختبار الجديد:** أُنشئت هوية Firebase مجهولة على مثيل الهاتف الأصلي؛ عبرت إثبات PIN من 6 أرقام وفق قواعد Firestore القديمة، ثم استُخدم `EmailAuthProvider.credential` و`linkWithCredential` على **نفس Firebase Auth UID**. أدخل هاتفان افتراضيان مستقلان الرقم والرمز عبر **Firebase Auth Emulator الحقيقي**، وأُثبت أن `signInWithEmailAndPassword` أعاد **نفس UID الأصلي**، ورفض رمزاً خاطئاً. وصل رمز Firebase Auth الفعلي إلى **Functions Emulator** ووُصف بـ`auth: VALID` في سجل المحاكي. تم منح إذنين منفصلين للجهازين عبر معاملة Firestore خادمية، ثم أمكن تحديث `deda_sessions` والحصول على ملف المالك الأصلي من الأجهزة الثلاثة. `signOut` في الهاتف الثاني **لم يسجّل خروج الهاتف الأصلي أو الثالث**. حُظر دخول مستخدم مجهول مختلف وحُظر منح إذن لدور إدارة.

**مهم بشأن App Check:** استُخدمت **بوابة اختبار محلية خاصة بمشروع `demo-`** تعطل enforcement في HTTPS callable ثم تمرّر سياق AppCheck تجريبياً إلى مصدر المُصدر. لذلك **لا يوجد إثبات لـAppCheck حقيقي**، ولا يجوز نقل هذا الملف إلى Cloud Functions المنشورة. إرسال طلبات رمز Firebase Auth كان حقيقياً داخل Auth Emulator، لكن سياق AppCheck لم يكن كذلك.

## العيوب التي كشفها التنفيذ وعلاجها داخل QA فقط

1. **تجاوز إذن الجهاز القديم:** بعد ربط UID من Anonymous إلى Password، بقي مستند `deda_auth_attempts/{uid}` وفيه إثبات PIN سابق؛ القاعدة الأولية كانت تقبل تحديث الجلسة الجديدة من دون إذن الانتقال. **أُصلح محلياً** بتخصيص أدلة `deda_auth_attempts` و`trustedInstallIds` لمسار **`anonymous` التقليدي**، وحصر مسار **`password` المرتبط** بإذن `dedaLinkedOriginalOwnerSessionBootstrap` المُثبت من الخادم. لم تُغيّر قواعد `firestore.rules` الأصلية. فحصنا استمرار دخول PIN المجهول القديم.
2. **حذف مستند جلسة مشترك:** كانت قاعدة `deda_sessions/{uid}` تسمح بحذفه من أي جهاز يحمل UID نفسه، ما قد يحرم بقية الهواتف من صلاحيات الأقسام. **أُغلق الحذف من `password` المرتبط في قواعد QA فقط**؛ وبقي حذف الـ`anonymous` التقليدي عاملاً كما في نسخة Play السابقة.
3. **إعداد المحاكي:** في تشغيل أول كان مسار القواعد ضمن Firebase CLI خاطئاً فتراجع المحاكي إلى قاعدة allow-all. **أُلغي قبول هذا الفحص**، وصُحح النسخ إلى مسار QA المؤقت وأُضيف اختبار يفرض فشل القراءة غير المصرح بها قبل أي فحص دخول. نجح الفحص النهائي مع القواعد المقيدة؛ لا fallback مفتوح.
4. **Firebase Admin في Functions Emulator:** المرشح كان يحتاج تهيئة Admin SDK في البيئة المحلية؛ أُضيفت داخل بوابة `demo-` فقط، مع عدم أي تغيير إلى `functions/index.js`.
5. **مشروع Auth مختلف عن Functions:** وُحّد مشروع Auth/Functions/Firestore إلى `demo-deda-100436-journal-qa` حتى يتطابق جمهور Auth token مع مشروع Firebase Functions.
6. **الطلبات المتزامنة:** اختبارات إصدار الإذن تفحص الآن **سجل العدّاد الخادمي والوثيقة النهائية** بدل افتراض صيغة محددة لردّي الطلب المتزامنين. نجح فحص عدم استهلاك أكثر من إذن واحد لنفس الجهاز.

**QA runtime source paths:**
- `qa/recovery_journal/deda_100436_real_auth_functions_three_devices.test.cjs`
- `qa/recovery_journal/functions_emulator/index.js` و`package.json` (بوابة الاختبار التجريبية فقط)
- `qa/recovery_journal/deda_100436_linked_session_bootstrap_emulator.test.cjs`
- `qa/recovery_journal/deda_100436_session_issuer_emulator.test.cjs`
- `qa/recovery_journal/assemble_emulator_rules.py`
- `qa/recovery_journal/deda_linked_owner_session_bootstrap_CANDIDATE_NOT_DEPLOYED.rules`
- `qa/recovery_journal/deda_linked_owner_session_grant_issuer_CANDIDATE_NOT_EXPORTED.js`

**ملف اعتماد انتقائي إضافي في الخزان:** `deda_100436_linked_uid_session_provider_protection_CANDIDATE_NOT_APPLIED.patch`؛ يعرض فرق التعديل المطلوب داخل `firestore.rules` على قاعدة 100436، ويشترط وجود مسودة دالة `dedaLinkedOriginalOwnerSessionBootstrap` المحفوظة مسبقاً. تم فحص **إعادة تطبيق الـUnified Diff نصياً بالذاكرة فقط**، ولم يُطبّق على `firestore.rules` أو ينشر.

## حدود النتيجة ومخاطر ما زالت مفتوحة

- **مشكلة متعددة الهواتف قائمة:** `deda_sessions/{uid}` وثيقة واحدة تحمل `installId` واحداً. أثبتنا بقاء **ثلاثة Firebase Auth ID tokens/جلسات** صالحة واستمرار قراءة ملف المالك، لكن تغيير الهاتف الثاني والثالث **يستبدل آخر `installId`** في تلك الوثيقة. لم نثبت سلامة كل خدمة في التطبيق تعتمد على `installId` أو جلسة الجهاز. لا نعلن حل مشاركة كل الهواتف حتى يتم تدقيق هذه الوظائف وتصميم سياسة جلسة متعددة الأجهزة عند الحاجة.
- الاختبار الجديد نفّذ **Firebase JS SDK متوافقاً مع منطق الربط**، لكنه **لم يُشغّل دالة Flutter `DedaOwnerUidContinuity.loginLinkedOriginalUid` من التطبيق الحقيقي**. تلك الدالة الموجودة في الخزان لا تستدعي مصدر إذن الانتقال الخادمي بين Firebase Auth ودخول `deda_sessions`، فلا بد من وصلها عبر حارس الجلسات قبل أي APK تجريبي.
- **App Check حقيقي، حدود محاولات رمز PIN ضد التخمين، وAuth/Functions App Check integration** لم تُفحص.
- كاتب الإثبات الخادمي لجميع مجالات استرجاع الحساب والـAdapters الفعلية للأكواد الـ12 **غير موصولين**. عدم تكرار الماسات والهدايا عبر `intentId` مختلف يحتاج ضماناً من مصدر الأموال/الجوائز لا من Journal فقط.
- لم يتم اختبار هاتف Android فعلي أو نسخة Play 100340 متصلة مع حساب مرتبط على هاتف ثانٍ؛ نجح فقط سيناريو Emulator المعزول.
- **لا تعديل على Firebase المنشور**؛ القواعد ومصدر Functions ما زالا مرشحين معطلين، وغير مسموح نقلهما إلى الإنتاج دون موافقة صريحة وفحوص أمنية.

## نقطة استئناف رقم 1

**المثبت:** نفس UID عند ربط الرقم والرمز على Auth Emulator، ودخول هاتفين جديدين، وبقاء الهواتف الثلاثة مسجلة، ومرور إذن خادمي عبر Functions Emulator، ونتيجة 66/66 ناجحة بعد فصل anonymous/linked ومنع حذف الجلسة المشتركة.  
**الخطوة التالية الآمنة:** تدقيق `installId` متعدد الأجهزة وآثار `deda_sessions` على كل الأقسام، ثم اختبار `App Check` الحقيقي وتحصين PIN، ثم تجهيز وصلة `DedaOwnerUidContinuity` و`DedaAuthSessionRuntime` مع مُصدر الإذن في **فرع تطوير مصدره نسخة 100436 الناجحة** بعد اعتماد صاحب المشروع. لا دمج الآن.

**النسخة المحمية:** 100436 بلا تعديل، الـ12 أصليين محفوظين، لا APK/AAB/Play/Firebase deploy.
