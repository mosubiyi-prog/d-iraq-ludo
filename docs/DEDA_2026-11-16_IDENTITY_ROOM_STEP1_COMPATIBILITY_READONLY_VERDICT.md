# DEDA — نتيجة النقطة الأولى: فحص توافق الغرفة الموحّدة للهويات الثلاث (قراءة فقط)

**التاريخ:** 2026-11-16  
**نوع العمل:** تدقيق توافق مصدر ثابت، بدون تعديل كود أو قاعدة بيانات أو قواعد Firebase أو أجهزة أو Play أو بناء APK  
**الهدف:** تقييم قابلية ربط A/B/C منطقياً تحت حساب DEDA مصرح به، واسترجاع الرقم والرمز، ومعالجة الجلسة المجهولة، مع عدم تخريب الأقسام.  
**مرجع المصدر الذي تمت قراءته:** `deda-100446-remove-session-card-uid-owner-hold-source-only-2026-11-14`، commit `fd8cfd590d0f6703e34d6fe8c6913b091c3468fd`.  
**مرجع القواعد:** [وثيقة الالتزام](./DEDA_2026-11-16_COMMITMENT_DOCUMENT.md) ونقطة توقف 15 نوفمبر `DEDA_2026-11-15_LOGICAL_IDENTITY_ROOM_CHECKPOINT.md`.  
**حالة جميع الادعاءات أدناه:** استنتاج من الشيفرة المتاحة وتقارير الفحص التاريخية؛ لا فحص مباشر لقواعد Firebase المنشورة أو سجلات إنتاجية جديدة ولا اختبار تشغيل على الهاتف في هذه الخطوة.  

## 1) بوابة الالتزام الإلزامية قبل العمل
- ✅ راجعت وثيقة الالتزام ونقطة التوقف قبل مراجعة المصدر.
- ✅ الخطوة مخولة قراءةً فقط، وحصرت العمل بتوافق الهوية والجلسة وأقسام DEDA.
- ✅ مصدر العمل ومعرّف commit ثابتان؛ لا تعديل على النسخ المحمية.
- ✅ راجعت نقاط تماس الإدارة والآيدي والمقتنيات والهدايا والماسات والدوري والأصدقاء والأماكن والملف.
- ✅ لم تنفذ أي كتابة إلى Firebase أو قواعده أو Play أو التطبيقات.
- ✅ معيار القرار: **لا تنفيذ إنتاجي أو ترخيص عرض بيانات عابر للـUID ما لم تُثبت الملكية مستقلاً وتُراجع القواعد المنشورة وتختبر آلية حماية وتراجع**.
- ⏸️ الفحوص السلوكية/التكاملية وقياس عدم التراجع غير منفذة هنا؛ تستلزم بيئة اختبار معزولة، وتُعد شرطاً لاحقاً لا نجاحاً مفترضاً.

## 2) النتيجة الحاسمة
**يمكن تصور طبقة حساب منطقي `canonicalAccountId` تحفظ A/B/C وسجلاتها كما هي، لكن الكود الحالي لا يحتوي على آلية تفويض موثوقة متكاملة تمنح هذا الحساب المنطقي صلاحيات كل الهويات.**

والسبب: قواعد ومسارات مختلفة تربط الدخول والبيانات بطرق مستقلة (`UID`، `accountKey`، الآيدي الأصلي، `admins/{uid}`، وإيصالات/مستندات لكل قسم). وضع `canonicalAccountId` أو `Custom Claims` وحده لا يغيّر شروط الأمان، ولا يثبت الملكية، ولا يحل غياب طريقة دخول إلى UID تاريخي.

**حكم تنفيذ الغرفة على الإنتاج الآن: NO-GO / SAFE HOLD.**  
**حكم الدراسة وإعداد تصميم واختبارات معزولة لاحقاً: GO مشروط** بآلية إثبات ملكية مستقلة وبمراجعة تطبيقية وأمنية لقواعد الإنتاج. هذه نتيجة واقعية، وليست إعلان فشل الفكرة ولا نجاح الاسترجاع.

