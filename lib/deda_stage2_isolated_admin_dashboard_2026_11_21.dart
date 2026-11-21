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

  bool _exiting = false;

  Future<void> _exit() async {
    if (_exiting) return;
    _exiting = true;
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
    // The gateway profile was verified against the server. Hide links that
    // this role cannot open; each read/write re-proves on the server too.
    bool can(String permission) => DedaIsolatedAdminProofPolicy.allowsPermission(
          admin: widget.profile,
          permission: permission,
        );
    final tabs = <Tab>[];
    final pages = <Widget>[];
    if (can('supportRead')) {
      tabs.add(Tab(text: t('الدعم', 'Support')));
      pages.add(_DedaIsolatedRequestTab(
        admin: widget.admin,
        dedaPhone: widget.dedaPhone,
        isArabic: widget.isArabic,
        profile: widget.profile,
        collection: 'support_requests',
      ));
    }
    if (can('viewPlaceRequests')) {
      tabs.add(Tab(text: t('طلبات الأماكن', 'Place requests')));
      pages.add(_DedaIsolatedRequestTab(
        admin: widget.admin,
        dedaPhone: widget.dedaPhone,
        isArabic: widget.isArabic,
        profile: widget.profile,
        collection: 'place_requests',
      ));
    }
    if (can('viewUsers')) {
      tabs.add(Tab(text: t('المستخدمون', 'Users')));
      pages.add(_DedaIsolatedReadOnlyTab(
        admin: widget.admin,
        dedaPhone: widget.dedaPhone,
        isArabic: widget.isArabic,
        collection: 'users',
      ));
    }
    if (can('viewAudit')) {
      tabs.add(Tab(text: t('سجل الإدارة', 'Admin audit')));
      pages.add(_DedaIsolatedReadOnlyTab(
        admin: widget.admin,
        dedaPhone: widget.dedaPhone,
        isArabic: widget.isArabic,
        collection: 'admin_audit',
      ));
    }
    if (can('viewTeam')) {
      tabs.add(Tab(text: t('فريق الإدارة', 'Admin team')));
      pages.add(_DedaIsolatedReadOnlyTab(
        admin: widget.admin,
        dedaPhone: widget.dedaPhone,
        isArabic: widget.isArabic,
        collection: 'admins',
      ));
    }
    // Only the server-proved GM may access reversible place archives.
    if (can('managePlaceArchives')) {
      for (final config in <(String, String, String)>[
        ('published_places', 'أماكن منشورة', 'Published places'),
        ('admin_trash_place_requests', 'محذوفات الطلبات', 'Request trash'),
        ('admin_trash_places', 'محذوفات الأماكن', 'Place trash'),
      ]) {
        tabs.add(Tab(text: t(config.$2, config.$3)));
        pages.add(_DedaIsolatedManagerPlacesTab(
          admin: widget.admin,
          dedaPhone: widget.dedaPhone,
          isArabic: widget.isArabic,
          sourceCollection: config.$1,
        ));
      }
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) await _exit();
      },
      child: DefaultTabController(
        length: tabs.length,
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
            bottom: tabs.isEmpty
                ? null
                : TabBar(isScrollable: true, tabs: tabs),
          ),
          body: tabs.isEmpty
              ? Center(child: Text(t(
                  'لا توجد صلاحيات إدارية متاحة لهذا الحساب.',
                  'No available administrative permissions.',
                )))
              : TabBarView(children: pages),
        ),
      ),
    );
  }
}

class _DedaIsolatedReadOnlyTab extends StatefulWidget {
  final DedaIsolatedAdminIdentity admin;
  final String dedaPhone;
  final String collection;
  final bool isArabic;

  const _DedaIsolatedReadOnlyTab({
    required this.admin,
    required this.dedaPhone,
    required this.collection,
    required this.isArabic,
  });

  @override
  State<_DedaIsolatedReadOnlyTab> createState() =>
      _DedaIsolatedReadOnlyTabState();
}

