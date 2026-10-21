# DEDA — موافقة المالك: المعرّف المميز يعمل في كل مكان مثل الأصلي

## القرار الملزم (2026-10-21)
وافق مالك تطبيق DEDA على **تفعيل ربط المعرّف المميز الفعّال الشامل**، بشرط ألّا تبقى أي شاشة أو بحث أو مشاركة تعرض الآيدي القديم إلا عند عودة المستخدم إلى الأصلي أو غياب إثبات موثوق.
- لا حذف أو تغيير المعرف الأصلي أبداً؛ هو الهوية الثابتة للتوجيه والمحاسبة والسجلات السابقة.
- الهوية العامة الظاهرة عند المرسل/المستلم/الصديق/الإدارة هي الآيدي المميز النشط، بما في ذلك نفس اللون/الفويل المثبت من سجل الملكية.
- قبول إدخال الآيدي المميز عند إرسال الموقع، البحث عن صديق، ومنح هدية جواهر، ثم **التوجيه داخلياً لحساب الآيدي الأصلي نفسه فقط**.
- إلغاء تفعيل الآيدي المميز يعيد عرض الأصلي، بدون إنشاء حساب جديد، أو فقد الماس/المستوى/الصداقة/الموقع.
- الحقوق/صلاحية استخدام الـID لا تُثبت من حقول يكتبها المستخدم؛ تتحقق خدمة الخادم من original -> active -> granted -> receipt.
- لا شراء أو صرف أو تبديل رصيد تلقائياً في خطوة تفعيل الربط.
- لا نشر Play حتى اختبار هاتف + تاب بحسابين مختلفين وموافقة المالك.

## شاشات ومسارات واجبة الفحص: لا تصنيف كامل قبلها

| الرقم | المسار | المصدر الداخلي | واجهة العرض | حالة الإثبات |
|---|---|---|---|---|
| 1 | معلومات حسابي / «معرفاتي» | الأصلي محفوظ | المميز الفعّال بنفس اللون | نجح في 100373 على الهاتف |
| 2 | إرسال موقعي / خانة «معرفي» | أصلي للربط | المميز | نجح عند المرسل |
| 3 | استلام الموقع | original senderPublicId | المميز ولونه | فشل فعلياً 100373، كود خدمة تحقق مُعَد وغير منشور |
| 4 | إرسال موقع **إلى آيدي مميز** | original recipientPublicId | يقبل المميز إدخالاً | أضيف resolver + backend مسار أصلي، فحص CI مطلوب |
| 5 | ملف الصديق العام | original publicId | المميز وفويله، اسم مقروء | فشل فعلياً 100373، stage50 يعالج العرض عند الخدمة المباشرة |
| 6 | إضافة صديق / البحث | original publicId / ownerUid | يقبل إدخال المميز | أضيف alias -> canonical بملف DedaSocialService، CI مطلوب |
| 7 | قائمة الأصدقاء / البحث الاجتماعي / الطلبات | سجلات الأصل | يظهر المميز عند كل مكان يعرض ID | **تدقيق شاشات العرض مفتوح**، لا تَعِد بأنه مكتمل |
| 8 | هدايا الجواهر: مستلم | original recipient | يقبل المميز واسم المستلم صحيح | فشل فعلياً 100373؛ جسر GM آمن موجود وأُجريت اختبارات، Firebase لم يُفعّل |
| 9 | الهدايا السابقة والسجل | immutable original ledger | عرض الهوية المميزة إذا تحقق | السجل موجود؛ ترقية العرض دون تغيير السجل مفتوحة |
| 10 | إدارة المعرفات GM «استخدام» / «منح» | محققة UID/accountKey/original | المميز بنفس اللون | اختبارات CI نجحت؛ هاتف لم يفحص التفعيل النهائي |
| 11 | هداياي / استلام معرف مميز | original recipient / gifted ID | المميز عند صاحب الحساب | نُفذ عند المالك، badge غير مقروء قبل الاستلام |
| 12 | الشارة الملونة على الملف الشخصي | الأصل بالربط | نفس الفويل الأربعة الأصلي | جزء Flutter مهيأ؛ الطرف الآخر ينتظر backend |
| 13 | النسخ/QR/دعوة/مشاركة رابط أو رسائل | أصل للفتح/التوجيه | المميز المفعّل إن كان المقصود الهوية الظاهرة | **تدقيق شاشة بشاشة مفتوح** |
| 14 | تبديل الحساب/الآيدي/الرجوع بعد عدم الاتصال | الأصل ثابت | تحديث alias/ink من السيرفر | Flutter lifecycle tests نجحت، الهاتف مفتوح |
| 15 | تحديث الهوية عبر جهاز ثانٍ | الحساب الأصلي الموثق | نفس alias للمالك والصديق | يحتاج Firebase/App Check وQA حقيقي |