## 3) أدلة المصدر: نظام الدخول والجلسة
1. `lib/deda_pin_auth.dart:35-75`: مسار `_ensureAnonymousSession` قد يستخدم `signInAnonymously` عند غياب جلسة مناسبة؛ حراسة رفض التحويل الصامت موجودة عند تفعيل `dedaLinkedOwnerCompatEnabled` فقط. لا يصح استنتاج أن المانع مفعّل في كل APK.
2. `lib/deda_100431_linked_owner_session_policy.dart:10-11`: `DEDA_STEP2_LINKED_OWNER_COMPAT` **false افتراضياً**. و`lib/deda_step2_existing_account_signin_page.dart:5-9`: مدخل الدخول المجهّز **false افتراضياً**، ويحتاج مفوض دخول موثوقاً.
3. `lib/deda_pin_auth.dart:203-234` و`lib/deda_100431_linked_owner_session_policy.dart:148-169`: فحص `_verifiedExistingPinUid` و`canOpenExistingPinSessionOnOriginalUid` يشترطان **`directory.createdUid == current UID == deda_share_ids/{originalId}.ownerUid`** مع إثبات بيانات المستخدم. بحسب الجرد التاريخي `B` في الدليل و`A` للآيدي الأصلي، الشرط لا يتحقق على الحساب المتعارض؛ المسار الحالي يوقف الطلب بدلاً من استرجاع UID تخميناً.
4. `lib/deda_pin_auth.dart:403-475`: `signIn` في الوضع المحمي يتحقق من UID أولاً ثم يختبر PIN ويكتب `deda_sessions/{uid}` و`users/{uid}` بشرط عدم تبدل الجلسة. هذه حماية للكتابة، **وليست آلية مستقلة لإثبات ملكية UID A أو ربط A/B/C**.
5. `lib/deda_backend.dart:56-139`: `_ensurePublicUser` لا ينشئ UID تلقائياً حين يكون العلم المحمي مفعلاً؛ في وضع التوافق القديم يمكن أن ينشئ UID مجهولاً؛ `_ensureOwnerSessionForAccountKey` يتعامل مع الجلسة والـUID الفعلي. `_currentAccountKey` قد يرجع UID إذا فشل جلب accountKey، وليس شهادة ملكية.
6. `lib/deda_auth_session_runtime.dart` و`lib/deda_session_transition_gate.dart`: آلية ترتيب/حراسة انتقالات الجلسة تعالج السباقات فقط، ولا تمنح صلاحية دخول أو امتلاك بيانات.
7. `firestore.rules:598-649`: PIN يثبت في `deda_auth_attempts/{uid}` المرتبط بـUID صاحب الطلب، ثم `deda_sessions/{uid}` يمكن إنشاؤها بناءً على PIN أو `trustedInstallIds` وفق القواعد المخزنة؛ هذه ليست مساوية لإثبات مستقل أن `UID` جديد يملك كل سجلات UID تاريخي.
8. `functions/index.js:15-49` و`functions/deda_stage2_live_gate.js`: مرشحات التحقق/الإذن مغلقة افتراضياً خلف شروط خادمية؛ لا يجوز تفعيلها بالعلم وحده. لا بيئة موثوقة مفوضة مُثبتة لهذه الخطة.

**النتيجة:** حل «الجلسة المجهولة» يحتاج مسار دخول أصلي صالح ومثبت/تفويض خادمي، وليس مجرد إخفاء UID من الواجهة أو كتابة accountKey تحت UID عابر. وعلى الأجهزة التي لا تملك جلسة مثبتة، يكون المنع الآمن متوقعاً إلى حين وجود إثبات.

