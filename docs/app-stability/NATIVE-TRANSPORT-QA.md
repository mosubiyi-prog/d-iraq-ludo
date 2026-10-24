# Native transport validation — Android 16, local demo only

24 October 2026 Baghdad. This is a separate disposable application under `dev.deda.qa.deda_transport_qa`, not a rebuilt DEDA APK or a replacement application. Its debug binary stays in the CI runner and is not uploaded. DEDA Android/signing/main/Firebase production configuration are never copied to this harness.

## Latest approved result — 22/22 native cases

[Native run 40091083991](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/40091083991) passed on source `6191447d38af7e0ff8051536620533bfa94511b1`, job 120863721226. Eighteen cases completed before force-stop and four after relaunch. The original twelve remain, plus ten real runtime/root cases. Android Home/return preserved PID **3234→3234**; force-stop/relaunch changed it **3234→4114** while preserving default/named Auth identities, native preferences and the two separate pending journals. A fresh runtime recovered account B using its original capture ID/provenance and then skipped an unchanged resubmission. The actual production host constructor/default Firebase factory also archived successfully in this isolated app.

Artifact 12558714509 was downloaded and ZIP SHA256 `ba3b29840ac657f2803499ecd84798e653d89cd62098ebc22d376f927ce67418` verified. It contains only fifteen log/result/manifest/hash files, no APK/AAB/keystore/Firebase configuration. All eight module hashes plus harness main and candidate rules match the tested source. All sixteen pinned transport packages match the immutable baseline; native analysis is clean and filtered process logs contain no unhandled runtime/plugin error. The exact verified report is NATIVE-TRANSPORT-RESULTS-2026-10-24.json.

[Source regression 40091083983](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/40091083983), attempt 2, passed all four jobs: Python52, Node78, standalone emulator74 and measured groups 38/30/32/13/21/36/35/43/27/40/29. Ten selected strict analyses were clean; inherited main issues remain 181. Attempt 1 had one concurrent-wrapper emulator rejection (`INVALID_ARGUMENT: Transaction is invalid or closed`); the SAME code and assertions passed the rerun, without adding retries or weakening checks. Its underlying cause was not proven.

The post-read hold used for Android background testing has a five-second fixture UI timeout, which can also expire during Home/return. This proves safe behavior across the combined lifecycle/timeout boundary; it does not isolate those causes or interrupt an in-flight network packet. Isolated lifecycle invalidation remains covered by the 32-case controller/widget suite. The native harness is still not full DEDA UI, actual DEDA PIN, a financial restore, sudden power loss or two physical phones. Production remains unchanged and the app pilot defaults to false.

## Test boundary

The harness copies eight actual source modules with SHA256 fingerprints and pins the Firebase/Auth/Firestore/SharedPreferences package families to the immutable 100380 lockfile versions. It uses actual Android plugins, an Android API 36 emulator and localhost Auth + Firestore demo emulators. The privileged local fixture service seeds session/users records for anonymous SDK users; **DEDA PIN login, credential verification and production rules are NOT being tested**.

The candidate rules had a compatibility gap: the new Dart owner check reads users/<uid>, while the isolated rules did not allow even a self get. An explicit self-get-only rule now permits the actual native proof read; cross-UID get, list, writes and unauthenticated reads remain denied and have additional emulator tests. This is not a finding about the deployed production rules and no rules are deployed.

## Original twelve native cases — retained in the expanded suite

1. Server proof plus exact raw text capture/save/readback using actual plugins.
2. Idempotent replay preserves original server timestamp.
3. A changed payload conflicts without overwriting the original local data.
4. Actual SDK denial for private cross-account/user reads and client user writes.
5. Missing users proof rejects before journal creation.
6. SDK disableNetwork preserves pending intent; enableNetwork permits later recovery.
7. A deliberate thrown lost acknowledgement AFTER a real native transaction is resolved by read-before-resend, with exactly one write dispatch.
8. A second emulated UID/install of the same seeded account reads old provenance/history.
9. A new UID cannot relabel an old-origin request absent from the server.
10. Prepare a pending native journal and checkpoint before process termination.
11. After host am force-stop and relaunch of the SAME installed binary, native preferences and journal survive.
12. Native Firebase Auth UID persists and the pending request uploads with original provenance after restart.

