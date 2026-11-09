# DEDA — البند 3: تحديد المراجع البرمجية القائمة ونقاط التداخل (قراءة فقط)

**التاريخ:** 2026-11-09 (العراق).  
**تعليمات صاحب المشروع:** «باشر» بعد إنهاء جرد البند 2، مع الالتزام بإيقاف إنشاء أكواد الاسترجاع الجديدة وعدم الانحراف.  
**الحالة:** قرار تنظيم **للمراجعة، وليس تغييراً أو إصلاحاً منشوراً**. لم يبدأ البند 4 (معالجة الفجوات).

## نطاق الفحص وطريقة الحكم

- مستودع: mosubiyi-prog/d-iraq-ludo.
- الفرع المُراجع: deda-100441-step1-legacy-google-proof-gate-isolated-no-deploy-2026-11-09، من نقطة التوقف a8f3750831373db6fb30afecea4e6d852ba18f30.
- مراجعة فعلية للمصادر ومداخل الربط: lib/main.dart، lib/deda_backend.dart، functions/index.js، أكواد UID/Google/PIN والحراس وmanifest/assembly والاسترجاع المالي والأماكن.
- **المرجعية هنا تعني الكود الموجود المسؤول عن الوظيفة حسب تصميمه الحالي، لا أنه مُفعّل في إنتاج Firebase أو مضمون على الجهاز.**
- لا قرار بحذف أو دمج أو تغيير صلاحية أو علامة تشغيل. لا تُخلق «وحدة سابعة» لحل التداخل.

## قرار مرجعية الوظائف، من الموجود فقط