## 4) مصفوفة التوافق حسب الأقسام
| المجال | الربط الموجود في المصدر | صلاحية الغرفة الموحدة | المانع أو شرط الأمان |
|---|---|---|---|
| الرقم والرمز/الملف الأساسي | `deda_account_directory`، `deda_credentials`، `deda_account_profiles/{accountKey}`، `deda_sessions/{uid}` | **مشروط**؛ accountKey صالح كمفتاح فهرسة تاريخي، وليس هوية دخول | B في الدليل مقابل A لمالك الآيدي؛ يحتاج دليل ملكية مستقل ومسار دخول صالح للـUID المرخص، مع توحيد تمثيل الرقم دون تغيير المفاتيح التاريخية |
| الآيدي الشخصي الأصلي | `deda_share_ids/{originalId}.ownerUid` و`users/{uid}.sharePersonalId` | **غير مباشر** | قاعدة `firestore.rules:703-732` وخدمة `DedaStage71OwnedIdentifierService._requireOriginal` تطلب UID مالكاً أصلياً؛ لا تعيين تلقائي إلى B أو D |
| الآيدي المميز وبطاقات الآيدي والإطارات | `deda_stage71_active_identifier/{originalId}` + منح وإيصالات، تحقق UID الأصلي | **قراءة تجميلية محتملة بعد الإثبات**، لا نقل ملكية ولا تفعيل تلقائي | `lib/deda_stage71_free_owned_use_profile.dart:61-101,167-240`؛ حق العرض مختلف عن حق البيع/الشراء/المنح؛ الاحتفاظ بقرار أن المميز للزينة لا يحوّله إلى هوية حساب |
| الأصدقاء والطلبات الاجتماعية | `deda_friendships` تحوي `members:[UID,...]` و`pairKey` مبني من UIDs؛ `deda_social_profiles` تحوي `ownerUid` | **تحتاج طبقة وصول محددة/تخطيطاً معزولاً** | `lib/deda_social_service.dart:129-169,218-315`؛ عرض الأصدقاء من accountKey وحده لا يعيد سجلات UID A/C ولا يُجيز تعديلها. لا تعاد كتابة العلاقات ولا تولّد دعوات مكررة |
| الهدايا والماسات | هدايا المحفظة `deda_diamond_gifts` و`deda_diamond_gift_balances/{originalId}` مع تحقق `verifiedDiamondsPersonalOwner`؛ هدايا الآيدي لها إيصالات مستقلة | **تحتاج تفويضاً خادمياً/إيصالات** | `firestore.rules:2033-2050,2263-2312` و`deda_stage74_id_gift_service.dart`؛ لا نقل أو جمع أرصدة افتراضي، لا إعادة منح أو صرف |
| الدوري والمهام والنقاط | `deda_weekly_direct_accounts/{publicId}` تربط `accountKey` بالآيدي؛ `scores` تحت الأسبوع؛ جلسة UID لازمة في مصادر التحديث | **عرض محتمل بعد إثبات**، و**تحديث مشروط** | `firestore.rules:2437-2475` و`lib/deda_weekly_firestore_direct_bridge.dart`؛ منع ازدواج نقاط المهام والجوائز وفحص قواعد نفس الحساب |
| الأماكن والخرائط ومشاركات الموقع | الأماكن المنشورة تقرأ علناً عند `published==true`؛ تحديثات ومشاركات المالك تستخدم `ownerUid` أو `accountKey` حسب العملية | **العرض العام ممكن بمساره الحالي**؛ إجراءات المالك مشروطة | `firestore.rules:735-793,1394-1414` و`deda_backend.dart`؛ إعادة ربط UID للمالك بلا إثبات قد تخلط ملكيات أماكن |
| الإدارة وبطاقة الدخول | `admins/{FirebaseAuth.currentUser.uid}` لمستخدم غير مجهول، و`admin_entry_access/{accountKey}` مسار منفصل | **ممنوع ربط صلاحيات الإدارة تلقائياً بالغرفة** | `lib/deda_backend.dart:198-245,1147-1170` و`firestore.rules:235,406`؛ يجب بقاء ظهور بطاقة الإدارة ودخولها للحساب المخوّل حصراً |
| المستوى والتقدم والإعدادات والمقتنيات التاريخية | خليط من قيم الهاتف `SharedPreferences` وسجلات خادمية وأرشيفات مختبرة | **غير مثبت الاسترجاع الكامل** | تقارير 12–15 نوفمبر توضح أن بعض أدلة التقدم/الإيصالات لم تتثبت في الأرشيف الخادمي؛ لا يعني غياب سجل أن الرصيد صفر؛ لا تحذف بيانات الهاتف القديم |
| التنقل بين الأقسام | شاشات مختلفة تفحص الجلسة/مالك السجل/الصلاحية بآليات متفاوتة | **مشروط باجتياز كل مسار وصول** | حل جلسة واحدة لا يجعل كل قسم مخولاً تلقائياً؛ يجب اختبار فتح/غلق/عودة كل قسم والصلاحيات دون تغيير الواجهة |

