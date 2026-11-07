import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'deda_google_recovery_progress_100439.dart';

/// Staged account recovery UI. OFF, not linked from main.dart, no implicit
/// Auth/Firestore request. A verified server-backed login delegate is required
/// before the button can ever submit phone+PIN.
const bool dedaStep2ExistingAccountEntryEnabled = bool.fromEnvironment(
  'DEDA_STEP2_EXISTING_ACCOUNT_ENTRY', defaultValue: false);

typedef DedaVerifiedExistingAccountLogin = Future<void> Function(
  String phone,
  String pin,
);

// This callback only proves existing Google/DEDA identity. A true result
// MUST NOT be interpreted as permission to hydrate financial account data.
typedef DedaVerifiedExistingGoogleLogin =
    Future<DedaGoogleRecoveryOutcome> Function(
        DedaGoogleRecoveryProgress report);

class DedaExistingAccountSignInPage extends StatefulWidget {
  const DedaExistingAccountSignInPage({
    super.key,
    this.verifiedLogin,
    this.verifiedGoogleLogin,
    this.googleEnabled = false,
    this.embedded = false,
    this.initialPhone,
    this.enabled = dedaStep2ExistingAccountEntryEnabled,
  });

  /// This callback must verify the original UID and server authorization,
  /// resolve original ID securely and commit the canonical recovered profile.
  /// It is NOT installed by the 100436 development candidate.
  final DedaVerifiedExistingAccountLogin? verifiedLogin;
  final DedaVerifiedExistingGoogleLogin? verifiedGoogleLogin;
  final bool googleEnabled;
  final bool embedded;
  final String? initialPhone;
  final bool enabled;

  @override
  State<DedaExistingAccountSignInPage> createState() =>
      _DedaExistingAccountSignInPageState();
}

