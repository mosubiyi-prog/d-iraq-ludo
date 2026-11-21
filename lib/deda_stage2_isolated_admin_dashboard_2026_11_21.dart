import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'deda_stage2_isolated_admin_identity_2026_11_21.dart';

/// Stage2 migration bridge, NOT the complete administrative Dashboard.
/// It never calls DedaBackend, the public Auth, or the public Firestore.
/// The stage flag remains OFF until all original admin operations are ported.
class DedaStage2IsolatedDashboardPage extends StatefulWidget {
  final DedaIsolatedAdminIdentity admin;
  final String dedaPhone;
  final Map<String, dynamic> profile;
  final bool isArabic;

  const DedaStage2IsolatedDashboardPage({
    super.key,
    required this.admin,
    required this.dedaPhone,
    required this.profile,
    required this.isArabic,
  });

  @override
  State<DedaStage2IsolatedDashboardPage> createState() =>
      _DedaStage2IsolatedDashboardPageState();
}

class _DedaStage2IsolatedDashboardPageState
    extends State<DedaStage2IsolatedDashboardPage> {
  String t(String ar, String en) => widget.isArabic ? ar : en;

  Future<void> _exit() async {
    try {
      await widget.admin.signOutSecondaryAdmin();
    } finally {
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!dedaIsolatedAdminIdentityEnabled) {
      return const Scaffold(body: Center(child: Text('Admin stage disabled')));
    }
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(t('إدارة DEDA', 'DEDA administration')),
          actions: [
            IconButton(
              tooltip: t('تسجيل خروج الإدارة', 'Admin sign out'),
              icon: const Icon(Icons.logout),
              onPressed: _exit,
            ),
          ],
          bottom: TabBar(tabs: [
            Tab(text: t('الدعم', 'Support')),
            Tab(text: t('طلبات الأماكن', 'Place requests')),
          ]),
        ),
        body: TabBarView(children: [
          _DedaIsolatedRequestTab(
            admin: widget.admin,
            dedaPhone: widget.dedaPhone,
            isArabic: widget.isArabic,
            profile: widget.profile,
            collection: 'support_requests',
          ),
          _DedaIsolatedRequestTab(
            admin: widget.admin,
            dedaPhone: widget.dedaPhone,
            isArabic: widget.isArabic,
            profile: widget.profile,
            collection: 'place_requests',
          ),
        ]),
      ),
    );
  }
}

class _DedaIsolatedRequestTab extends StatefulWidget {
  final DedaIsolatedAdminIdentity admin;
  final String dedaPhone;
  final String collection;
  final bool isArabic;
  final Map<String, dynamic> profile;

  const _DedaIsolatedRequestTab({
    required this.admin,
    required this.dedaPhone,
    required this.collection,
    required this.isArabic,
    required this.profile,
  });

  @override
  State<_DedaIsolatedRequestTab> createState() => _DedaIsolatedRequestTabState();
}

class _DedaIsolatedRequestTabState extends State<_DedaIsolatedRequestTab> {
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _stream;
  bool _sending = false;

  String t(String ar, String en) => widget.isArabic ? ar : en;

  @override
  void initState() {
    super.initState();
    _stream = widget.admin.watchScopedAdminRequests(
      dedaPhone: widget.dedaPhone,
      collection: widget.collection,
      maxItems: 50,
    );
  }

  bool get _canReply => widget.collection == 'support_requests' &&
      DedaIsolatedAdminProofPolicy.allowsPermission(
        admin: widget.profile, permission: 'supportReply',
      );

  Future<void> _setStatus(String id, String status) async {
    if (!_canReply || _sending) return;
    setState(() => _sending = true);
    try {
      await widget.admin.updateScopedSupportStatus(
        dedaPhone: widget.dedaPhone, requestId: id, status: status,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t('تم التحديث.', 'Updated.'))),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t('تعذر التحديث.', 'Could not update.'))),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _reply(String id) async {
    if (!_canReply || _sending) return;
    final reply = TextEditingController();
    final message = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(t('رد الإدارة', 'Admin reply')),
        content: TextField(
          controller: reply,
          maxLines: 5,
          maxLength: 4000,
          decoration: InputDecoration(
            labelText: t('اكتب الرد', 'Write reply'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(t('إلغاء', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, reply.text.trim()),
            child: Text(t('إرسال', 'Send')),
          ),
        ],
      ),
    );
    reply.dispose();
    if (message == null || message.isEmpty || !mounted) return;
    setState(() => _sending = true);
    try {
      await widget.admin.replyToScopedSupport(
        dedaPhone: widget.dedaPhone, requestId: id, message: message,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t('تم إرسال الرد.', 'Reply sent.'))),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t('تعذر إرسال الرد.', 'Could not send reply.'))),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Widget _request(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final support = widget.collection == 'support_requests';
    final title = (data[support ? 'name' : 'placeName'] ?? doc.id).toString();
    final status = (data['status'] ?? '').toString();
    return Card(
      child: ExpansionTile(
        title: Text(title),
        subtitle: Text(status),
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text((data[support ? 'message' : 'description'] ?? '')
                .toString()),
          ),
          if (support && _canReply)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Wrap(spacing: 8, children: [
                OutlinedButton(
                  onPressed: _sending ? null :
                      () => _setStatus(doc.id, 'in_progress'),
                  child: Text(t('قيد المعالجة', 'In progress')),
                ),
                FilledButton(
                  onPressed: _sending ? null : () => _reply(doc.id),
                  child: Text(t('إرسال رد', 'Reply')),
                ),
                OutlinedButton(
                  onPressed: _sending ? null :
                      () => _setStatus(doc.id, 'closed'),
                  child: Text(t('إغلاق', 'Close')),
                ),
              ]),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!dedaIsolatedAdminIdentityEnabled) {
      return const SizedBox.shrink();
    }
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text(t(
            'تعذر تأكيد صلاحيات الإدارة من الخادم.',
            'Could not verify admin permissions from the server.',
          )));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final records = snapshot.data!.docs;
        if (records.isEmpty) {
          return Center(child: Text(t('لا توجد طلبات.', 'No requests.')));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: records.length,
          itemBuilder: (context, index) => _request(records[index]),
        );
      },
    );
  }
}
