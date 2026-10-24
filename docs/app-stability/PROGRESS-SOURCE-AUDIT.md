# مصادر التقدم وحدود الربط — 2026-10-23

مراجعة مصدر بعد نقطة 69d7801. مصدر Flutter هو main.dart المستعاد من أرشيف 100380 المثبت، وليس main الأقدم في جذر المستودع. دوال functions قُرئت من فرع المرحلة دون استدعائها. هذه نتائج جرد، وليست إصلاحاً أو فحص أجهزة أو تحققاً من حالة الخدمات المنشورة.

| المصدر الأصلي | الأثر والهوية | نتيجة الربط |
| --- | --- | --- |
| DedaTaskEngine.claimTaskReward | +5 points، task\|cycle\|taskId؛ completion محلي | لا إثبات خادمي من السجل المحلي وحده |
| شاشة _claimTaskReward ثم DedaSocialProgressWallet.awardTaskClaim | بعد منح النقاط لأول مرة: +10 coins و+20 XP؛ taskClaims = cycle\|taskId | كتابتان محليتان منفصلتان. فشل الثانية يُبتلع؛ إعادة المطالبة لا تعيدها لأن pointsAwarded أصبح false. لا يثبت وجود النقاط وجود coins/XP دائماً |
| claimDailyLoginReward | +10 points، daily_login\|localDay | يوم الهاتف محلي؛ يحتاج عقد دورة خادمية يحفظ حدود اليوم السابقة |
| DedaTaskEngine، فرع trafficQuizCorrectAnswer | +5 points، traffic_answer\|cycle\|dedupeKey | المفتاح المحلي لا يثبت صحة الإجابة لدى الخادم |
| _watchTaskRewardedAd ثم claimTaskRewardedAdBonus | +5 points بعد المكافأة الأساسية، rewarded_ad\|cycle\|taskId | callback الهاتف ليس receipt خادم. rewarded-ad-v1 في النموذج مخصص earnedDiamonds فلا يستخدم لهذا المسار |
| _watchDiamondsRewardedAd ثم DedaDiamondsWallet.claimReward | +3 earnedDiamonds؛ حد 5 مشاهدات/يوم محلي؛ balance/day/viewsToday | السجل لا يحفظ معرّف معاملة مزود. العداد أو callback لا يثبت إعلاناً خادمياً |
| _openPointTier | -threshold points، point_tier_reserve\|threshold؛ يشترط claim المرحلة السابقة | الرصيد المتاح يتضمن bonus المدير، بينما النموذج يستبعده. يجب الحفاظ على استحقاق المدير قبل نقل هذا المسار |
| _claimPointTierReward | للأربع الأولى: +threshold+bonus مرة مع reserve سابق؛ الخامسة 25000 نهائية بلا إرجاع | ليست مكافأة مهمة عامة أو إلغاء بسيط. تحتاج ربط الحجز بالمطالبة والتحقق من جدول المراحل. يوجد تنفيذان للشاشة في main |
| DedaSocialProgressWallet.spendCoins | -price coins دون نقصان XP | لا orderId أو معاملة مشتركة مع المقتنى |
| DedaDiamondsWallet.spend | العادي يصرف earned ثم gifted في توزيع المبلغ؛ عند الحاجة يخصم gifted خادمياً قبل حفظ earned محلياً. المدير يصرف محفظته الشخصية المنفصلة | لا يرسل كامل price كخصم earnedDiamonds ولا يكرر خصم gifted/GM داخل الإسقاط |
| _buyFrame / _buyBadge | _payForIndex ثم DedaStyleInventory.addOwned | يمكن الفشل بين الدفع وحفظ المقتنى. _busy قفل شاشة واحدة، وليس طلباً خادمياً بين هاتفين. لا تعويض مثبت في هذا التسلسل |
| functions/deda_telegram_verified_claim.js، claimVerifiedTelegramFollow | +10 إلى deda_diamond_gift_balances/personalId مع accountClaims وTelegram identityClaims وaudit في معاملة واحدة بعد التحقق | gifted لا earned؛ يستبعد من إسقاط earnedDiamonds لمنع المضاعفة. قراءة المصدر لا تثبت نشره أو تفعيله أو جاهزية البوت |

## خدمات سابقة لا تصلح كإثبات إنتاج

