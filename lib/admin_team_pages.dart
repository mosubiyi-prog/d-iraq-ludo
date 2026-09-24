import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'deda_backend.dart';

const List<String> dedaAdminGovernorates = <String>[
  'بغداد',
  'البصرة',
  'نينوى',
  'أربيل',
  'النجف',
  'كربلاء',
  'كركوك',
  'الأنبار',
  'بابل',
  'ديالى',
  'ذي قار',
  'صلاح الدين',
  'واسط',
  'ميسان',
  'المثنى',
  'الديوانية',
  'دهوك',
  'السليمانية',
  'حلبجة',
];

const List<String> dedaAdminPermissionKeys = <String>[
  'supportRead',
  'supportReply',
  'viewPlaceRequests',
  'reviewPlaceRequests',
  'approvePlaces',
  'rejectPlaces',
  'viewUsers',
  'viewReports',
  'manageReports',
  'viewGovernorates',
  'viewAudit',
];

String dedaAdminRoleLabel(bool ar, dynamic value) {
  switch (DedaBackend.normalizeAdminRole(value)) {
    case 'general_manager':
      return ar ? 'المدير العام' : 'General manager';
    case 'deputy_manager':
      return ar ? 'معاون المدير' : 'Deputy manager';
    case 'province_agent':
      return ar ? 'وكيل محافظة' : 'Province agent';
    case 'employee':
      return ar ? 'موظف' : 'Employee';
    default:
      return value?.toString() ?? '';
  }
}

String dedaAdminStatusLabel(bool ar, String value) {
  switch (value) {
    case 'active':
      return ar ? 'نشط' : 'Active';
    case 'temporarily_stopped':
      return ar ? 'متوقف مؤقتًا' : 'Temporarily stopped';
    case 'disabled':
      return ar ? 'معطّل' : 'Disabled';
    default:
      return value;
  }
}

String dedaAdminTimestamp(dynamic value) {
  DateTime? date;
  if (value is Timestamp) date = value.toDate();
  if (value is DateTime) date = value;
  if (date == null) return '—';
  final local = date.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)}/${local.year} '
      '${two(local.hour)}:${two(local.minute)}';
}

Map<String, bool> dedaDefaultAdminPermissions(String role) {
  final values = <String, bool>{
    for (final key in dedaAdminPermissionKeys) key: false,
  };
  if (role == 'general_manager' || role == 'deputy_manager') {
    for (final key in dedaAdminPermissionKeys) values[key] = true;
  } else if (role == 'province_agent') {
    values['viewPlaceRequests'] = true;
    values['reviewPlaceRequests'] = true;
    values['viewReports'] = false;
    values['viewGovernorates'] = true;
  }
  if (role == 'province_agent') {
    values['supportRead'] = false;
    values['supportReply'] = false;
    values['viewUsers'] = false;
    values['viewAudit'] = false;
    values['manageReports'] = false;
  }
  return values;
}

String dedaPermissionLabel(bool ar, String key) {
  const arLabels = <String, String>{
    'supportRead': 'مشاهدة رسائل الدعم',
    'supportReply': 'الرد على الدعم وتغيير حالته',
    'viewPlaceRequests': 'مشاهدة طلبات الأماكن',
    'reviewPlaceRequests': 'بدء المراجعة وطلب التعديل',
    'approvePlaces': 'اعتماد الأماكن',
    'rejectPlaces': 'رفض طلبات الأماكن',
    'viewUsers': 'مشاهدة حسابات المستخدمين • قراءة فقط',
    'viewReports': 'مشاهدة البلاغات والتقارير',
    'manageReports': 'إدارة البلاغات',
    'viewGovernorates': 'مشاهدة قسم المحافظات',
    'viewAudit': 'مشاهدة السجل الإداري',
  };
  const enLabels = <String, String>{
    'supportRead': 'View support messages',
    'supportReply': 'Reply to support and change status',
    'viewPlaceRequests': 'View place requests',
    'reviewPlaceRequests': 'Review and request changes',
    'approvePlaces': 'Approve places',
    'rejectPlaces': 'Reject place requests',
    'viewUsers': 'View user accounts • read only',
    'viewReports': 'View reports and analytics',
    'manageReports': 'Manage reports',
    'viewGovernorates': 'View governorates section',
    'viewAudit': 'View administrative audit log',
  };
  return (ar ? arLabels : enLabels)[key] ?? key;
}

String dedaFriendlyAdminError(bool ar, Object error) {
  final raw = error.toString();
  if (raw.contains('last-general-manager')) {
    return ar
        ? 'لا يمكن تنفيذ العملية لأنها ستترك DEDA بدون مدير عام نشط.'
        : 'This action would leave DEDA without an active general manager.';
  }
  if (raw.contains('cannot-stop-current-session')) {
    return ar
        ? 'لا يمكنك إيقاف حسابك الإداري الحالي من نفس الجلسة.'
        : 'You cannot stop your current admin account from this session.';
  }
  if (raw.contains('cannot-delete-current-admin')) {
    return ar
        ? 'لا يمكنك حذف حسابك الإداري الحالي.'
        : 'You cannot delete your current admin account.';
  }
  if (raw.contains('email-already-exists')) {
    return ar ? 'هذا البريد مستخدم بالفعل.' : 'This email is already in use.';
  }
  if (raw.contains('invite-already-exists')) {
    return ar
        ? 'توجد دعوة إدارية معلقة لهذا البريد بالفعل.'
        : 'There is already a pending admin invitation for this email.';
  }
  if (raw.contains('cannot-change-current-admin-access')) {
    return ar
        ? 'لا يمكنك تغيير دور أو حالة حسابك الإداري الحالي من نفس الجلسة.'
        : 'You cannot change the role or status of your current admin account from this session.';
  }
  if (raw.contains('reason-required')) {
    return ar ? 'اكتب سبب الإجراء أولًا.' : 'Enter a reason for this action.';
  }
  if (raw.contains('governorate-required')) {
    return ar
        ? 'اختيار المحافظة إلزامي لوكيل المحافظة.'
        : 'Province is required for a province agent.';
  }
  if (raw.contains('general-manager-required')) {
    return ar
        ? 'هذه العملية للمدير العام فقط.'
        : 'Only the general manager can do this.';
  }
  return ar
      ? 'تعذر تنفيذ العملية. تحقق من الاتصال وحاول مجددًا.'
      : 'The action could not be completed. Check the connection and try again.';
}

class DedaAdminTeamPage extends StatefulWidget {
  final bool isArabic;
  final Map<String, dynamic> currentAdmin;

  const DedaAdminTeamPage({
    super.key,
    required this.isArabic,
    required this.currentAdmin,
  });

  @override
  State<DedaAdminTeamPage> createState() => _DedaAdminTeamPageState();
}

class _DedaAdminTeamPageState extends State<DedaAdminTeamPage> {
  final _search = TextEditingController();
  String _roleFilter = 'all';
  String _statusFilter = 'all';
  String _governorateFilter = 'all';

