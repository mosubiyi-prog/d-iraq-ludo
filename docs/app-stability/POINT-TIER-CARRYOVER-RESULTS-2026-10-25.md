# حفظ حقوق مراحل النقاط — 25 أكتوبر 2026 بتوقيت بغداد

## الناتج

أضيف `savePointTierCarryover` تحت tools فقط؛ ليس Functions/API أو منطق شراء/محفظة جديداً. يقرأ approval محفوظاً نتج من مراجعة مدير عام وقرار grandfathering خاص، ويتحقق من تطابق الأرشيف/تقريره والبصمة والـbaseline المقترح وإصدار السياسة. يشترط root.phase=baseline-approved، وعدم وجود deda_verified_progress، واستمرار السياسة والمراجع النشط/الدور والبريد. لا يطلب token جديداً للمراجع ولا يدعي فحص revocation جديداً؛ يعتمد قرار المراجعة المحمي السابق داخل عامل خادم داخلي. العميل لا يمرر مبلغاً أو مرحلة أو reviewerUid/verified.

يكتب atomically خمس pointTierEntitlements وملخص pointTierCarryovers/<migrationId> داخل deda_progress_migrations/<account> الخاص فقط. يربط basisDigest هوية القرار وتاريخه وسياساته وبصمة الدليل والـbaseline والجدول الخام. لا رصيد أو verified receipt أو event أو user/role أو مقتنى/محفظة أو settlement يُكتب، ولا root phase يتقدم.

| حالة الخام المعتمد | حالة النقل الخاص | عائد مستقبلي مرصود | المسموح الآن |
| --- | --- | --- | --- |
| reserve لأول أربع مراحل بلا claim | reserved-awaiting-cutover | threshold+bonus من الجدول الأصلي | لا صرف/تعويض |
| reserve مع claim قائم | claimed-in-baseline | null؛ الاستلام محسوب في الخام | لا إعادة الاستلام |
| reserve25000 بتسلسل صحيح | terminal-prize-spent | null؛ الخصم نهائي | لا رد25000 أو bonus250 |
| لا reserve/claim في اللقطة | not-observed | null | لا افتراض صفر رصيد أو منح حق فتح |

الشروط المفقودة/المتناقضة/مقادير أو metadata خاطئة/claim بلا reserve/مرحلة بلا claim سابقة/point_tier|5000 التاريخية/claim25000 الملغاة توقف النقل للمراجعة. لا حذف من awards أو clamp للرصيد أو استعادة تلقائية.

إعادة نفس الطلب تعيد الملخص دون الكتابة أو تعديل timestamps. لا يكتب فوق stage جزئي أو مبلغ محرف، ولا يعيد الاستيراد بعد cutover أو فوق حالة مالية قائمة. كل القراءة والكتابة داخل نفس معاملة Admin Firestore؛ تغير الدور/السياسة أثناء retry يعاد فحصه. الفشل لا يترك نصف الحقوق أو يمس الأصل.

## الفحص

Node273/273 محلياً (241 سابقة+32 جديدة). أضيفت14حالة Auth/Firestore Emulator تستخدم approveLegacyBaseline مع token صادر من Auth emulator والتحقق الحقيقي السابق عبر Admin SDK، ثم عامل النقل ومعاملاته. تغطي الحفظ المحمي والتزامن ومرحلة مستلمة/أخيرة وبيانات غير متسقة وتغيير الدور/السياسة والأصل ومنع العميل وفشل commit وتعارض replay. CI قيد الانتظار.

لا تغيير Flutter أو قواعد أو مخطط الأرشيف أو PIN/SDK أو native harness؛ لم تُكرر native24/PIN24 التي اجتازتها نسخة الربط المحفوظة في checkpoint-stability-purchase-evidence-native-pass-2026-10-25. لا حسابات حية أو Firebase deploy أو تفعيل سياسة إنتاج أو APK ديدا.

## الحدود والمتبقي

هذه **حماية وحفظ لحقوق مرشحة** بعد مراجعة يدوية؛ ليست استلام نقاط أو ضماناً لمصدر الإعلانات/المهام القديمة. الحقوق مخفية عن العملاء، canClaimNow/canRefundNow/canReleaseBalance/canAutoSettle كلهاfalse. observedUnclaimedReturns ليس pendingReservations تسوية؛ لا يجعل0فيه الحساب settled ولا ينشئ fence.

باقي إصدار baseline الموثوق وتسوية المشتريات/المعلقات ووقف الكاتب القديم فعلياً، ثم نقل/صرف الحقوق المسموح بها مرة واحدة وربط الاسترجاع في التطبيق وبقية البيانات وهاتفين ونسخة مراجعة. لا تمس المليون المشتق للمدير أو محفظته الشخصية أو الهدايا/المنح؛ الرصيد الخام السالب/المفقود لا يرحل تلقائياً.

الرجوع: checkpoint-stability-before-point-tier-carryover-2026-10-25 عند1b9487e2aea37f2865d6876e300a693d0ed33f4e.
