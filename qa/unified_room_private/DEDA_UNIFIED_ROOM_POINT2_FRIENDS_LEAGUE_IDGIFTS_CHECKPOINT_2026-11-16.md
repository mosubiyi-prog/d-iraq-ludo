# DEDA — نقطة إنجاز رقم 2: الأصدقاء + الدوري الأسبوعي + هدايا الآيدي

**التاريخ:** 16 نوفمبر 2026
**حالة النقطة:** منجزة ومفحوصة داخل مختبر Firebase Auth + Firestore Emulator فقط. لا دمج UIDs أو نشر أو تفعيل حسابات إنتاجية.

## المراجع والنطاق
- GitHub: `mosubiyi-prog/d-iraq-ludo`.
- المصدر المحمي: `fd8cfd590d0f6703e34d6fe8c6913b091c3468fd` — لم يُعدّل.
- فرع المعمل: `deda-unified-room-authz-scopes-isolated-qa-2026-11-16`.
- مدخل الربط: `qa/unified_room_private/deda_friends_league_gifts_REAL_SCHEMA_EMULATOR_ONLY.cjs`.
- اختبار التكامل: `qa/unified_room_private/deda_second_scope_real_sources_EMULATOR_ONLY.test.cjs`.
- وصلة الحارس المعزولة: `room_admin_firestore_gateway_EMULATOR_ONLY.cjs`، مع `sourceMode=deda-real-schema-qa`.
- نتيجة GitHub Actions المثبتة: [43928881497](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/43928881497) — **SUCCESS, 5/5 integration tests** (تشمل النقطة الأولى وفحوص الحارس وتوافق مسارات قديمة محددة).

## الإنجاز الفعلي

1. **الأصدقاء:** من `deda_social_profiles/{originalId}` و`deda_friendships` باستعلام `members array-contains {reviewedSourceUid}`، مع تحقق من `pairKey`, طرفَي العلاقة، `requesterPublicId`, `recipientPublicId`, `status` وUID المصدر الاجتماعي. الناتج `friendCount` للعلاقات المقبولة فقط. رفض تطابقات الهوية الخاطئة وتغيّر `status` بين المعاينة ومعاملة الإصدار. لم تُعدّل العلاقات.
2. **الدوري:** من `deda_weekly_direct_accounts/{originalId}` و`deda_weekly_direct_weeks/{weekId}/scores/{originalId}`، مع تحقق `createdByUid`, `accountKey`, `weekId`, `publicId`, `claimedKeys`, `completedTasks` و`weeklyXp=20*completedTasks`. الناتج `weeklyPoints` للعرض فقط؛ لا إعادة احتساب مستوى اللاعب، ولا زيادة XP، ولا توزيع جوائز. المصدر محدّد للدوري المباشر؛ لم نخلط مع جداول الدوري التجريبية أو المجتمعية الأخرى.
3. **الهدايا:** تم ربط **هدايا الآيدي المميز فقط**: `deda_stage71_granted_registry` و`deda_stage74_id_gift_receipts` باستعلام `recipientOriginalId`، مع التحقق من `group`, `kind=gifted`, `baseColor`, `originalId`, وإيصال `receivedAt` إذا كان موجوداً. يعرض `giftCount` يشمل المعلّقة والمستلمة كسجل، ولا يستلم هدية أو ينشئ إيصالاً أو ينقل الملكية. الهدايا المالية وجوائز الدوري وأنواع هدايا «هداياي» الأخرى **لم تُربط ولم تُعتبر مكتملة**.
4. **جلسة واحدة:** استخدم المختبر حساب Auth Emulator واحد UID B؛ سجلات A وC بيانات تاريخية مصطنعة فقط. التقسيم المنطقي يحصل عن طريق تصريح نطاق مستقل لكل قسم. لا `createUser` في الوصلة، ولا دخول Auth منفصل لـA/C، ولا تغيير UID.
5. **إعادة فحص أمني:** المصدر الفعلي لكل قسم يُقرأ مرتين، آخرهما داخل معاملة Firestore بعد فحص تفويض المالك والجلسة والنطاق. تغيير الصداقة قبل الإصدار يوقف المعاملة؛ فساد نقاط الدوري أو تناقض إيصال الهدية أو مالك ملف الأصدقاء يرفض الإسقاط.
6. **صلاحيات القراءة:** UID آخر لا يقرأ عروض B، ولا يقدر العميل قراءة التصاريح أو تعديل العرض. إلغاء نطاق الدوري لا يلغي صلاحية عرض هدايا الآيدي.
7. **الحفاظ على التقدم:** رصيد النقاط الأسبوعية الأصلي يبقى كما هو؛ الموجود عرض آمن فقط، دون تحويله إلى XP أو جوائز. بيانات الصداقات والهدايا الأصلية لم تُعدّل. هذا لا يعني نجاح استرجاع تقدم المستخدم الحقيقي على هاتف جديد.

## نتيجة الاختبار

- `5/5` اختبارات تكامل رئيسية ناجحة، `0` إخفاقات، [GitHub Actions 43928881497](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/43928881497).
- سجلات الاختبار تضمنت `PASS_POINT2_REAL_FRIENDS_WEEKLY_SCORES_IDENTIFIER_GIFTS_ONE_UID`, `PASS_FRIEND_STATUS_RACE_FAIL_CLOSED`, `PASS_CORRUPTED_WEEKLY_SCORE_GIFT_RECEIPT_SOCIAL_OWNER_DENIED`, `PASS_REVOKE_LEAGUE_ONLY_GIFTS_STAY_INDEPENDENT`.
- فحص Play السابق يخص حالات تمثيلية فقط؛ لم تُجرَ مراجعة كل الأقسام/النسخ القديمة.
- كل التغييرات في ملفات `qa/unified_room_private/` وWorkflow من نمط `deda-unified-room-*`، وليست في ملفات التطبيق المحمية.

## ما لم يُنجز بعد

- ربط جميع أنواع «هداياي» (الماسات، جوائز الدوري، الهدايا الأخرى) مع مصادرها التاريخية وإثبات ملكيتها: يحتاج تحديد المصدر ونطاق تفويض مستقل قبل أي ادعاء.
- إثبات ملكية حقيقي للهويات A/B/C والحساب الأصلي، وإكمال الاسترجاع على هاتف جديد، وربط Google الدائم: **غير مفعّل**.
- لا نشر لFirebase الحقيقي أو قواعده، ولا تعديل `lib/`, `functions/`, `firestore.rules` أو Google Play.

## نقطة الاستئناف المتفق عليها

**النقطة الثالثة:** ربط الماسات والأماكن المنشورة في المختبر، دون الصرف/الشراء أو تغيير ملكية الأماكن، وبنفس الحارس والجلسة الواحدة؛ مع الانتباه إلى عدم الخلط بين الرصيد الخادمي والرصد المحلي القديم.

**منع الانحراف:** لا انتقال للنقطة الثالثة بدون إبلاغ المستخدم بإنجاز الثانية، ولا إعادة فحص A/B/C التاريخية من البداية.