## 5) عدم التطابق المحتمل في قواعد Firebase — خطر مستقل
- `firebase.json` يشير إلى `firestore.rules` بالمستودع.
- `firestore.rules:2023-2027` نفسه يحذر أن سياسات المحفظة التاريخية قد تكون موجودة ضمن قواعد منشورة / إضافات بناء غير موجودة في ملف المصدر، ويحظر نشر لقطة المصدر وحدها دون دمج ومراجعة القواعد الفعلية.
- فحص نص `firestore.rules` في هذا commit **لم يجد** `match` صريحاً لـ`deda_friendships` أو `deda_social_profiles` أو `deda_stage71_active_identifier`، رغم استعمالها في ملفات `lib`. **هذا لا يثبت نقص القواعد المنشورة الآن**؛ يثبت أن لقطة المصدر وحدها لا تكفي للتصديق على صلاحيات هذه الأقسام.
- لذلك **NO-GO لأي نشر Rules أو تبديل قواعد صلاحيات اعتماداً على هذا الملف وحده**. في مرحلة لاحقة، وبصلاحية وبيئة مخولتين، يلزم *قراءة* القواعد المنشورة ومقارنتها باللقطة قبل أي مقترح تعديل أو اختبار حي.

## 6) لماذا لا يكفي UID mapping وحده؟
- `sameAccount(accountKey)` في `firestore.rules:111-121` يتحقق من `deda_sessions` أو `users/{request.auth.uid}.accountKey`؛ هذا فهرس عضوية حالي، لا شهادة ملكية لجميع السجلات القديمة. توسيع الصلاحيات اعتماداً عليه يسمح مبدئياً بقفز غير مأذون عبر الهوية.
- `Custom Claims` أو map جديد لا يصدُر من Flutter، ولا يكتب في إنتاج قبل إثبات أن الشخص يملك الحساب المعني، وتحديد صلاحيات كل قسم وخادم موثوق وسجل تدقيق ومنع التكرار.
- وحدة حساب منطقية ليست دمج Firebase Authentication ولا تعيد جلسة A القديمة من تلقاء نفسها.

## 7) وضع توافق نسخ Play
**غير مثبت.** لم أقرأ قواعد Firebase المنشورة أو أقارن سلوك APK/AAB 100340/100447 بنسخة تنفيذ جديدة هنا. يُمنع تعديل قواعد الإنتاج أو جعل ميزة جديدة افتراضية قبل فحص مستخدمي النسخة القديمة في بيئة مناسبة. المصدر الحالي فيه flags افتراضها OFF؛ لا يعني ذلك أنها OFF في كل بناء سابق أو حالي.

