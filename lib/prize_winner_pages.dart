import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'deda_backend.dart';

class DedaPrizeWinnerRequestPage extends StatefulWidget {
  final bool isArabic;
  final String name;
  final String phone;
  final String dedaId;
  final String rewardCode;
  final int pointsAtCompletion;

  const DedaPrizeWinnerRequestPage({
    super.key,
    required this.isArabic,
    required this.name,
    required this.phone,
    required this.dedaId,
    required this.rewardCode,
    required this.pointsAtCompletion,
  });

  @override
  State<DedaPrizeWinnerRequestPage> createState() =>
      _DedaPrizeWinnerRequestPageState();
}

class _DedaPrizeWinnerRequestPageState
    extends State<DedaPrizeWinnerRequestPage> {
  bool _submitting = false;

  String t(String ar, String en) => widget.isArabic ? ar : en;

  String _statusLabel(String status) => switch (status) {
        'new' => t('جديد', 'New'),
        'reviewing' => t('قيد التدقيق', 'Under review'),
        'needs_info' => t('مطلوب معلومات إضافية', 'More information needed'),
        'approved' => t('تم اعتماد الفوز', 'Win approved'),
        'prize_sent' => t('تم إرسال الجائزة', 'Prize sent'),
        'delivered' => t('تم تسليم الجائزة', 'Prize delivered'),
        'rejected' => t('مرفوض', 'Rejected'),
        _ => status,
      };

  Future<void> _submitRequest() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      await DedaBackend.submitPrizeWinnerRequest(
        name: widget.name,
        phone: widget.phone,
        dedaId: widget.dedaId,
        rewardCode: widget.rewardCode,
        pointsAtCompletion: widget.pointsAtCompletion,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            t(
              'تم إرسال طلب الجائزة إلى إدارة DEDA بنجاح.',
              'Your prize request was sent to DEDA administration.',
            ),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            t(
              'تعذر إرسال طلب الجائزة الآن. تحقق من الإنترنت وحاول مرة أخرى.',
              'Could not send the prize request. Check your connection and try again.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _replyToAdmin() async {
    final controller = TextEditingController();
    final reply = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(t('الرد على الإدارة', 'Reply to administration')),
        content: TextField(
          controller: controller,
          minLines: 3,
          maxLines: 6,
          maxLength: 600,
          decoration: InputDecoration(
            hintText: t(
              'اكتب المعلومات المطلوبة هنا...',
              'Enter the requested information here...',
            ),
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(t('إلغاء', 'Cancel')),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(
              dialogContext,
              controller.text.trim(),
            ),
            icon: const Icon(Icons.send_outlined),
            label: Text(t('إرسال الرد', 'Send reply')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (reply == null || reply.trim().isEmpty) return;
    try {
      await DedaBackend.replyToPrizeWinnerRequestFromUser(
        phone: widget.phone,
        message: reply,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('تم إرسال ردك.', 'Your reply was sent.'))),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            t('تعذر إرسال الرد الآن.', 'Could not send the reply right now.'),
          ),
        ),
      );
    }
  }

  Widget _infoTile(IconData icon, String title, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5DEC5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF9A7415), size: 21),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF6B6658),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                SelectableText(
                  value.isEmpty ? '—' : value,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF2),
      appBar: AppBar(
        title: Text(t('جائزتي في DEDA', 'My DEDA prize')),
        centerTitle: true,
      ),
      body: StreamBuilder<Map<String, dynamic>?>(
        stream: DedaBackend.prizeWinnerRequestForUser(widget.phone),
        builder: (context, snapshot) {
          final data = snapshot.data;
          final status = (data?['status'] ?? '').toString();
          final adminMessage = (data?['adminMessage'] ?? '').toString().trim();
          final prizeDetails = (data?['prizeDetails'] ?? '').toString().trim();
          final userReply = (data?['userReply'] ?? '').toString().trim();

          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 30),
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF17130A), Color(0xFF34280B)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFFFFD76A), width: 1.5),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x22000000),
                      blurRadius: 14,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    const Icon(Icons.emoji_events_rounded,
                        color: Color(0xFFFFD76A), size: 52),
                    const SizedBox(height: 8),
                    Text(
                      t(
                        '🎉 مبروك! أكملت جميع مراحل بطاقات DEDA',
                        '🎉 Congratulations! You completed all DEDA card stages',
                      ),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      t(
                        'لقد حصلت على الجائزة النهائية 👏',
                        'You earned the final prize 👏',
                      ),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFFFFD76A),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      t('الرمز النهائي الكامل', 'Complete final code'),
                      style: const TextStyle(
                        color: Color(0xFFFFD76A),
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: SelectableText(
                        widget.rewardCode,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 21,
                          letterSpacing: 2.4,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              if (data == null) ...[
                Text(
                  t(
                    'هذه البطاقة هي الوحيدة التي تتيح لك التواصل مع الإدارة للمطالبة بالجائزة.',
                    'Only the final card can contact administration to claim the prize.',
                  ),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF5F655E),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _submitting ? null : _submitRequest,
                  icon: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.admin_panel_settings_outlined),
                  label: Text(
                    t(
                      'مراسلة إدارة DEDA للمطالبة بالجائزة',
                      'Contact DEDA administration to claim prize',
                    ),
                  ),
                ),
              ] else ...[
                _infoTile(
                  Icons.assignment_turned_in_outlined,
                  t('حالة الطلب', 'Request status'),
                  _statusLabel(status),
                ),
                _infoTile(
                  Icons.badge_outlined,
                  t('معرف DEDA', 'DEDA ID'),
                  widget.dedaId,
                ),
                if (adminMessage.isNotEmpty)
                  _infoTile(
                    Icons.mark_email_read_outlined,
                    t('رسالة الإدارة', 'Administration message'),
                    adminMessage,
                  ),
                if (userReply.isNotEmpty)
                  _infoTile(
                    Icons.reply_outlined,
                    t('آخر رد منك', 'Your latest reply'),
                    userReply,
                  ),
                if (prizeDetails.isNotEmpty)
                  _infoTile(
                    Icons.card_giftcard_rounded,
                    t('الجائزة المخصصة لك', 'Your assigned prize'),
                    prizeDetails,
                  ),
                if (status == 'needs_info') ...[
                  const SizedBox(height: 4),
                  FilledButton.icon(
                    onPressed: _replyToAdmin,
                    icon: const Icon(Icons.reply_rounded),
                    label: Text(t('الرد على الإدارة', 'Reply to administration')),
                  ),
                ],
                if (status == 'delivered') ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF7EC),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFB7DDBD)),
                    ),
                    child: Text(
                      t(
                        '✅ تم تسليم الجائزة. تهانينا من فريق DEDA.',
                        '✅ Prize delivered. Congratulations from the DEDA team.',
                      ),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF17652F),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ],
            ],
          );
        },
      ),
    );
  }
}

