import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'deda_backend.dart';

class DedaAdminRecoveryRequestPage extends StatefulWidget {
  final bool isArabic;
  final String dedaPhone;
  final String initialName;
  final String initialEmail;

  const DedaAdminRecoveryRequestPage({
    super.key,
    required this.isArabic,
    required this.dedaPhone,
    this.initialName = '',
    this.initialEmail = '',
  });

  @override
  State<DedaAdminRecoveryRequestPage> createState() =>
      _DedaAdminRecoveryRequestPageState();
}

class _DedaAdminRecoveryRequestPageState
    extends State<DedaAdminRecoveryRequestPage> {
  late final TextEditingController _name;
  late final TextEditingController _email;
  final _code = TextEditingController();

  String? _requestId;
  String? _error;
  bool _submitting = false;
  bool _completing = false;

  String t(String ar, String en) => widget.isArabic ? ar : en;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initialName.trim());
    _email = TextEditingController(text: widget.initialEmail.trim());
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  String _friendlyError(Object error) {
    final raw = error.toString().toLowerCase();
    if (raw.contains('admin-recovery-not-authorized') ||
        raw.contains('admin-recovery-identity-mismatch') ||
        raw.contains('permission-denied')) {
      return t(
        'بيانات الحساب لا تطابق صلاحية الإدارة المرتبطة برقم DEDA الحالي. راجع المدير العام.',
        'The account details do not match the administration access linked to this DEDA number. Contact the general manager.',
      );
    }
    if (raw.contains('recovery-code-expired') ||
        raw.contains('deadline-exceeded')) {
      return t(
        'انتهت صلاحية رمز الاسترجاع. أرسل طلبًا جديدًا.',
        'The recovery code has expired. Send a new request.',
      );
    }
    if (raw.contains('invalid-recovery-code')) {
      return t(
        'رمز الاسترجاع غير صحيح.',
        'The recovery code is incorrect.',
      );
    }
    if (raw.contains('network') ||
        raw.contains('unavailable') ||
        raw.contains('timeout')) {
      return t(
        'تعذر الاتصال بالخدمة الآن. تحقق من الإنترنت وحاول مرة أخرى.',
        'Could not reach the service. Check your internet connection and try again.',
      );
    }
    return t(
      'تعذر إكمال العملية الآن. حاول مرة أخرى.',
      'The operation could not be completed right now. Try again.',
    );
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    final email = _email.text.trim().toLowerCase();
    if (name.length < 2 || email.isEmpty || !email.contains('@')) {
      setState(() {
        _error = t(
          'أكمل الاسم والبريد الإلكتروني الإداري بشكل صحيح.',
          'Enter a valid name and administration email.',
        );
      });
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final id = await DedaBackend.requestAdminPasswordRecovery(
        phone: widget.dedaPhone,
        fullName: name,
        email: email,
      );
      if (!mounted) return;
      setState(() => _requestId = id);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _verifyCodeAndSendResetLink(String requestId) async {
    final code = _code.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() {
        _error = t(
          'أدخل رمز الاسترجاع المكوّن من 6 أرقام.',
          'Enter the 6-digit recovery code.',
        );
      });
      return;
    }

    setState(() {
      _completing = true;
      _error = null;
    });
    try {
      await DedaBackend.completeAdminPasswordRecovery(
        requestId: requestId,
        recoveryCode: code,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _completing = false);
    }
  }

  void _restart() {
    setState(() {
      _requestId = null;
      _error = null;
      _code.clear();
    });
  }

  Widget _requestStatus(Map<String, dynamic> data) {
    final status = (data['status'] ?? 'new').toString();
    final requestId = (data['id'] ?? _requestId ?? '').toString();

    if (status == 'rejected') {
      final reason = (data['rejectionReason'] ?? '').toString().trim();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(
            Icons.cancel_outlined,
            size: 54,
            color: Color(0xFFB3261E),
          ),
          const SizedBox(height: 10),
          Text(
            t('تم رفض طلب الاسترجاع', 'Recovery request rejected'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          if (reason.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              reason,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF6B625F)),
            ),
          ],
          const SizedBox(height: 14),
          OutlinedButton(
            onPressed: _restart,
            child: Text(t('إرسال طلب جديد', 'Send a new request')),
          ),
        ],
      );
    }

    if (status == 'reset_link_sent') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(
            Icons.mark_email_read_outlined,
            size: 60,
            color: Color(0xFF17652F),
          ),
          const SizedBox(height: 12),
          Text(
            t(
              'تم التحقق من رمز DEDA وإرسال رابط تغيير كلمة المرور',
              'DEDA code verified and password reset link sent',
            ),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          Text(
            t(
              'افتح البريد الإلكتروني الإداري، عيّن كلمة المرور الجديدة من رابط Firebase الآمن، ثم ارجع إلى DEDA وسجّل الدخول بها.',
              'Open the administration email, set the new password from the secure Firebase link, then return to DEDA and sign in with it.',
            ),
            textAlign: TextAlign.center,
            style: const TextStyle(height: 1.45),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.login),
            label: Text(t('العودة إلى شاشة الدخول', 'Back to sign in')),
          ),
        ],
      );
    }

    if (status == 'ready') {
      final issuedCode = (data['recoveryPin'] ?? '').toString();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(
            Icons.verified_user_outlined,
            size: 54,
            color: Color(0xFF17652F),
          ),
          const SizedBox(height: 8),
          Text(
            t(
              'وافق المدير العام وتم إصدار رمز الاسترجاع',
              'The general manager approved the request and issued a recovery code',
            ),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          if (issuedCode.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFE7F3E7),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF96B99B)),
              ),
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: SelectableText(
                  issuedCode,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 28,
                    letterSpacing: 7,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            t(
              'أدخل الرمز نفسه أدناه للتأكيد. بعد نجاح التحقق سيرسل DEDA رابط تغيير كلمة المرور إلى بريدك الإداري.',
              'Enter the same code below to confirm. After verification, DEDA will send a password reset link to your administration email.',
            ),
            textAlign: TextAlign.center,
            style: const TextStyle(height: 1.4, color: Color(0xFF5A655D)),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _code,
            keyboardType: TextInputType.number,
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.center,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: t('أدخل رمز الـ 6 أرقام', 'Enter the 6-digit code'),
              border: const OutlineInputBorder(),
              counterText: '',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFFB3261E)),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _completing
                ? null
                : () => _verifyCodeAndSendResetLink(requestId),
            icon: _completing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.email_outlined),
            label: Text(
              t(
                'تحقق وأرسل رابط تغيير كلمة المرور',
                'Verify and send password reset link',
              ),
            ),
          ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: _completing ? null : _restart,
            child: Text(
              t(
                'الرمز منتهي أو أحتاج طلبًا جديدًا',
                'Code expired or I need a new request',
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 16),
        Text(
          t(
            'تم إرسال الطلب إلى المدير العام. ستتحدث هذه الصفحة تلقائيًا عند الرد.',
            'The request was sent to the general manager. This page will update automatically when a decision arrives.',
          ),
          textAlign: TextAlign.center,
          style: const TextStyle(height: 1.45, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final requestId = _requestId;
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF2),
      appBar: AppBar(
        title: Text(t('استرجاع دخول الإدارة', 'Administration recovery')),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: requestId == null
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Icon(
                          Icons.lock_reset,
                          size: 68,
                          color: Color(0xFF17652F),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          t(
                            'طلب رمز جديد من المدير العام',
                            'Request a new code from the general manager',
                          ),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 18),
                        TextField(
                          controller: _name,
                          decoration: InputDecoration(
                            labelText: t('الاسم الكامل', 'Full name'),
                            prefixIcon: const Icon(Icons.person_outline),
                            border: const OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          textDirection: TextDirection.ltr,
                          decoration: InputDecoration(
                            labelText:
                                t('البريد الإلكتروني الإداري', 'Admin email'),
                            prefixIcon: const Icon(Icons.email_outlined),
                            border: const OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          initialValue: widget.dedaPhone,
                          readOnly: true,
                          textDirection: TextDirection.ltr,
                          decoration: InputDecoration(
                            labelText: t(
                              'رقم DEDA المخول',
                              'Authorized DEDA number',
                            ),
                            prefixIcon: const Icon(Icons.phone_android_outlined),
                            border: const OutlineInputBorder(),
                          ),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 10),
                          Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Color(0xFFB3261E)),
                          ),
                        ],
                        const SizedBox(height: 18),
                        FilledButton.icon(
                          onPressed: _submitting ? null : _submit,
                          icon: _submitting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.send_outlined),
                          label: Text(
                            t(
                              'إرسال طلب الاسترجاع',
                              'Send recovery request',
                            ),
                          ),
                        ),
                      ],
                    )
                  : StreamBuilder<Map<String, dynamic>?>(
                      stream:
                          DedaBackend.adminRecoveryRequestStream(requestId),
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return Text(
                            t(
                              'تعذر متابعة حالة الطلب الآن.',
                              'Could not load the request status right now.',
                            ),
                            textAlign: TextAlign.center,
                          );
                        }
                        final data = snapshot.data;
                        if (data == null) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        return _requestStatus(data);
                      },
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class DedaAdminRecoveryInboxPage extends StatelessWidget {
  final bool isArabic;

  const DedaAdminRecoveryInboxPage({
    super.key,
    required this.isArabic,
  });

  String t(String ar, String en) => isArabic ? ar : en;

  String _roleLabel(String role) {
    switch (DedaBackend.normalizeAdminRole(role)) {
      case 'deputy_manager':
        return t('معاون المدير', 'Deputy manager');
      case 'province_agent':
        return t('وكيل محافظة', 'Province agent');
      case 'employee':
        return t('موظف', 'Employee');
      default:
        return role;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'new':
        return t('بانتظار قرار المدير', 'Waiting for manager');
      case 'approved':
        return t('تمت الموافقة', 'Approved');
      case 'ready':
        return t('تم إصدار الرمز', 'Code issued');
      case 'reset_link_sent':
        return t('أُرسل رابط التغيير', 'Reset link sent');
      case 'completed':
        return t('مكتمل', 'Completed');
      case 'rejected':
        return t('مرفوض', 'Rejected');
      case 'error':
        return t('خطأ بالإصدار', 'Issue error');
      default:
        return status;
    }
  }

  String _formatTime(dynamic value) {
    if (value is! Timestamp) return '';
    final date = value.toDate().toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${date.year} '
        '${two(date.hour)}:${two(date.minute)}';
  }

  Future<void> _approve(
    BuildContext context,
    Map<String, dynamic> data,
  ) async {
    final id = (data['id'] ?? '').toString();
    if (id.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(t('إصدار رمز استرجاع', 'Issue recovery code')),
        content: Text(
          t(
            'سيصدر رمز من 6 أرقام لهذا الموظف بعد الموافقة.',
            'A 6-digit code will be issued to this staff member after approval.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(t('إلغاء', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(t('موافقة وإصدار رمز', 'Approve and issue code')),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await DedaBackend.decideAdminPasswordRecovery(
        requestId: id,
        approve: true,
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            t('تعذر اعتماد الطلب الآن.', 'Could not approve the request.'),
          ),
        ),
      );
    }
  }

  Future<void> _reject(
    BuildContext context,
    Map<String, dynamic> data,
  ) async {
    final id = (data['id'] ?? '').toString();
    if (id.isEmpty) return;
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(t('رفض طلب الاسترجاع', 'Reject recovery request')),
        content: TextField(
          controller: controller,
          minLines: 2,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: t('سبب الرفض', 'Reason'),
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(t('إلغاء', 'Cancel')),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) Navigator.pop(dialogContext, value);
            },
            child: Text(t('رفض', 'Reject')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (reason == null || reason.isEmpty || !context.mounted) return;

    try {
      await DedaBackend.decideAdminPasswordRecovery(
        requestId: id,
        approve: false,
        rejectionReason: reason,
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            t('تعذر رفض الطلب الآن.', 'Could not reject the request.'),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF2),
      appBar: AppBar(
        title: Text(
          t(
            'طلبات استرجاع دخول الموظفين',
            'Staff sign-in recovery requests',
          ),
        ),
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: DedaBackend.adminRecoveryRequestsStream(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text(
                t(
                  'تعذر تحميل طلبات الاسترجاع.',
                  'Could not load recovery requests.',
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final items = snapshot.data!;
          if (items.isEmpty) {
            return Center(
              child: Text(
                t(
                  'لا توجد طلبات استرجاع حاليًا.',
                  'There are no recovery requests right now.',
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(14),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final data = items[index];
              final status = (data['status'] ?? '').toString();
              final canDecide = status == 'new';
              final createdAt = _formatTime(data['createdAt']);

              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.lock_reset,
                            color: Color(0xFF17652F),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              (data['fullName'] ?? '').toString(),
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          Chip(label: Text(_statusLabel(status))),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Directionality(
                        textDirection: TextDirection.ltr,
                        child: SelectableText(
                          (data['email'] ?? '').toString(),
                          textAlign: TextAlign.left,
                        ),
                      ),
                      Directionality(
                        textDirection: TextDirection.ltr,
                        child: SelectableText(
                          (data['phone'] ?? '').toString(),
                          textAlign: TextAlign.left,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _roleLabel((data['targetRole'] ?? '').toString()),
                        style: const TextStyle(color: Color(0xFF5A655D)),
                      ),
                      if (createdAt.isNotEmpty)
                        Text(
                          createdAt,
                          style: const TextStyle(
                            color: Color(0xFF7A827B),
                            fontSize: 12,
                          ),
                        ),
                      if (canDecide) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: () => _approve(context, data),
                                icon: const Icon(Icons.check_circle_outline),
                                label: Text(
                                  t(
                                    'موافقة وإصدار رمز',
                                    'Approve & issue code',
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              onPressed: () => _reject(context, data),
                              icon: const Icon(Icons.close),
                              label: Text(t('رفض', 'Reject')),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
