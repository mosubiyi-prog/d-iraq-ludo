import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Staged account recovery UI. OFF, not linked from main.dart, no implicit
/// Auth/Firestore request. A verified server-backed login delegate is required
/// before the button can ever submit phone+PIN.
const bool dedaStep2ExistingAccountEntryEnabled = bool.fromEnvironment(
  'DEDA_STEP2_EXISTING_ACCOUNT_ENTRY', defaultValue: false);

typedef DedaVerifiedExistingAccountLogin = Future<void> Function(
  String phone,
  String pin,
);

class DedaExistingAccountSignInPage extends StatefulWidget {
  const DedaExistingAccountSignInPage({
    super.key,
    this.verifiedLogin,
    this.enabled = dedaStep2ExistingAccountEntryEnabled,
  });

  /// This callback must verify the original UID and server authorization,
  /// resolve original ID securely and commit the canonical recovered profile.
  /// It is NOT installed by the 100436 development candidate.
  final DedaVerifiedExistingAccountLogin? verifiedLogin;
  final bool enabled;

  @override
  State<DedaExistingAccountSignInPage> createState() =>
      _DedaExistingAccountSignInPageState();
}

class _DedaExistingAccountSignInPageState
    extends State<DedaExistingAccountSignInPage> {
  final _phone = TextEditingController();
  final _pin = TextEditingController();
  bool _busy = false;
  bool _explicitRecoveryConsent = false;
  String? _error;

  bool get _valid =>
      RegExp(r'^07\d{9}$').hasMatch(_phone.text.trim()) &&
      RegExp(r'^\d{6}$').hasMatch(_pin.text) &&
      !_busy && _explicitRecoveryConsent &&
      widget.enabled && widget.verifiedLogin != null;

  Future<void> _submit() async {
    if (!_valid) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Never log or save the PIN; a verified server path owns the action.
      await widget.verifiedLogin!(_phone.text.trim(), _pin.text);
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'تعذر التحقق من الحساب. لم تُغيّر بياناتك.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _phone.dispose();
    _pin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('لدي حساب')),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(20),
            children: [
              const Text('تسجيل الدخول بحسابك السابق',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
              const SizedBox(height: 18),
              TextField(
                controller: _phone,
                onChanged: (_) => setState(() {}),
                keyboardType: TextInputType.phone,
                textDirection: TextDirection.ltr,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(11),
                ],
                decoration: const InputDecoration(
                  labelText: 'رقم الهاتف',
                  hintText: '07XXXXXXXXX',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _pin,
                onChanged: (_) => setState(() {}),
                obscureText: true,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                decoration: const InputDecoration(
                  labelText: 'الرمز السري (6 أرقام)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              CheckboxListTile(
                value: _explicitRecoveryConsent,
                onChanged: _busy || !widget.enabled
                    ? null
                    : (value) => setState(
                        () => _explicitRecoveryConsent = value == true),
                title: const Text('أطلب استرجاع حسابي السابق وبياناته'),
                subtitle: const Text(
                  'لا يتم نقل أو تصفير أي بيانات قبل التحقق من مصدرها '
                  'على الخادم. احتفظ بالهاتف القديم لحين نجاح الفحص.'),
                controlAffinity: ListTileControlAffinity.leading,
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _valid ? _submit : null,
                child: Text(_busy ? 'جارٍ فحص الاسترجاع...' :
                    'التحقق واسترجاع حسابي'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, textAlign: TextAlign.center),
              ],
              if (!widget.enabled || widget.verifiedLogin == null) ...[
                const SizedBox(height: 12),
                const Text(
                  'الدخول بالحساب السابق غير مفعّل في هذه النسخة.',
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