## ما تمَّ تجهيزه ضمن الفرع
- Functions owner-approved exports staged (private branch only):
  `dedaPremiumReadPublicIdentifierStyle` — verified public ID + permanent foil.
  `dedaPremiumResolvePublicRecipient` — active ID to ORIGINAL for friend/location input.
  `dedaPremiumResolveAdminGiftRecipient` — general-manager-only lookup, canonical original gift destination.
- Source `functions/deda_qa32_public_alias_resolver_NOT_EXPORTED.js` validates immutable original route + currently active selection + grant owner/color/group + claimed gift receipt as needed. No user wallet/UID/phone in responses.
- `lib/deda_qa32_public_recipient_resolver.dart`: strict 3-field canonical result; new `DedaBackend.createLocationShare` and `DedaSocialService.findByPublicId` consume ONLY canonical original after validation. Original IDs take precedence in ambiguous six-character matches. Premium IDs allow four through 12 characters.
- Existing friend/received display `DedaStage50VerifiedFriendInkBadge` and GM `DedaQa32AdminGiftRecipientAliasBridge` now initialize App Check through `lib/deda_qa32_premium_app_check.dart` before a trusted callable. Added `firebase_app_check` dependency. Default live feature flags stay OFF until proven Firebase deployment + Play Integrity registration.
- Exact private branch: `deda-100374-ids-qa32-frames-deferred-2026-10-21`. Production APK 100373 and original immutable rollback preserved.

## Confirmed REAL deployment blocker — fresh IAM test (2026-10-21)
[Actions 39668595065](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/39668595065) read-only:
- `IAM_TEST_PERMISSIONS_HTTP 200`; `CAN_CLOUDFUNCTIONS_FUNCTIONS_LIST/GET/CREATE/UPDATE = False`.
- `CLOUD_FUNCTIONS_V1_LIST_HTTP 403`.
- `FIREBASE_PROJECT_ID_MATCHES True` for `deda-25b88`.
- `FIREBASE_CI_TOKEN_NOT_CONFIGURED`.
Consequently **neither this agent nor GitHub Actions can currently deploy/activate the three Functions** using current credentials. This is NOT a Flutter test failure. Owner/admin must grant the existing GitHub service account necessary least-privilege Cloud Functions deployment permissions or provide an authorized Firebase deployment connection. Do not invent a credential, bypass IAM or claim live.

## AppCheck second precondition
- Repo originally lacked `firebase_app_check`; AppCheck is now staged but Android Play Integrity requires Firebase App Check registration for the actual DEDA app/package and signing certificate.
- Do NOT set any of these flags true merely because Node/Flutter CI passed:
  `DEDA_PREMIUM_IDS_SERVER_LIVE`,
  `DEDA_STAGE50_PUBLIC_IDENTIFIER_STYLE_LIVE`,
  `DEDA_QA32_ADMIN_GIFT_RECIPIENT_ALIAS_LIVE`,
  `DEDA_QA32_PUBLIC_RECIPIENT_LOOKUP_LIVE`.
- A private sideloaded release APK may not pass Play Integrity (requires real attestation); validate separately and never weaken production AppCheck as a workaround.
- First obtain IAM + provider configuration and run no-user-mutation preflight, then targeted 3-function deploy, then signed two-account QA APK and exact 15-surface acceptance. Release wider only with owner signoff.

## Zero-wallet/data mutation
Do not change Firestore rules, ID grant registry, users, wallet, diamond gift ledger, points, purchase receipts, existing places, friends, historical location shares or live Play app as a shortcut. Server exports are read-only and branch-staged, not deployed.
