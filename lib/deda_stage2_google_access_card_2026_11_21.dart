import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'deda_stable_google_login_2026_11_21.dart';
export 'deda_stable_google_login_2026_11_21.dart'
    show dedaStableGoogleLoginEnabled;

/// Place above the EXISTING Settings sign-out control only in explicit QA.
/// No management role or legacy A/B/C property is ever assigned here.
class DedaStage2GoogleAccessCard extends StatefulWidget {
  const DedaStage2GoogleAccessCard({super.key});

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