class _DedaIsolatedReadOnlyTabState
    extends State<_DedaIsolatedReadOnlyTab> {
  late Future<List<Map<String, dynamic>>> _rows;

  String t(String ar, String en) => widget.isArabic ? ar : en;

  @override
  void initState() {
    super.initState();
    _rows = _fetch();
  }

  Future<List<Map<String, dynamic>>> _fetch() =>
      widget.admin.readScopedAdminList(
        dedaPhone: widget.dedaPhone,
        collection: widget.collection,
        maxItems: 25,
      );

  void _refresh() => setState(() => _rows = _fetch());

  String _timestamp(dynamic value) {
    if (value is! Timestamp) return '';
    final date = value.toDate().toLocal();
    return date.toString().substring(0, 16);
  }

  Widget _record(Map<String, dynamic> data) {
    // Show only existing human-readable fields, not raw Firestore records,
    // internal tokens, private maps or free-form audit metadata.
    final user = widget.collection == 'users';
    final team = widget.collection == 'admins';
    final title = team
        ? (data['displayName'] ?? data['name'] ?? '').toString()
        : user
            ? (data['name'] ?? '').toString()
            : (data['action'] ?? '').toString();
    final subtitle = team
        ? (data['email'] ?? '').toString()
        : user
            ? (data['phone'] ?? '').toString()
            : (data['adminName'] ?? '').toString();
    final detail = team
        ? (data['role'] ?? '').toString()
        : user
            ? (data['accountType'] ?? '').toString()
            : _timestamp(data['createdAt']);
    return Card(
      child: ListTile(
        title: Text(title.isEmpty ? '—' : title),
        subtitle: Text(subtitle),
        trailing: Text(detail),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _rows,
      builder: (context, snapshot) {
        // A pending refresh must never leave previously fetched privileged
        // rows visible if a new server proof is denied or connectivity fails.
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(t(
                  'تعذر التحقق من صلاحيات القراءة من الخادم.',
                  'Could not verify read access from the server.',
                )),
                TextButton(
                  onPressed: _refresh,
                  child: Text(t('إعادة المحاولة', 'Retry')),
                ),
              ],
            ),
          );
        }
        final rows = snapshot.data!;
        return Column(
          children: [
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton.icon(
                onPressed: _refresh,
                icon: const Icon(Icons.refresh),
                label: Text(t('تحديث من الخادم', 'Refresh from server')),
              ),
            ),
            Expanded(
              child: rows.isEmpty
                  ? Center(child: Text(t('لا توجد سجلات.', 'No records.')))
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: rows.length,
                      itemBuilder: (context, index) => _record(rows[index]),
                    ),
            ),
          ],
        );
      },
    );
  }
}

/// General-manager-only list for published places and both protected
/// archives. All records are re-fetched from server after each mutation.
class _DedaIsolatedManagerPlacesTab extends StatefulWidget {
  final DedaIsolatedAdminIdentity admin;
  final String dedaPhone;
  final String sourceCollection;
  final bool isArabic;

  const _DedaIsolatedManagerPlacesTab({
    required this.admin,
    required this.dedaPhone,
    required this.sourceCollection,
    required this.isArabic,
  });

  @override
  State<_DedaIsolatedManagerPlacesTab> createState() =>
      _DedaIsolatedManagerPlacesTabState();
}