## 8) فحوص قبول لازمة إن أُجيز نموذج معزول في خطوة لاحقة
1. بيانات اختبار اصطناعية تمثل A/B/C وD غير مخوّل. تحقق عدم منح D أي قراءة أو كتابة بملفات A/B/C بمجرد رقم/رمز أو accountKey.
2. إثبات ملكية مستقل وقابل للتدقيق، ثم mapping خادمي يربط الحساب المنطقي فقط بالـUID المُصادق والمصرح؛ اختبار إبطال الإذن وتغيير الجلسة وإلغاء الطلب.
3. استرجاع الرقم والرمز وعدم إنشاء UID غير مقصود؛ اختبار افتتاح التطبيق، الإغلاق والعودة، تبديل القسم والشبكة والهاتف، ورفض الجلسة المجهولة دون تجميد واجهة التطبيق.
4. فحص صلاحيات **كل** قسم على حدة: الآيدي الأصلي/المميز، الأصدقاء، الهدايا، الماسات، الدوري، المهام، الأماكن، الإدارة؛ لا رصيد/هدية/جائزة مكررة ولا فقد سجلات.
5. فصل بطاقة الإدارة والتحقق من `admins/{uid}` عن تفويض حساب DEDA المنطقي؛ الحجب الافتراضي لأي مستخدم لا يملك دوراً خادمياً.
6. مطابقة snapshot من Rules الإنتاجية وأثرها على Play القديم **بعد تفويض مستقل**؛ إجراء rollback قابلة للتحقق ولا نشر على نحو افتراضي.
7. فحوص كود/Rules عبر emulator، واختبارات الواجهات وعدم التراجع، وتسجيل `diff` وأدلة النجاح قبل أي بناء APK.

## 9) قرار الخطوة الأولى والسجل
**الخطوة 1، دراسة التوافق:** مكتملة كـ**تقرير توافق مصدر ثابت** مع تحديد الموانع والشروط؛ ليست فحص تكامل أو تفعيل أو إثباتاً لاسترجاع حساب فعلي.  
**نتيجة قابلية الفكرة:** ممكنة **كمفهوم هندسي مشروط**، لكنها **غير مصدّقة للتنفيذ** في ظروف الحساب الحالية.  
**قرار المتابعة للتنفيذ الآن:** **NO-GO / SAFE HOLD** ما دام إثبات الملكية المستقل، وخادم التفويض، وقواعد الإنتاج الفعلية/التوافق غير مثبتة.  
**العمل الذي يجوز دراسته لاحقاً بموافقة:** إثبات ملكية مستقل وتحديد مخطط صلاحيات الحساب المنطقي، ثم محاكاة معزولة قابلة للتراجع؛ لا نقل/دمج UID ولا تفعيل إنتاج.  
**التغييرات التي حدثت في نطاق هذه الخطوة:** **تقرير توثيقي فقط بفرع وثائق معزول**؛ لا تغيّر أي كود أو Rule أو Firebase أو مستخدم أو APK.  
**شرط النجاح النهائي للمشروع:** دخول نفس الحساب برقم الهاتف والرمز مع صلاحيات صحيحة وتنقل سليم وعدم فقدان البيانات والإدارة، بعد اختبار عملي مثبت، ولم يتحقق هذا بعد.

