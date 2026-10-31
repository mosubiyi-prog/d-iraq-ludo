# DEDA 100405 — إيجاز النقاط السبع قبل تحضير APK

**المرجع المحفوظ:** إصدار الهاتف المقبول **100404**؛ لا تعديل ولا نشر عليه.
**فرع العمل:** `deda-100405-admin-five-points-integrated-no-apk-until-qa-2026-10-31`.
**حالة النشر:** ماكو APK جديد، ماكو نشر Play، ماكو توزيع ماسات فعلي، وماكو تفعيل لقواعد الإدارة الجديدة على Firebase الحقيقي.

## النقاط السبع — تنفيذ الفرع والفحوص

| النقطة | الموجود فعلياً في فرع 100405 | نتيجة الاختبار | الذي يتطلب تفعيل/قبول حقيقي |
|---|---|---|---|
| 1. المتصدرون العشرة والثلاثة الأوائل | بطاقة المدير تقرأ مباشرة `deda_weekly_direct_weeks/{weekId}/scores`، وتعرض الاسم والآيدي والنقاط والمركز بدون قائمة تجريبية | نجح Flutter + projection tests؛ الوحدات تقرأ نفس السجل | نتيجة صاحب التطبيق على 100404 بعد السادسة كانت +20 XP محلياً لكن **لا مركز حقيقياً**. يجب تشخيص تسجيل نقاط الخادم قبل اعتماد الربط حيّاً |
| 2. التحكم بالدوري | إيقاف/استئناف بإدارة المدير العام فقط، سبب القرار وسجل دائم، وقيد `weekId` حتى إيقاف الأسبوع القديم لا يعطّل بداية السبت 6 صباحاً | نجحت فحوص حماية Firebase emulator بما فيها صلاحيات المدير فقط | نشر إضافات `firestore.rules` على Firebase الفعلي **بعد مراجعة المالك** |
| 3. الأرشيف الأسبوعي والشهري | اختيار شهر، قراءة الأسابيع المكتملة العشرة الأوائل، إبراز 1–3 في بطاقة مستقلة؛ لا حد 12 أسبوعاً، ولا إدخال الأسبوع الحالي في الأرشيف قبل السبت 6 | نجحت اختبارات الحدود والأشهر وFlutter | التحقق من سجلات الأسابيع الحقيقية عند انتهاء أول دورة |
| 4. الجوائز إلى هداياي | مخطط 150/100/50/10×7؛ عامل Admin SDK ينشئ **نفس مستندات `deda_diamond_gifts` بحالة pending**، مع رقم هدية ثابت لكل أسبوع+مستخدم لمنع التكرار. `هداياي` الأصلي يستلم الهدية ويضيفها للرصيد مرة واحدة. شاشة الإدارة تعرض عدد الهدايا المعلقة/المستلمة الحقيقي. عند تجميد فائز تُعلّق جائزته بدون إزاحة المراكز؛ بعد فكها يعاد التحقق ويُصدر المستحق إن لم يصرف. | نجحت فحوص العامل المحلي والمحاكي للتجميد، إعادة التشغيل، عدم زيادة رصيد قبل الاستلام، ورفض الاستلام مرتين | التشغيل الآلي على Firebase الحقيقي **غير مفعل**؛ جدول GitHub مضبوط فقط على فرع العمل، ومقفول بمتغير `DEDA_100405_WEEKLY_SETTLEMENT_OWNER_APPROVED` غير المفعّل. GitHub cron أفضل جهد وقد يتأخر عن الدقيقة 06:00؛ الدقة بالدقيقة غير مضمونة |
| 5. تجميد نقاط مستخدم مع إشعار | المدير العام يجمد/يرفع التجميد مع سبب وسجل. المستخدم يشوف **الإشعار المحايد فقط**، ولا يشوف السبب الإداري. فترة التجميد لا تلغي مستوى أو ماسات أو مهام المستخدم. خيار مراجعة الأسابيع السابقة داخل الإدارة بعد بدء الأسبوع الجديد. طلبات المهام الصحيحة محفوظة بطابور نفس الأسبوع على الجهاز وتستعاد بعد فك التجميد، مع رفض نقلها لأسبوع آخر | نجحت فحوص صلاحيات Firestore ونقل الإشعارات عبر المستندات المنفصلة، وفحوص Flutter لاسترجاع الطلبات من نفس الأسبوع | الطابور على الجهاز فقط؛ إن حُذفت بيانات التطبيق أثناء التجميد فقد لا يمكن استرجاع الطلبات التي لم تصل للخادم. يحتاج فحص عملي للهاتف/التابلت قبل ضمان الاسترجاع الكامل |