class DedaAdminPrizeWinnersPage extends StatelessWidget {
  final bool isArabic;

  const DedaAdminPrizeWinnersPage({super.key, required this.isArabic});

  String t(String ar, String en) => isArabic ? ar : en;

  String _statusLabel(String status) => switch (status) {
        'new' => t('جديد', 'New'),
        'reviewing' => t('قيد التدقيق', 'Under review'),
        'needs_info' => t('نحتاج معلومات', 'Needs info'),
        'approved' => t('تم اعتماد الفوز', 'Approved'),
        'prize_sent' => t('تم إرسال الجائزة', 'Prize sent'),
        'delivered' => t('تم التسليم', 'Delivered'),
        'rejected' => t('مرفوض', 'Rejected'),
        _ => status,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF2),
      appBar: AppBar(
        title: Text(t('🏆 الرابحون معنا', '🏆 Prize winners')),
        centerTitle: true,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: DedaBackend.prizeWinnerRequestsForAdmin(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text(t('تعذر تحميل طلبات الفوز.', 'Could not load prize requests.')),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snapshot.data!.docs;
          if (docs.isEmpty) {
            return Center(
              child: Text(t('لا توجد طلبات فوز حاليًا.', 'No prize requests yet.')),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data();
              final name = (data['name'] ?? '—').toString();
              final dedaId = (data['dedaId'] ?? '—').toString();
              final code = (data['rewardCode'] ?? '—').toString();
              final status = (data['status'] ?? 'new').toString();
              return Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(19),
                child: InkWell(
                  borderRadius: BorderRadius.circular(19),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DedaAdminPrizeWinnerDetailPage(
                        isArabic: isArabic,
                        requestId: doc.id,
                        initialData: data,
                      ),
                    ),
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(19),
                      border: Border.all(color: const Color(0xFFE5D5A5)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xFFFFF3C8),
                          ),
                          child: const Icon(
                            Icons.emoji_events_rounded,
                            color: Color(0xFF9A7415),
                          ),
                        ),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 16)),
                              const SizedBox(height: 3),
                              Directionality(
                                textDirection: TextDirection.ltr,
                                child: Text(dedaId,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                              ),
                              const SizedBox(height: 3),
                              Directionality(
                                textDirection: TextDirection.ltr,
                                child: Text(code,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: Color(0xFF7A5A10),
                                        fontWeight: FontWeight.w800)),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 6),
                          decoration: BoxDecoration(
                            color: status == 'new'
                                ? const Color(0xFFFFE5E2)
                                : const Color(0xFFEAF4EC),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(
                            _statusLabel(status),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w900),
                          ),
                        ),
                      ],
                    ),
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

class DedaAdminPrizeWinnerDetailPage extends StatefulWidget {
  final bool isArabic;
  final String requestId;
  final Map<String, dynamic> initialData;

  const DedaAdminPrizeWinnerDetailPage({
    super.key,
    required this.isArabic,
    required this.requestId,
    required this.initialData,
  });

