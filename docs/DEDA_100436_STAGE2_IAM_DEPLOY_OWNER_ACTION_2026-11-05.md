# DEDA 100436 — إجراء صلاحيات نشر استرجاع الحساب

## الحالة المثبتة 2026-11-05
- مشروع Firebase: `deda-25b88`.
- حساب خدمة GitHub الحالي (هوية IAM، وليس مفتاحاً سرياً):
  `firebase-adminsdk-fbsvc@deda-25b88.iam.gserviceaccount.com`
- فحص Google Cloud الفعلي: [GitHub Actions 42100821956](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/42100821956).
- `cloudfunctions.functions.create`, `cloudfunctions.functions.update`: YES.
- `cloudbuild.builds.create`: NO.
- `resourcemanager.projects.getIamPolicy`, `resourcemanager.projects.setIamPolicy`: NO. لا يمكن لهذا الحساب رفع صلاحيات نفسه من GitHub.
- `iam.serviceAccounts.actAs`: غير مُثبت على حساب تشغيل Function محدد. اختبار نطاق المشروع أعطى NO، واختبار App Engine الافتراضي HTTP 403؛ لذلك لا تصفه بأنه ممنوع على كل حساب خدمة بدون فحص دقيق.
- حساب خدمة احتياطي في GitHub: غير مهيأ. رمز `FIREBASE_TOKEN`: غير مهيأ.
- قواعد أرشيف الأماكن والإعدادات نُشرت بالفعل وبقيت قائمة؛ لا تُعد نشرها لمجرد تعديل IAM.
- Cloud Functions المطلوبة `dedaVerifyExistingOwnerPin` و `dedaIssueLinkedOriginalUidDeviceGrant` و `dedaRecoveryJournalComplete` غير منشورة حسب جرد v1/v2 لجميع المناطق.
- **ليس مطلوباً إعادة أي عمل من 12 كوداً أو تعديل الرصيد أو فتح ملف الفوترة.**

## إجراء مالك Google Cloud فقط
1. افتح Google Cloud Console واختر المشروع `deda-25b88`. اذهب إلى **IAM & Admin → IAM → Grant access**.
2. أضف الحساب `firebase-adminsdk-fbsvc@deda-25b88.iam.gserviceaccount.com` بدور **Cloud Build Editor** (`roles/cloudbuild.builds.editor`). احتفظ بالأدوار الحالية كما هي؛ لا تستبدل IAM policy بالكامل ولا تمنح Owner/Editor عاماً.
3. في **IAM & Admin → Service Accounts**، حدد حساب تشغيل **Cloud Functions gen2** الفعلي الذي سيُستخدم لهذه الوظائف. من **Permissions → Grant access**، امنح نفس حساب GitHub دور **Service Account User** (`roles/iam.serviceAccountUser`) على حساب التشغيل المحدد فقط. **لا تمنحه على مستوى المشروع كاملاً**.
4. راجع الدورين؛ لا تعطِ مفتاح JSON لأي شخص، ولا ترسل كلمة مرور أو رمز Firebase.

## بعد تطبيق الأذونات
- أعد تشغيل workflow `qa-deda-100436-stage2-live-spark-rules-readonly.yml` على فرع تجهيز 100436: يجب أن تتغير نتيجة Cloud Build إلى TRUE، ويجب التحقق من `actAs` على حساب التشغيل المحدد. إذا ظهر نقص صلاحية إضافية، لا تخمن دوراً واسعاً؛ افحص مورد الخطأ نفسه.
- بعدها فقط: نشر Cloud Functions **الثلاث المستهدفة فقط** مع الخادم مقفلاً افتراضياً، والتحقق من النشر. تجهيز قواعد `deda_recovery_journals` كإضافة محافظة على القواعد الحية، وفحص UID/AppCheck. ثم تفعيل الحارس على بيئة فحص آمنة بعد إثبات بقية مصادر البيانات.
- لا ترفع `fullAccountRestored` و`canPrepareFullRecoveryApk` إلى true، ولا تعلن APK كاملاً قبل نجاح استرجاع جميع المجالات على هاتفين حقيقيين.
- النسخة الأساسية `100436` عند `fea54d7db2e8a24a74267f04a14c9572bcb408ee` ممنوع تعديلها؛ العمل مستمر فقط بالفرع `deda-100436-stage2-recovery-buildable-integration-qa-2026-11-05`.