| 6. إزالة مختبر الدوري من واجهة المستخدم | حُذف زر «فتح مختبر الدوري» من نافذة معلومات المتصدرين **في مشروع 100405 المجمّع فقط**؛ تبقى ملفات الاختبارات التجريبية معزولة خارج الواجهة، ولا تُمس بيانات حساب المستخدم | اختبار واجهة Flutter للتحقق من غياب الزر مع بقاء زر المعلومات والمهام | فحص الشكل على الهاتف والتابلت ضمن APK المجمّع بعد مراجعة المالك |
| 7. عداد الدوري بالأيام والساعات | بقي العداد بنفس موضعه وحجم البطاقة، لكن النص يتحول من `161:34:21` إلى «**6 أيام و17 ساعة**» وتحتها «**34 دقيقة و21 ثانية**»؛ نفس تاريخ البداية ونفس تجميد السبت 00–06 | اختبار وحدة + هاتف/تابلت للعدّاد وأيام الأسبوع والتجميد، بدون تغيير الحساب الزمني | فحص العرض الحقيقي في النسخة المجمّعة، خصوصاً الخطوط عند الشاشات الصغيرة |

## تثبيت القرارات

- السبت الساعة **06:00 صباحاً بغداد** يبدأ الأسبوع الجديد، حتى إذا كان الأسبوع السابق متوقفاً يدوياً. **لا يتكرر التجميد كل يوم**.
- السبت عند **00:00 منتصف الليل** فقط في نهاية الأسبوع يتوقف احتساب XP الدوري لغاية **06:00**؛ يبقى الترتيب ظاهراً ثابتاً.
- لا تغيير لنقاط المستوى (+20 XP لكل إنجاز)، نظام الترقية، الماسات الأصلية، الهدايا، هوية الحساب، أو تصميم قائمة المتصدرين.
- زر «الأسبوع السابق» **محذوف من قائمة المتصدرين للمستخدم**؛ اختيار أسبوع قديم يكون داخل **إدارة الدوري فقط**.
- **لا يظهر مختبر الدوري في واجهة المستخدم** بعد 100405. محاكاة الجوائز منفصلة عن الدوري الحقيقي.
- **وقت الدوري مقروء بالأيام والساعات والدقائق والثواني، وليس مجموع الساعات**، مع الاحتفاظ بالعداد في مكانه وحجمه.
- لا يُدفع أي مبلغ من محفظة المدير الشخصية؛ جوائز الدوري مستندات منفصلة داخل نظام «هداياي» الأصلي.

## فحوص مؤيدة

- Flutter full integration (فروع ما قبل آخر تعديل): **41161958645**, **41162153967**, **41162433560**, **41165289210**, **41165820597**.
- قواعد صلاحية المدير والتجميد، والإشعار الخاص + منع الاستلام المكرر: **41165401372**, **41165836214**.
- مخطط الجوائز + عامل الإيداع في `هداياي` على المحاكي: **41162308786**, **41165488205**, **41165876534**.
- فحص Flutter الأخير بعد اختيار الأسبوع السابق بالإدارة: تُثبت نتيجته قبل اعتبار التجميع جاهزاً.

## قبل بناء نسخة واحدة

1. اعتماد المالك للإيجاز والتعديلات المتعلقة بالدوري والآيدي؛ **لا APK الآن**.
2. فصل خلل نقاط الدوري الحقيقية المشاهد في 100404 (200→220 XP محلياً، بلا ترتيب) عن خلل تأخر ظهور الآيدي المميز في الملف الشخصي، حسب طلب المالك؛ يفحصان قبل إصدار النسخة المجمعة.
3. تطبيق قواعد Firebase الجديدة بطريقة additive محافظة على قواعد الإنتاج السابقة، وفحص النشر الحقيقي، وتفعيل مشغل الجوائز فقط **بعد موافقة المالك الصريحة**. لا نفترض أن نجاح المحاكي هو تشغيل حقيقي.
4. فحص التسجيل من حسابين على الهاتف/التابلت، تجميد ورفع، التوقيت، أرشيف الأسبوع، هدية مستلمة مرة واحدة، واستعادة الآيدي.
5. إصدار APK واحد للفحص الشخصي دون نشر Play، بعد اكتمال النقاط والموافقة.

