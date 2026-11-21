import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'deda_stable_google_login_2026_11_21.dart';
export 'deda_stable_google_login_2026_11_21.dart'
    show dedaStableGoogleLoginEnabled, DedaStableGoogleLogin;

/// Place above the EXISTING Settings sign-out control only in explicit QA.
/// No management role or legacy A/B/C property is ever assigned here.
class DedaStage2GoogleAccessCard extends StatefulWidget {
  const DedaStage2GoogleAccessCard({
    super.key,
    required this.onFreshGoogleIdentity,
  });

  /// The caller must quarantine the legacy live DEDA account and routes.
  final Future<void> Function(String uid) onFreshGoogleIdentity;

  @override
  State<DedaStage2GoogleAccessCard> createState() =>
      _DedaStage2GoogleAccessCardState();
}

class _DedaStage2GoogleAccessCardState extends State<DedaStage2GoogleAccessCard> {
  bool _busy = false;
  bool _consentToNewUid = false;
  String? _result;

  Future<void> _connect() async {
    if (_busy) return;
    setState(() { _busy = true; _result = null; });
    try {
      final result = await DedaStableGoogleLogin().signIn(
        explicitAnonymousReplacement: _consentToNewUid,
      );
      if (!result.cancelled && !result.reused && result.uid != null) {
        await widget.onFreshGoogleIdentity(result.uid!);
        return;
      }
      if (!mounted) return;
      setState(() => _result = result.cancelled
          ? 'تم إلغاء اختيار Google دون تغيير جلسة Firebase.'
          : result.reused
              ? 'حساب Google الحالي ثابت. لم تتغير هوية Firebase.'
              : 'تمت مصادقة Google على UID جديد/ثابت. '
                'حساب DEDA القديم وممتلكاته والإدارة لم تُربط تلقائياً. '
                'يلزم إكمال تهيئة حساب DEDA الجديد.');
    } catch (_) {
      if (mounted) {
        setState(() => _result =
            'تعذّر توثيق Google بأمان. لم يُسمح بمنح صلاحيات أو نقل بيانات.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!dedaStableGoogleLoginEnabled) return const SizedBox.shrink();
    final user = Firebase.apps.isEmpty ? null : FirebaseAuth.instance.currentUser;
    final isAnonymous = user != null && user.isAnonymous;
    final hasGoogle = user != null && !user.isAnonymous &&
        user.providerData.any((p) => p.providerId == 'google.com');
    // Consent is required even when Auth is empty: a local DEDA login can
    // still be remembered on this device and must not be fenced off silently.
    final canStart = hasGoogle ||
        ((user == null || isAnonymous) && _consentToNewUid);
    return Card(
      key: const ValueKey('deda-stage2-google-identity-card'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('هوية Google الثابتة',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(hasGoogle
                ? 'الجلسة الحالية تستخدم Google. لا يتطلب الأمر إنشاء UID آخر.'
                : 'تسجيل دخول Google اختيار مستقل، ولا يسترجع سجلات A/B/C '
                  'ولا يمنح صلاحيات الإدارة تلقائياً.'),
            if (isAnonymous || user == null)
              CheckboxListTile(
                value: _consentToNewUid,
                onChanged: _busy
                    ? null : (value) =>
                        setState(() => _consentToNewUid = value == true),
                title: const Text('أوافق على بدء/استبدال جلسة Firebase بحساب Google ثابت. '
                  'قد يتوقف اعتماد تسجيل DEDA المحلي القديم على هذا الجهاز، '
                  'ولا تنتقل أرصدته وممتلكاته تلقائياً.'),
              ),
            if (user != null && !isAnonymous && !hasGoogle)
              const Text('توجد جلسة موثوقة غير Google. لن نستبدلها من هنا.'),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: !_busy && canStart ? _connect : null,
              icon: const Icon(Icons.verified_user_outlined),
              label: Text(_busy ? 'جارٍ التحقق...' :
                  hasGoogle ? 'فحص هوية Google الحالية' : 'الدخول عبر Google'),
            ),
            if (_result != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(_result!, textAlign: TextAlign.start),
              ),
          ],
        ),
      ),
    );
  }
}

/// A fresh Google principal is NOT a DEDA phone/profile or an administrator.
/// No map ownership, wallet, ID, or legacy data may be shown until a separate
/// server-authorized DEDA enrollment has been implemented and verified.
class DedaStage2GooglePendingPage extends StatefulWidget {
  const DedaStage2GooglePendingPage({
    super.key,
    required this.expectedUid,
    required this.loginPageBuilder,
    this.onSignedOut,
  });

  final String expectedUid;
  final WidgetBuilder loginPageBuilder;
  final VoidCallback? onSignedOut;

  @override
  State<DedaStage2GooglePendingPage> createState() =>
      _DedaStage2GooglePendingPageState();
}

class _DedaStage2GooglePendingPageState
    extends State<DedaStage2GooglePendingPage> {
  bool _busy = false;
  String? _error;

  Future<void> _returnToLogin() async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      // Only the user's explicit button may sign out this pending Google UID.
      // It never calls the admin Auth client, DEDA PIN, or legacy owner logout.
      final pending = await DedaStableGoogleLogin.pendingGoogleUid();
      final active = FirebaseAuth.instance.currentUser;
      if (pending != widget.expectedUid ||
          active == null || active.uid != widget.expectedUid) {
        throw StateError('deda-stage2-pending-google-identity-changed');
      }
      await FirebaseAuth.instance.signOut();
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.remove(DedaStableGoogleLogin.verifiedUidKey)) {
        throw StateError('deda-stage2-pending-google-marker-not-cleared');
      }
      widget.onSignedOut?.call();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: widget.loginPageBuilder),
        (_) => false,
      );
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'تعذر الخروج بأمان. لم يتم فتح بيانات حساب DEDA القديم.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('هوية Google قيد التهيئة'),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.verified_user_outlined, size: 64),
                const SizedBox(height: 16),
                const Text(
                  'تم التحقق من Google. حساب DEDA الجديد لم يكتمل بعد.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                const Text(
                  'لا يمكن عرض آيدي أو رصيد أو إدارة أو أماكن حساب DEDA '
                  'القديم تحت هذه الهوية. لم نحذف بيانات الحساب القديم.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                if (_error != null)
                  Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: _busy ? null : _returnToLogin,
                  icon: const Icon(Icons.logout),
                  label: Text(_busy
                      ? 'جارٍ تسجيل الخروج...'
                      : 'تسجيل خروج Google والعودة لتسجيل الدخول'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
