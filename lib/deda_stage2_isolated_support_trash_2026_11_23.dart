import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'deda_stage2_isolated_admin_identity_2026_11_21.dart';

/// Original Support Trash, now restricted to SECONDARY admin Auth.
class DedaStage2IsolatedSupportTrashPage extends StatefulWidget {
  final DedaIsolatedAdminIdentity admin;
  final String dedaPhone;
  final bool isArabic;

  const DedaStage2IsolatedSupportTrashPage({
    super.key,
    required this.admin,
    required this.dedaPhone,
    required this.isArabic,
  });

  @override
  State<DedaStage2IsolatedSupportTrashPage> createState() =>
      _DedaStage2IsolatedSupportTrashPageState();
}

class _DedaStage2IsolatedSupportTrashPageState
    extends State<DedaStage2IsolatedSupportTrashPage> {
  late Future<DedaIsolatedManagerPage> _page;
  QueryDocumentSnapshot<Map<String, dynamic>>? _pageStart;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>?> _back = [];
  bool _busy = false;

  String t(String ar, String en) => widget.isArabic ? ar : en;

  @override
  void initState() {
    super.initState();
    _page = _fetch();
  }

  Future<DedaIsolatedManagerPage> _fetch() =>
      widget.admin.readScopedSupportTrashPage(
        dedaPhone: widget.dedaPhone, startAfter: _pageStart,
      );

  void _refresh() => setState(() {
    _pageStart = null;
    _back.clear();
    _page = _fetch();
  });

  void _next(DedaIsolatedManagerPage page) {
    if (_busy || page.nextCursor == null) return;
    setState(() {
      _back.add(_pageStart);
      _pageStart = page.nextCursor;
      _page = _fetch();
    });
  }

  void _previous() {
    if (_busy || _back.isEmpty) return;
    setState(() {
      _pageStart = _back.removeLast();
      _page = _fetch();
    });
  }

  String _time(dynamic value) {
    if (value is! Timestamp) return '—';
    final v = value.toDate().toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return two(v.day) + '/' + two(v.month) + '/' + v.year.toString() +
        ' ' + two(v.hour) + ':' + two(v.minute);
  }

  bool _hasRemoteImages(Map<String, dynamic> data) {
    if ((data['imageUrl'] ?? '').toString().trim().isNotEmpty) return true;
    final urls = data['imageUrls'];
    return urls is List &&
        urls.any((v) => (v ?? '').toString().trim().isNotEmpty);
  }

  Future<void> _operate(String id, String action) async {
    if (_busy) return;
    final permanent = action == 'permanent';
    final confirmId = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, updateDialog) => AlertDialog(
          title: Text(action == 'restore'
              ? t('استرجاع رسالة الدعم', 'Restore support message')
              : t('حذف نهائي لا يمكن التراجع عنه',
                  'Irreversible permanent deletion')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(t('معرّف الرسالة: ', 'Message ID: ') + id),
              const SizedBox(height: 8),
              Text(action == 'restore'
                  ? t('ستعود الرسالة إلى الدعم بصلاحياتها الأصلية.',
                      'Message returns to support with original permissions.')
                  : t('هذا الحذف نهائي ولا يشمل صوراً خارجية. '
                      'اكتب المعرّف للتأكيد.',
                      'Permanent deletion is limited to records without '
                      'external images. Type the exact ID.')),
              if (permanent) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: confirmId,
                  onChanged: (_) => updateDialog(() {}),
                  decoration: InputDecoration(
                    labelText: t('اكتب المعرّف', 'Type the ID'),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(t('إلغاء', 'Cancel')),
            ),
            FilledButton(
              onPressed: permanent && confirmId.text.trim() != id
                  ? null : () => Navigator.pop(dialogContext, true),
              child: Text(action == 'restore'
                  ? t('استرجاع', 'Restore')
                  : t('حذف نهائي', 'Delete forever')),
            ),
          ],
        ),
      ),
    );
    confirmId.dispose();
    if (accepted != true || !mounted || _busy) return;
    setState(() => _busy = true);
    try {
      await widget.admin.mutateScopedSupportTrash(
        dedaPhone: widget.dedaPhone,
        requestId: id,
        action: action,
        permanentConfirmation: permanent ? id : null,
      );
      if (!mounted) return;
      _refresh();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(t('تم تسجيل العملية في سجل الإدارة.',
            'Operation committed with admin audit.')),
      ));
    } catch (_) {
      if (!mounted) return;
      _refresh();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(t('تعذرت العملية، راجع صلاحية المدير وحالة السجل.',
            'Operation denied; verify GM permission and record state.')),
      ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _record(Map<String, dynamic> data) {
    final id = (data['id'] ?? '').toString();
    final name = (data['name'] ?? '').toString().trim();
    final phone = (data['phone'] ?? '').toString().trim();
    final message = (data['message'] ?? '').toString().trim();
    final by = (data['deletedByName'] ?? '').toString().trim();
    final remote = _hasRemoteImages(data);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              const Icon(Icons.delete_sweep_outlined,
                  color: Color(0xFFB3261E)),
              const SizedBox(width: 8),
              Expanded(child: Text(name.isEmpty
                  ? t('رسالة دعم محذوفة', 'Deleted support message')
                  : name, style: const TextStyle(fontWeight: FontWeight.w800))),
            ]),
            if (phone.isNotEmpty)
              Directionality(textDirection: TextDirection.ltr,
                  child: Text(phone)),
            if (message.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(message, maxLines: 3,
                    overflow: TextOverflow.ellipsis),
              ),
            const SizedBox(height: 8),
            Text(t('حذف بواسطة: ', 'Deleted by: ') +
                (by.isEmpty ? '—' : by) + ' • ' + _time(data['deletedAt']),
                style: const TextStyle(fontSize: 12.5)),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _operate(id, 'restore'),
                icon: const Icon(Icons.restore),
                label: Text(t('استرجاع', 'Restore')),
              ),
              OutlinedButton.icon(
                onPressed: _busy || remote
                    ? null : () => _operate(id, 'permanent'),
                icon: const Icon(Icons.delete_forever_outlined),
                label: Text(t('حذف نهائي', 'Delete forever')),
              ),
            ]),
            if (remote)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(t('الحذف النهائي محجوب لحماية الصور الخارجية، '
                    'والاسترجاع متاح.',
                    'Permanent deletion is blocked to protect external '
                    'images. Restoration remains available.')),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!dedaIsolatedAdminIdentityEnabled) {
      return const SizedBox.shrink();
    }
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF2),
      appBar: AppBar(
        title: Text(t('محذوفات الدعم • المدير العام',
            'Support trash • General manager')),
        actions: [
          IconButton(
            tooltip: t('تحديث', 'Refresh'),
            onPressed: _busy ? null : _refresh,
            icon: const Icon(Icons.refresh_outlined),
          ),
        ],
      ),
      body: FutureBuilder<DedaIsolatedManagerPage>(
        future: _page,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return Center(child: TextButton(
              onPressed: _refresh,
              child: Text(t('تعذر تحميل المحذوفات. إعادة المحاولة',
                  'Could not load trash. Retry')),
            ));
          }
          final page = snapshot.data!;
          return Column(children: [
            Expanded(
              child: page.rows.isEmpty
                  ? Center(child: Text(t('لا توجد رسائل محذوفة.',
                      'There are no deleted support messages.')))
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: page.rows.length,
                      itemBuilder: (_, index) => _record(page.rows[index]),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 6),
              child: Row(children: [
                Text(t('صفحة ', 'Page ') +
                    (_back.length + 1).toString()),
                const Spacer(),
                TextButton.icon(
                  onPressed: !_busy && _back.isNotEmpty
                      ? _previous : null,
                  icon: const Icon(Icons.chevron_left),
                  label: Text(t('السابق', 'Previous')),
                ),
                TextButton.icon(
                  onPressed: !_busy && page.nextCursor != null
                      ? () => _next(page) : null,
                  icon: const Icon(Icons.chevron_right),
                  label: Text(t('التالي', 'Next')),
                ),
              ]),
            ),
          ]);
        },
      ),
    );
  }
}
