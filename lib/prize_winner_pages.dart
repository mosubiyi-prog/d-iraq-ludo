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
        'prize_sent' => t('بانتظار تأكيد استلامك', 'Waiting for your confirmation'),
        'delivered' => t('تم تأكيد استلام الجائزة', 'Prize receipt confirmed'),
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

  Future<void> _confirmPrizeReceived() async {
    if (_submitting) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(t('تأكيد استلام الجائزة', 'Confirm prize receipt')),
        content: Text(
          t(
            'هل تؤكد أنك استلمت جائزتك؟ بعد التأكيد ستُغلق دورة الجوائز الحالية ولن يمكن إعادة تأكيدها.',
            'Do you confirm that you received your prize? This will close the current prize cycle and cannot be repeated.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(t('إلغاء', 'Cancel')),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.verified_rounded),
            label: Text(t('نعم، تم الاستلام', 'Yes, I received it')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _submitting = true);
    try {
      await DedaBackend.confirmPrizeReceivedByUser(phone: widget.phone);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            t(
              'تم تأكيد استلام الجائزة وإغلاق دورة الجوائز الحالية.',
              'Prize receipt confirmed and the current prize cycle is closed.',
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
              'تعذر تأكيد الاستلام الآن. تحقق من الإنترنت وحاول مرة أخرى.',
              'Could not confirm receipt. Check your connection and try again.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _infoTile(
    IconData icon,
    String title,
    String value, {
    bool ltr = false,
  }) {
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
                Directionality(
                  textDirection: ltr ? TextDirection.ltr : TextDirection.rtl,
                  child: SelectableText(
                    value.isEmpty ? '—' : value,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
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
                  ltr: true,
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
                if (status == 'prize_sent') ...[
                  const SizedBox(height: 5),
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 9),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7DB),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE2C865)),
                    ),
                    child: Text(
                      t(
                        'تحقق من تفاصيل جائزتك أعلاه. إذا استلمتها فعليًا اضغط الزر أدناه ثم أكد الاستلام.',
                        'Check your prize details above. If you actually received it, press the button below and confirm receipt.',
                      ),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _submitting ? null : _confirmPrizeReceived,
                    icon: _submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.task_alt_rounded),
                    label: Text(t('✅ تم استلام الجائزة', '✅ I received the prize')),
                  ),
                ],
                if (status == 'delivered') ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF7EC),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFB7DDBD)),
                    ),
                    child: Column(
                      children: [
                        const Icon(Icons.emoji_events_rounded,
                            color: Color(0xFF9A7415), size: 34),
                        const SizedBox(height: 7),
                        Text(
                          t(
                            '✅ تم تأكيد استلام جائزتك بنجاح',
                            '✅ Your prize receipt was confirmed',
                          ),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFF17652F),
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          t(
                            'شكرًا لمشاركتك مع DEDA. انتظر الحدث القادم وشارك من جديد يا عزيزي 🌟',
                            'Thank you for joining DEDA. Wait for the next event and join again 🌟',
                          ),
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ],
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

class DedaAdminPrizeWinnersPage extends StatefulWidget {
  final bool isArabic;

  const DedaAdminPrizeWinnersPage({super.key, required this.isArabic});

  @override
  State<DedaAdminPrizeWinnersPage> createState() =>
      _DedaAdminPrizeWinnersPageState();
}

class _DedaAdminPrizeWinnersPageState extends State<DedaAdminPrizeWinnersPage> {
  final TextEditingController _search = TextEditingController();
  String _query = '';

  String t(String ar, String en) => widget.isArabic ? ar : en;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String _statusLabel(String status) => switch (status) {
        'new' => t('جديد', 'New'),
        'reviewing' => t('قيد التدقيق', 'Under review'),
        'needs_info' => t('نحتاج معلومات', 'Needs info'),
        'approved' => t('تم اعتماد الفوز', 'Approved'),
        'prize_sent' => t('بانتظار تأكيد الفائز', 'Awaiting winner confirmation'),
        'delivered' => t('تم التسليم بتأكيد الفائز', 'Confirmed delivered'),
        'rejected' => t('مرفوض', 'Rejected'),
        _ => status,
      };

  String _displayDedaId(String value) {
    final clean = value.trim().replaceAll('@', '');
    return clean.isEmpty ? '—' : '@$clean';
  }

  int _createdMillis(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final value = doc.data()['createdAt'];
    return value is Timestamp ? value.millisecondsSinceEpoch : 0;
  }

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

          final allDocs = snapshot.data!.docs.toList();
          final byCreated = allDocs.toList()
            ..sort((a, b) => _createdMillis(a).compareTo(_createdMillis(b)));
          final serialById = <String, int>{
            for (var i = 0; i < byCreated.length; i++) byCreated[i].id: i + 1,
          };
          final q = _query.trim().toLowerCase();
          final docs = allDocs.where((doc) {
            if (q.isEmpty) return true;
            final d = doc.data();
            final serial = serialById[doc.id] ?? 0;
            final haystack = <String>[
              (d['name'] ?? '').toString(),
              (d['dedaId'] ?? '').toString(),
              (d['phone'] ?? '').toString(),
              (d['rewardCode'] ?? '').toString(),
              doc.id,
              _statusLabel((d['status'] ?? '').toString()),
              serial.toString(),
              '#${serial.toString().padLeft(3, '0')}',
            ].join(' ').toLowerCase();
            return haystack.contains(q);
          }).toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
                child: TextField(
                  controller: _search,
                  onChanged: (value) => setState(() => _query = value),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: t('مسح البحث', 'Clear search'),
                            onPressed: () {
                              _search.clear();
                              setState(() => _query = '');
                            },
                            icon: const Icon(Icons.close_rounded),
                          ),
                    hintText: t(
                      'ابحث بالاسم أو المعرف أو الهاتف أو رقم الفائز',
                      'Search name, ID, phone, or winner number',
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: allDocs.isEmpty
                    ? Center(
                        child: Text(t('لا توجد طلبات فوز حاليًا.', 'No prize requests yet.')),
                      )
                    : docs.isEmpty
                        ? Center(
                            child: Text(t('لا توجد نتائج مطابقة.', 'No matching winners.')),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(14, 8, 14, 28),
                            itemCount: docs.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final doc = docs[index];
                              final data = doc.data();
                              final serial = serialById[doc.id] ?? 0;
                              final serialText =
                                  '#${serial.toString().padLeft(3, '0')}';
                              final name = (data['name'] ?? '—').toString();
                              final dedaId =
                                  _displayDedaId((data['dedaId'] ?? '').toString());
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
                                        isArabic: widget.isArabic,
                                        requestId: doc.id,
                                        initialData: data,
                                        serialNumber: serial,
                                      ),
                                    ),
                                  ),
                                  child: Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(19),
                                      border: Border.all(
                                        color: const Color(0xFFE5D5A5),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        Row(
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
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    name,
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      fontWeight: FontWeight.w900,
                                                      fontSize: 16,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 3),
                                                  Directionality(
                                                    textDirection: TextDirection.ltr,
                                                    child: FittedBox(
                                                      fit: BoxFit.scaleDown,
                                                      alignment: Alignment.centerLeft,
                                                      child: Text.rich(
                                                        TextSpan(
                                                          children: [
                                                            TextSpan(text: dedaId),
                                                            const TextSpan(text: '   '),
                                                            TextSpan(
                                                              text: code,
                                                              style: const TextStyle(
                                                                color: Color(0xFF7A5A10),
                                                                fontWeight: FontWeight.w800,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                        maxLines: 1,
                                                        softWrap: false,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 6,
                                              ),
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
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w900,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 9),
                                        Align(
                                          alignment: AlignmentDirectional.centerEnd,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 9,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFF5F0E1),
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: Directionality(
                                              textDirection: widget.isArabic
                                                  ? TextDirection.rtl
                                                  : TextDirection.ltr,
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(
                                                    t('رقم الفائز:', 'Winner:'),
                                                    style: const TextStyle(
                                                      color: Color(0xFF6F5715),
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.w900,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Directionality(
                                                    textDirection: TextDirection.ltr,
                                                    child: Text(
                                                      serialText,
                                                      style: const TextStyle(
                                                        color: Color(0xFF6F5715),
                                                        fontSize: 11,
                                                        fontWeight: FontWeight.w900,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
              ),
            ],
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
  final int serialNumber;

  const DedaAdminPrizeWinnerDetailPage({
    super.key,
    required this.isArabic,
    required this.requestId,
    required this.initialData,
    required this.serialNumber,
  });

  @override
  State<DedaAdminPrizeWinnerDetailPage> createState() =>
      _DedaAdminPrizeWinnerDetailPageState();
}

class _DedaAdminPrizeWinnerDetailPageState
    extends State<DedaAdminPrizeWinnerDetailPage> {
  late String _status;
  late String _savedStatus;
  late final TextEditingController _message;
  late final TextEditingController _prize;
  bool _saving = false;

  String t(String ar, String en) => widget.isArabic ? ar : en;

  @override
  void initState() {
    super.initState();
    _status = (widget.initialData['status'] ?? 'new').toString();
    _savedStatus = _status;
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
        'prize_sent' => t('إرسال الجائزة / انتظار تأكيد الفائز', 'Send prize / await winner'),
        'delivered' => t('تم التسليم بتأكيد الفائز', 'Confirmed delivered'),
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
    final prizeText = _prize.text.trim();
    if (_status == 'prize_sent' && prizeText.isEmpty) {
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
      var finalStatus = _status;
      await DedaBackend.updatePrizeWinnerRequestFromAdmin(
        requestId: widget.requestId,
        status: _status,
        adminMessage: _message.text,
        prizeDetails: _prize.text,
      );
      if (_status == 'approved' && prizeText.isNotEmpty) {
        await DedaBackend.updatePrizeWinnerRequestFromAdmin(
          requestId: widget.requestId,
          status: 'prize_sent',
          adminMessage: _message.text,
          prizeDetails: _prize.text,
        );
        finalStatus = 'prize_sent';
      }
      if (!mounted) return;
      setState(() {
        _status = finalStatus;
        _savedStatus = finalStatus;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            finalStatus == 'prize_sent'
                ? t(
                    'تم اعتماد الفوز وإرسال الجائزة للفائز. بانتظار تأكيد الاستلام.',
                    'Win approved and prize sent. Waiting for winner confirmation.',
                  )
                : t('تم حفظ تحديث الفائز.', 'Winner updated.'),
          ),
        ),
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

  List<String> _statusChoices() {
    switch (_savedStatus) {
      case 'new':
        return const <String>['new', 'reviewing', 'needs_info', 'approved', 'rejected'];
      case 'reviewing':
        return const <String>['reviewing', 'needs_info', 'approved', 'rejected'];
      case 'needs_info':
        return const <String>['needs_info', 'reviewing', 'approved', 'rejected'];
      case 'approved':
        return const <String>['approved', 'prize_sent', 'rejected'];
      case 'prize_sent':
        return const <String>['prize_sent'];
      case 'delivered':
        return const <String>['delivered'];
      case 'rejected':
        return const <String>['rejected', 'reviewing'];
      default:
        return <String>[_status];
    }
  }

  String _timestampText(dynamic value) {
    if (value is! Timestamp) return '';
    final d = value.toDate().toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  Widget _dataRow(
    String label,
    dynamic value, {
    bool ltr = false,
    bool singleLine = false,
  }) {
    final text = (value ?? '').toString().trim();
    final shown = text.isEmpty ? '—' : text;
    final valueWidget = SelectableText(
      shown,
      maxLines: singleLine ? 1 : null,
      style: const TextStyle(fontWeight: FontWeight.w900),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 118,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF6D746D),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Directionality(
              textDirection: ltr ? TextDirection.ltr : TextDirection.rtl,
              child: singleLine
                  ? FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: ltr
                          ? Alignment.centerLeft
                          : Alignment.centerRight,
                      child: valueWidget,
                    )
                  : valueWidget,
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
                _dataRow(t('رقم الفائز', 'Winner number'),
                    '#${widget.serialNumber.toString().padLeft(3, '0')}', ltr: true),
                _dataRow(t('معرف DEDA', 'DEDA ID'), d['dedaId'], ltr: true),
                _dataRow(t('الهاتف', 'Phone'), d['phone'], ltr: true),
                _dataRow(t('الرمز الكامل', 'Full code'), d['rewardCode'],
                    ltr: true, singleLine: true),
                _dataRow(t('الرصيد عند الفوز', 'Balance at win'),
                    d['pointsAtCompletion']),
                _dataRow(t('النقاط المستقطعة نهائيًا', 'Final reserved points'),
                    d['finalReservedPoints']),
                _dataRow(t('رد الفائز', 'Winner reply'), d['userReply']),
                if (d['createdAt'] != null)
                  _dataRow(t('تاريخ الفوز', 'Won at'),
                      _timestampText(d['createdAt']), ltr: true),
                if (d['prizeSentAt'] != null)
                  _dataRow(t('إرسال الجائزة', 'Prize sent at'),
                      _timestampText(d['prizeSentAt']), ltr: true),
                if (d['winnerConfirmedAt'] != null)
                  _dataRow(t('تأكيد الفائز', 'Winner confirmed at'),
                      _timestampText(d['winnerConfirmedAt']), ltr: true),
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
            items: _statusChoices()
                .map(
                  (value) => DropdownMenuItem<String>(
                    value: value,
                    child: Text(_label(value)),
                  ),
                )
                .toList(),
            onChanged: _savedStatus == 'delivered' || _savedStatus == 'prize_sent'
                ? null
                : (value) {
                    if (value != null) setState(() => _status = value);
                  },
          ),
          if (_savedStatus == 'prize_sent') ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7DB),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE2C865)),
              ),
              child: Text(
                t(
                  'تم إرسال الجائزة. الحالة الآن بانتظار أن يضغط الفائز «تم استلام الجائزة» ويؤكد الاستلام بنفسه.',
                  'Prize sent. Waiting for the winner to confirm receipt.',
                ),
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
          if (_savedStatus == 'delivered') ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFEAF7EC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFB7DDBD)),
              ),
              child: Text(
                t(
                  '✅ الفائز أكد استلام الجائزة. أُغلقت دورة الجوائز لهذا الطلب.',
                  '✅ The winner confirmed receipt. This prize cycle is closed.',
                ),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF17652F),
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
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
            onPressed: _saving || _savedStatus == 'delivered' ? null : _save,
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