## 10) مسارات الأدلة المقروءة (المرجع الثابت)
- [`lib/deda_pin_auth.dart`](https://github.com/mosubiyi-prog/d-iraq-ludo/blob/fd8cfd590d0f6703e34d6fe8c6913b091c3468fd/lib/deda_pin_auth.dart)
- [`lib/deda_backend.dart`](https://github.com/mosubiyi-prog/d-iraq-ludo/blob/fd8cfd590d0f6703e34d6fe8c6913b091c3468fd/lib/deda_backend.dart)
- [`lib/deda_100431_linked_owner_session_policy.dart`](https://github.com/mosubiyi-prog/d-iraq-ludo/blob/fd8cfd590d0f6703e34d6fe8c6913b091c3468fd/lib/deda_100431_linked_owner_session_policy.dart)
- [`lib/deda_auth_session_runtime.dart`](https://github.com/mosubiyi-prog/d-iraq-ludo/blob/fd8cfd590d0f6703e34d6fe8c6913b091c3468fd/lib/deda_auth_session_runtime.dart)
- [`lib/deda_session_transition_gate.dart`](https://github.com/mosubiyi-prog/d-iraq-ludo/blob/fd8cfd590d0f6703e34d6fe8c6913b091c3468fd/lib/deda_session_transition_gate.dart)
- [`lib/deda_social_service.dart`](https://github.com/mosubiyi-prog/d-iraq-ludo/blob/fd8cfd590d0f6703e34d6fe8c6913b091c3468fd/lib/deda_social_service.dart)
- [`lib/deda_stage71_free_owned_use_profile.dart`](https://github.com/mosubiyi-prog/d-iraq-ludo/blob/fd8cfd590d0f6703e34d6fe8c6913b091c3468fd/lib/deda_stage71_free_owned_use_profile.dart)
- [`lib/deda_stage74_id_gift_service.dart`](https://github.com/mosubiyi-prog/d-iraq-ludo/blob/fd8cfd590d0f6703e34d6fe8c6913b091c3468fd/lib/deda_stage74_id_gift_service.dart)
- [`lib/deda_weekly_firestore_direct_bridge.dart`](https://github.com/mosubiyi-prog/d-iraq-ludo/blob/fd8cfd590d0f6703e34d6fe8c6913b091c3468fd/lib/deda_weekly_firestore_direct_bridge.dart)
- [`lib/deda_qa32_manager_original_owner_proof.dart`](https://github.com/mosubiyi-prog/d-iraq-ludo/blob/fd8cfd590d0f6703e34d6fe8c6913b091c3468fd/lib/deda_qa32_manager_original_owner_proof.dart)
- [`lib/deda_100430_owner_uid_continuity.dart`](https://github.com/mosubiyi-prog/d-iraq-ludo/blob/fd8cfd590d0f6703e34d6fe8c6913b091c3468fd/lib/deda_100430_owner_uid_continuity.dart)
- [`lib/deda_step2_account_domains_recovery_readback.dart`](https://github.com/mosubiyi-prog/d-iraq-ludo/blob/fd8cfd590d0f6703e34d6fe8c6913b091c3468fd/lib/deda_step2_account_domains_recovery_readback.dart)
- [`lib/deda_step2_existing_account_signin_page.dart`](https://github.com/mosubiyi-prog/d-iraq-ludo/blob/fd8cfd590d0f6703e34d6fe8c6913b091c3468fd/lib/deda_step2_existing_account_signin_page.dart)
- [`lib/deda_session_recovery_coordinator.dart`](https://github.com/mosubiyi-prog/d-iraq-ludo/blob/fd8cfd590d0f6703e34d6fe8c6913b091c3468fd/lib/deda_session_recovery_coordinator.dart)
- [`lib/deda_protected_section_entry.dart`](https://github.com/mosubiyi-prog/d-iraq-ludo/blob/fd8cfd590d0f6703e34d6fe8c6913b091c3468fd/lib/deda_protected_section_entry.dart)
- [`firestore.rules`](https://github.com/mosubiyi-prog/d-iraq-ludo/blob/fd8cfd590d0f6703e34d6fe8c6913b091c3468fd/firestore.rules) و[`firebase.json`](https://github.com/mosubiyi-prog/d-iraq-ludo/blob/fd8cfd590d0f6703e34d6fe8c6913b091c3468fd/firebase.json)
- [`functions/index.js`](https://github.com/mosubiyi-prog/d-iraq-ludo/blob/fd8cfd590d0f6703e34d6fe8c6913b091c3468fd/functions/index.js) و[`functions/deda_stage2_live_gate.js`](https://github.com/mosubiyi-prog/d-iraq-ludo/blob/fd8cfd590d0f6703e34d6fe8c6913b091c3468fd/functions/deda_stage2_live_gate.js)
- الوثائق التاريخية: `docs/DEDA_MISSION_FATE_DECISION_GENERAL_AUDIT_2026-11-13.md` و`docs/DEDA_100441_OWNER_SOURCE_AND_RECOVERY_INTEGRATION_AUDIT_2026-11-12.md` ونقطة توقف 15 نوفمبر.

**لا تغييرات خارج التوثيق. لا إعادة لاختبارات تاريخية، ولا ادعاء بمطابقة إنتاجية غير مقروءة.**