  bool get ar => widget.isArabic;
  String t(String a, String e) => ar ? a : e;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _openEditor([Map<String, dynamic>? member]) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DedaAdminMemberEditorPage(
          isArabic: ar,
          currentAdmin: widget.currentAdmin,
          member: member,
        ),
      ),
    );
  }

  Widget _filterMenu({
    required String value,
    required IconData icon,
    required String label,
    required Map<String, String> items,
    required ValueChanged<String> onChanged,
  }) {
    return PopupMenuButton<String>(
      initialValue: value,
      onSelected: onChanged,
      itemBuilder: (_) => items.entries
          .map(
            (entry) => PopupMenuItem<String>(
              value: entry.key,
              child: Text(entry.value),
            ),
          )
          .toList(),
      child: Chip(
        avatar: Icon(icon, size: 18),
        label: Text('$label: ' + (items[value] ?? '')),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF2),
      appBar: AppBar(
        title: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Text(t('إدارة الفريق والصلاحيات', 'Team & permissions')),
        ),
        actions: [
          IconButton(
            tooltip: t('الدعوات الإدارية', 'Admin invitations'),
            icon: const Icon(Icons.mark_email_unread_outlined),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => DedaAdminInvitationsPage(isArabic: ar),
                ),
              );
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.person_add_alt_1),
        label: Text(t('إضافة عضو', 'Add member')),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: DedaBackend.adminMembers(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text(t('تعذر تحميل الفريق.', 'Could not load team.')),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final all = snapshot.data!.docs.map((doc) {
            final data = <String, dynamic>{'uid': doc.id, ...doc.data()};
            if (doc.id == widget.currentAdmin['uid']?.toString()) {
              for (final key in ['displayName', 'email', 'adminId', 'phone']) {
                final currentValue = (data[key] ?? '').toString().trim();
                final resolvedValue =
                    (widget.currentAdmin[key] ?? '').toString().trim();
                if (currentValue.isEmpty && resolvedValue.isNotEmpty) {
                  data[key] = resolvedValue;
                }
              }
            }
            data['roleNormalized'] = DedaBackend.normalizeAdminRole(
              data['role'] ?? data['jobTitle'],
            );
            data['statusNormalized'] = DedaBackend.normalizeAdminStatus(data);
            return data;
          }).toList()
            ..sort(
              (a, b) => (a['displayName'] ?? a['name'] ?? a['email'] ?? '')
                  .toString()
                  .compareTo(
                    (b['displayName'] ?? b['name'] ?? b['email'] ?? '')
                        .toString(),
                  ),
            );

          final query = _search.text.trim().toLowerCase();
          final visible = all.where((member) {
            final haystack =
                ((member['displayName'] ?? member['name'] ?? '').toString() +
                        ' ' +
                        (member['email'] ?? '').toString() +
                        ' ' +
                        (member['adminId'] ?? '').toString())
                    .toLowerCase();
            if (query.isNotEmpty && !haystack.contains(query)) return false;
            if (_roleFilter != 'all' &&
                member['roleNormalized'] != _roleFilter) {
              return false;
            }
            if (_statusFilter != 'all' &&
                member['statusNormalized'] != _statusFilter) {
              return false;
            }
            if (_governorateFilter != 'all' &&
                (member['governorate'] ?? '').toString() !=
                    _governorateFilter) {
              return false;
            }
            return true;
          }).toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                child: TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: t(
                      'بحث بالاسم أو البريد أو الرقم الإداري',
                      'Search name, email or admin ID',
                    ),
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _filterMenu(
                      value: _roleFilter,
                      icon: Icons.badge_outlined,
                      label: t('الدور', 'Role'),
                      items: <String, String>{
                        'all': t('الكل', 'All'),
                        'general_manager':
                            t('مدير عام', 'General manager'),
                        'deputy_manager':
                            t('معاون مدير', 'Deputy manager'),
                        'employee': t('موظف', 'Employee'),
                        'province_agent':
                            t('وكيل محافظة', 'Province agent'),
                      },
                      onChanged: (value) =>
                          setState(() => _roleFilter = value),
                    ),
                    _filterMenu(
                      value: _statusFilter,
                      icon: Icons.toggle_on_outlined,
                      label: t('الحالة', 'Status'),
                      items: <String, String>{
                        'all': t('الكل', 'All'),
                        'active': t('نشط', 'Active'),
                        'temporarily_stopped':
                            t('متوقف مؤقتًا', 'Temporarily stopped'),
                        'disabled': t('معطّل', 'Disabled'),
                      },
                      onChanged: (value) =>
                          setState(() => _statusFilter = value),
                    ),
                    _filterMenu(
                      value: _governorateFilter,
                      icon: Icons.location_on_outlined,
                      label: t('المحافظة', 'Province'),
                      items: <String, String>{
                        'all': t('الكل', 'All'),
                        for (final item in dedaAdminGovernorates) item: item,
                      },
                      onChanged: (value) =>
                          setState(() => _governorateFilter = value),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: visible.isEmpty
                    ? Center(
                        child: Text(t('لا توجد نتائج.', 'No results.')),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 90),
                        itemCount: visible.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final member = visible[index];
                          final status =
                              member['statusNormalized'].toString();
                          final active = status == 'active';
                          return Card(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.all(14),
                              onTap: () => _openEditor(member),
                              leading: CircleAvatar(
                                backgroundColor: active
                                    ? const Color(0xFFDDEEDD)
                                    : const Color(0xFFE7E7E7),
                                child: Icon(
                                  Icons.person_outline,
                                  color: active
                                      ? const Color(0xFF17652F)
                                      : Colors.grey,
                                ),
                              ),
                              title: Builder(
                                builder: (context) {
                                  final title =
                                      (member['displayName'] ??
                                              member['name'] ??
                                              member['email'] ??
                                              t(
                                                'عضو إداري',
                                                'Admin member',
                                              ))
                                          .toString()
                                          .trim();
                                  final isEmail = title.contains('@');
                                  return Directionality(
                                    textDirection: isEmail
                                        ? TextDirection.ltr
                                        : Directionality.of(context),
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      alignment:
                                          AlignmentDirectional.centerStart,
                                      child: Text(
                                        title,
                                        maxLines: 1,
                                        softWrap: false,
                                        overflow: TextOverflow.visible,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 5),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      dedaAdminRoleLabel(
                                        ar,
                                        member['roleNormalized'],
                                      ),
                                    ),
                                    if ((member['department'] ?? '')
                                        .toString()
                                        .trim()
                                        .isNotEmpty)
                                      Text(
                                        t('القسم: ', 'Department: ') +
                                            member['department'].toString(),
                                      ),
                                    if ((member['governorate'] ?? '')
                                        .toString()
                                        .trim()
                                        .isNotEmpty)
                                      Text(
                                        t('المحافظة: ', 'Province: ') +
                                            member['governorate'].toString(),
                                      ),
                                    Text(
                                      t('آخر دخول: ', 'Last sign-in: ') +
                                          dedaAdminTimestamp(
                                            member['lastLoginAt'] ??
                                                member['lastSeenAt'],
                                          ),
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: active
                                      ? const Color(0xFFDFF0E0)
                                      : const Color(0xFFECECEC),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  dedaAdminStatusLabel(ar, status),
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: active
                                        ? const Color(0xFF17652F)
                                        : const Color(0xFF5F6368),
                                  ),
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


class DedaAdminInvitationsPage extends StatelessWidget {
  final bool isArabic;

  const DedaAdminInvitationsPage({
    super.key,
    required this.isArabic,
  });

  String t(String a, String e) => isArabic ? a : e;

  String _statusLabel(String value) {
    switch (value) {
      case 'pending':
        return t('بانتظار التفعيل', 'Pending activation');
      case 'claimed':
        return t('جارٍ التفعيل', 'Activation in progress');
      case 'completed':
        return t('مفعّلة', 'Activated');
      default:
        return value;
    }
  }

  String _inviteMessage(
    String inviteId,
    Map<String, dynamic> data,
  ) {
    final email = (data['email'] ?? '').toString();
    final code = (data['activationCode'] ?? '').toString();
    final adminId = (data['adminId'] ?? '').toString();
    final expiry = dedaAdminTimestamp(data['expiresAt']);
    return t(
      'دعوة إدارية إلى DEDA - الدليل الدقيق\n\n'
      'البريد: $email\n'
      'معرّف الدعوة: $inviteId\n'
      'رمز التفعيل: $code\n'
      'الرقم الإداري: $adminId\n'
      'تنتهي الصلاحية: $expiry\n\n'
      'من شاشة دخول الإدارة اختر «تفعيل دعوة إدارية»، ثم أدخل هذه البيانات وحدد كلمة مرور خاصة بك.\n'
      'لا تشارك رمز التفعيل مع أي شخص آخر.',
      'DEDA administration invitation\n\n'
      'Email: $email\n'
      'Invitation ID: $inviteId\n'
      'Activation code: $code\n'
      'Admin ID: $adminId\n'
      'Expires: $expiry\n\n'
      'From admin sign-in choose “Activate admin invitation”, enter these details, then create your own password.\n'
      'Do not share the activation code with anyone else.',
    );
  }

  Future<void> _sendInvite(
    BuildContext context,
    String inviteId,
    Map<String, dynamic> data,
  ) async {
    final email = (data['email'] ?? '').toString().trim();
    final code = (data['activationCode'] ?? '').toString().trim();
    if (email.isEmpty || code.isEmpty) return;

    final uri = Uri(
      scheme: 'mailto',
      path: email,
      queryParameters: <String, String>{
        'subject': t(
          'دعوة إدارية إلى DEDA',
          'DEDA administration invitation',
        ),
        'body': _inviteMessage(inviteId, data),
      },
    );

    try {
      final opened = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!opened) {
        await Clipboard.setData(
          ClipboardData(text: _inviteMessage(inviteId, data)),
        );
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              t(
                'تعذر فتح البريد. تم نسخ الدعوة للمشاركة اليدوية.',
                'Could not open mail. The invitation was copied for manual sharing.',
              ),
            ),
          ),
        );
        await DedaBackend.markAdminInvitationShared(
          inviteId: inviteId,
          channel: 'copy_fallback',
        );
        return;
      }
      await DedaBackend.markAdminInvitationShared(
        inviteId: inviteId,
        channel: 'email_draft',
      );
    } catch (_) {
      await Clipboard.setData(
        ClipboardData(text: _inviteMessage(inviteId, data)),
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            t(
              'تعذر فتح البريد. تم نسخ الدعوة للمشاركة اليدوية.',
              'Could not open mail. The invitation was copied for manual sharing.',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _copyInvite(
    BuildContext context,
    String inviteId,
    Map<String, dynamic> data,
  ) async {
    await Clipboard.setData(
      ClipboardData(text: _inviteMessage(inviteId, data)),
    );
    try {
      await DedaBackend.markAdminInvitationShared(
        inviteId: inviteId,
        channel: 'copy',
      );
    } catch (_) {}
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          t(
            'تم نسخ الدعوة للمشاركة.',
            'Invitation copied for sharing.',
          ),
        ),
      ),
    );
  }

  Future<void> _showInvite(
    BuildContext context,
    String inviteId,
    Map<String, dynamic> data,
  ) async {
    final code = (data['activationCode'] ?? '').toString();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(t('بيانات الدعوة الإدارية', 'Admin invitation details')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SelectableText(
                t('الاسم: ', 'Name: ') +
                    (data['displayName'] ?? '').toString(),
              ),
              const SizedBox(height: 7),
              SelectableText(
                t('البريد: ', 'Email: ') +
                    (data['email'] ?? '').toString(),
              ),
              const SizedBox(height: 7),
              Text(
                t('معرّف الدعوة:', 'Invitation ID:'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Directionality(
                textDirection: TextDirection.ltr,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: SelectableText(
                    inviteId,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                    ),
                  ),
                ),
              ),
              if (code.isNotEmpty) ...[
                const SizedBox(height: 7),
                SelectableText(
                  t('رمز التفعيل: ', 'Activation code: ') + code,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                  ),
                ),
              ],
              const SizedBox(height: 7),
              Text(
                t('الرقم الإداري:', 'Admin ID:'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Directionality(
                textDirection: TextDirection.ltr,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: SelectableText(
                    (data['adminId'] ?? '').toString(),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              const SizedBox(height: 7),
              Text(
                t('الحالة: ', 'Status: ') +
                    _statusLabel((data['status'] ?? '').toString()),
              ),
              const SizedBox(height: 7),
              Text(
                t('تنتهي: ', 'Expires: ') +
                    dedaAdminTimestamp(data['expiresAt']),
              ),
            ],
          ),
        ),
        actions: [
          if (code.isNotEmpty)
            TextButton.icon(
              onPressed: () => _copyInvite(
                context,
                inviteId,
                data,
              ),
              icon: const Icon(Icons.copy_all_outlined),
              label: Text(t('نسخ للمشاركة', 'Copy to share')),
            ),
          if (code.isNotEmpty)
            FilledButton.icon(
              onPressed: () => _sendInvite(
                context,
                inviteId,
                data,
              ),
              icon: const Icon(Icons.outgoing_mail),
              label: Text(t('إرسال الدعوة', 'Send invitation')),
            ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(t('تم', 'Done')),
          ),
        ],
      ),
    );
  }

  Future<void> _cancelInvite(
    BuildContext context,
    String inviteId,
    Map<String, dynamic> data,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(t('إلغاء الدعوة؟', 'Cancel invitation?')),
        content: Text(
          t(
            'سيتم إلغاء دعوة ${(data['displayName'] ?? data['email'] ?? '').toString()} ولن يمكن استخدامها بعد ذلك.',
            'The invitation for ${(data['displayName'] ?? data['email'] ?? '').toString()} will be cancelled and can no longer be used.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(t('رجوع', 'Back')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(t('إلغاء الدعوة', 'Cancel invitation')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await DedaBackend.cancelAdminInvitation(inviteId);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(t('تم إلغاء الدعوة.', 'Invitation cancelled.')),
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(dedaFriendlyAdminError(isArabic, error))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF2),
      appBar: AppBar(
        title: Text(t('الدعوات الإدارية', 'Admin invitations')),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: DedaBackend.adminInvitations(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text(
                t(
                  'تعذر تحميل الدعوات الإدارية.',
                  'Could not load admin invitations.',
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs.where((doc) {
            final status = (doc.data()['status'] ?? '').toString();
            return status == 'pending' || status == 'claimed';
          }).toList();

          if (docs.isEmpty) {
            return Center(
              child: Text(
                t(
                  'لا توجد دعوات معلقة.',
                  'There are no pending invitations.',
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data();
              final status = (data['status'] ?? '').toString();
              return Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(14),
                  onTap: () => _showInvite(context, doc.id, data),
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFE7F1E4),
                    child: Icon(
                      Icons.mail_outline,
                      color: Color(0xFF17652F),
                    ),
                  ),
                  title: Text(
                    (data['displayName'] ?? data['email'] ?? '').toString(),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (data['email'] ?? '').toString(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textDirection: TextDirection.ltr,
                        textAlign: TextAlign.left,
                      ),
                      Text(
                        dedaAdminRoleLabel(isArabic, data['role']) +
                            ' • ' +
                            _statusLabel(status),
                      ),
                      Text(
                        t('تنتهي: ', 'Expires: ') +
                            dedaAdminTimestamp(data['expiresAt']),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                  trailing: status == 'pending'
                      ? IconButton(
                          tooltip: t('إلغاء الدعوة', 'Cancel invitation'),
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () =>
                              _cancelInvite(context, doc.id, data),
                        )
                      : null,
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class DedaAdminMemberEditorPage extends StatefulWidget {
  final bool isArabic;
  final Map<String, dynamic> currentAdmin;
  final Map<String, dynamic>? member;

  const DedaAdminMemberEditorPage({
    super.key,
    required this.isArabic,
    required this.currentAdmin,
    this.member,
  });

  @override
  State<DedaAdminMemberEditorPage> createState() =>
      _DedaAdminMemberEditorPageState();
}

class _DedaAdminMemberEditorPageState
    extends State<DedaAdminMemberEditorPage> {
  late final TextEditingController _name;
  late final TextEditingController _email;
  late final TextEditingController _phone;
  late final TextEditingController _department;
  late final TextEditingController _reason;
  late String _role;
  late String _status;
  String _governorate = '';
  late Map<String, bool> _permissions;
  bool _saving = false;

  bool get ar => widget.isArabic;
  bool get editing => widget.member != null;
  String t(String a, String e) => ar ? a : e;

  @override
  void initState() {
    super.initState();
    final member = widget.member ?? const <String, dynamic>{};
    _name = TextEditingController(
      text: (member['displayName'] ?? member['name'] ?? '').toString(),
    );
    _email =
        TextEditingController(text: (member['email'] ?? '').toString());
    _phone =
        TextEditingController(text: (member['phone'] ?? '').toString());
    _department = TextEditingController(
      text: (member['department'] ?? '').toString(),
    );
    _reason = TextEditingController();
    _role = editing
        ? DedaBackend.normalizeAdminRole(
            member['role'] ?? member['jobTitle'],
          )
        : 'employee';
    _status =
        editing ? DedaBackend.normalizeAdminStatus(member) : 'active';
    _governorate = (member['governorate'] ?? '').toString();
    _permissions = dedaDefaultAdminPermissions(_role);
    final stored = member['permissions'];
    if (stored is Map) {
      for (final key in dedaAdminPermissionKeys) {
        if (stored.containsKey(key)) {
          _permissions[key] = stored[key] == true;
        }
      }
    }
    _enforceRolePermissions();
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _department.dispose();
    _reason.dispose();
    super.dispose();
  }

  void _enforceRolePermissions() {
    if (_role == 'general_manager') {
      for (final key in dedaAdminPermissionKeys) {
        _permissions[key] = true;
      }
    }
    if (_role == 'province_agent') {
      _permissions['supportRead'] = false;
      _permissions['supportReply'] = false;
      _permissions['viewUsers'] = false;
      _permissions['viewReports'] = false;
      _permissions['viewAudit'] = false;
      _permissions['manageReports'] = false;
    }
  }

  void _changeRole(String value) {
    setState(() {
      _role = value;
      _permissions = dedaDefaultAdminPermissions(value);
      if (value != 'province_agent') _governorate = '';
      _enforceRolePermissions();
    });
  }

  void _setPermission(String key, bool value) {
    setState(() {
      _permissions[key] = value;

      if (key == 'supportReply' && value) {
        _permissions['supportRead'] = true;
      }
      if (key == 'supportRead' && !value) {
        _permissions['supportReply'] = false;
      }

      if (<String>{
        'reviewPlaceRequests',
        'approvePlaces',
        'rejectPlaces',
      }.contains(key) && value) {
        _permissions['viewPlaceRequests'] = true;
      }
      if (key == 'viewPlaceRequests' && !value) {
        _permissions['reviewPlaceRequests'] = false;
        _permissions['approvePlaces'] = false;
        _permissions['rejectPlaces'] = false;
      }

      if (key == 'manageReports' && value) {
        _permissions['viewReports'] = true;
      }
      if (key == 'viewReports' && !value) {
        _permissions['manageReports'] = false;
      }

      _enforceRolePermissions();
    });
  }

  Future<String?> _askReason(String title) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          minLines: 2,
          maxLines: 5,
          decoration: InputDecoration(
            labelText: t('سبب الإجراء', 'Reason'),
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
            child: Text(t('تأكيد', 'Confirm')),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  String _invitationMessage(Map<String, dynamic> result) {
    final email = (result['email'] ?? '').toString();
    final inviteId = (result['inviteId'] ?? '').toString();
    final code = (result['activationCode'] ?? '').toString();
    final adminId = (result['adminId'] ?? '').toString();
    final expiresAt = result['expiresAt'];
    final expiry = dedaAdminTimestamp(expiresAt);
    return t(
      'دعوة إدارية إلى DEDA - الدليل الدقيق\n\n'
      'البريد: $email\n'
      'معرّف الدعوة: $inviteId\n'
      'رمز التفعيل: $code\n'
      'الرقم الإداري: $adminId\n'
      'تنتهي الصلاحية: $expiry\n\n'
      'من شاشة دخول الإدارة اختر «تفعيل دعوة إدارية»، ثم أدخل هذه البيانات وحدد كلمة مرور خاصة بك.\n'
      'لا تشارك رمز التفعيل مع أي شخص آخر.',
      'DEDA administration invitation\n\n'
      'Email: $email\n'
      'Invitation ID: $inviteId\n'
      'Activation code: $code\n'
      'Admin ID: $adminId\n'
      'Expires: $expiry\n\n'
      'From admin sign-in choose “Activate admin invitation”, enter these details, then create your own password.\n'
      'Do not share the activation code with anyone else.',
    );
  }

  Future<void> _sendInvitationEmail(Map<String, dynamic> result) async {
    final email = (result['email'] ?? '').toString().trim();
    final inviteId = (result['inviteId'] ?? '').toString().trim();
    if (email.isEmpty || inviteId.isEmpty) return;

    final uri = Uri(
      scheme: 'mailto',
      path: email,
      queryParameters: <String, String>{
        'subject': t(
          'دعوة إدارية إلى DEDA',
          'DEDA administration invitation',
        ),
        'body': _invitationMessage(result),
      },
    );

    try {
      final opened = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!opened) {
        await Clipboard.setData(
          ClipboardData(text: _invitationMessage(result)),
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              t(
                'تعذر فتح تطبيق البريد. تم نسخ الدعوة لتشاركها يدويًا.',
                'Could not open the mail app. The invitation was copied for manual sharing.',
              ),
            ),
          ),
        );
        try {
          await DedaBackend.markAdminInvitationShared(
            inviteId: inviteId,
            channel: 'copy_fallback',
          );
        } catch (_) {}
        return;
      }

      try {
        await DedaBackend.markAdminInvitationShared(
          inviteId: inviteId,
          channel: 'email_draft',
        );
      } catch (_) {}
    } catch (_) {
      await Clipboard.setData(
        ClipboardData(text: _invitationMessage(result)),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            t(
              'تعذر فتح تطبيق البريد. تم نسخ الدعوة لتشاركها يدويًا.',
              'Could not open the mail app. The invitation was copied for manual sharing.',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _copyInvitationForSharing(
    Map<String, dynamic> result,
  ) async {
    final inviteId = (result['inviteId'] ?? '').toString().trim();
    await Clipboard.setData(
      ClipboardData(text: _invitationMessage(result)),
    );
    if (inviteId.isNotEmpty) {
      await DedaBackend.markAdminInvitationShared(
        inviteId: inviteId,
        channel: 'copy',
      );
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          t(
            'تم نسخ الدعوة. يمكنك إرسالها عبر واتساب أو الرسائل أو أي تطبيق آخر.',
            'Invitation copied. You can send it through WhatsApp, messages, or another app.',
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final email = _email.text.trim();
    final department = _department.text.trim();
    if (name.isEmpty ||
        department.isEmpty ||
        (!editing && (email.isEmpty || !email.contains('@')))) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            t(
              'أكمل الاسم والبريد والقسم.',
              'Complete name, email and department.',
            ),
          ),
        ),
      );
      return;
    }
    if (_role == 'province_agent' && _governorate.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(t('اختر محافظة الوكيل.', 'Select the agent province.')),
        ),
      );
      return;
    }
    if (editing && _reason.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            t(
              'اكتب سبب التعديل حتى يُحفظ في السجل الإداري.',
              'Enter the reason so it is stored in the audit log.',
            ),
          ),
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      if (editing) {
        await DedaBackend.updateAdminMember(
          uid: widget.member!['uid'].toString(),
          displayName: name,
          phone: _phone.text,
          role: _role,
          department: department,
          governorate: _governorate,
          status: _status,
          permissions: _permissions,
          reason: _reason.text,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(t('تم حفظ التعديلات.', 'Changes saved.')),
          ),
        );
        Navigator.pop(context);
      } else {
        final result = await DedaBackend.createAdminInvitation(
          displayName: name,
          email: email,
          phone: _phone.text,
          role: _role,
          department: department,
          governorate: _governorate,
          permissions: _permissions,
        );
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            title: Text(
              t('تم إنشاء الدعوة الإدارية', 'Admin invitation created'),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    t(
                      'أرسل للعضو البريد ومعرّف الدعوة ورمز التفعيل. من شاشة دخول الإدارة يختار «تفعيل دعوة إدارية» ويحدد كلمة المرور بنفسه.',
                      'Send the member the email, invitation ID, and activation code. From admin sign-in they choose “Activate admin invitation” and set their own password.',
                    ),
                  ),
                  const SizedBox(height: 14),
                  SelectableText(
                    t('البريد: ', 'Email: ') +
                        (result['email'] ?? '').toString(),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    t('معرّف الدعوة:', 'Invitation ID:'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: SelectableText(
                        (result['inviteId'] ?? '').toString(),
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    t('رمز التفعيل: ', 'Activation code: ') +
                        (result['activationCode'] ?? '').toString(),
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 20,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    t('الرقم الإداري:', 'Admin ID:'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: SelectableText(
                        (result['adminId'] ?? '').toString(),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    t(
                      'صلاحية الدعوة 7 أيام. لا يتم إنشاء صلاحية إدارية فعلية إلا بعد التفعيل.',
                      'The invitation is valid for 7 days. Admin access is not created until activation.',
                    ),
                    style: const TextStyle(color: Color(0xFF5C665E)),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton.icon(
                onPressed: () => _copyInvitationForSharing(result),
                icon: const Icon(Icons.copy_all_outlined),
                label: Text(t('نسخ للمشاركة', 'Copy to share')),
              ),
              FilledButton.icon(
                onPressed: () => _sendInvitationEmail(result),
                icon: const Icon(Icons.outgoing_mail),
                label: Text(t('إرسال الدعوة', 'Send invitation')),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(t('تم', 'Done')),
              ),
            ],
          ),
        );
        if (mounted) Navigator.pop(context);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(dedaFriendlyAdminError(ar, error))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _revokeSessions() async {
    final reason = await _askReason(
      t(
        'إيقاف وصول العضو مؤقتًا',
        'Temporarily suspend member access',
      ),
    );
    if (reason == null) return;
    try {
      await DedaBackend.revokeAdminMemberSessions(
        uid: widget.member!['uid'].toString(),
        reason: reason,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            t(
              'تم إيقاف وصول العضو مؤقتًا.',
              'Member access was temporarily suspended.',
            ),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(dedaFriendlyAdminError(ar, error))),
      );
    }
  }

  Future<void> _sendPasswordResetEmail() async {
    final email = (widget.member?['email'] ?? '').toString().trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            t(
              'لا يوجد بريد إلكتروني لهذا العضو.',
              'This member has no email address.',
            ),
          ),
        ),
      );
      return;
    }
    try {
      await DedaBackend.sendAdminPasswordReset(email: email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            t(
              'تم إرسال رابط إعادة تعيين كلمة المرور إلى بريد العضو.',
              'A password reset link was sent to the member email.',
            ),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(dedaFriendlyAdminError(ar, error))),
      );
    }
  }

  Future<void> _deleteMember() async {
    final reason = await _askReason(
      t(
        'حذف العضو الإداري نهائيًا',
        'Delete admin member permanently',
      ),
    );
    if (reason == null) return;
    try {
      await DedaBackend.deleteAdminMember(
        uid: widget.member!['uid'].toString(),
        reason: reason,
      );
      if (!mounted) return;
      Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(dedaFriendlyAdminError(ar, error))),
      );
    }
  }

  Widget _metaRow(String label, dynamic value) {
    final text = value?.toString().trim() ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w700)),
          Expanded(child: Text(text.isEmpty ? '—' : text)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final member = widget.member;
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF2),
      appBar: AppBar(
        title: Text(
          editing
              ? t('تفاصيل العضو والصلاحيات', 'Member & permissions')
              : t('إضافة عضو إداري', 'Add admin member'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (editing)
            Card(
              color: const Color(0xFFF0F5EE),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _metaRow(
                      t('الرقم الإداري', 'Admin ID'),
                      member?['adminId'],
                    ),
                    _metaRow(t('البريد', 'Email'), member?['email']),
                    _metaRow(
                      t('تاريخ الإنشاء', 'Created'),
                      dedaAdminTimestamp(member?['createdAt']),
                    ),
                    _metaRow(
                      t('أضيف بواسطة', 'Created by'),
                      member?['createdByName'],
                    ),
                    _metaRow(
                      t('آخر دخول', 'Last sign-in'),
                      dedaAdminTimestamp(
                        member?['lastLoginAt'] ?? member?['lastSeenAt'],
                      ),
                    ),
                    _metaRow(
                      t(
                        'آخر تعديل للصلاحيات',
                        'Permissions updated',
                      ),
                      dedaAdminTimestamp(member?['permissionsUpdatedAt']),
                    ),
                    _metaRow(
                      t(
                        'عدّل الصلاحيات',
                        'Permissions updated by',
                      ),
                      member?['permissionsUpdatedByName'],
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 10),
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
            enabled: !editing,
            keyboardType: TextInputType.emailAddress,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(
              labelText: t('البريد الإلكتروني', 'Email'),
              prefixIcon: const Icon(Icons.email_outlined),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: t(
                'رقم الهاتف (اختياري)',
                'Phone (optional)',
              ),
              prefixIcon: const Icon(Icons.phone_outlined),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _department,
            decoration: InputDecoration(
              labelText: t('القسم', 'Department'),
              prefixIcon: const Icon(Icons.work_outline),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _role,
            decoration: InputDecoration(
              labelText: t('الدور', 'Role'),
              prefixIcon: const Icon(Icons.badge_outlined),
              border: const OutlineInputBorder(),
            ),
            items: [
              DropdownMenuItem(
                value: 'general_manager',
                child: Text(t('المدير العام', 'General manager')),
              ),
              DropdownMenuItem(
                value: 'deputy_manager',
                child: Text(t('معاون المدير', 'Deputy manager')),
              ),
              DropdownMenuItem(
                value: 'employee',
                child: Text(t('موظف', 'Employee')),
              ),
              DropdownMenuItem(
                value: 'province_agent',
                child: Text(t('وكيل محافظة', 'Province agent')),
              ),
            ],
            onChanged: _saving
                ? null
                : (value) {
                    if (value != null) _changeRole(value);
                  },
          ),
          if (_role == 'province_agent') ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _governorate.isEmpty ? null : _governorate,
              decoration: InputDecoration(
                labelText: t('المحافظة', 'Province'),
                prefixIcon: const Icon(Icons.location_on_outlined),
                border: const OutlineInputBorder(),
              ),
              items: dedaAdminGovernorates
                  .map(
                    (item) => DropdownMenuItem<String>(
                      value: item,
                      child: Text(item),
                    ),
                  )
                  .toList(),
              onChanged: _saving
                  ? null
                  : (value) =>
                      setState(() => _governorate = value ?? ''),
            ),
          ],
          if (editing) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _status,
              decoration: InputDecoration(
                labelText: t('حالة الحساب', 'Account status'),
                prefixIcon: const Icon(Icons.toggle_on_outlined),
                border: const OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem(
                  value: 'active',
                  child: Text(t('نشط', 'Active')),
                ),
                DropdownMenuItem(
                  value: 'temporarily_stopped',
                  child:
                      Text(t('متوقف مؤقتًا', 'Temporarily stopped')),
                ),
                DropdownMenuItem(
                  value: 'disabled',
                  child: Text(t('معطّل', 'Disabled')),
                ),
              ],
              onChanged: _saving
                  ? null
                  : (value) =>
                      setState(() => _status = value ?? 'active'),
            ),
          ],
          const SizedBox(height: 18),
          Text(
            t('الصلاحيات الفردية', 'Individual permissions'),
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _role == 'general_manager'
                ? t(
                    'المدير العام يملك جميع الصلاحيات تلقائيًا.',
                    'The general manager automatically has all permissions.',
                  )
                : _role == 'province_agent'
                    ? t(
                        'وكيل المحافظة مقيد بمحافظته، وبعض الصلاحيات العامة معطلة لحماية البيانات.',
                        'The province agent is restricted to the assigned province; global permissions are disabled.',
                      )
                    : t(
                        'فعّل فقط ما يحتاجه هذا العضو لعمله.',
                        'Enable only what this member needs.',
                      ),
            style: const TextStyle(color: Color(0xFF5C665E)),
          ),
          const SizedBox(height: 8),
          ...dedaAdminPermissionKeys.map((key) {
            final locked = _role == 'general_manager' ||
                (_role == 'province_agent' &&
                    <String>{
                      'supportRead',
                      'supportReply',
                      'viewUsers',
                      'viewAudit',
                      'manageReports',
                    }.contains(key));
            return Card(
              elevation: 0,
              child: SwitchListTile(
                value: _permissions[key] == true,
                onChanged: locked || _saving
                    ? null
                    : (value) => _setPermission(key, value),
                title: Text(dedaPermissionLabel(ar, key)),
              ),
            );
          }),
          if (editing) ...[
            const SizedBox(height: 14),
            TextField(
              controller: _reason,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: t(
                  'سبب التعديل • يُحفظ في السجل',
                  'Reason for change • saved to audit',
                ),
                border: const OutlineInputBorder(),
              ),
            ),
          ],
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(
              editing
                  ? t('حفظ التعديلات', 'Save changes')
                  : t('إنشاء دعوة العضو', 'Create member invitation'),
            ),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(54),
              backgroundColor: const Color(0xFF17652F),
            ),
          ),
          if (editing) ...[
            const SizedBox(height: 20),
            const Divider(),
            Text(
              t('إجراءات أمنية', 'Security actions'),
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _revokeSessions,
              icon: const Icon(Icons.logout),
              label: Text(
                t(
                  'إيقاف الوصول مؤقتًا',
                  'Temporarily suspend access',
                ),
              ),
            ),
            OutlinedButton.icon(
              onPressed: _sendPasswordResetEmail,
              icon: const Icon(Icons.password_outlined),
              label: Text(
                t(
                  'إرسال رابط إعادة تعيين كلمة المرور',
                  'Send password reset link',
                ),
              ),
            ),
            OutlinedButton.icon(
              onPressed: _deleteMember,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
              ),
              icon: const Icon(Icons.delete_outline),
              label: Text(
                t(
                  'حذف العضو الإداري نهائيًا',
                  'Delete admin member permanently',
                ),
              ),
            ),
          ],
          const SizedBox(height: 30),
        ],
      ),
    );
  }
}