**هذه قائمة مراجعة النقاط السبع ما قبل النسخة، وليست إعلان جاهزية إطلاق أو صرف جوائز حيّة.**

## Owner video QA — 1000101803.mp4: legacy full QA lab is embedded in 100404

Source of evidence: owner's 13.31-second screen recording, inspected at sampled frames 0–13 s. First screen is the real **متصدرين المهام** leaderboard, with correct countdown **161:19:56**, but vacant rank 1–10 and personal rank. Owner taps info icon, then **فتح مختبر الدوري**, which navigates to a second screen titled **DEDA دوري مختبر**. That page explicitly says **بيانات ومكافآت تجريبية فقط** and **ماكو مستخدمين وهميين في الدوري الحقيقي**. It shows **220 XP** local task signal and **550** sample sandbox diamonds; it can switch among fictitious rank/weekly cycles (example displayed test week **23-11-2026**, not the actual league starting 31 Oct). The 150/100/50/10 prize test is NOT a real Hadaya credit.

CODE VERIFIED:
- `tools/app_stability/app_package/bind_weekly_full_qa_stage18.py` injects the **فتح مختبر الدوري** button into the *real* leaderboard info dialog, navigating to `DedaWeeklyQaFullTrialPage`.
- `lib/deda_weekly_qa_full_trial.dart::DedaWeeklyQaSandbox` stores fake ranks/payouts in local `SharedPreferences`, under `deda_weekly_qa_earned_shadow_v1_${accountKey}`; **no Firebase points or real diamonds**.
- `lib/deda_weekly_private_trial_local_xp.dart` counts an independent Monday-based local QA test week; it is NOT the authentic Saturday 06:00 league scoring calendar, explaining mismatch between 220 QA XP and real vacant ranks.
- `tools/app_stability/app_package/bind_weekly_100402_firestore_direct.py` wires the authentic route to `DedaWeeklyFirestoreDirectBridge.loadStandings/claimAfterOriginalReward` and Firestore `deda_weekly_direct_weeks/{weekId}/scores`, separate from the mock lab. Presence of lab is visually confusing but **NOT demonstrably a cause of missing Firestore scores**.
- Owner says the premium ID eventually rendered normally, while real league still showed no user entry; independent review must focus on claim call, account identity/UID, score write + rules and parser; do NOT arbitrarily alter the premium ID.
- Prebuild owner review: propose hiding/removing the QA lab button and its entry in final single 100405 APK, **without deleting or mutating real XP, Hadaya or database**. Wait for owner approval before declaring it removed. Keep 100404 unchanged.

## ملاحظات إضافة المالك للنقطتين 6 و7

المالك اعتمد بالصورة بتاريخ 31 أكتوبر 2026 إزالة مختبر الدوري حتى لا يلتبس مع الترتيب الحقيقي، وإظهار ما تبقى باليوم والساعة والدقيقة بدل العدد الإجمالي للساعات. لا تُبنى نسخة مستقلة لهذين التغييرين. **إجمالي النسخة المقبلة 7 نقاط**؛ إصدار 100404 مرجع رجوع ولا يُمس. تنفيذ النقطتين على فرع 100405 جارٍ مع فحوص Flutter؛ لا تُعتبر النسخة مكتملة قبل إثبات نتائج GitHub النهائية، والموافقة على المسائل الحية المرتبطة بالتحكم والجوائز وإثبات نقاط الدوري.

> المرجع السابق لأجزاء الإدارة الخمسة موجود في سجل النقاط الخمس، وهذا هو مرجع المالك الحالي للمراجعة **السباعية**. لا تعادل نتيجة الاختبارات الموافقة على تشغيل الجوائز الحية.

## فحص النقطتين السادسة والسابعة — PASS