- functions/deda_daily_reward_shadow_ledger.js يفرض مشروع demo ويقرأ fixtures ويكتب shadow balances.
- functions/deda_social_task_stage2.js، rewardDecision، يعيد live-wallet-ledger-not-ready صراحة.
- tools/deda_jamal_stage21_reward_attestation_emulator_only_2026_10_19.js يستخدم HMAC اصطناعياً للمحاكي ويصرح أنه ليس AdMob SSV. لا تنقل تذاكره أو مفاتيحه إلى الإنتاج.
- في النطاق المقروء (functions وmain المستعاد) لم يظهر تنفيذ SSV فعلي أو ربط serverSideVerification للإعلانات. هذه نتيجة جرد النطاق المحدد، وليست نفياً لوجود خدمة خارج المستودع.

## شروط الترحيل المستخلصة

1. لا إعادة بناء إجمالي من ledger وحده: سجل النقاط مقصوص إلى 600 وtaskClaims إلى 180. تحفظ النصوص وawards/completions كدليل غير موثوق؛ لا يستخدم clamp أو fallback إلى empty لاعتماد بداية مالية.
2. لا اشتقاق coins/XP من عدد claims النقاط، ولا جمع أو max أو أحدث createdAt بين لقطات أجهزة مختلفة؛ قد تتضمن كتابات جزئية وصرفاً قديماً.
3. غياب سجل على هاتف جديد لا يثبت حساباً جديداً أو رصيد صفر. عند غياب بداية معتمدة تبقى migration pending؛ لا استبدال بيانات المستخدم بصفر.
4. يلزم حد انتقال لكل حساب: بداية معتمدة وآخر أحداث مشمولة فيها ثم أحداث تالية. تفرد eventKey لا يمنع احتساب مكافأة ضمن baseline ثم إضافتها مرة ثانية كحدث. يلزم تسوية الكتابة القديمة والطلب الجاري والهاتف القديم غير المتصل؛ هذا غير منفذ.
5. المنتج الخادمي يحتاج هوية مزود مستقرة فريدة عالمياً مربوطة بالحساب ونوع الاستحقاق، وليس verified=true أو sourceId أو مبلغاً من العميل.
6. شراء المظهر يحتاج orderId ثابتاً وحالة معلقة/مكتملة وتعافياً يثبت الدفع والمقتنى، مع فصل earned/gifted/GM. لا يضاف خصم جديد إلى checkout القديم.
7. حجز مراحل النقاط ومطالبتها يحتاجان حالة مرتبطة واستحقاقاً مستقلاً. لا يمثل threshold+bonus كـtask-claim غير مقيد؛ عقد النموذج الحالي لا يغطي هذا المسار.

## نقطة المتابعة

لم يصبح أي مصدر عملة محلية أعلاه منتجاً خادمياً موصولاً إلى reconcileVerifiedReceipt. التنفيذ التالي عقد انتقال الحساب بحالات pending/evidence-saved/baseline-approved/cutover-complete، يربط اعتماد البداية بمعرف الأدلة وحد الأحداث المشمولة ويمنع تطبيق الأحداث أثناء pending. تُسوّى نوايا الشراء والحجوزات قبل cutover. العقد لا يعتمد الرصيد المحلي تلقائياً. يليه منتج إثبات حقيقي لكل مسار واختبارات SDK والقواعد ومقارنة هاتفين.

هذه الدفعة وثائق فقط: لا اختبارات جديدة أو تغيير التطبيق/functions/rules أو الأرصدة أو صلاحيات الإدارة. آخر نتائج التنفيذ المعتمدة تبقى كما في CURRENT.


## تحديث التنفيذ — 25 أكتوبر 2026 بغداد

أضيف عقد point-tier-return-v1 وعامل point-tier-claim.cjs لاستلام الحق المنقول المحفوظ بعد تحقق baseline/cutover/settlement/الأرشيف والموافقة والخمس مراحل في المعاملة نفسها. أول أربع مراحل فقط بقيم5050/10100/15150/20200؛ الخامسة25000 وما استلم ضمن الخام لا يعاد. receipt والتصنيف والحدث والإسقاط وعلامة الاستلام تكتب ذرياً، وإعادة الطلب ترجع الحالة الحالية دون تكرار. هذا يغطي استلام حق قديم منقول حصراً، ولا يغطي إنشاء حجوزات مستقبلية أو منح المهمة/الإعلان أو توثيق حساب المستدعي. العامل غير منشور؛ legacyFenceId ما زال مرجعاً وليس وقفاً حقيقياً للكتابة القديمة، وتسوية الشراء/منتج cutover ومدخل خادمي يثبت الحساب وربط التطبيق باقية. لا تعتبره تفعيلاً أو تحققاً لهاتفين. المصدر1343e514؛ فحص40139845610 نجح بكل5مهام، Node351 وEmulator189؛ التفاصيل POINT-TIER-CLAIM-RESULTS-2026-10-25.md/.json.
