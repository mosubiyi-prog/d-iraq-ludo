import 'package:flutter/material.dart';

import 'deda_pin_auth.dart';

/// Private, opt-in second screen. The original DEDA first login screen is
/// unchanged. No Firebase/user record is written until onCreateNew succeeds.
const bool dedaSmartSecondStageAccountEnabled = bool.fromEnvironment(
  'DEDA_SMART_SECOND_STAGE_ACCOUNT', defaultValue: false);

enum DedaSmartAccountChoice { newAccount, existingAccount }

typedef DedaCreateNewAccountVerified = Future<void> Function(
    String name, String phone, String pin);

/// A user-facing choice, never an authority for restoring an old UID.
/// Both creation and recovery delegate to previously reviewed server flows.
class DedaSmartSecondStageAccountPage extends StatefulWidget {
  const DedaSmartSecondStageAccountPage({
    super.key,
    required this.initialName,
    required this.initialPhone,
    required this.onCreateNew,
    required this.existingAccountBuilder,
    this.initialChoice = DedaSmartAccountChoice.newAccount,
  });

  final String initialName, initialPhone;
  final DedaCreateNewAccountVerified onCreateNew;
  final WidgetBuilder existingAccountBuilder;
  final DedaSmartAccountChoice initialChoice;

  @override
  State<DedaSmartSecondStageAccountPage> createState() =>
      _DedaSmartSecondStageAccountPageState();
}