- GitHub Actions **41167320222**: **SUCCESS** على مشروع Flutter الأصلي المجمّع برقم 100405، بدون إنشاء APK أو نشر Firebase أو Play.
- أُزيل مدخل «فتح مختبر الدوري» من نافذة معلومات قائمة المستخدم، وبقيت اختبارات المختبر البرمجية مستقلة وغير قابلة للدخول من واجهة المستخدم.
- اختبار عداد عيّنة `161:34:21` → **«6 أيام و17 ساعة»**، وتحتها **«34 دقيقة و21 ثانية»**، مع تحديث الثواني وعدم تغيير حساب بداية ونهاية الأسبوع.
- فحوص القائمة الثابتة بلا تمرير، وأزرار المهام الأصلية، وعرض الهاتف والتابلت، والتجميد الأسبوعي، والتأكد من عدم إرجاع «الأسبوع السابق» نجحت.
- لا يجوز وصف جوائز «هداياي» أو التحكم الإداري بالتشغيل الحي قبل نشر القواعد المحمية وتفعيل الخدمة بموافقة المالك؛ ولا يجوز وصف نقاط الدوري الحقيقية ناجحة قبل إثبات تسجيلها من حساب حقيقي.

## 31 October 2026 — verified backend activation checkpoint (owner explicitly requested activation)

- **Real Firebase service project verified**: `deda-25b88`; read-only gate run **41168299019** checked published policy, IAM permission to update rules, and current week's real score collection. Scores for `2026-10-31` were zero. Original league scores were published, but GM pause/freeze rules were not yet live.
- **Actual production additive permissions deployed**: run **41168397421** succeeded. The workflow extracted the original deployed rules, proved the exact 100404 score block matched the previously deployed one, replaced **only that block** with the manager-only pause/freeze/notices/audit version, tested the exact merged policy on Firebase emulator, checked production rules unchanged between test and deployment, deployed Firestore rules only, then independently read back the published ruleset. It did **not** write XP, gifts, wallets, IDs, storage, or deploy to Play.
- **Owner account diagnosis**: read-only run **41168501541** verified original public ID `@DEDA-D62UEB` is a real active personal identifier; UID's `users` document and `deda_sessions` have matching canonical account keys; user ID matches original. No `deda_weekly_direct_accounts` account binding existed and no weekly score row was written. Read-only auth check **41168580890** verified Firebase Auth original UID is enabled and anonymous-compatible; this rules out disabled/nonanonymous provider as the obvious cause, not a full proof of the current device session.
- **Owner canonical league enrollment corrected without XP**: run **41168627731** created `deda_weekly_direct_accounts/@DEDA-D62UEB` only after strict original UID/session/user/active-personal-ID checks. Result: `CANONICAL_ACCOUNT_ENROLLED`. No invented point, no weekly score insertion, no gifts, no wallet writes. A post-reward real client claim must still be observed to confirm the league source works.
- **Signed owner QA build requested**: run **41168456756** generates a private `100405` signed APK with all seven UI/code points, retaining the official app package/signature and the rollback `100404`. Record result/artifact separately when finished. This build does NOT automatically enable the weekly prize job.
- **Critical unresolved integrity point**: current direct weekly score writes are generated from client reports and not independently attested by the server against original task completion. The former server prototype explicitly warned that phone task notification is not independent proof. **Do not enable real scheduled Hadaya diamonds** until trustworthy source receipts, anti-forgery restrictions and a safe scheduling mechanism are proven. Workflow `deda-weekly-100405-awards-OWNER-HELD-SCHEDULE.yml` is still approval-gated and on a nondefault branch, so no live automatic payout.
- **No false complete declaration**: production admin permissions and owner binding are real, but five-point end-to-end completion requires an original task award -> verified score on the server -> visible rank from two devices, plus safe live gift distribution. Emulator checks alone cannot substitute for those facts.

### One signed 100405 APK successfully generated and verified

- GitHub Actions **41168456756**: SUCCESS. Full original Flutter tests and final signed APK build passed. Private artifact **13030252749**, file `DEDA-100405-SEVEN-POINTS-OWNER-QA.apk`, exact original package `com.diraq.ludo.d_iraq_ludo` and versionCode **100405**.
- SHA-256: `3c1457117ae0596892e87ef115dc119ebca6d9468ffcfcaf1eb49694ed444f0c`. File verified after extraction, **88,219,434 bytes**. No Play publication.
- Real production admin controls/read-back: **41168397421** success; direct owner account enrollment: **41168627731** success. No explicit evidence of first real client daily task XP-to-score write yet; no live automatic Hadaya settlement enabled. The APK is for **owner device QA**, not a false five-point production acceptance.
