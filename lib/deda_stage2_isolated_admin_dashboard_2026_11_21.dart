import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

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
      tabs.add(Tab(text: t('الدعوات الإدارية', 'Admin invitations')));
      pages.add(_DedaIsolatedReadOnlyTab(
        admin: widget.admin,
        dedaPhone: widget.dedaPhone,
        isArabic: widget.isArabic,
        collection: 'admin_invites',
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
  bool _mutating = false;

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

  Future<void> _createInvitation() async {
    if (_mutating || widget.collection != 'admin_invites') return;
    setState(() => _mutating = true);
    final name = TextEditingController();
    final email = TextEditingController();
    final phone = TextEditingController();
    final department = TextEditingController();
    final province = TextEditingController();
    var role = 'employee';
    try {
      final data = await showDialog<Map<String, String>>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, updateDialog) => AlertDialog(
            title: Text(t('دعوة موظف إداري', 'Invite administrative staff')),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    maxLength: 100,
                    decoration: InputDecoration(
                      labelText: t('الاسم الكامل', 'Full name'),
                    ),
                  ),
                  TextField(
                    controller: email,
                    keyboardType: TextInputType.emailAddress,
                    maxLength: 254,
                    decoration: InputDecoration(
                      labelText: t('البريد الإداري', 'Admin email'),
                    ),
                  ),
                  TextField(
                    controller: phone,
                    keyboardType: TextInputType.phone,
                    maxLength: 16,
                    decoration: InputDecoration(
                      labelText: t('رقم حساب DEDA', 'DEDA account phone'),
                    ),
                  ),
                  TextField(
                    controller: department,
                    maxLength: 100,
                    decoration: InputDecoration(
                      labelText: t('القسم', 'Department'),
                    ),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: role,
                    decoration: InputDecoration(
                      labelText: t('الدور', 'Role'),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 'employee',
                        child: Text(t('موظف', 'Employee')),
                      ),
                      DropdownMenuItem(
                        value: 'deputy_manager',
                        child: Text(t('معاون المدير', 'Deputy manager')),
                      ),
                      DropdownMenuItem(
                        value: 'province_agent',
                        child: Text(t('وكيل محافظة', 'Province agent')),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) updateDialog(() => role = value);
                    },
                  ),
                  if (role == 'province_agent')
                    TextField(
                      controller: province,
                      maxLength: 80,
                      decoration: InputDecoration(
                        labelText: t('المحافظة', 'Governorate'),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Text(t(
                    'الصلاحيات الافتراضية للدور؛ لا تُفعّل الدعوة قبل قبولها.',
                    'Role defaults; the invitation does not create an admin login.',
                  )),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(t('إلغاء', 'Cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, <String, String>{
                  'name': name.text,
                  'email': email.text,
                  'phone': phone.text,
                  'department': department.text,
                  'province': province.text,
                  'role': role,
                }),
                child: Text(t('إنشاء الدعوة', 'Create invitation')),
              ),
            ],
          ),
        ),
      );
      if (data == null || !mounted) return;
      final cleanRole = data['role'] ?? '';
      final result = await widget.admin.createScopedAdminInvitation(
        dedaPhone: widget.dedaPhone,
        displayName: data['name'] ?? '',
        email: data['email'] ?? '',
        phone: data['phone'] ?? '',
        role: cleanRole,
        department: data['department'] ?? '',
        governorate: cleanRole == 'province_agent'
            ? data['province'] ?? '' : '',
        permissions: DedaIsolatedAdminProofPolicy
            .defaultInvitationPermissions(cleanRole),
      );
      if (!mounted) return;
      _refresh();
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(t('دعوة إدارية جديدة', 'New administrative invitation')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t(
                  'شارك التفاصيل مع صاحب البريد فقط، ولا تنشر رمز التفعيل.',
                  'Share with the invited email owner only; keep the activation code private.',
                )),
                const SizedBox(height: 10),
                SelectableText('Email: ${result['email']}'),
                SelectableText('Invite ID: ${result['inviteId']}'),
                SelectableText('Admin ID: ${result['adminId']}'),
                SelectableText('Activation code: ${result['activationCode']}'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(t('إغلاق', 'Close')),
            ),
          ],
        ),
      );
    } catch (_) {
      if (mounted) {
        _refresh();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(t(
            'لم تُنشأ الدعوة: تحقق من البيانات والصلاحيات وعدم استخدام البريد أو الهاتف مسبقاً.',
            'Invitation not created: check inputs, manager rights, email and phone.',
          )),
        ));
      }
    } finally {
      name.dispose();
      email.dispose();
      phone.dispose();
      department.dispose();
      province.dispose();
      if (mounted) setState(() => _mutating = false);
    }
  }

  Future<String?> _askTeamReason({
    required String title,
    required String displayName,
  }) async {
    String reason = '';
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, updateDialog) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(displayName),
              const SizedBox(height: 12),
              TextField(
                maxLength: 400,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: t('السبب', 'Reason'),
                ),
                onChanged: (value) => updateDialog(() => reason = value.trim()),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(t('إلغاء', 'Cancel')),
            ),
            FilledButton(
              onPressed: reason.isEmpty
                  ? null : () => Navigator.pop(dialogContext, reason),
              child: Text(t('تأكيد', 'Confirm')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _suspendMember(Map<String, dynamic> member) async {
    if (_mutating || widget.collection != 'admins') return;
    final targetUid = (member['id'] ?? '').toString();
    if (!DedaIsolatedAdminProofPolicy.validScopedDocumentId(targetUid)) {
      return;
    }
    final confirmedReason = await _askTeamReason(
      title: t('تعليق صلاحيات الموظف', 'Suspend staff access'),
      displayName: (member['displayName'] ?? '').toString(),
    );
    if (confirmedReason == null || !mounted) return;
    setState(() => _mutating = true);
    try {
      await widget.admin.suspendScopedAdminMember(
        dedaPhone: widget.dedaPhone,
        targetUid: targetUid,
        reason: confirmedReason,
      );
      if (!mounted) return;
      _refresh();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(t('تم تعليق صلاحيات الموظف.', 'Staff access suspended.')),
      ));
    } catch (_) {
      if (!mounted) return;
      _refresh();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(t(
          'تعذر التعليق: يجب إعادة التحقق من صلاحية المدير والاتصال بالخادم.',
          'Suspension denied: verify manager rights and server connectivity.',
        )),
      ));
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }



  Future<void> _cancelInvitation(Map<String, dynamic> invitation) async {
    if (_mutating || widget.collection != 'admin_invites') return;
    final inviteId = (invitation['id'] ?? '').toString();
    if (!DedaIsolatedAdminProofPolicy.validScopedDocumentId(inviteId)) {
      return;
    }
    final confirmedReason = await _askTeamReason(
      title: t('إلغاء دعوة معلقة', 'Cancel pending invitation'),
      displayName: (invitation['displayName'] ?? '').toString(),
    );
    if (confirmedReason == null || !mounted) return;
    setState(() => _mutating = true);
    try {
      await widget.admin.cancelScopedAdminInvitation(
        dedaPhone: widget.dedaPhone,
        inviteId: inviteId,
        reason: confirmedReason,
      );
      if (!mounted) return;
      _refresh();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(t('تم إلغاء الدعوة المعلقة.', 'Pending invitation cancelled.')),
      ));
    } catch (_) {
      if (!mounted) return;
      _refresh();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(t(
          'تعذر الإلغاء: الدعوة غير معلقة أو تغيرت الصلاحيات أو بوابة الهاتف.',
          'Cancellation denied: invitation, permission or gateway changed.',
        )),
      ));
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }


  Future<void> _editMember(Map<String, dynamic> member) async {
    if (_mutating || widget.collection != 'admins') return;
    final id = (member['id'] ?? '').toString();
    if (!DedaIsolatedAdminProofPolicy.validScopedDocumentId(id)) return;
    final name = TextEditingController(text: (member['displayName'] ?? '').toString());
    final phone = TextEditingController(text: (member['phone'] ?? '').toString());
    final department = TextEditingController(text: (member['department'] ?? '').toString());
    final province = TextEditingController(text: (member['governorate'] ?? '').toString());
    var role = (member['role'] ?? 'employee').toString();
    var status = (member['status'] ?? 'disabled').toString();
    if (!const <String>{'active', 'temporarily_stopped', 'disabled'}.contains(status)) {
      status = member['active'] == true ? 'active' : 'disabled';
    }
    final prior = member['permissions'];
    var permissions = <String, bool>{
      for (final key in DedaIsolatedAdminProofPolicy.invitationPermissionKeys)
        key: prior is Map && prior[key] == true,
    };
    try {
      final values = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (dialog) => StatefulBuilder(
          builder: (dialog, refresh) => AlertDialog(
            title: Text(t('تعديل الموظف وصلاحياته', 'Edit staff and permissions')),
            content: SizedBox(width: 430, child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(controller: name, maxLength: 100,
                  decoration: InputDecoration(labelText: t('الاسم', 'Name'))),
                TextField(controller: phone, keyboardType: TextInputType.phone,
                  maxLength: 16,
                  decoration: InputDecoration(labelText: t('هاتف حساب DEDA', 'DEDA phone'))),
                TextField(controller: department, maxLength: 100,
                  decoration: InputDecoration(labelText: t('القسم', 'Department'))),
                DropdownButtonFormField<String>(
                  initialValue: role,
                  decoration: InputDecoration(labelText: t('الدور', 'Role')),
                  items: [
                    DropdownMenuItem(value: 'employee', child: Text(t('موظف', 'Employee'))),
                    DropdownMenuItem(value: 'deputy_manager', child: Text(t('معاون', 'Deputy'))),
                    DropdownMenuItem(value: 'province_agent', child: Text(t('وكيل محافظة', 'Province agent'))),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      refresh(() {
                        role = v;
                        permissions = DedaIsolatedAdminProofPolicy
                            .defaultInvitationPermissions(v);
                      });
                    }
                  },
                ),
                if (role == 'province_agent')
                  TextField(controller: province, maxLength: 80,
                    decoration: InputDecoration(labelText: t('المحافظة', 'Governorate'))),
                DropdownButtonFormField<String>(
                  initialValue: status,
                  decoration: InputDecoration(labelText: t('حالة الوصول', 'Access status')),
                  items: [
                    DropdownMenuItem(value: 'active', child: Text(t('نشط', 'Active'))),
                    DropdownMenuItem(value: 'temporarily_stopped', child: Text(t('موقوف مؤقتاً', 'Suspended'))),
                    DropdownMenuItem(value: 'disabled', child: Text(t('معطّل', 'Disabled'))),
                  ],
                  onChanged: (v) { if (v != null) refresh(() => status = v); },
                ),
                const Divider(),
                Text(t('الصلاحيات', 'Permissions')),
                ...DedaIsolatedAdminProofPolicy.invitationPermissionKeys.map((key) =>
                  SwitchListTile(
                    dense: true, title: Text(key),
                    value: permissions[key] ?? false,
                    onChanged: (v) => refresh(() => permissions[key] = v),
                  )),
              ]),
            )),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialog),
                child: Text(t('إلغاء', 'Cancel'))),
              FilledButton(onPressed: () => Navigator.pop(dialog, <String, dynamic>{
                'name': name.text, 'phone': phone.text, 'department': department.text,
                'province': province.text, 'role': role, 'status': status,
                'permissions': Map<String, bool>.from(permissions),
              }), child: Text(t('متابعة', 'Continue'))),
            ],
          ),
        ),
      );
      if (values == null || !mounted) return;
      final reason = await _askTeamReason(
        title: t('تأكيد تعديل الموظف', 'Confirm staff update'),
        displayName: (member['displayName'] ?? '').toString(),
      );
      if (reason == null || !mounted) return;
      setState(() => _mutating = true);
      try {
        await widget.admin.updateScopedAdminMember(
          dedaPhone: widget.dedaPhone, targetUid: id,
          displayName: values['name'] as String, phone: values['phone'] as String,
          role: values['role'] as String, department: values['department'] as String,
          governorate: values['role'] == 'province_agent' ? values['province'] as String : '',
          status: values['status'] as String,
          permissions: values['permissions'] as Map<String, bool>, reason: reason,
        );
        if (mounted) { _refresh(); ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(t('تم تعديل الموظف وبوابته.', 'Staff and gateway updated.')))); }
      } catch (_) {
        if (mounted) { _refresh(); ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(t('فشل التعديل: راجع الصلاحيات وربط الهاتف.',
            'Update denied: verify permissions and phone binding.')))); }
      } finally { if (mounted) setState(() => _mutating = false); }
    } finally {
      name.dispose(); phone.dispose(); department.dispose(); province.dispose();
    }
  }

  Future<void> _removeMemberAccess(Map<String, dynamic> member) async {
    if (_mutating || widget.collection != 'admins') return;
    final id = (member['id'] ?? '').toString();
    if (!DedaIsolatedAdminProofPolicy.validScopedDocumentId(id)) return;
    final reason = await _askTeamReason(
      title: t('إزالة وصول الموظف', 'Remove staff access'),
      displayName: (member['displayName'] ?? '').toString(),
    );
    if (reason == null || !mounted) return;
    final confirm = await showDialog<bool>(context: context,
      builder: (dialog) => AlertDialog(
        title: Text(t('تأكيد نهائي', 'Final confirmation')),
        content: Text(t('سيُحذف وصول الإدارة وبوابة الهاتف فقط، ولن يُحذف حساب DEDA أو Firebase Auth.',
          'Only admin access and its gateway are removed, not DEDA or Firebase Auth.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false),
            child: Text(t('إلغاء', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(dialog, true),
            child: Text(t('إزالة الوصول', 'Remove access'))),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => _mutating = true);
    try {
      await widget.admin.removeScopedAdminMemberAccess(
        dedaPhone: widget.dedaPhone, targetUid: id, reason: reason,
      );
      if (mounted) { _refresh(); ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(t('أُزيل وصول الإدارة فقط.', 'Admin access removed.')))); }
    } catch (_) {
      if (mounted) { _refresh(); ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(t('تعذرت الإزالة: لم يثبت ربط الموظف وبوابة الهاتف.',
          'Removal denied: staff gateway binding unverified.')))); }
    } finally { if (mounted) setState(() => _mutating = false); }
  }

  Future<void> _resetMemberPassword(Map<String, dynamic> member) async {
    if (_mutating || widget.collection != 'admins') return;
    final id = (member['id'] ?? '').toString();
    if (!DedaIsolatedAdminProofPolicy.validScopedDocumentId(id)) return;
    final confirm = await showDialog<bool>(context: context,
      builder: (dialog) => AlertDialog(
        title: Text(t('إعادة تعيين كلمة المرور', 'Password reset')),
        content: Text(t('إرسال رابط إعادة تعيين إلى البريد الموثق لهذا الموظف؟',
          'Send a password reset link to the verified staff email?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false),
            child: Text(t('إلغاء', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(dialog, true),
            child: Text(t('طلب الرابط', 'Request link'))),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => _mutating = true);
    try {
      await widget.admin.requestScopedMemberPasswordReset(
        dedaPhone: widget.dedaPhone, targetUid: id,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(t('طُلب رابط إعادة التعيين.', 'Reset email requested.')),
        ));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(t('تعذر الطلب. راجع تخويل الإدارة والاتصال.',
            'Password reset denied; verify authorization and connection.')),
        ));
      }
    } finally { if (mounted) setState(() => _mutating = false); }
  }

  Future<void> _shareInvitation(Map<String, dynamic> invitation) async {
    if (_mutating || widget.collection != 'admin_invites') return;
    final id = (invitation['id'] ?? '').toString();
    if (!DedaIsolatedAdminProofPolicy.validScopedDocumentId(id)) return;
    setState(() => _mutating = true);
    try {
      final live = await widget.admin.readScopedAdminRecord(
        dedaPhone: widget.dedaPhone, collection: 'admin_invites', recordId: id,
      );
      final expiry = live?['expiresAt'];
      if (live == null || live['status'] != 'pending' ||
          (live['claimedUid'] ?? '').toString().trim().isNotEmpty ||
          expiry is! Timestamp || !expiry.toDate().isAfter(DateTime.now()) ||
          !RegExp(r'^[0-9]{8}$').hasMatch(
            (live['activationCode'] ?? '').toString())) {
        throw StateError('deda-admin-invitation-share-denied');
      }
      final email = (live['email'] ?? '').toString().trim();
      final msg = t(
        'دعوة إدارية إلى DEDA\n'
        'البريد: $email\n'
        'معرّف الدعوة: $id\n'
        'الرقم الإداري: ${live['adminId']}\n'
        'رمز التفعيل: ${live['activationCode']}\n'
        'من دخول الإدارة اختر تفعيل الدعوة. لا تشارك الرمز مع شخص آخر.',
        'DEDA administration invitation\n'
        'Email: $email\n'
        'Invitation ID: $id\n'
        'Admin ID: ${live['adminId']}\n'
        'Activation code: ${live['activationCode']}\n'
        'Choose Activate invitation from admin sign-in. Keep code private.',
      );
      if (!mounted) return;
      final action = await showDialog<String>(context: context,
        builder: (dialog) => AlertDialog(
          title: Text(t('مشاركة الدعوة', 'Share invitation')),
          content: Text(t('لصاحب البريد المقصود فقط. فتح البريد لا يثبت الإرسال.',
            'Share only with intended recipient; opening mail does not prove delivery.')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialog),
              child: Text(t('إلغاء', 'Cancel'))),
            TextButton(onPressed: () => Navigator.pop(dialog, 'copy'),
              child: Text(t('نسخ', 'Copy'))),
            FilledButton(onPressed: () => Navigator.pop(dialog, 'email_draft'),
              child: Text(t('فتح البريد', 'Open email'))),
          ],
        ),
      );
      if (action == null || !mounted) return;
      if (action == 'copy') {
        await Clipboard.setData(ClipboardData(text: msg));
      } else if (action == 'email_draft') {
        final uri = Uri(scheme: 'mailto', path: email, queryParameters: {
          'subject': t('دعوة إدارية إلى DEDA', 'DEDA admin invitation'),
          'body': msg,
        });
        if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
          throw StateError('deda-admin-mail-not-available');
        }
      } else { return; }
      await widget.admin.markScopedAdminInvitationShared(
        dedaPhone: widget.dedaPhone, inviteId: id, channel: action,
      );
      if (mounted) { _refresh(); ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(t(
          action == 'copy' ? 'نُسخت الدعوة.' : 'فُتحت مسودة البريد.',
          action == 'copy' ? 'Invitation copied.' : 'Email draft opened.',
        )))); }
    } catch (_) {
      if (mounted) { _refresh(); ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(t('تعذرت المشاركة: تحقق من صلاحية الدعوة.',
          'Share denied: verify invitation and authorization.')))); }
    } finally { if (mounted) setState(() => _mutating = false); }
  }

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
    final invite = widget.collection == 'admin_invites';
    final title = (team || invite)
        ? (data['displayName'] ?? data['name'] ?? '').toString()
        : user ? (data['name'] ?? '').toString()
            : (data['action'] ?? '').toString();
    final subtitle = (team || invite)
        ? (data['email'] ?? '').toString()
        : user ? (data['phone'] ?? '').toString()
            : (data['adminName'] ?? '').toString();
    final detail = team ? (data['role'] ?? '').toString()
        : invite ? (data['status'] ?? '').toString()
        : user ? (data['accountType'] ?? '').toString()
        : _timestamp(data['createdAt']);
    final subordinate = const <String>{
      'deputy_manager', 'employee', 'province_agent',
    }.contains((data['role'] ?? '').toString().trim().toLowerCase());
    final canSuspend = team && data['active'] == true && subordinate;
    final canCancel = invite && data['status'] == 'pending' && subordinate;
    return Card(
      child: ListTile(
        title: Text(title.isEmpty ? '—' : title),
        subtitle: Text(subtitle),
        trailing: (team && subordinate) || canCancel
            ? PopupMenuButton<String>(
                enabled: !_mutating,
                tooltip: t('إجراءات الإدارة', 'Administration actions'),
                itemBuilder: (_) => [
                  if (team) PopupMenuItem(value: 'edit',
                    child: Text(t('تعديل', 'Edit'))),
                  if (canSuspend) PopupMenuItem(value: 'suspend',
                    child: Text(t('تعليق', 'Suspend'))),
                  if (team) PopupMenuItem(value: 'reset',
                    child: Text(t('رابط كلمة المرور', 'Password reset'))),
                  if (team) PopupMenuItem(value: 'remove',
                    child: Text(t('إزالة الوصول', 'Remove access'))),
                  if (canCancel) PopupMenuItem(value: 'share',
                    child: Text(t('مشاركة', 'Share'))),
                  if (canCancel) PopupMenuItem(value: 'cancel',
                    child: Text(t('إلغاء الدعوة', 'Cancel invitation'))),
                ],
                onSelected: (action) {
                  switch (action) {
                    case 'edit': _editMember(data); break;
                    case 'suspend': _suspendMember(data); break;
                    case 'reset': _resetMemberPassword(data); break;
                    case 'remove': _removeMemberAccess(data); break;
                    case 'share': _shareInvitation(data); break;
                    case 'cancel': _cancelInvitation(data); break;
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(detail), const Icon(Icons.more_vert),
                  ]),
                ),
              )
            : Text(detail),
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
              child: Wrap(
                spacing: 8,
                children: [
                  if (widget.collection == 'admin_invites')
                    FilledButton.icon(
                      onPressed: _mutating ? null : _createInvitation,
                      icon: const Icon(Icons.person_add_alt_1_outlined),
                      label: Text(t('دعوة موظف', 'Invite staff')),
                    ),
                  TextButton.icon(
                    onPressed: _mutating ? null : _refresh,
                    icon: const Icon(Icons.refresh),
                    label: Text(t('تحديث من الخادم', 'Refresh from server')),
                  ),
                ],
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
  late Future<DedaIsolatedManagerPage> _page;
  QueryDocumentSnapshot<Map<String, dynamic>>? _pageStart;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>?> _back = [];
  bool _mutating = false;

  String t(String ar, String en) => widget.isArabic ? ar : en;

  bool get _isArchive => widget.sourceCollection != 'published_places';

  String get _targetCollection =>
      widget.sourceCollection == 'admin_trash_place_requests'
          ? 'place_requests' : 'published_places';

  @override
  void initState() {
    super.initState();
    _page = _fetch();
  }

  Future<DedaIsolatedManagerPage> _fetch() =>
      widget.admin.readScopedManagerPage(
        dedaPhone: widget.dedaPhone,
        collection: widget.sourceCollection,
        startAfter: _pageStart,
        pageSize: 50,
      );

  void _refresh() => setState(() {
    _pageStart = null;
    _back.clear();
    _page = _fetch();
  });

  void _next(DedaIsolatedManagerPage page) {
    if (_mutating || page.nextCursor == null) return;
    setState(() {
      _back.add(_pageStart);
      _pageStart = page.nextCursor;
      _page = _fetch();
    });
  }

  void _previous() {
    if (_mutating || _back.isEmpty) return;
    setState(() {
      _pageStart = _back.removeLast();
      _page = _fetch();
    });
  }

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
                  : action == 'hide'
                      ? t('إخفاء المكان عن الخارطة', 'Hide place from map')
                      : action == 'show'
                          ? t('إظهار المكان مجدداً', 'Show place again')
                          : t('نقل إلى محذوفات المدير العام',
                              'Move to general-manager trash')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text("${t('المعرّف', 'Record ID')}: $id"),
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
      if (action == 'hide' || action == 'show') {
        if (_isArchive) {
          throw StateError('deda-admin-visibility-source-invalid');
        }
        await widget.admin.setScopedPublishedVisibility(
          dedaPhone: widget.dedaPhone,
          placeId: id,
          hide: action == 'hide',
        );
      } else {
        await widget.admin.mutateScopedPlaceArchive(
          dedaPhone: widget.dedaPhone,
          sourceCollection: _targetCollection,
          recordId: id,
          action: action,
          permanentConfirmation: action == 'permanent' ? confirmation : null,
        );
      }
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
    final published = data['published'] == true;
    final managerHidden = data['hiddenByManager'] == true;
    final canRestoreHidden = !published && managerHidden &&
        data['hiddenAt'] is Timestamp &&
        (data['hiddenByUid'] ?? '').toString().trim().isNotEmpty;
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
            if (!_isArchive && !published)
              Text(managerHidden
                  ? t('مخفي بواسطة الإدارة', 'Hidden by administration')
                  : t('غير منشور', 'Not published')),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (!_isArchive && published && !managerHidden)
                OutlinedButton.icon(
                  onPressed: _mutating ? null : () => _mutate(id, 'hide'),
                  icon: const Icon(Icons.visibility_off_outlined),
                  label: Text(t('إخفاء المكان', 'Hide place')),
                ),
              if (!_isArchive && canRestoreHidden)
                OutlinedButton.icon(
                  onPressed: _mutating ? null : () => _mutate(id, 'show'),
                  icon: const Icon(Icons.visibility_outlined),
                  label: Text(t('إظهار المكان', 'Restore visibility')),
                ),
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
    return FutureBuilder<DedaIsolatedManagerPage>(
      future: _page,
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
        final page = snapshot.data!;
        final rows = page.rows;
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(children: [
              Text("${t('صفحة', 'Page')} ${_back.length + 1}"),
              const Spacer(),
              TextButton.icon(
                onPressed: !_mutating && _back.isNotEmpty
                    ? _previous : null,
                icon: const Icon(Icons.chevron_left),
                label: Text(t('السابق', 'Previous')),
              ),
              TextButton.icon(
                onPressed: !_mutating && page.nextCursor != null
                    ? () => _next(page) : null,
                icon: const Icon(Icons.chevron_right),
                label: Text(t('التالي', 'Next')),
              ),
            ]),
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
  late Stream<QuerySnapshot<Map<String, dynamic>>> _stream;
  QueryDocumentSnapshot<Map<String, dynamic>>? _pageStart;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>?> _back = [];
  int _pageEpoch = 0;
  bool _sending = false;

  String t(String ar, String en) => widget.isArabic ? ar : en;

  @override
  void initState() {
    super.initState();
    _stream = _watchPage();
  }

  // Keep live server-confirmed updates for every page. The 51st result is
  // ONLY a pagination sentinel; it is never displayed as a request card.
  Stream<QuerySnapshot<Map<String, dynamic>>> _watchPage() =>
      widget.admin.watchScopedAdminRequests(
        dedaPhone: widget.dedaPhone,
        collection: widget.collection,
        maxItems: 51,
        startAfter: _pageStart,
      );

  void _nextPage(QuerySnapshot<Map<String, dynamic>> snapshot) {
    if (_sending || snapshot.docs.length <= 50) return;
    final cursor = snapshot.docs[49];
    if (cursor.metadata.isFromCache || cursor.metadata.hasPendingWrites) return;
    setState(() {
      _back.add(_pageStart);
      _pageStart = cursor;
      _pageEpoch++;
      _stream = _watchPage();
    });
  }

  void _previousPage() {
    if (_sending || _back.isEmpty) return;
    setState(() {
      _pageStart = _back.removeLast();
      _pageEpoch++;
      _stream = _watchPage();
    });
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
        content: Text("${t('تأكيد نقل الطلب إلى المحذوفات؟',
            'Move this request to recoverable trash?')}\n$id"),
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
      // Prevent the previous page's privileged rows from remaining visible
      // while the new page is still waiting for fresh server authorization.
      key: ValueKey(_pageEpoch),
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
        final serverPage = snapshot.data!;
        final records = serverPage.docs.take(50).toList(growable: false);
        final hasNext = serverPage.docs.length > 50;
        return Column(children: [
          Expanded(
            child: records.isEmpty
                ? Center(child: Text(t('لا توجد طلبات.', 'No requests.')))
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: records.length,
                    itemBuilder: (context, index) => _request(records[index]),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 12, vertical: 6,
            ),
            child: Row(children: [
              Text("${t('صفحة', 'Page')} ${_back.length + 1}"),
              const Spacer(),
              TextButton.icon(
                onPressed: !_sending && _back.isNotEmpty
                    ? _previousPage : null,
                icon: const Icon(Icons.chevron_left),
                label: Text(t('السابق', 'Previous')),
              ),
              TextButton.icon(
                onPressed: !_sending && hasNext
                    ? () => _nextPage(serverPage) : null,
                icon: const Icon(Icons.chevron_right),
                label: Text(t('التالي', 'Next')),
              ),
            ]),
          ),
        ]);
      },
    );
  }
}