class DedaAdminAuditPage extends StatelessWidget {
  final bool isArabic;

  const DedaAdminAuditPage({super.key, required this.isArabic});

  String t(String a, String e) => isArabic ? a : e;

  String _actionLabel(String value) {
    const ar = <String, String>{
      'admin_member_created': 'إضافة عضو إداري',
      'admin_member_updated': 'تعديل عضو/صلاحيات',
      'admin_member_deleted': 'حذف عضو إداري',
      'admin_invite_created': 'إنشاء دعوة عضو إداري',
      'admin_invite_shared': 'مشاركة دعوة إدارية',
      'support_deleted': 'حذف رسالة دعم',
      'support_bulk_deleted': 'حذف مجموعة رسائل دعم',
      'support_restored': 'استرجاع رسالة دعم',
      'support_permanently_deleted': 'حذف رسالة دعم نهائيًا',
      'published_place_hidden': 'إخفاء مكان من الخريطة',
      'published_place_restored': 'إظهار مكان على الخريطة',
      'published_place_deleted': 'حذف مكان من الخريطة',
      'published_place_restored_from_trash': 'استرجاع مكان محذوف',
      'published_place_permanently_deleted': 'حذف مكان نهائيًا',
      'admin_invite_cancelled': 'إلغاء دعوة إدارية',
      'admin_invite_accepted': 'تفعيل دعوة إدارية',
      'admin_access_suspended': 'إيقاف وصول عضو مؤقتًا',
      'admin_password_reset_sent': 'إرسال رابط إعادة تعيين كلمة المرور',
      'admin_member_access_removed': 'إزالة صلاحية عضو إداري',
      'admin_sessions_revoked': 'تسجيل خروج من جميع الأجهزة',
      'admin_temporary_password_reset': 'إنشاء رمز دخول مؤقت',
      'admin_first_login_completed': 'اكتمال أول دخول',
      'admin_signed_in': 'تسجيل دخول إداري',
      'admin_signed_out': 'تسجيل خروج إداري',
      'admin_profile_normalized': 'تهيئة بيانات الحساب الإداري',
      'admin_display_name_updated': 'تعديل الاسم الإداري',
      'recovery_approved': 'اعتماد استرجاع الدخول',
      'recovery_rejected': 'رفض استرجاع الدخول',
      'read_user_account': 'مشاهدة حساب مستخدم',
      'account_deletion_status_changed': 'تحديث طلب حذف حساب',
      'road_hazard_deleted': 'حذف بلاغ طريق',
      'request_viewed': 'مشاهدة طلب',
      'support_replied': 'الرد على الدعم',
      'support_status_changed': 'تغيير حالة الدعم',
      'place_status_changed': 'تغيير حالة طلب مكان',
      'place_approved': 'اعتماد مكان',
    };
    return isArabic
        ? (ar[value] ?? value)
        : value.replaceAll('_', ' ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF2),
      appBar: AppBar(
        title: Text(t('السجل الإداري', 'Administrative audit log')),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: DedaBackend.adminAudit(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text(
                t('تعذر تحميل السجل.', 'Could not load audit log.'),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snapshot.data!.docs;
          if (docs.isEmpty) {
            return Center(
              child: Text(t('لا توجد سجلات بعد.', 'No audit entries yet.')),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final data = docs[index].data();
              final reason = (data['reason'] ?? '').toString().trim();
              final action = (data['action'] ?? '').toString();
              String target;
              if (action == 'read_user_account') {
                final targetName =
                    (data['targetUserName'] ?? '').toString().trim();
                final targetPhone =
                    (data['targetUserPhone'] ?? '').toString().trim();
                if (targetName.isNotEmpty && targetPhone.isNotEmpty) {
                  target = '$targetName • \u200E$targetPhone\u200E';
                } else if (targetName.isNotEmpty) {
                  target = targetName;
                } else if (targetPhone.isNotEmpty) {
                  target = '\u200E$targetPhone\u200E';
                } else {
                  target = t(
                    'بيانات غير مكتملة',
                    'Incomplete profile',
                  );
                }
              } else {
                target = (data['targetAdminName'] ??
                        data['targetUserName'] ??
                        data['targetUserPhone'] ??
                        data['targetId'] ??
                        data['sourceId'] ??
                        '')
                    .toString()
                    .trim();
              }
              return Card(
                child: ListTile(
                  leading: const Icon(
                    Icons.fact_check_outlined,
                    color: Color(0xFF17652F),
                  ),
                  title: Text(
                    _actionLabel((data['action'] ?? '').toString()),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    (data['adminName'] ?? t('الإدارة', 'Administration'))
                            .toString() +
                        ' • ' +
                        dedaAdminRoleLabel(isArabic, data['adminRole']) +
                        '\n' +
                        dedaAdminTimestamp(data['createdAt']) +
                        (target.isEmpty
                            ? ''
                            : '\n' + t('الهدف: ', 'Target: ') + target) +
                        (reason.isEmpty
                            ? ''
                            : '\n' + t('السبب: ', 'Reason: ') + reason),
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

class DedaAdminUsersPage extends StatefulWidget {
  final bool isArabic;

  const DedaAdminUsersPage({super.key, required this.isArabic});

  @override
  State<DedaAdminUsersPage> createState() => _DedaAdminUsersPageState();
}

class _DedaAdminUsersPageState extends State<DedaAdminUsersPage> {
  final _search = TextEditingController();
  final Set<String> _openingUsers = <String>{};

  bool get ar => widget.isArabic;
  String t(String a, String e) => ar ? a : e;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Widget _readOnlyRow(
    String label,
    dynamic value, {
    bool ltr = false,
  }) {
    final text = value?.toString().trim() ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label: ',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          Expanded(
            child: Directionality(
              textDirection: ltr ? TextDirection.ltr : Directionality.of(context),
              child: Text(
                text.isEmpty ? t('غير محدد', 'Not provided') : text,
                textAlign: ltr ? TextAlign.left : TextAlign.start,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openUser(String uid) async {
    final cleanUid = uid.trim();
    if (cleanUid.isEmpty || _openingUsers.contains(cleanUid)) return;
    _openingUsers.add(cleanUid);
    try {
      final snapshot = await DedaBackend.adminUserSnapshot(
        ownerUid: cleanUid,
        sourceCollection: 'users',
        sourceId: cleanUid,
      );
      if (!mounted) return;
      final profile = Map<String, dynamic>.from(
        snapshot['profile'] as Map? ?? const <String, dynamic>{},
      );
      final places = snapshot['publishedPlaces'] as List? ?? const [];
      final requests = snapshot['placeRequests'] as List? ?? const [];
      final support = snapshot['supportRequests'] as List? ?? const [];

      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.visibility_outlined),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  t(
                    'حساب المستخدم • قراءة فقط',
                    'User account • read only',
                  ),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _readOnlyRow(t('الاسم', 'Name'), profile['name']),
                _readOnlyRow(
                  t('الهاتف', 'Phone'),
                  profile['phone'],
                  ltr: true,
                ),
                _readOnlyRow(
                  t('نوع الحساب', 'Account type'),
                  profile['accountType'],
                ),
                const Divider(),
                _readOnlyRow(
                  t('الأماكن المعتمدة', 'Approved places'),
                  places.length,
                ),
                _readOnlyRow(
                  t('طلبات الأماكن', 'Place requests'),
                  requests.length,
                ),
                _readOnlyRow(
                  t('رسائل الدعم', 'Support messages'),
                  support.length,
                ),
                if (places.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    t('أماكن المستخدم', 'User places'),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  ...places.take(10).map((raw) {
                    final item =
                        Map<String, dynamic>.from(raw as Map);
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.storefront_outlined),
                      title: Text(
                        (item['placeName'] ?? '').toString(),
                      ),
                      subtitle: Text(
                        (item['approvalNumber'] ?? '').toString(),
                      ),
                    );
                  }),
                ],
                const SizedBox(height: 8),
                Text(
                  t(
                    'لا يمكن تعديل بيانات المستخدم من هذه النافذة. تم تسجيل هذه المشاهدة في السجل الإداري.',
                    'User data cannot be edited here. This review was recorded in the admin audit log.',
                  ),
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: Color(0xFF5B665D),
                  ),
                ),
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
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              t(
                'تعذر فتح حساب المستخدم الآن.',
                'Could not open the user account now.',
              ),
            ),
          ),
        );
      }
    } finally {
      _openingUsers.remove(cleanUid);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF2),
      appBar: AppBar(
        title: Text(t('المستخدمون • قراءة فقط', 'Users • read only')),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: DedaBackend.adminUsers(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text(
                t(
                  'تعذر تحميل المستخدمين.',
                  'Could not load users.',
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final query = _search.text.trim().toLowerCase();
          final items = snapshot.data!.docs.where((doc) {
            final data = doc.data();
            final haystack =
                ((data['name'] ?? '').toString() +
                        ' ' +
                        (data['phone'] ?? '').toString() +
                        ' ' +
                        (data['accountType'] ?? '').toString())
                    .toLowerCase();
            return query.isEmpty || haystack.contains(query);
          }).toList()
            ..sort(
              (a, b) => (a.data()['name'] ?? '')
                  .toString()
                  .compareTo((b.data()['name'] ?? '').toString()),
            );

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: t(
                      'بحث بالاسم أو الهاتف',
                      'Search name or phone',
                    ),
                    prefixIcon: const Icon(Icons.search),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              Expanded(
                child: items.isEmpty
                    ? Center(
                        child: Text(t('لا توجد نتائج.', 'No results.')),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        itemCount: items.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final doc = items[index];
                          final data = doc.data();
                          final name =
                              (data['name'] ?? '').toString().trim();
                          final phone =
                              (data['phone'] ?? '').toString().trim();
                          final accountType =
                              (data['accountType'] ?? '').toString().trim();
                          final incomplete = name.isEmpty ||
                              phone.isEmpty ||
                              accountType.isEmpty;
                          return Card(
                            child: ListTile(
                              onTap: () => _openUser(doc.id),
                              leading: Icon(
                                incomplete
                                    ? Icons.person_off_outlined
                                    : Icons.person_outline,
                              ),
                              title: Text(
                                name.isEmpty
                                    ? t(
                                        'بيانات غير مكتملة',
                                        'Incomplete profile',
                                      )
                                    : name,
                                style: TextStyle(
                                  fontWeight: incomplete
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(t('الهاتف: ', 'Phone: ')),
                                      Expanded(
                                        child: Directionality(
                                          textDirection: TextDirection.ltr,
                                          child: FittedBox(
                                            fit: BoxFit.scaleDown,
                                            alignment: Alignment.centerLeft,
                                            child: Text(
                                              (data['phone'] ?? '—')
                                                  .toString(),
                                              maxLines: 1,
                                              softWrap: false,
                                              textAlign: TextAlign.left,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  Text(
                                    t(
                                          'نوع الحساب: ',
                                          'Account type: ',
                                        ) +
                                        (data['accountType'] ?? '—')
                                            .toString(),
                                  ),
                                ],
                              ),
                              trailing: incomplete
                                  ? Chip(
                                      label: Text(
                                        t(
                                          'بيانات ناقصة',
                                          'Incomplete',
                                        ),
                                      ),
                                      visualDensity: VisualDensity.compact,
                                    )
                                  : const Icon(Icons.chevron_right),
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


class DedaAccountDeletionRequestsPage extends StatefulWidget {
  final bool isArabic;

  const DedaAccountDeletionRequestsPage({
    super.key,
    required this.isArabic,
  });

  @override
  State<DedaAccountDeletionRequestsPage> createState() =>
      _DedaAccountDeletionRequestsPageState();
}

class _DedaAccountDeletionRequestsPageState
    extends State<DedaAccountDeletionRequestsPage> {
  String _filter = 'all';

  bool get ar => widget.isArabic;
  String t(String a, String e) => ar ? a : e;

  String _statusLabel(String status) {
    switch (status) {
      case 'new':
        return t('جديد', 'New');
      case 'reviewing':
        return t('قيد المراجعة', 'Under review');
      case 'deleted':
        return t('تم الحذف', 'Deleted');
      case 'cancelled':
      case 'rejected':
        return t('ملغي / مرفوض', 'Cancelled / rejected');
      default:
        return status;
    }
  }

  bool _matches(String status) {
    if (_filter == 'all') return true;
    if (_filter == 'closed') {
      return status == 'cancelled' || status == 'rejected';
    }
    return status == _filter;
  }

  Future<String?> _askNote(String title) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          minLines: 2,
          maxLines: 5,
          decoration: InputDecoration(
            labelText: t('ملاحظة الإدارة', 'Administration note'),
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(t('إلغاء', 'Cancel')),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: Text(t('تأكيد', 'Confirm')),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _changeStatus(
    String requestId,
    String status,
    Map<String, dynamic> data,
  ) async {
    final title = status == 'deleted'
        ? t(
            'تأكيد تسجيل الطلب كتم الحذف',
            'Confirm marking this request as deleted',
          )
        : status == 'reviewing'
            ? t('بدء المراجعة', 'Start review')
            : t('إغلاق الطلب', 'Close request');
    final note = await _askNote(title);
    if (note == null) return;

    try {
      await DedaBackend.updateAccountDeletionRequestStatus(
        requestId: requestId,
        status: status,
        note: note,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            t('تم تحديث حالة الطلب.', 'Request status updated.'),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(dedaFriendlyAdminError(ar, error))),
      );
    }
  }

  Widget _filterChip(String value, String arLabel, String enLabel) {
    return ChoiceChip(
      selected: _filter == value,
      selectedColor: const Color(0xFFDDEDDD),
      label: Text(t(arLabel, enLabel)),
      onSelected: (_) => setState(() => _filter = value),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF2),
      appBar: AppBar(
        title: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            t('طلبات حذف الحساب', 'Account deletion requests'),
          ),
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: DedaBackend.accountDeletionRequests(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text(
                t(
                  'تعذر تحميل طلبات حذف الحساب.',
                  'Could not load account deletion requests.',
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs.where((doc) {
            final status = (doc.data()['status'] ?? 'new').toString();
            return _matches(status);
          }).toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8EFEA),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: const Color(0xFFD8B9AD),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.info_outline,
                        color: Color(0xFF8A3C32),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          t(
                            'هذه الصفحة لمتابعة طلبات الحذف. سجّل «تم الحذف» فقط بعد تنفيذ حذف الحساب فعليًا.',
                            'This page tracks deletion requests. Mark “Deleted” only after the account has actually been deleted.',
                          ),
                          style: const TextStyle(fontSize: 12.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _filterChip('all', 'الكل', 'All'),
                    _filterChip('new', 'جديد', 'New'),
                    _filterChip('reviewing', 'قيد المراجعة', 'Under review'),
                    _filterChip('deleted', 'تم الحذف', 'Deleted'),
                    _filterChip('closed', 'ملغي/مرفوض', 'Cancelled/rejected'),
                  ],
                ),
              ),
              Expanded(
                child: docs.isEmpty
                    ? Center(
                        child: Text(
                          t(
                            'لا توجد طلبات في هذا القسم.',
                            'There are no requests in this section.',
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: docs.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final doc = docs[index];
                          final data = doc.data();
                          final status =
                              (data['status'] ?? 'new').toString();
                          final name =
                              (data['name'] ?? '').toString().trim();
                          final phone =
                              (data['phone'] ?? '').toString().trim();
                          final reason =
                              (data['reason'] ?? '').toString().trim();
                          return Card(
                            clipBehavior: Clip.antiAlias,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: ExpansionTile(
                              leading: const CircleAvatar(
                                backgroundColor: Color(0xFFF3E7E4),
                                child: Icon(
                                  Icons.person_remove_alt_1_outlined,
                                  color: Color(0xFF8A3C32),
                                ),
                              ),
                              title: Text(
                                name.isEmpty
                                    ? t(
                                        'طلب حذف حساب',
                                        'Account deletion request',
                                      )
                                    : name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (phone.isNotEmpty)
                                    Directionality(
                                      textDirection: TextDirection.ltr,
                                      child: Text(
                                        phone,
                                        textAlign: TextAlign.left,
                                      ),
                                    ),
                                  Text(
                                    t('الحالة: ', 'Status: ') +
                                        _statusLabel(status),
                                  ),
                                  Text(
                                    t('التاريخ: ', 'Date: ') +
                                        dedaAdminTimestamp(
                                          data['createdAt'],
                                        ),
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ],
                              ),
                              childrenPadding:
                                  const EdgeInsets.fromLTRB(16, 0, 16, 14),
                              children: [
                                if (reason.isNotEmpty)
                                  Align(
                                    alignment:
                                        AlignmentDirectional.centerStart,
                                    child: Text(
                                      t('السبب: ', 'Reason: ') + reason,
                                    ),
                                  ),
                                const SizedBox(height: 8),
                                if ((data['reviewNote'] ?? '')
                                    .toString()
                                    .trim()
                                    .isNotEmpty)
                                  Align(
                                    alignment:
                                        AlignmentDirectional.centerStart,
                                    child: Text(
                                      t(
                                            'ملاحظة الإدارة: ',
                                            'Administration note: ',
                                          ) +
                                          data['reviewNote'].toString(),
                                    ),
                                  ),
                                if ((data['reviewedByName'] ?? '')
                                    .toString()
                                    .trim()
                                    .isNotEmpty)
                                  Align(
                                    alignment:
                                        AlignmentDirectional.centerStart,
                                    child: Text(
                                      t(
                                            'آخر إجراء بواسطة: ',
                                            'Last action by: ',
                                          ) +
                                          data['reviewedByName'].toString(),
                                    ),
                                  ),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    if (status != 'reviewing' &&
                                        status != 'deleted' &&
                                        status != 'cancelled' &&
                                        status != 'rejected')
                                      OutlinedButton.icon(
                                        onPressed: () => _changeStatus(
                                          doc.id,
                                          'reviewing',
                                          data,
                                        ),
                                        icon: const Icon(
                                          Icons.manage_search_outlined,
                                        ),
                                        label: Text(
                                          t(
                                            'قيد المراجعة',
                                            'Under review',
                                          ),
                                        ),
                                      ),
                                    if (status != 'deleted')
                                      FilledButton.icon(
                                        onPressed: () => _changeStatus(
                                          doc.id,
                                          'deleted',
                                          data,
                                        ),
                                        icon: const Icon(
                                          Icons.delete_forever_outlined,
                                        ),
                                        label: Text(
                                          t('تم الحذف', 'Deleted'),
                                        ),
                                      ),
                                    if (status != 'cancelled' &&
                                        status != 'rejected' &&
                                        status != 'deleted')
                                      OutlinedButton.icon(
                                        onPressed: () => _changeStatus(
                                          doc.id,
                                          'rejected',
                                          data,
                                        ),
                                        icon: const Icon(
                                          Icons.cancel_outlined,
                                        ),
                                        label: Text(
                                          t(
                                            'ملغي / مرفوض',
                                            'Cancelled / rejected',
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
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

class DedaAdminRoadReportsPage extends StatefulWidget {
  final bool isArabic;
  final Map<String, dynamic> adminProfile;

  const DedaAdminRoadReportsPage({
    super.key,
    required this.isArabic,
    required this.adminProfile,
  });

  @override
  State<DedaAdminRoadReportsPage> createState() =>
      _DedaAdminRoadReportsPageState();
}

class _DedaAdminRoadReportsPageState
    extends State<DedaAdminRoadReportsPage> {
  late Future<List<Map<String, dynamic>>> _future;

  bool get ar => widget.isArabic;
  String t(String a, String e) => ar ? a : e;

  @override
  void initState() {
    super.initState();
    _future = DedaBackend.roadHazards();
  }

  void _reload() {
    setState(() => _future = DedaBackend.roadHazards());
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(t('حذف البلاغ', 'Delete report')),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: t('سبب الحذف', 'Reason'),
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
            child: Text(t('حذف', 'Delete')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (reason == null) return;
    try {
      await DedaBackend.deleteRoadHazardAsAdmin(
        id: item['id'].toString(),
        reason: reason,
      );
      _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(dedaFriendlyAdminError(ar, error))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final canManage =
        DedaBackend.adminHasPermission(widget.adminProfile, 'manageReports') &&
            DedaBackend.normalizeAdminRole(widget.adminProfile['role']) !=
                'province_agent';
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF2),
      appBar: AppBar(
        title: Text(t('البلاغات', 'Reports')),
        actions: [
          IconButton(
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text(
                t(
                  'تعذر تحميل البلاغات.',
                  'Could not load reports.',
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
                t('لا توجد بلاغات نشطة.', 'No active reports.'),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final item = items[index];
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.warning_amber_rounded),
                  title: Text(
                    (item['type'] ??
                            t('بلاغ طريق', 'Road report'))
                        .toString(),
                  ),
                  subtitle: Text(
                    t('التأكيدات: ', 'Confirmations: ') +
                        (item['confirmations'] ?? 0).toString() +
                        ' • ' +
                        t('طلبات الإلغاء: ', 'Resolve reports: ') +
                        (item['resolvedReports'] ?? 0).toString(),
                  ),
                  trailing: canManage
                      ? IconButton(
                          onPressed: () => _delete(item),
                          icon: const Icon(Icons.delete_outline),
                        )
                      : null,
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class DedaGovernoratesPage extends StatelessWidget {
  final bool isArabic;
  final Map<String, dynamic> adminProfile;

  const DedaGovernoratesPage({
    super.key,
    required this.isArabic,
    required this.adminProfile,
  });

  String t(String a, String e) => isArabic ? a : e;

  @override
  Widget build(BuildContext context) {
    final scope =
        DedaBackend.normalizeAdminRole(adminProfile['role']) ==
                'province_agent'
            ? (adminProfile['governorate'] ?? '').toString()
            : '';
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF2),
      appBar: AppBar(title: Text(t('المحافظات', 'Governorates'))),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (scope.isNotEmpty)
            Card(
              color: const Color(0xFFE6F1E4),
              child: ListTile(
                leading: const Icon(Icons.location_on_outlined),
                title: Text(t('نطاق حسابك', 'Your account scope')),
                subtitle: Text(scope),
              ),
            ),
          ...(scope.isNotEmpty ? <String>[scope] : dedaAdminGovernorates).map(
            (name) => Card(
              child: ListTile(
                leading: const Icon(Icons.location_city_outlined),
                title: Text(name),
                trailing: scope == name
                    ? const Icon(
                        Icons.verified,
                        color: Color(0xFF17652F),
                      )
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class DedaAdminReportsPage extends StatefulWidget {
  final bool isArabic;
  final Map<String, dynamic> adminProfile;

  const DedaAdminReportsPage({
    super.key,
    required this.isArabic,
    required this.adminProfile,
  });

  @override
  State<DedaAdminReportsPage> createState() =>
      _DedaAdminReportsPageState();
}

class _DedaAdminReportsPageState extends State<DedaAdminReportsPage> {
  late Future<List<Map<String, dynamic>>> _hazards;

  bool get ar => widget.isArabic;
  String t(String a, String e) => ar ? a : e;

  @override
  void initState() {
    super.initState();
    _hazards = DedaBackend.roadHazards();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF2),
      appBar: AppBar(title: Text(t('التقارير', 'Analytics'))),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _hazards,
        builder: (context, snapshot) {
          final count = snapshot.data?.length;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: ListTile(
                  leading: const Icon(
                    Icons.report_outlined,
                    color: Color(0xFF17652F),
                  ),
                  title: Text(
                    t('البلاغات النشطة', 'Active road reports'),
                  ),
                  trailing: Text(
                    count?.toString() ?? '…',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 22,
                    ),
                  ),
                ),
              ),
              Card(
                child: ListTile(
                  leading: const Icon(
                    Icons.security_outlined,
                    color: Color(0xFF17652F),
                  ),
                  title: Text(t('نطاق صلاحياتك', 'Your access scope')),
                  subtitle: Text(
                    DedaBackend.normalizeAdminRole(
                              widget.adminProfile['role'],
                            ) ==
                            'province_agent'
                        ? t('محافظة: ', 'Province: ') +
                            (widget.adminProfile['governorate'] ?? '—')
                                .toString()
                        : dedaAdminRoleLabel(
                            ar,
                            widget.adminProfile['role'],
                          ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class DedaAdminSettingsPage extends StatefulWidget {
  final bool isArabic;
  final Map<String, dynamic> profile;

  const DedaAdminSettingsPage({
    super.key,
    required this.isArabic,
    required this.profile,
  });

  @override
  State<DedaAdminSettingsPage> createState() =>
      _DedaAdminSettingsPageState();
}

class _DedaAdminSettingsPageState extends State<DedaAdminSettingsPage> {
  late Map<String, dynamic> _profile;

  bool get isArabic => widget.isArabic;
  String t(String a, String e) => isArabic ? a : e;

  @override
  void initState() {
    super.initState();
    _profile = Map<String, dynamic>.from(widget.profile);
  }

  String get _email => (_profile['email'] ?? '').toString().trim();

  String get _adminName {
    final rawName =
        (_profile['displayName'] ?? _profile['name'] ?? '').toString().trim();
    if (rawName.isEmpty ||
        (_email.isNotEmpty &&
            rawName.toLowerCase() == _email.toLowerCase())) {
      return t('غير محدد', 'Not provided');
    }
    return rawName;
  }

  Future<void> _editName() async {
    final controller = TextEditingController(
      text: _adminName == t('غير محدد', 'Not provided') ? '' : _adminName,
    );
    String? dialogError;

    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(t('تعديل الاسم الإداري', 'Edit admin name')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: t('الاسم الكامل', 'Full name'),
                  prefixIcon: const Icon(Icons.person_outline),
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (text) {
                  final clean = text.trim();
                  if (clean.length < 2) {
                    setDialogState(() {
                      dialogError = t(
                        'اكتب اسمًا واضحًا من حرفين على الأقل.',
                        'Enter a clear name with at least 2 characters.',
                      );
                    });
                    return;
                  }
                  Navigator.pop(dialogContext, clean);
                },
              ),
              if (dialogError != null) ...[
                const SizedBox(height: 10),
                Text(
                  dialogError!,
                  style: const TextStyle(color: Colors.red),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(t('إلغاء', 'Cancel')),
            ),
            FilledButton(
              onPressed: () {
                final clean = controller.text.trim();
                if (clean.length < 2) {
                  setDialogState(() {
                    dialogError = t(
                      'اكتب اسمًا واضحًا من حرفين على الأقل.',
                      'Enter a clear name with at least 2 characters.',
                    );
                  });
                  return;
                }
                Navigator.pop(dialogContext, clean);
              },
              child: Text(t('حفظ', 'Save')),
            ),
          ],
        ),
      ),
    );
    controller.dispose();

    if (value == null || value.trim().isEmpty) return;
    try {
      await DedaBackend.updateCurrentAdminDisplayName(value);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('deda_admin_last_name_v1', value.trim());
      if (!mounted) return;
      setState(() {
        _profile['displayName'] = value.trim();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            t('تم تحديث الاسم الإداري.', 'Admin name updated.'),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            t(
              'تعذر تحديث الاسم الآن. حاول مجددًا.',
              'Could not update the name now. Try again.',
            ),
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
        title: Text(t('إعدادات الإدارة', 'Admin settings')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(t('الاسم', 'Name')),
                  subtitle: Text(_adminName),
                  trailing: IconButton(
                    tooltip: t('تعديل الاسم', 'Edit name'),
                    onPressed: _editName,
                    icon: const Icon(Icons.edit_outlined),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.email_outlined),
                  title: Text(t('البريد', 'Email')),
                  subtitle: Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text(
                      _email.isEmpty ? '—' : _email,
                      textAlign: TextAlign.left,
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.badge_outlined),
                  title: Text(t('الدور', 'Role')),
                  subtitle: Text(
                    dedaAdminRoleLabel(isArabic, _profile['role']),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.toggle_on_outlined),
                  title: Text(t('حالة الحساب', 'Account status')),
                  subtitle: Text(
                    dedaAdminStatusLabel(
                      isArabic,
                      DedaBackend.normalizeAdminStatus(_profile),
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.schedule),
                  title: Text(t('آخر دخول', 'Last sign-in')),
                  subtitle: Text(
                    dedaAdminTimestamp(
                      _profile['lastLoginAt'] ?? _profile['lastSeenAt'],
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
}
