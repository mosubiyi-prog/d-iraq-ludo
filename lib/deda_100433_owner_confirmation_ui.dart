import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'deda_100430_owner_uid_continuity.dart';
import 'deda_100431_linked_owner_session_policy.dart';

/// DEDA 100433: explicit user action and non-persistent PIN entry only.
/// This is NOT password reset, not Google Sign-In and does not transfer money.
class DedaOwnerPinPrompt {
  const DedaOwnerPinPrompt._();

  static Future<String?> ask(
    BuildContext context, {
    required String title,
    required String explanation,
  }) => showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _DedaOwnerPinDialog(
      title: title, explanation: explanation),
  );
}

class _DedaOwnerPinDialog extends StatefulWidget {
  const _DedaOwnerPinDialog({
    required this.title, required this.explanation,
  });
  final String title, explanation;
  @override
  State<_DedaOwnerPinDialog> createState() => _DedaOwnerPinDialogState();
}

class _DedaOwnerPinDialogState extends State<_DedaOwnerPinDialog> {
  final controller = TextEditingController();
  @override
  void dispose() {
    controller.clear();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(widget.explanation),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('deda-owner-pin-input'),
          controller: controller,
          autofocus: true,
          obscureText: true,
          enableSuggestions: false,
          autocorrect: false,
          keyboardType: TextInputType.number,
          textDirection: TextDirection.ltr,
          maxLength: 6,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: 'رمز الحساب / Account PIN',
            border: OutlineInputBorder(),
          ),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('إلغاء / Cancel'),
      ),
      FilledButton(
        key: const ValueKey('deda-owner-pin-submit'),
        onPressed: () {
          final value = controller.text;
          if (RegExp(r'^\d{6}$').hasMatch(value)) {
            Navigator.pop(context, value);
          }
        },
        child: const Text('تأكيد / Confirm'),
      ),
    ],
  );
}

/// Visible above Sign out ONLY when owner explicitly opts into the private
/// build's separately reviewed account confirmation feature.
class DedaOwnerConfirmButton extends StatefulWidget {
  const DedaOwnerConfirmButton({
    super.key,
    required this.phone,
    required this.originalId,
    this.forTesting = false,
    this.confirm,
  });

  final String phone;
  final String originalId;
  final bool forTesting;
  final Future<String> Function(String phone,String pin,String originalId)? confirm;

  @override
  State<DedaOwnerConfirmButton> createState() => _DedaOwnerConfirmButtonState();
}

class _DedaOwnerConfirmButtonState extends State<DedaOwnerConfirmButton> {
  bool _running = false;

  Future<void> _submit() async {
    if (_running) return;
    final pin = await DedaOwnerPinPrompt.ask(
      context,
      title: 'تأكيد حساب DEDA / Confirm account',
      explanation: 'أدخل رمز حسابك على الهاتف الأصلي فقط. '
        'لا تسجل خروجك أو تحذف التطبيق قبل نجاح فحص الهاتف الثاني. '
        'هذه الخطوة لا تسترجع الماسات أو النقاط تلقائياً.',
    );
    if (pin == null || !mounted) return;
    setState(() => _running = true);
    try {
      final confirmed = widget.confirm ??
          (phone,pin,originalId) => DedaOwnerUidContinuity.linkExistingOriginalUid(
                phone:phone,pin:pin,originalId:originalId);
      final uid = await confirmed(widget.phone,pin,widget.originalId);
      if (!mounted) return;
      if (uid.isEmpty) throw StateError('owner-link-failed');
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('تم ربط معرّف Firebase الأصلي. '
          'احتفظ بالتطبيق على هذا الهاتف لحين فحص الاسترجاع.'),
      ));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('تعذر تأكيد الحساب بأمان. لم يتم استرجاع أو نقل أي رصيد.'),
      ));
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!dedaLinkedOwnerCompatEnabled && !widget.forTesting) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: OutlinedButton.icon(
        key: const ValueKey('deda-owner-confirm-action'),
        onPressed: _running ? null : _submit,
        icon: const Icon(Icons.verified_user_outlined),
        label: const Text('تأكيد الحساب / Confirm account'),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
        ),
      ),
    );
  }
}
).hasMatch(value)) {
            Navigator.pop(context, value);
          }
        },
        child: const Text('تأكيد / Confirm'),
      ),
    ],
  );
}

/// Visible above Sign out ONLY when owner explicitly opts into the private
/// build's separately reviewed account confirmation feature.
class DedaOwnerConfirmButton extends StatefulWidget {
  const DedaOwnerConfirmButton({
    super.key,
    required this.phone,
    required this.originalId,
    this.forTesting = false,
    this.confirm,
  });

  final String phone;
  final String originalId;
  final bool forTesting;
  final Future<String> Function(String phone,String pin,String originalId)? confirm;

  @override
  State<DedaOwnerConfirmButton> createState() => _DedaOwnerConfirmButtonState();
}

class _DedaOwnerConfirmButtonState extends State<DedaOwnerConfirmButton> {
  bool _running = false;

  Future<void> _submit() async {
    if (_running) return;
    final pin = await DedaOwnerPinPrompt.ask(
      context,
      title: 'تأكيد حساب DEDA / Confirm account',
      explanation: 'أدخل رمز حسابك على الهاتف الأصلي فقط. '
        'لا تسجل خروجك أو تحذف التطبيق قبل نجاح فحص الهاتف الثاني. '
        'هذه الخطوة لا تسترجع الماسات أو النقاط تلقائياً.',
    );
    if (pin == null || !mounted) return;
    setState(() => _running = true);
    try {
      final confirmed = widget.confirm ??
          (phone,pin,originalId) => DedaOwnerUidContinuity.linkExistingOriginalUid(
                phone:phone,pin:pin,originalId:originalId);
      final uid = await confirmed(widget.phone,pin,widget.originalId);
      if (!mounted) return;
      if (uid.isEmpty) throw StateError('owner-link-failed');
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('تم ربط معرّف Firebase الأصلي. '
          'احتفظ بالتطبيق على هذا الهاتف لحين فحص الاسترجاع.'),
      ));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('تعذر تأكيد الحساب بأمان. لم يتم استرجاع أو نقل أي رصيد.'),
      ));
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!dedaLinkedOwnerCompatEnabled && !widget.forTesting) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: OutlinedButton.icon(
        key: const ValueKey('deda-owner-confirm-action'),
        onPressed: _running ? null : _submit,
        icon: const Icon(Icons.verified_user_outlined),
        label: const Text('تأكيد الحساب / Confirm account'),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
        ),
      ),
    );
  }
}