class _DedaExistingAccountSignInPageState
    extends State<DedaExistingAccountSignInPage> {
  final _phone = TextEditingController();
  final _pin = TextEditingController();

  @override
  void initState() {
    super.initState();
    final value = widget.initialPhone?.trim() ?? '';
    _phone.text = value.startsWith('+964')
        ? '0${value.substring(4)}' : value;
  }
  bool _busy = false;
  bool _explicitRecoveryConsent = false;
  String? _error;
  int _googlePercent = 0;
  int _googleAttempt = 0;
  bool _googleFailed = false;
  bool _googleIdentityVerified = false;
  bool _googleFullyRestored = false;
  DedaGoogleRecoveryStage? _googleStage;

  bool get _valid =>
      RegExp(r'^07\d{9}$').hasMatch(_phone.text.trim()) &&
      RegExp(r'^\d{6}$').hasMatch(_pin.text) &&
      !_busy && _explicitRecoveryConsent &&
      widget.enabled && widget.verifiedLogin != null;

  bool get _googleValid => !_busy && !_googleIdentityVerified &&
      !_googleFullyRestored && _explicitRecoveryConsent &&
      widget.enabled && widget.googleEnabled &&
      widget.verifiedGoogleLogin != null;

  Future<void> _submitGoogle() async {
    if (!_googleValid) return;
    final attempt = ++_googleAttempt;
    setState(() {
      _busy = true;
      _error = null;
      _googleFailed = false;
      _googlePercent = 0;
      _googleStage = null;
      _googleIdentityVerified = false;
      _googleFullyRestored = false;
    });
    try {
      // Advance ONLY after the real Auth/Firestore operation has finished.
      // Late callbacks from cancelled/replaced attempts are discarded.
      final outcome = await widget.verifiedGoogleLogin!((stage) {
        if (!mounted || !_busy || _googleAttempt != attempt) return;
        final next = DedaGoogleRecoveryProgressPolicy.percent(stage);
        if (DedaGoogleRecoveryProgressPolicy.isSafeStep(
            _googlePercent, stage)) {
          setState(() {
            _googlePercent = next;
            _googleStage = stage;
          });
        }
      });
      if (!mounted || _googleAttempt != attempt) return;
      switch (outcome) {
        case DedaGoogleRecoveryOutcome.cancelled:
          setState(() {
            _googlePercent = 0;
            _googleStage = null;
          });
          break;
        case DedaGoogleRecoveryOutcome.identityVerifiedOnly:
          // Source cannot authorize financial grants or claim full recovery.
          setState(() {
            _googleIdentityVerified = true;
            _googleStage = DedaGoogleRecoveryStage.originalOwnerVerified;
            _googlePercent = 85;
            _error = 'تم التحقق من هوية حساب ديدا الأصلية. '
                'استرجاع البيانات والممتلكات لم يكتمل بعد؛ '
                'احتفظ بهاتفك القديم.';
          });
          break;
        case DedaGoogleRecoveryOutcome.fullAccountRestored:
          // Reserved for a future, independently verified guardian
          // completion report. The current Google binder never emits it.
          setState(() {
            _googleIdentityVerified = true;
            _googleFullyRestored = true;
            _googlePercent = 100;
            _error = null;
          });
          break;
      }
    } catch (_) {
      if (mounted && _googleAttempt == attempt) {
        setState(() {
          // Freeze the LAST REAL percentage. It must never keep growing
          // on failure, and no green tick may be displayed.
          _googleFailed = true;
          _error = 'تعذّر إثبات حساب جوجل الأصلي. لم تُسترجع '
              'أي بيانات ولم تُمنح ماسات. اضغط إعادة المحاولة.';
        });
      }
    } finally {
      if (mounted && _googleAttempt == attempt) {
        setState(() => _busy = false);
      }
    }
  }

  Widget _googleProgressBar() {
    final color = _googleFailed
        ? const Color(0xFFB3261E) : const Color(0xFF188038);
    final status = _googleFailed
        ? 'توقف التحقق، اضغط إعادة المحاولة'
        : _googleFullyRestored
            ? 'اكتمل استرجاع حسابك'
            : _googleStage == null
                ? 'جاهز للتحقق من حساب جوجل'
                : DedaGoogleRecoveryProgressPolicy.label(_googleStage!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          Expanded(child: Text(status,
              key: const ValueKey('deda-google-progress-status'),
              style: TextStyle(fontSize: 12, color: color))),
          if (_googleFullyRestored)
            const Icon(Icons.check_circle, color: Color(0xFF188038),
                key: ValueKey('deda-google-recovery-complete')),
          const SizedBox(width: 6),
          Text('$_googlePercent%',
              key: const ValueKey('deda-google-progress-percent'),
              style: TextStyle(fontSize: 12,
                  fontWeight: FontWeight.w700, color: color)),
        ]),
        const SizedBox(height: 5),
        Semantics(
          label: 'تقدم استرجاع حساب ديدا',
          value: '$_googlePercent بالمئة',
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: _googlePercent.toDouble()),
            duration: const Duration(milliseconds: 280),
            builder: (context, progress, child) => LinearProgressIndicator(
              key: const ValueKey('deda-google-smart-progress'),
              value: progress / 100,
              minHeight: 7,
              color: color,
              backgroundColor: const Color(0xFFE3EAE6),
              borderRadius: BorderRadius.circular(9),
            ),
          ),
        ),
        if (_googleFailed) ...[
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              key: const ValueKey('deda-google-retry'),
              onPressed: _googleValid ? _submitGoogle : null,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('إعادة المحاولة'),
            ),
          ),
        ],
      ],
    );
  }

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

  Widget _existingForm() => SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: ListView(
            shrinkWrap: true,
            physics: widget.embedded ? const NeverScrollableScrollPhysics() : null,
            padding: widget.embedded ? EdgeInsets.zero : const EdgeInsets.all(20),
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
              if (widget.googleEnabled &&
                  widget.verifiedGoogleLogin != null) ...[
                const SizedBox(height: 12),
                _googleProgressBar(),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: const ValueKey('deda-existing-owner-google-login'),
                  onPressed: _googleValid ? _submitGoogle : null,
                  icon: const Icon(Icons.account_circle_outlined),
                  label: Text(_busy
                      ? 'جارٍ التحقق من حساب جوجل...'
                      : 'التحقق بحساب جوجل المرتبط'),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, textAlign: TextAlign.center),
              ],
              if (!widget.enabled ||
                  (widget.verifiedLogin == null &&
                      widget.verifiedGoogleLogin == null)) ...[
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
    );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: widget.embedded
        ? _existingForm()
        : Scaffold(
            appBar: AppBar(title: const Text('لدي حساب')),
            body: _existingForm(),
          ),
  );
}