class _DedaSmartSecondStageAccountPageState
    extends State<DedaSmartSecondStageAccountPage> {
  late final TextEditingController _name;
  late String _pin;
  late DedaSmartAccountChoice _choice;
  bool _savedPinConsent = false;
  bool _creating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initialName.trim());
    _pin = DedaPinAuth.generatePin();
    _choice = widget.initialChoice;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _readyForCreation =>
      !_creating && _choice == DedaSmartAccountChoice.newAccount &&
      _savedPinConsent && _name.text.trim().length >= 2 &&
      RegExp(r'^\d{6}$').hasMatch(_pin) &&
      RegExp(r'^\+9647\d{9}$').hasMatch(widget.initialPhone);

  void _select(DedaSmartAccountChoice choice) {
    if (_creating) return;
    setState(() {
      _choice = choice;
      _error = null;
    });
  }

  void _regenerate() {
    if (_creating) return;
    setState(() {
      _pin = DedaPinAuth.generatePin();
      _savedPinConsent = false;
      _error = null;
    });
  }

  Future<void> _create() async {
    if (!_readyForCreation) return;
    final name = _name.text.trim();
    final pin = _pin;
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      // The delegate MUST check the server directory and rely on the
      // atomic createAccount() transaction. Never overwrite an old owner.
      await widget.onCreateNew(name, widget.initialPhone, pin);
    } on StateError catch (e) {
      if (!mounted) return;
      final duplicate = e.toString().contains('account-already-exists') ||
          e.toString().contains('existing-owner-number');
      setState(() => _error = duplicate
          ? 'هذا الرقم عنده حساب ديدا سابق. اختَر «لدي حساب سابق» حتى تحافظ على هويتك وممتلكاتك.'
          : 'تعذر تأكيد إنشاء الحساب على الخادم. لم يتم تسجيل دخول جديد؛ حاول مرة أخرى.');
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'تعذر تأكيد إنشاء الحساب على الخادم. لم يتم تسجيل دخول جديد؛ حاول مرة أخرى.');
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_creating,
    child: Scaffold(
      appBar: AppBar(title: const Text('تأكيد حساب ديدا')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: ListView(
              key: const ValueKey('deda-smart-second-stage'),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              children: [
                const Icon(Icons.verified_user_outlined,
                    size: 44, color: Color(0xFF17652F)),
                const SizedBox(height: 6),
                const Text('اختَر طريقة الدخول',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                SegmentedButton<DedaSmartAccountChoice>(
                  key: const ValueKey('deda-second-stage-mode-choice'),
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: DedaSmartAccountChoice.newAccount,
                      label: Text('حساب جديد'),
                      icon: Icon(Icons.person_add_alt),
                    ),
                    ButtonSegment(
                      value: DedaSmartAccountChoice.existingAccount,
                      label: Text('لدي حساب سابق'),
                      icon: Icon(Icons.person_outline),
                    ),
                  ],
                  selected: {_choice},
                  onSelectionChanged: _creating ? null :
                      (values) => _select(values.first),
                ),
                const SizedBox(height: 12),
                if (_choice == DedaSmartAccountChoice.newAccount) ...[
                  TextField(
                    key: const ValueKey('deda-second-stage-name'),
                    controller: _name,
                    onChanged: (_) => setState(() {}),
                    maxLength: 80,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      labelText: 'الاسم الكامل',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 4),
                  InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'رقم الهاتف',
                      border: OutlineInputBorder(),
                    ),
                    child: Directionality(
                      textDirection: TextDirection.ltr,
                      child: Text(widget.initialPhone,
                          key: const ValueKey('deda-second-stage-phone')),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(children: [
                        const Text('رمز حسابك الجديد (6 أرقام)',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        SelectableText(_pin,
                            key: const ValueKey('deda-second-stage-new-pin'),
                            style: const TextStyle(
                              fontSize: 27, letterSpacing: 4,
                              fontWeight: FontWeight.w800,
                            )),
                        const SizedBox(height: 6),
                        const Text('احفظ هذا الرمز بمكان آمن، راح تحتاجه لاحقاً.',
                            textAlign: TextAlign.center),
                        TextButton.icon(
                          key: const ValueKey('deda-second-stage-new-pin-regenerate'),
                          onPressed: _creating ? null : _regenerate,
                          icon: const Icon(Icons.refresh),
                          label: const Text('توليد رمز جديد'),
                        ),
                      ]),
                    ),
                  ),
                  CheckboxListTile(
                    key: const ValueKey('deda-second-stage-pin-saved'),
                    contentPadding: EdgeInsets.zero,
                    value: _savedPinConsent,
                    onChanged: _creating ? null :
                        (value) => setState(() => _savedPinConsent = value == true),
                    title: const Text('حفظت الرمز السري بمكان آمن'),
                    subtitle: const Text('ما ننشئ الحساب قبل تأكيدك وحفظ الرمز.'),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  FilledButton.icon(
                    key: const ValueKey('deda-second-stage-confirm-create'),
                    onPressed: _readyForCreation ? _create : null,
                    icon: const Icon(Icons.check),
                    label: Text(_creating
                        ? 'جارٍ التأكد وإنشاء الحساب...' : 'تأكيد إنشاء الحساب'),
                  ),
                ] else ...[
                  const Text('استرجع حسابك السابق دون إنشاء حساب بديل.',
                      textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  widget.existingAccountBuilder(context),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!,
                      key: const ValueKey('deda-second-stage-error'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xFFB3261E))),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
).hasMatch(_pin) &&
      RegExp(r'^\\+9647\\d{9}$').hasMatch(widget.initialPhone);

  void _select(DedaSmartAccountChoice choice) {
    if (_creating) return;
    setState(() {
      _choice = choice;
      _error = null;
    });
  }

  void _regenerate() {
    if (_creating) return;
    setState(() {
      _pin = DedaPinAuth.generatePin();
      _savedPinConsent = false;
      _error = null;
    });
  }

  Future<void> _create() async {
    if (!_readyForCreation) return;
    final name = _name.text.trim();
    final pin = _pin;
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      // The delegate MUST check the server directory and rely on the
      // atomic createAccount() transaction. Never overwrite an old owner.
      await widget.onCreateNew(name, widget.initialPhone, pin);
    } on StateError catch (e) {
      if (!mounted) return;
      final duplicate = e.toString().contains('account-already-exists') ||
          e.toString().contains('existing-owner-number');
      setState(() => _error = duplicate
          ? 'هذا الرقم عنده حساب ديدا سابق. اختَر «لدي حساب سابق» حتى تحافظ على هويتك وممتلكاتك.'
          : 'تعذر تأكيد إنشاء الحساب على الخادم. لم يتم تسجيل دخول جديد؛ حاول مرة أخرى.');
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'تعذر تأكيد إنشاء الحساب على الخادم. لم يتم تسجيل دخول جديد؛ حاول مرة أخرى.');
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_creating,
    child: Scaffold(
      appBar: AppBar(title: const Text('تأكيد حساب ديدا')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: ListView(
              key: const ValueKey('deda-smart-second-stage'),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              children: [
                const Icon(Icons.verified_user_outlined,
                    size: 44, color: Color(0xFF17652F)),
                const SizedBox(height: 6),
                const Text('اختَر طريقة الدخول',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                SegmentedButton<DedaSmartAccountChoice>(
                  key: const ValueKey('deda-second-stage-mode-choice'),
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: DedaSmartAccountChoice.newAccount,
                      label: Text('حساب جديد'),
                      icon: Icon(Icons.person_add_alt),
                    ),
                    ButtonSegment(
                      value: DedaSmartAccountChoice.existingAccount,
                      label: Text('لدي حساب سابق'),
                      icon: Icon(Icons.person_outline),
                    ),
                  ],
                  selected: {_choice},
                  onSelectionChanged: _creating ? null :
                      (values) => _select(values.first),
                ),
                const SizedBox(height: 12),
                if (_choice == DedaSmartAccountChoice.newAccount) ...[
                  TextField(
                    key: const ValueKey('deda-second-stage-name'),
                    controller: _name,
                    onChanged: (_) => setState(() {}),
                    maxLength: 80,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      labelText: 'الاسم الكامل',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 4),
                  InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'رقم الهاتف',
                      border: OutlineInputBorder(),
                    ),
                    child: Directionality(
                      textDirection: TextDirection.ltr,
                      child: Text(widget.initialPhone,
                          key: const ValueKey('deda-second-stage-phone')),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(children: [
                        const Text('رمز حسابك الجديد (6 أرقام)',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        SelectableText(_pin,
                            key: const ValueKey('deda-second-stage-new-pin'),
                            style: const TextStyle(
                              fontSize: 27, letterSpacing: 4,
                              fontWeight: FontWeight.w800,
                            )),
                        const SizedBox(height: 6),
                        const Text('احفظ هذا الرمز بمكان آمن، راح تحتاجه لاحقاً.',
                            textAlign: TextAlign.center),
                        TextButton.icon(
                          key: const ValueKey('deda-second-stage-new-pin-regenerate'),
                          onPressed: _creating ? null : _regenerate,
                          icon: const Icon(Icons.refresh),
                          label: const Text('توليد رمز جديد'),
                        ),
                      ]),
                    ),
                  ),
                  CheckboxListTile(
                    key: const ValueKey('deda-second-stage-pin-saved'),
                    contentPadding: EdgeInsets.zero,
                    value: _savedPinConsent,
                    onChanged: _creating ? null :
                        (value) => setState(() => _savedPinConsent = value == true),
                    title: const Text('حفظت الرمز السري بمكان آمن'),
                    subtitle: const Text('ما ننشئ الحساب قبل تأكيدك وحفظ الرمز.'),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  FilledButton.icon(
                    key: const ValueKey('deda-second-stage-confirm-create'),
                    onPressed: _readyForCreation ? _create : null,
                    icon: const Icon(Icons.check),
                    label: Text(_creating
                        ? 'جارٍ التأكد وإنشاء الحساب...' : 'تأكيد إنشاء الحساب'),
                  ),
                ] else ...[
                  const Text('استرجع حسابك السابق دون إنشاء حساب بديل.',
                      textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  widget.existingAccountBuilder(context),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!,
                      key: const ValueKey('deda-second-stage-error'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xFFB3261E))),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
).hasMatch(widget.initialPhone);

  void _select(DedaSmartAccountChoice choice) {
    if (_creating) return;
    setState(() {
      _choice = choice;
      _error = null;
    });
  }

  void _regenerate() {
    if (_creating) return;
    setState(() {
      _pin = DedaPinAuth.generatePin();
      _savedPinConsent = false;
      _error = null;
    });
  }

  Future<void> _create() async {
    if (!_readyForCreation) return;
    final name = _name.text.trim();
    final pin = _pin;
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      // The delegate MUST check the server directory and rely on the
      // atomic createAccount() transaction. Never overwrite an old owner.
      await widget.onCreateNew(name, widget.initialPhone, pin);
    } on StateError catch (e) {
      if (!mounted) return;
      final duplicate = e.toString().contains('account-already-exists') ||
          e.toString().contains('existing-owner-number');
      setState(() => _error = duplicate
          ? 'هذا الرقم عنده حساب ديدا سابق. اختَر «لدي حساب سابق» حتى تحافظ على هويتك وممتلكاتك.'
          : 'تعذر تأكيد إنشاء الحساب على الخادم. لم يتم تسجيل دخول جديد؛ حاول مرة أخرى.');
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'تعذر تأكيد إنشاء الحساب على الخادم. لم يتم تسجيل دخول جديد؛ حاول مرة أخرى.');
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_creating,
    child: Scaffold(
      appBar: AppBar(title: const Text('تأكيد حساب ديدا')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: ListView(
              key: const ValueKey('deda-smart-second-stage'),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              children: [
                const Icon(Icons.verified_user_outlined,
                    size: 44, color: Color(0xFF17652F)),
                const SizedBox(height: 6),
                const Text('اختَر طريقة الدخول',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                SegmentedButton<DedaSmartAccountChoice>(
                  key: const ValueKey('deda-second-stage-mode-choice'),
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: DedaSmartAccountChoice.newAccount,
                      label: Text('حساب جديد'),
                      icon: Icon(Icons.person_add_alt),
                    ),
                    ButtonSegment(
                      value: DedaSmartAccountChoice.existingAccount,
                      label: Text('لدي حساب سابق'),
                      icon: Icon(Icons.person_outline),
                    ),
                  ],
                  selected: {_choice},
                  onSelectionChanged: _creating ? null :
                      (values) => _select(values.first),
                ),
                const SizedBox(height: 12),
                if (_choice == DedaSmartAccountChoice.newAccount) ...[
                  TextField(
                    key: const ValueKey('deda-second-stage-name'),
                    controller: _name,
                    onChanged: (_) => setState(() {}),
                    maxLength: 80,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      labelText: 'الاسم الكامل',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 4),
                  InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'رقم الهاتف',
                      border: OutlineInputBorder(),
                    ),
                    child: Directionality(
                      textDirection: TextDirection.ltr,
                      child: Text(widget.initialPhone,
                          key: const ValueKey('deda-second-stage-phone')),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(children: [
                        const Text('رمز حسابك الجديد (6 أرقام)',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        SelectableText(_pin,
                            key: const ValueKey('deda-second-stage-new-pin'),
                            style: const TextStyle(
                              fontSize: 27, letterSpacing: 4,
                              fontWeight: FontWeight.w800,
                            )),
                        const SizedBox(height: 6),
                        const Text('احفظ هذا الرمز بمكان آمن، راح تحتاجه لاحقاً.',
                            textAlign: TextAlign.center),
                        TextButton.icon(
                          key: const ValueKey('deda-second-stage-new-pin-regenerate'),
                          onPressed: _creating ? null : _regenerate,
                          icon: const Icon(Icons.refresh),
                          label: const Text('توليد رمز جديد'),
                        ),
                      ]),
                    ),
                  ),
                  CheckboxListTile(
                    key: const ValueKey('deda-second-stage-pin-saved'),
                    contentPadding: EdgeInsets.zero,
                    value: _savedPinConsent,
                    onChanged: _creating ? null :
                        (value) => setState(() => _savedPinConsent = value == true),
                    title: const Text('حفظت الرمز السري بمكان آمن'),
                    subtitle: const Text('ما ننشئ الحساب قبل تأكيدك وحفظ الرمز.'),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  FilledButton.icon(
                    key: const ValueKey('deda-second-stage-confirm-create'),
                    onPressed: _readyForCreation ? _create : null,
                    icon: const Icon(Icons.check),
                    label: Text(_creating
                        ? 'جارٍ التأكد وإنشاء الحساب...' : 'تأكيد إنشاء الحساب'),
                  ),
                ] else ...[
                  const Text('استرجع حسابك السابق دون إنشاء حساب بديل.',
                      textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  widget.existingAccountBuilder(context),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!,
                      key: const ValueKey('deda-second-stage-error'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xFFB3261E))),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
).hasMatch(_pin) &&
      RegExp(r'^\\+9647\\d{9}$').hasMatch(widget.initialPhone);

  void _select(DedaSmartAccountChoice choice) {
    if (_creating) return;
    setState(() {
      _choice = choice;
      _error = null;
    });
  }

  void _regenerate() {
    if (_creating) return;
    setState(() {
      _pin = DedaPinAuth.generatePin();
      _savedPinConsent = false;
      _error = null;
    });
  }

  Future<void> _create() async {
    if (!_readyForCreation) return;
    final name = _name.text.trim();
    final pin = _pin;
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      // The delegate MUST check the server directory and rely on the
      // atomic createAccount() transaction. Never overwrite an old owner.
      await widget.onCreateNew(name, widget.initialPhone, pin);
    } on StateError catch (e) {
      if (!mounted) return;
      final duplicate = e.toString().contains('account-already-exists') ||
          e.toString().contains('existing-owner-number');
      setState(() => _error = duplicate
          ? 'هذا الرقم عنده حساب ديدا سابق. اختَر «لدي حساب سابق» حتى تحافظ على هويتك وممتلكاتك.'
          : 'تعذر تأكيد إنشاء الحساب على الخادم. لم يتم تسجيل دخول جديد؛ حاول مرة أخرى.');
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'تعذر تأكيد إنشاء الحساب على الخادم. لم يتم تسجيل دخول جديد؛ حاول مرة أخرى.');
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_creating,
    child: Scaffold(
      appBar: AppBar(title: const Text('تأكيد حساب ديدا')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: ListView(
              key: const ValueKey('deda-smart-second-stage'),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              children: [
                const Icon(Icons.verified_user_outlined,
                    size: 44, color: Color(0xFF17652F)),
                const SizedBox(height: 6),
                const Text('اختَر طريقة الدخول',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                SegmentedButton<DedaSmartAccountChoice>(
                  key: const ValueKey('deda-second-stage-mode-choice'),
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: DedaSmartAccountChoice.newAccount,
                      label: Text('حساب جديد'),
                      icon: Icon(Icons.person_add_alt),
                    ),
                    ButtonSegment(
                      value: DedaSmartAccountChoice.existingAccount,
                      label: Text('لدي حساب سابق'),
                      icon: Icon(Icons.person_outline),
                    ),
                  ],
                  selected: {_choice},
                  onSelectionChanged: _creating ? null :
                      (values) => _select(values.first),
                ),
                const SizedBox(height: 12),
                if (_choice == DedaSmartAccountChoice.newAccount) ...[
                  TextField(
                    key: const ValueKey('deda-second-stage-name'),
                    controller: _name,
                    onChanged: (_) => setState(() {}),
                    maxLength: 80,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      labelText: 'الاسم الكامل',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 4),
                  InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'رقم الهاتف',
                      border: OutlineInputBorder(),
                    ),
                    child: Directionality(
                      textDirection: TextDirection.ltr,
                      child: Text(widget.initialPhone,
                          key: const ValueKey('deda-second-stage-phone')),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(children: [
                        const Text('رمز حسابك الجديد (6 أرقام)',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        SelectableText(_pin,
                            key: const ValueKey('deda-second-stage-new-pin'),
                            style: const TextStyle(
                              fontSize: 27, letterSpacing: 4,
                              fontWeight: FontWeight.w800,
                            )),
                        const SizedBox(height: 6),
                        const Text('احفظ هذا الرمز بمكان آمن، راح تحتاجه لاحقاً.',
                            textAlign: TextAlign.center),
                        TextButton.icon(
                          key: const ValueKey('deda-second-stage-new-pin-regenerate'),
                          onPressed: _creating ? null : _regenerate,
                          icon: const Icon(Icons.refresh),
                          label: const Text('توليد رمز جديد'),
                        ),
                      ]),
                    ),
                  ),
                  CheckboxListTile(
                    key: const ValueKey('deda-second-stage-pin-saved'),
                    contentPadding: EdgeInsets.zero,
                    value: _savedPinConsent,
                    onChanged: _creating ? null :
                        (value) => setState(() => _savedPinConsent = value == true),
                    title: const Text('حفظت الرمز السري بمكان آمن'),
                    subtitle: const Text('ما ننشئ الحساب قبل تأكيدك وحفظ الرمز.'),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  FilledButton.icon(
                    key: const ValueKey('deda-second-stage-confirm-create'),
                    onPressed: _readyForCreation ? _create : null,
                    icon: const Icon(Icons.check),
                    label: Text(_creating
                        ? 'جارٍ التأكد وإنشاء الحساب...' : 'تأكيد إنشاء الحساب'),
                  ),
                ] else ...[
                  const Text('استرجع حسابك السابق دون إنشاء حساب بديل.',
                      textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  widget.existingAccountBuilder(context),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!,
                      key: const ValueKey('deda-second-stage-error'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xFFB3261E))),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