The original suite required ten first-phase and twelve final cases; the expanded verified suite now requires eighteen before force-stop and twenty-two final cases. The host requires two DISTINCT native process IDs and no reported failure. No uninstall/data clear/mock preferences occurs between the two processes. The complete Android logcat and per-process filtered logcat are retained; unhandled Flutter/plugin/runtime failures fail the job. This is a process-stop persistence check, not sudden power-loss or physical two-phone validation. New UID/install is simulated sequentially on one emulator, not two physical devices.

## Isolation and validation

Demo project ID and explicit emulator endpoints are hardcoded; no real Firebase config, service-account key, app production signature, billing or deployment command is used. The host fixture refuses non-local emulator environment variables or GOOGLE_APPLICATION_CREDENTIALS. Only its privileged test fixture seeds users/session state. The app exercises real SDK methods for evidence and journal operations. Existing source/rules tests remain separate and active.

The original seven offline boundary checks covered required harness identity, refusal to target the repository, absent flutter-create marker, production app/config rejection, refusal to overwrite prepared work, pinned-version drift, and the Firebase config rules staying inside the demo project root. That first version had 24 local checks. The current suite has 52, including restoration/endpoint/merge/runtime boundaries and the Android background protocol guard. Creating a workflow or debug APK alone is never success.

The candidate/current published policy comparison later passed 93 local-emulator cases, and the first passive root binding is now tested below. Remaining work includes native DEDA PIN and complete auth integration, old-origin pending review where the server record is missing, coherent producer snapshots, verified baseline/event cutover, nonfinancial migration, and actual DEDA acceptance across phones. No balances are interpreted or restored by these tests.

Reference APIs: https://firebase.google.com/docs/emulator-suite/connect_auth and https://docs.flutter.dev/testing/integration-tests . The controlled cold-restart harness uses explicit host lifecycle control instead of a mocked plugin binding.


## First native run — infrastructure failure before application cases

Run 40041219643, source 95016c6bacdb05fedac3afd1c78324e772cdb1fb, built the isolated debug APK and booted Android API 36 successfully, but Firebase CLI rejected `../progress_archive/firestore.rules` as outside its config project directory before running the application cases. No native case passed or failed in that run. The correction copies the exact candidate rules and a local-path config into a disposable demo directory, with the rules SHA256 recorded. The harness Dart/modules/plugin versions are unchanged. SDK download caching is enabled for the pinned Flutter distribution only; no test APK is cached or uploaded.

The source/rules regression run 40041219729 passed all four jobs: 78 Node and 74 emulator cases, and the earlier Dart groups. Artifact 12539463536 from the failed native run contains build/analysis/version/source evidence only; digest ad9f9aef2fb9a7d2e75163fec5357b9781435e1ad36931162b4ca46408caebb7. It is not proof of actual native transport. Native verification is still pending the corrected run.


## Second native run — default SDK bootstrap missing in standalone harness

Run 40042336988, source 7e163777a1dc221a527da1627d31e05c767f091b, started both local emulators and the actual Android application, but its bootstrap failed before any case: cloud_firestore_platform_interface's instanceFor path initializes its platform singleton via Firebase.app(), so a DEFAULT app is required even when named clients are used. The harness initially created named demo clients only. Actual DEDA main already initializes the default Firebase app.

The correction initializes a DEFAULT demo app and explicitly points its Auth/Firestore instances to the SAME localhost demo emulators before creating named clients. No production Firebase config is introduced; the seven application modules and native package versions are unchanged. The failed result recorded passed=[], phase=1. Artifact 12540361115, digest fb486824b8ffd6268bb322229b0a2e964db7a7e909e9c7411183348909e9ab7b, preserves the exact bootstrap stack and native logs. It is not a pass of any of the twelve data cases.


## نتيجة أصلية سابقة معتمدة — 12 حالة قبل توسيع فحص الربط

