// Completely separate Android application com.deda.qa.uiddevice.
// No DEDA production imports, Firestore, phone, PIN, wallet or admin access.
// This pilot is NOT wired into the real DEDA app. Config MUST pass lab_guard.
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'lab_guard.dart';

void main() => runApp(const DedaUidQaLab());

class DedaUidQaLab extends StatefulWidget {
  const DedaUidQaLab({super.key});
  @override
  State<DedaUidQaLab> createState() => _DedaUidQaLabState();
}

class _DedaUidQaLabState extends State<DedaUidQaLab> {
  static const config = LabQaConfig.compiled;
  static const firebaseAppName = 'deda-uid-lab-qa-only';
  bool busy = false;
  bool initialized = false;
  String status = 'QA_IDLE_NO_AUTH';
  String? fingerprint;

  GoogleSignIn googleClient() => GoogleSignIn(
        scopes: const <String>['email'],
        serverClientId: config.googleWebClientId,
      );

  Future<void> signInTestGoogle() async {
    if (busy || !config.isAllowed) return;
    setState(() {
      busy = true;
      status = 'QA_SIGN_IN_REQUESTED';
    });
    try {
      if (!initialized) {
        final app = await Firebase.initializeApp(
          name: firebaseAppName,
          options: FirebaseOptions(
            apiKey: config.apiKey,
            appId: config.firebaseAppId,
            messagingSenderId: config.messagingSenderId,
            projectId: config.projectId,
          ),
        );
        if (app.options.projectId != config.projectId ||
            app.options.projectId == LabQaConfig.productionProjectId) {
          throw StateError('QA_FIREBASE_PROJECT_MISMATCH');
        }
        initialized = true;
      }
      // Never use FirebaseAuth.instance (default app may be production).
      final qaApp = Firebase.app(firebaseAppName);
      if (qaApp.options.projectId != config.projectId) {
        throw StateError('QA_FIREBASE_PROJECT_MISMATCH');
      }
      final auth = FirebaseAuth.instanceFor(app: qaApp);
      final google = googleClient();
      // Clear only this QA app's Google selection to expose chooser.
      await google.signOut();
      final selected = await google.signIn();
      if (selected == null) {
        if (mounted) setState(() => status = 'GOOGLE_CHOOSER_CANCELLED');
        return;
      }
      final tokens = await selected.authentication;
      if ((tokens.idToken ?? '').isEmpty) {
        throw StateError('QA_GOOGLE_ID_TOKEN_ABSENT');
      }
      final credential = GoogleAuthProvider.credential(
        idToken: tokens.idToken,
        accessToken: tokens.accessToken,
      );
      final signed = await auth.signInWithCredential(credential);
      final user = signed.user;
      if (user == null || user.uid.isEmpty || user.isAnonymous ||
          !user.providerData.any((p) => p.providerId == 'google.com') ||
          qaApp.options.projectId != config.projectId) {
        throw StateError('QA_GOOGLE_UID_UNVERIFIED');
      }
      if (mounted) {
        setState(() {
          fingerprint = LabUidFingerprint.fromUid(user.uid);
          status = 'QA_GOOGLE_UID_VERIFIED_NO_DEDA_ACCOUNT_CREATED';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          fingerprint = null;
          status = 'QA_SIGN_IN_DENIED_CHECK_LOCAL_CONFIG';
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> signOutTestOnly() async {
    if (busy || !config.isAllowed || !initialized) return;
    setState(() => busy = true);
    try {
      final qaApp = Firebase.app(firebaseAppName);
      if (qaApp.options.projectId != config.projectId) {
        throw StateError('QA_PROJECT_MISMATCH');
      }
      await FirebaseAuth.instanceFor(app: qaApp).signOut();
      await googleClient().signOut();
      if (mounted) {
        setState(() {
          fingerprint = null;
          status = 'QA_ONLY_SIGNED_OUT';
        });
      }
    } catch (_) {
      if (mounted) setState(() => status = 'QA_SIGN_OUT_DENIED');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: true,
        title: 'DEDA UID QA LAB — NOT DEDA',
        home: Scaffold(
          appBar: AppBar(title: const Text('مختبر UID — ليس تطبيق ديدا')),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(22),
                  children: [
                    const Icon(Icons.science_outlined, size: 60),
                    const SizedBox(height: 12),
                    const Text(
                      'تطبيق اختبار مستقل. ما بيه رقم هاتف أو رمز PIN أو '
                      'ماسات أو هدايا أو صلاحيات إدارة.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 14),
                    Text('الحماية: ${config.denial}',
                        key: const ValueKey('qa-guard')),
                    Text('الحالة: ${status}',
                        key: const ValueKey('qa-status')),
                    if (fingerprint != null) ...[
                      const SizedBox(height: 16),
                      SelectableText(
                        'بصمة UID للاختبار: ${fingerprint!}',
                        key: const ValueKey('qa-uid-fingerprint'),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: !busy && config.isAllowed
                          ? signInTestGoogle
                          : null,
                      icon: const Icon(Icons.login),
                      label: const Text('اختيار حساب Google للاختبار'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: !busy && initialized && config.isAllowed
                          ? signOutTestOnly
                          : null,
                      child: const Text('خروج من المختبر فقط'),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'اختر نفس حساب Google التجريبي على الجهازين وقارن بصمة '
                      'UID. اختيار حساب مختلف لازم يعطي بصمة مختلفة. '
                      'هذا لا يثبت ملكية أي رقم هاتف.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'لا تسجّل خروجاً من DEDA الحقيقية. التطبيق الاختباري '
                      'له حزمة مختلفة ولا يقرأ بيانات حسابك الأصلي.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}