class _DedaIsolatedManagerPlacesTabState
    extends State<_DedaIsolatedManagerPlacesTab> {
  late Future<List<Map<String, dynamic>>> _rows;
  bool _mutating = false;

  String t(String ar, String en) => widget.isArabic ? ar : en;

  bool get _isArchive => widget.sourceCollection != 'published_places';

  String get _targetCollection =>
      widget.sourceCollection == 'admin_trash_place_requests'
          ? 'place_requests' : 'published_places';

  @override
  void initState() {
    super.initState();
    _rows = _fetch();
  }

  Future<List<Map<String, dynamic>>> _fetch() =>
      widget.admin.readScopedAdminList(
        dedaPhone: widget.dedaPhone,
        collection: widget.sourceCollection,
        maxItems: 50,
      );

  void _refresh() => setState(() => _rows = _fetch());

  Future<String?> _confirm({
    required String id,
    required String action,
  }) async {
    final permanent = action == 'permanent';
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, refreshDialog) => AlertDialog(
          title: Text(permanent
              ? t('حذف نهائي لا يمكن التراجع عنه', 'Irreversible deletion')
              : action == 'restore'
                  ? t('تأكيد استرجاع السجل', 'Confirm restore')
                  : t('نقل إلى محذوفات المدير العام',
                      'Move to general-manager trash')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(t('المعرّف', 'Record ID') + ': $id'),
              if (permanent) ...[
                const SizedBox(height: 12),
                Text(t(
                  'الحذف النهائي يمحو النسخة المؤرشفة فقط. '
                  'اكتب المعرّف كاملاً للتأكيد.',
                  'Permanently removes ONLY the archived record. '
                  'Type its full ID to confirm.',
                )),
                const SizedBox(height: 8),
                TextField(
                  controller: controller,
                  onChanged: (_) => refreshDialog(() {}),
                  decoration: InputDecoration(
                    labelText: t('اكتب المعرّف', 'Type the ID'),
                  ),
                ),
              ] else
                Text(t(
                  'لا تُعدّل بيانات المستخدمين أو حساباتهم.',
                  'User accounts and ownership are unchanged.',
                )),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(t('إلغاء', 'Cancel')),
            ),
            FilledButton(
              onPressed: permanent && controller.text.trim() != id
                  ? null : () => Navigator.pop(dialogContext, id),
              child: Text(t('تأكيد', 'Confirm')),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _mutate(String id, String action) async {
    if (_mutating) return;
    final confirmation = await _confirm(id: id, action: action);
    if (!mounted || confirmation != id || _mutating) return;
    setState(() => _mutating = true);
    try {
      await widget.admin.mutateScopedPlaceArchive(
        dedaPhone: widget.dedaPhone,
        sourceCollection: _targetCollection,
        recordId: id,
        action: action,
        permanentConfirmation: action == 'permanent' ? confirmation : null,
      );
      if (mounted) {
        _refresh();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(t('تم تسجيل العملية في سجل الإدارة.',
              'Operation completed and audited.')),
        ));
      }
    } catch (_) {
      if (mounted) {
        _refresh(); // Discard any stale privileged result on failure.
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(t(
            'تعذرت العملية. تحقق من صلاحية المدير وحالة السجل.',
            'Operation denied; verify GM access and current record state.',
          )),
        ));
      }
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  Widget _record(Map<String, dynamic> data) {
    final id = (data['id'] ?? '').toString();
    final placeName = (data['placeName'] ?? data['name'] ?? '').toString();
    final approvalNumber = (data['approvalNumber'] ?? '').toString();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(placeName.isEmpty ? id : placeName,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(id, style: Theme.of(context).textTheme.bodySmall),
            if (approvalNumber.isNotEmpty)
              Text(approvalNumber),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (!_isArchive)
                OutlinedButton.icon(
                  onPressed: _mutating ? null : () => _mutate(id, 'trash'),
                  icon: const Icon(Icons.delete_outline),
                  label: Text(t('إلى المحذوفات', 'Move to trash')),
                ),
              if (_isArchive) ...[
                FilledButton.icon(
                  onPressed: _mutating ? null : () => _mutate(id, 'restore'),
                  icon: const Icon(Icons.restore),
                  label: Text(t('استرجاع', 'Restore')),
                ),
                OutlinedButton.icon(
                  onPressed: _mutating ? null :
                      () => _mutate(id, 'permanent'),
                  icon: const Icon(Icons.delete_forever_outlined),
                  label: Text(t('حذف نهائي', 'Delete permanently')),
                ),
              ],
            ]),
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
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _rows,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return Center(child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(t('لا يمكن قراءة السجلات من الخادم.',
                  'Could not verify archive access from server.')),
              TextButton(
                onPressed: _refresh,
                child: Text(t('إعادة المحاولة', 'Retry')),
              ),
            ],
          ));
        }
        final rows = snapshot.data!;
        return Column(children: [
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton.icon(
              onPressed: _mutating ? null : _refresh,
              icon: const Icon(Icons.refresh),
              label: Text(t('تحديث من الخادم', 'Refresh from server')),
            ),
          ),
          Expanded(
            child: rows.isEmpty
                ? Center(child: Text(t('لا توجد سجلات.', 'No records.')))
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: rows.length,
                    itemBuilder: (context, index) => _record(rows[index]),
                  ),
          ),
        ]);
      },
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

  bool get _canArchivePlace => widget.collection == 'place_requests' &&
      DedaIsolatedAdminProofPolicy.allowsPermission(
        admin: widget.profile, permission: 'managePlaceArchives',
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

  Future<String?> _editApprovalMessage(Map<String, dynamic> prepared) async {
    final controller = TextEditingController(
      text: (prepared['message'] ?? '').toString(),
    );
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(t('رسالة اعتماد المكان', 'Place approval message')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(t(
                'راجع الرسالة ورقم الاعتماد قبل إرسال الموافقة.',
                'Review the message and approval number before approving.',
              )),
              const SizedBox(height: 8),
              Text(
                '${(prepared['approvalNumber'] ?? '').toString()} • '
                '${(prepared['approvalDate'] ?? '').toString()}',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                minLines: 5,
                maxLines: 8,
                maxLength: 4000,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(t('إلغاء', 'Cancel')),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(
              dialogContext, controller.text.trim(),
            ),
            icon: const Icon(Icons.send_outlined),
            label: Text(t('إرسال واعتماد', 'Send & approve')),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _approvePlace(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    if (widget.collection != 'place_requests' || _sending ||
        !DedaIsolatedAdminProofPolicy.placeApprovalAllowed(
          admin: widget.profile, request: doc.data(),
          requestId: doc.id,
          expectedStatus: (doc.data()['status'] ?? '').toString(),
        )) {
      return;
    }
    final expectedStatus = (doc.data()['status'] ?? '').toString();
    setState(() => _sending = true);
    try {
      final prepared = await widget.admin.prepareScopedPlaceApproval(
        dedaPhone: widget.dedaPhone,
        requestId: doc.id,
        expectedStatus: expectedStatus,
      );
      if (!mounted) {
        return;
      }
      final message = await _editApprovalMessage(prepared);
      if (message == null || !mounted) {
        return;
      }
      await widget.admin.finalizeScopedPlaceApproval(
        dedaPhone: widget.dedaPhone,
        requestId: doc.id,
        expectedStatus: expectedStatus,
        expectedApprovalNumber:
            (prepared['approvalNumber'] ?? '').toString(),
        expectedApprovalDate: (prepared['approvalDate'] ?? '').toString(),
        message: message,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t(
            'تم اعتماد المكان ونشره وتسجيل القرار.',
            'The place was approved, published and audited.',
          ))),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t(
            'تعذر الاعتماد. تأكد من الصلاحيات وبيانات المكان.',
            'Approval failed. Verify permissions and place details.',
          ))),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _archivePlaceRequest(String id) async {
    if (!_canArchivePlace || _sending) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(t('نقل الطلب إلى محذوفات المدير العام',
            'Move request to general-manager trash')),
        content: Text(t('تأكيد نقل الطلب إلى المحذوفات؟',
            'Move this request to recoverable trash?') + '\n$id'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(t('إلغاء', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(t('تأكيد', 'Confirm')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _sending) return;
    setState(() => _sending = true);
    try {
      await widget.admin.mutateScopedPlaceArchive(
        dedaPhone: widget.dedaPhone,
        sourceCollection: 'place_requests',
        recordId: id,
        action: 'trash',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(t('نُقل الطلب إلى المحذوفات.',
              'Request archived for recovery.')),
        ));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(t(
            'تعذّر نقل الطلب؛ راجع حالة الصلاحيات والسجل.',
            'Could not archive the request; verify rights and record.',
          )),
        ));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<String?> _askPlaceReason(String targetStatus) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(targetStatus == 'rejected'
            ? t('سبب رفض الطلب', 'Reason for rejection')
            : t('التعديل المطلوب', 'Required changes')),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 2,
          maxLines: 4,
          maxLength: 1000,
          decoration: InputDecoration(
            labelText: t('اكتب السبب', 'Write a reason'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(t('إلغاء', 'Cancel')),
          ),
          FilledButton(
            onPressed: () {
              final reason = controller.text.trim();
              if (reason.isNotEmpty) {
                Navigator.pop(dialogContext, reason);
              }
            },
            child: Text(t('تأكيد', 'Confirm')),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _placeReview(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    String targetStatus,
  ) async {
    if (widget.collection != 'place_requests' || _sending) return;
    final data = doc.data();
    final expectedStatus = (data['status'] ?? '').toString();
    // This local check only controls buttons. The isolated transport
    // re-checks server role, gateway, activation and latest record.
    final noteRequired = targetStatus != 'reviewing';
    if (!DedaIsolatedAdminProofPolicy.placeReviewMutationAllowed(
      admin: widget.profile,
      request: data,
      requestId: doc.id,
      expectedStatus: expectedStatus,
      targetStatus: targetStatus,
      note: noteRequired ? 'required' : null,
    )) {
      return;
    }
    final note = noteRequired ? await _askPlaceReason(targetStatus) : null;
    if (noteRequired && (note == null || note.isEmpty)) {
      return;
    }
    if (!mounted || _sending) {
      return;
    }
    setState(() => _sending = true);
    try {
      await widget.admin.updateScopedPlaceReview(
        dedaPhone: widget.dedaPhone,
        requestId: doc.id,
        expectedStatus: expectedStatus,
        targetStatus: targetStatus,
        note: note,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t('تم تسجيل قرار المراجعة.',
              'Review decision recorded.'))),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t(
            'تعذر حفظ القرار؛ تأكد من الصلاحيات والطلب الحالي.',
            'Could not save the decision; verify access and current status.',
          ))),
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
    final canApprove = !support &&
        DedaIsolatedAdminProofPolicy.placeApprovalAllowed(
          admin: widget.profile,
          request: data,
          requestId: doc.id,
          expectedStatus: status,
        );
    bool canReview(String targetStatus) =>
        !support && DedaIsolatedAdminProofPolicy.placeReviewMutationAllowed(
          admin: widget.profile,
          request: data,
          requestId: doc.id,
          expectedStatus: status,
          targetStatus: targetStatus,
          note: targetStatus == 'reviewing' ? null : 'required',
        );
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
          if (!support)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                '${t('المحافظة', 'Governorate')}: '
                '${(data['governorate'] ?? '').toString()}'
                ' • ${(data['address'] ?? '').toString()}',
              ),
            ),
          if (!support &&
              (canApprove || canReview('reviewing') ||
               canReview('needs_changes') ||
               canReview('rejected')))
            Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                if (canApprove)
                  FilledButton.icon(
                    onPressed: _sending ? null : () => _approvePlace(doc),
                    icon: const Icon(Icons.verified_outlined),
                    label: Text(t('اعتماد المكان', 'Approve place')),
                  ),
                if (canReview('reviewing'))
                  OutlinedButton(
                    onPressed: _sending ? null :
                        () => _placeReview(doc, 'reviewing'),
                    child: Text(t('قيد المراجعة', 'Reviewing')),
                  ),
                if (canReview('needs_changes'))
                  OutlinedButton(
                    onPressed: _sending ? null :
                        () => _placeReview(doc, 'needs_changes'),
                    child: Text(t('يحتاج تعديل', 'Needs changes')),
                  ),
                if (canReview('rejected'))
                  OutlinedButton(
                    onPressed: _sending ? null :
                        () => _placeReview(doc, 'rejected'),
                    child: Text(t('رفض الطلب', 'Reject request')),
                  ),
              ]),
            ),
          if (!support && _canArchivePlace)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: OutlinedButton.icon(
                  onPressed: _sending ? null :
                      () => _archivePlaceRequest(doc.id),
                  icon: const Icon(Icons.delete_outline),
                  label: Text(t('نقل الطلب للمحذوفات', 'Archive request')),
                ),
              ),
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