| الوظيفة | المرجع الحالي المعتمد للمراجعة | الملفات الأخرى وعلاقتها |
|---|---|---|
| **انتقالات Firebase Auth داخل التطبيق** | lib/deda_auth_session_runtime.dart + lib/deda_session_transition_gate.dart | lib/deda_owner_session_firebase_port.dart / lib/deda_session_principal_tracker.dart منافذ ومراقبة؛ **لا** حارس Auth ثانٍ. |
| **تطابق UID وسجلات الحساب على الخادم** | functions/deda_100441_canonical_uid_anti_split_preflight_PRIVATE_NOT_EXPORTED.js (دالة inspectCanonicalUid) | functions/deda_100441_server_canonical_uid_read_adapter_PRIVATE_NOT_EXPORTED.js يقرأ Auth/Firestore ويستدعي سياسة المطابقة؛ functions/deda_100441_canonical_uid_preflight_callable_PRIVATE_NOT_EXPORTED.js مغلّف مستقل مع rate limit؛ لا نشر ولا إثبات ملكية في حد ذاتها. |
| **مراجعة ملكية A/B/C المتعارضة** | functions/deda_100441_owner_split_identity_challenge_review_private_v1.js | safeEvidenceAssessment يكرر بعض شروط فحص الانقسام الموجودة بالمرجع السابق، وreviewReadiness يضيف PIN/العامل المستقل/المراجعة والنسخ الاحتياطية. **تداخل منطقي مثبت**؛ يظل المصدر محفوظاً، ويجب عدم اعتبار التقييم المزدوج إذنين مستقلين أو رفع نتيجة HOLD. |
| **حماية هوية صاحب الحساب في واجهة DEDA** | lib/deda_100431_linked_owner_session_policy.dart | lib/deda_qa32_manager_original_owner_proof.dart فحص محدود للآيدي/الإدارة؛ lib/deda_owner18_original_account_proof.dart تعايش للهوية القديمة؛ ليست بدائل مطلقة عن فحص الخادم. |
| **الربط الاختياري لـGoogle بنفس UID المؤكد** | lib/deda_100430_owner_uid_continuity.dart، تحديداً linkGoogleToConfirmedOriginalUid | lib/deda_step1_google_settings_link_100439.dart واجهة الإعدادات فقط؛ يجب أن تكون هوية صاحب الحساب مؤكدة **قبل** linkWithCredential. |
| **تسجيل الدخول بحساب Google مرتبط مسبقاً بالـUID القديم** | lib/deda_step2_google_replacement_login_100439.dart | existingIdpRequest يضع autoCreate:false ويرفض isNewUser، ثم يتحقق من UID والسجلات. هذا المسار **غير صالح للحساب الحالي A/B/C** ما لم يثبت تاريخ الربط فعلاً، ولا يجوز فتح علاماته لمجرد نجاح المختبر. |
| **Google جديد لم يكن مربوطاً بالحساب القديم** | functions/deda_100441_legacy_google_oidc_verifier_PRIVATE_NOT_EXPORTED.js (مرشح تحقق OIDC معزول) | functions/deda_100441_lab_to_legacy_google_proof_gate_PRIVATE_NOT_EXPORTED.js طبقة تصنيف ومراجعة تعتمد على حارس A/B/C ولا تصدر صلاحية؛ OIDC نجح بمفاتيح اصطناعية في CI وليس endpoint إنتاجياً. **لا يعتبر Google الجديد دليل ملكية UID القديم وحده.** |
| **حساب Google للمستخدم الجديد كلياً** | functions/deda_100441_stage7_google_uid_root_reservation_PRIVATE_NOT_EXPORTED.js، ثم functions/deda_100441_new_owner_google_enrollment_PRIVATE_NOT_EXPORTED.js كمرشحين بمهام مختلفة | منع خلط إنشاء المستخدم الجديد بحساب DEDA القديم A/B/C. الكودان غير منشورين؛ أحدهما حجز Google مؤقت والآخر تسجيل مزوّد عند توفر إثبات مستقل للرقم والحساب الجديد. |
| **الرقم والرمز القديم** | lib/deda_pin_auth.dart للتوافق التاريخي؛ functions/deda_owner_pin_verify_private_v1.js كمرشح إثبات خادمي مقيد | PIN وحده ليس إثبات ملكية UID. functions/deda_pin_manual_recovery_compat_private_v1.js مزامنة/تدوير رمز منفصلة. functions/deda_pin_auto_recovery_worker.js / policy + functions/deda_linked_pin_reissue.js لإعادة الإصدار عند نسيان الرمز، ليست بدائل عن إثبات الهوية. |
| **ترتيب استرجاع الممتلكات** | lib/deda_step2_recovery_guardian.dart: DedaVaultManifest الذي يحصي **12 كوداً مؤرشفاً** | lib/deda_step2_linked_owner_guardian_assembly.dart يحقن **4 adapters** حالياً (original backup / purchase backup / level points / published place). lib/deda_step2_linked_owner_guardian_bridge.dart ينسّق الدخول والقراءة. ليس هناك 12 عملية استرجاع منفّذة بمجرد وجود manifest. |
| **إنقاذ قراءة جلسة قديمة دون استرجاع الممتلكات** | lib/deda_session_recovery_coordinator.dart | lib/deda_session_rescue_stage3_core.dart / stage3_bridge واجهة تنسيق وإعادة محاولة؛ هذه وظيفة **جلسة**، ولا تغني عن حارس الممتلكات ذي 12 كوداً. |
| **أرشفة/قراءة تقدم الحساب والمشتريات والماسّات** | lib/deda_step2_original_backup_readback.dart، purchase_backup_readback.dart، assets_readback.dart، diamond_reconciliation_readonly.dart | لكل ملف نطاق دليل مختلف. lib/deda_step2_financial_source_audit.dart وlegacy_ad_wallet_audit.dart يحللان أدلة محلية غير موثقة، وليس من حقهما إعادة صرف الماسّات أو الجوائز. لا دمج مالي على أساس تقارب الاسم. |
| **الأماكن والإعدادات والأصدقاء** | lib/deda_step2_linked_published_place_recovery.dart؛ ملفات owner_place_local_archive / global_places_settings_archive / restore للأدلة المحلية؛ lib/deda_social_service.dart للخدمة الاجتماعية | المنشور على الخادم مختلف عن أرشيف جهاز قديم؛ لا توحيد ملكيات الأماكن بمجرد تطابق الاسم. |
| **سجل الاسترجاع وإثبات الاكتمال** | lib/deda_step2_recovery_journal_firestore.dart (نقل الحالة) + functions/deda_recovery_journal_completion_private_v1.js (مراجعة خادمية) | lib/deda_step2_completion_gate.dart يعرض حالات الأدلة؛ تقرير «مكتمل» لا يعادل نجاح Auth وعودة جميع الممتلكات. |
| **فتح واجهة لدي حساب** | lib/deda_step2_existing_account_signin_page.dart ومعها lib/main.dart | الاستدعاء في main.dart يمر بـ DedaLinkedOwnerGuardianAssembly.prepare، ويتوقف إذا لم تُفعّل شروط عدة؛ وجود زر الواجهة أو استيراد الصفحة لا يثبت جاهزية الاسترجاع. |

## التداخل الحقيقي الذي يُمنع تضخيمه