  @override
  State<DedaAdminPrizeWinnerDetailPage> createState() =>
      _DedaAdminPrizeWinnerDetailPageState();
}

class _DedaAdminPrizeWinnerDetailPageState
    extends State<DedaAdminPrizeWinnerDetailPage> {
  late String _status;
  late final TextEditingController _message;
  late final TextEditingController _prize;
  bool _saving = false;

  String t(String ar, String en) => widget.isArabic ? ar : en;

  @override
  void initState() {
    super.initState();
    _status = (widget.initialData['status'] ?? 'new').toString();
    _message = TextEditingController(
      text: (widget.initialData['adminMessage'] ?? '').toString(),
    );
    _prize = TextEditingController(
      text: (widget.initialData['prizeDetails'] ?? '').toString(),
    );
  }

  @override
  void dispose() {
    _message.dispose();
    _prize.dispose();
    super.dispose();
  }

  String _label(String status) => switch (status) {
        'new' => t('جديد', 'New'),
        'reviewing' => t('قيد التدقيق', 'Under review'),
        'needs_info' => t('طلب معلومات إضافية', 'Request more info'),
        'approved' => t('اعتماد الفوز', 'Approve win'),
        'prize_sent' => t('إرسال الجائزة', 'Prize sent'),
        'delivered' => t('تم تسليم الجائزة', 'Delivered'),
        'rejected' => t('مرفوض', 'Rejected'),
        _ => status,
      };

  Future<void> _save() async {
    if (_saving) return;
    if (_status == 'needs_info' && _message.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(t('اكتب المعلومات المطلوبة من الفائز.',
              'Enter what information is required from the winner.')),
        ),
      );
      return;
    }
    if ((_status == 'prize_sent' || _status == 'delivered') &&
        _prize.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(t('اكتب تفاصيل الجائزة المخصصة أولًا.',
              'Enter the assigned prize details first.')),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await DedaBackend.updatePrizeWinnerRequestFromAdmin(
        requestId: widget.requestId,
        status: _status,
        adminMessage: _message.text,
        prizeDetails: _prize.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('تم حفظ تحديث الفائز.', 'Winner updated.'))),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(t('تعذر حفظ التحديث.', 'Could not save the update.')),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _dataRow(String label, dynamic value, {bool ltr = false}) {
    final text = (value ?? '').toString().trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 118,
            child: Text(label,
                style: const TextStyle(
                    color: Color(0xFF6D746D), fontWeight: FontWeight.w700)),
          ),
          Expanded(
            child: Directionality(
              textDirection: ltr ? TextDirection.ltr : TextDirection.rtl,
              child: SelectableText(text.isEmpty ? '—' : text,
                  style: const TextStyle(fontWeight: FontWeight.w900)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.initialData;
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF2),
      appBar: AppBar(
        title: Text(t('تفاصيل الفائز', 'Winner details')),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
        children: [
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE5D5A5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _dataRow(t('الاسم', 'Name'), d['name']),
                _dataRow(t('معرف DEDA', 'DEDA ID'), d['dedaId'], ltr: true),
                _dataRow(t('الهاتف', 'Phone'), d['phone'], ltr: true),
                _dataRow(t('الرمز الكامل', 'Full code'), d['rewardCode'], ltr: true),
                _dataRow(t('الرصيد عند الفوز', 'Balance at win'),
                    d['pointsAtCompletion']),
                _dataRow(t('النقاط المستقطعة نهائيًا', 'Final reserved points'),
                    d['finalReservedPoints']),
                _dataRow(t('رد الفائز', 'Winner reply'), d['userReply']),
              ],
            ),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            value: _status,
            decoration: InputDecoration(
              labelText: t('حالة الطلب', 'Request status'),
              border: const OutlineInputBorder(),
            ),
            items: const <String>[
              'new',
              'reviewing',
              'needs_info',
              'approved',
              'prize_sent',
              'delivered',
              'rejected',
            ]
                .map((value) => DropdownMenuItem(
                      value: value,
                      child: Text(_label(value)),
                    ))
                .toList(),
            onChanged: (value) {
              if (value != null) setState(() => _status = value);
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _message,
            minLines: 3,
            maxLines: 6,
            maxLength: 800,
            decoration: InputDecoration(
              labelText: t('رسالة الإدارة للفائز', 'Administration message'),
              hintText: t(
                'مثال: نحتاج معلومات إضافية لإكمال التدقيق...',
                'Example: We need additional information to complete review...',
              ),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _prize,
            minLines: 2,
            maxLines: 5,
            maxLength: 800,
            decoration: InputDecoration(
              labelText: t('تفاصيل الجائزة المخصصة', 'Assigned prize details'),
              hintText: t(
                'اكتب الجائزة أو رمزها أو تعليمات الاستلام...',
                'Enter the prize, code, or delivery instructions...',
              ),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(t('حفظ وإرسال التحديث للفائز', 'Save and send update')),
          ),
        ],
      ),
    );
  }
}