المصدر `59720a61a55042d31cc93ce22812a28ee07f20b5`؛ تشغيل النقل [40043426916](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/40043426916) ناجح، وتشغيل المصدر [40043426967](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/40043426967) ناجح في الأوضاع الثلاثة ومهمة المحاكي. اجتازت **12/12 حالة أصلية**: 10 قبل إيقاف العملية و2 بعد إعادة فتح نفس الحزمة دون إزالة/مسح البيانات. PID الأول 3078 والثاني 3766؛ حفظ UID الخاص بـFirebase Auth وjournal والنصوص المحلية، واستكمال طلب معلق من عملية جديدة، كلها مؤكدة من التقرير. نجحت أيضاً حالات الاستجابة المفقودة المحقونة بعد معاملة native فعلية، offline/online عبر SDK، UID/install جديد لنفس الحساب المزروع، وقواعد المنع. هذا ليس PIN ديدا حقيقياً أو هاتفين فعليين أو ترحيلاً مالياً.

أثر النتائج `12540587647`، SHA256 للأرشيف `62aeb50ade4fe4cf5a2dd08ff526e35bd1cb33c2528987c98219e345b548a51a`. نُزل وتحقق من بصمته، ومن غياب APK/AAB/keystore داخله، ومن تطابق بصمات الـmodules السبعة وmain الخاص بالاختبار والقواعد مع المصدر. بقيت إصدارات حزم النقل الـ16 مطابقة للمرجع. التقرير الأحدث NATIVE-TRANSPORT-RESULTS-2026-10-24.json أصبح 22 حالة؛ نسخة 12 الأصلية محفوظة بسجل git. لا يُخلط main الاختبار مع main تطبيق ديدا.

نجحت فحوص الاستعادة/حدود harness **24/24**، وNode **78/78**، ومحاكي القواعد **74/74**، وبقيت مجموعات Dart السابقة ناجحة (38/30/13/21/36/35/43/27/40/29 بحسب مواضعها). التحليل الصارم للـmodules وحزمة الاختبار بلا ملاحظات؛ بقيت 181 ملاحظة/تحذيراً قديمة في main المرجعي. تم إنشاء debug APK مؤقت بحزمة dev.deda.qa.deda_transport_qa وتوقيع اختبار runner فقط؛ لم يُرفع أو يُنشر ولم يتغير Android أو توقيع التطبيق الأصلي أو main/Backend/PinAuth أو قواعد الإنتاج.

هذه نتيجة نقل وتخزين فعلية للمكونات المعزولة. لا يعلن اكتمال حفظ تقدم مستخدمي ديدا أو جاهزية تحديث رسمي؛ ربط حساب ديدا الحقيقي، ومطابقة القواعد المنشورة، واعتماد التقدم القديم والأحداث، وحفظ غير المالي، والإدارة والأقسام وفحص هاتفين والنسخة الموقعة باقية. CURRENT أعيد تنظيمه ليعرض الحالة الأحدث أولاً؛ التاريخ والحدود السابقة محفوظة هنا وفي NATIVE-TRANSPORT-QA.md وسجل git.


## Verified follow-up: passive runtime/root on the same native plugins

The harness passed 22 cases (the original 12 plus 10 runtime/root cases). It copies the unchanged real runtime module as the eighth transport module and opts in ONLY in the disposable debug build. New cases cover root selection/default driver, unchanged suppression after owner proof, changed raw text, A→B→A after a completed native server read, real Android Home/resume while that read result is held, offline pending recovery, the production host constructor/default Firebase factory and default Auth/pending account-B recovery across force-stop. The held-read seam pauses AFTER a real server read; it does not interrupt a network packet.

The host presses Home, waits for the actual root pause/hidden lifecycle callback reported by the app, and relaunches the same process. It requires equal PIDs across this background cycle. It then force-stops/relaunches the same installed APK/data and requires different PIDs. Account-B has a separate journal from the retained original account-A restart cases. Fixture install markers are changed explicitly for these tests; this is one emulator, not two physical phones. Sessions/users remain local privileged fixtures; no real DEDA PIN/native sign-in UI is claimed.

Offline boundaries now pass 52 Python checks. New shell/Node syntax checks pass. The 22-case result and downloaded artifact have been verified as detailed at the top of this document. No production runtime, Firebase rule, account, official signing or APK-delivery workflow changes here.