1. **فحص الانقسام نفسه** موزّع بين: inspectCanonicalUid على الخادم، safeEvidenceAssessment في حارس مراجعة A/B/C، ownerDocumentsMatch في سياسة Flutter. هذه **ثلاث طبقات فحص بمتطلبات مختلفة**، لكن تشابهها قد يسبب تناقض تعريف «مطابق». قرار البند 3: المعاينة الأصلية للـUID على الخادم مرجعها inspectCanonicalUid؛ حارس الملكية مسؤول عن إثبات الملكية، وFlutter مسؤول عن منع الانتقال إلى جلسة خاطئة. **لا حذف ولا دمج الآن.**
2. **Google** فيه مرحلتان منفصلتان: إثبات مزوّد Google، وإثبات ملكية الحساب التاريخي. بوابة المختبر/Google الأخيرة تعيد فحص بعض شروط حارس A/B/C. لا يحق لها تحويل نجاح المختبر إلى UID للإنتاج أو اعتباره إذن دخول. الاحتفاظ بالملفات لا يعني اعتماد تكرار التصنيف بوصفه تصميمًا نهائيًا.
3. **حارسان باسم إنقاذ/استرجاع**: DedaSessionRecoveryCoordinator للجلسة، وDedaStep2RecoveryGuardian للأدلة والممتلكات. **ليسا نسختين متطابقتين**؛ يجب تثبيت مسؤولية كل واحد.
4. **PIN**: تحقق الملكية، تغيير/تدوير الرمز، واسترجاع الرمز المنسي مهام متباينة. توحيدها بكود واحد قد يكسر الحماية.
5. **منظومة الـ12 كود**: DedaVaultManifest يحفظ 12 وظيفة، لكن التجميع الحالي يستدعي أربعة adapters فقط. بقية العناصر ليست مفعّلة لمجرد وجودها في الـmanifest. هذا **نقص ربط مثبت بالمصدر**، وليس دليلاً بأن الحساب القديم استُرجع.
6. **حالة تفعيل الإنتاج**: بعض الوظائف مُصدّرة في functions/index.js لكنها محكومة بـ deda_stage2_live_gate.js؛ كود مستورد ليس دليلاً أن cloud deployment الحالي فعّلها. بعض وحدات 100441 PRIVATE_NOT_EXPORTED غير موصولة تماماً بمدخل Functions. أعلام Flutter الافتراضية لربط Google/الحارس/الدخول القديم false. لا تخلط CI SUCCESS مع تشغيل حي.
7. **لا يوجد في المصادر التي روجعت حل منشور موثّق يثبت من مالك UID A/B/C**. خيار A لأنه مالك الآيدي أو B لأنه منشئ الرقم أو C لوجود جلسة تاريخية يبقى غير مفوض. هذه **العقبة الحقيقية الأساسية** قبل نقل حساب أو ربط Google.

## قرار البند 3 — بلا أي تعديل برمجي

- اعتمد **المراجع الموجودة** أعلاه للمراجعات اللاحقة؛ أي كود جديد ممنوع ضمن قرار صاحب المشروع البند 1.
- احفظ الملفات الأخرى كما هي، واعتبر التداخل مرشحاً لإعادة استعمال كود موجود مستقبلاً فقط بعد موافقة منفصلة واختبار توافق. لا تسمِّ حذف كود «تنظيفاً» قبل إثبات عدم استخدامه.
- لا تُفعّل رايات موجودة على الإنتاج لتجاوز نقص إثبات الملكية، ولا تجرّب Google على UID قديم متعارض، ولا تُعدّل حقوق الإدارة أو الماسّات.
- الخطوة التالية عند أمر صاحب المشروع (البند 4): **تحديد فجوة تنفيذية واحدة مثبتة، وتقديم أقل إصلاح قابل للفحص مع خطة تراجع وموافقة**؛ لا إضافات حراس أو إعادة كتابة منظومة الاسترجاع.
- **الحالة:** البند 3 (قرار المرجعية والتداخل) مكتمل كمراجعة مصدر؛ إصلاح استرجاع الحساب على الهاتف غير مكتمل.

## حدود التحقق

هذا التدقيق مقصور على فروع المصدر وسلاسل الاستدعاء التي فُحصت. لم يراجع حالة نشر Cloud Functions الفعلية داخل Firebase أو يصلح قاعدة البيانات، ولم يشغّل فحص أجهزة جديداً. لا يجوز استخدامه كإثبات أن جميع الأكواد خالية من التعارضات؛ ولا يجوز استخدامه كإذن لتغيير الحساب.

**تغيير هذه المهمة:** إضافة هذه الوثيقة فقط، دون إنشاء أو تعديل أي ملفات .dart/.js أو CI، وبدون Firebase deploy أو build أو Google Play.
