import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'admin_place_map.dart';
import 'admin_team_pages.dart';
import 'deda_backend.dart';

class DedaAdminLoginPage extends StatefulWidget {
  final bool isArabic;

  const DedaAdminLoginPage({super.key, required this.isArabic});

  @override
  State<DedaAdminLoginPage> createState() => _DedaAdminLoginPageState();
}

class _DedaAdminLoginPageState extends State<DedaAdminLoginPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  String? _error;

  String t(String ar, String en) => widget.isArabic ? ar : en;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_email.text.trim().isEmpty || _password.text.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final allowed = await DedaBackend.signInAdmin(
        email: _email.text,
        password: _password.text,
      );
      if (!mounted) return;
      if (!allowed) {
        setState(() => _error = t(
              'هذا الحساب ليس مديرًا معتمدًا.',
              'This is not an approved admin account.',
            ));
        return;
      }
      final profile = await DedaBackend.currentAdminProfile();
      if (profile['mustChangePassword'] == true) {
        final changed = await _forcePasswordChange();
        if (!changed) {
          await DedaBackend.signOutAdmin();
          return;
        }
      }
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => DedaAdminDashboardPage(isArabic: widget.isArabic),
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(() => _error = t(
              'تعذر تسجيل الدخول. تحقق من البيانات واتصال الإنترنت.',
              'Sign-in failed. Check the details and internet connection.',
            ));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<bool> _forcePasswordChange() async {
    final first = TextEditingController();
    final second = TextEditingController();
    String? dialogError;
    final newPassword = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(t(
            'تغيير كلمة المرور لأول دخول',
            'Change password on first sign-in',
          )),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(t(
                'هذا الرمز مؤقت. اختر كلمة مرور جديدة قبل الدخول إلى الإدارة.',
                'The invitation code is temporary. Choose a new password before entering administration.',
              )),
              const SizedBox(height: 14),
              TextField(
                controller: first,
                obscureText: true,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(
                  labelText: t('كلمة المرور الجديدة', 'New password'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: second,
                obscureText: true,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(
                  labelText: t('تأكيد كلمة المرور', 'Confirm password'),
                  border: const OutlineInputBorder(),
                ),
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
            FilledButton(
              onPressed: () {
                final value = first.text;
                if (value.length < 8) {
                  setDialogState(() => dialogError = t(
                    'استخدم 8 أحرف/أرقام على الأقل.',
                    'Use at least 8 characters.',
                  ));
                  return;
                }
                if (value != second.text) {
                  setDialogState(() => dialogError = t(
                    'كلمتا المرور غير متطابقتين.',
                    'Passwords do not match.',
                  ));
                  return;
                }
                Navigator.pop(dialogContext, value);
              },
              child: Text(t('حفظ والمتابعة', 'Save and continue')),
            ),
          ],
        ),
      ),
    );
    first.dispose();
    second.dispose();
    if (newPassword == null) return false;
    await DedaBackend.changeCurrentAdminPassword(newPassword);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF2),
      appBar: AppBar(title: Text(t('إدارة DEDA', 'DEDA administration'))),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.admin_panel_settings,
                  size: 72,
                  color: Color(0xFF17652F),
                ),
                const SizedBox(height: 18),
                Text(
                  t('دخول الإدارة المحمي', 'Protected admin sign-in'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 22),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(
                    labelText: t('البريد الإلكتروني الإداري', 'Admin email'),
                    prefixIcon: const Icon(Icons.email_outlined),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _password,
                  obscureText: true,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(
                    labelText: t('كلمة المرور', 'Password'),
                    prefixIcon: const Icon(Icons.lock_outline),
                    border: const OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _login(),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: _loading ? null : _login,
                  icon: _loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.login),
                  label: Text(t('دخول', 'Sign in')),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                    backgroundColor: const Color(0xFF17652F),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


class DedaAdminDashboardPage extends StatefulWidget {
  final bool isArabic;

  const DedaAdminDashboardPage({super.key, required this.isArabic});

  @override
  State<DedaAdminDashboardPage> createState() =>
      _DedaAdminDashboardPageState();
}

class _DedaAdminDashboardPageState extends State<DedaAdminDashboardPage> {
  Map<String, dynamic>? _profile;
  String? _error;

  bool get ar => widget.isArabic;
  String t(String a, String e) => ar ? a : e;

  String _roleLabel(dynamic value) {
    switch (DedaBackend.normalizeAdminRole(value)) {
      case 'general_manager':
        return t('المدير العام', 'General manager');
      case 'deputy_manager':
        return t('معاون المدير', 'Deputy manager');
      case 'province_agent':
        return t('وكيل محافظة', 'Province agent');
      case 'employee':
        return t('موظف', 'Employee');
      default:
        return value?.toString() ?? '';
    }
  }

  String _statusLabel(Map<String, dynamic> value) {
    switch (DedaBackend.normalizeAdminStatus(value)) {
      case 'active':
        return t('نشط', 'Active');
      case 'temporarily_stopped':
        return t('متوقف مؤقتًا', 'Temporarily stopped');
      case 'disabled':
        return t('معطّل', 'Disabled');
      default:
        return '';
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final profile = await DedaBackend.currentAdminProfile();
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = t(
            'تعذر تحميل صلاحيات الحساب الإداري.',
            'Could not load the administrative account permissions.',
          ));
    }
  }

  Future<void> _open(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    if (mounted) _load();
  }

  Widget _dashboardCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 2,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 38, color: const Color(0xFF17652F)),
              const SizedBox(height: 10),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: Color(0xFF5D685F),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF2),
      appBar: AppBar(
        title: Text(t('إدارة DEDA', 'DEDA administration')),
        actions: [
          IconButton(
            tooltip: t('تحديث', 'Refresh'),
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: t('تسجيل الخروج', 'Sign out'),
            onPressed: () async {
              await DedaBackend.signOutAdmin();
              if (context.mounted) Navigator.pop(context);
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: profile == null
          ? Center(
              child: _error == null
                  ? const CircularProgressIndicator()
                  : Padding(
                      padding: const EdgeInsets.all(22),
                      child: Text(_error!, textAlign: TextAlign.center),
                    ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE7F1E4),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFB8CCB6)),
                    ),
                    child: Row(
                      children: [
                        const CircleAvatar(
                          radius: 28,
                          backgroundColor: Color(0xFF17652F),
                          child: Icon(
                            Icons.admin_panel_settings,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                (profile['displayName'] ?? '').toString(),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 18,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(_roleLabel(profile['role'])),
                              if ((profile['governorate'] ?? '')
                                  .toString()
                                  .trim()
                                  .isNotEmpty)
                                Text(
                                  t('المحافظة: ', 'Province: ') +
                                      profile['governorate'].toString(),
                                  style: const TextStyle(fontSize: 12.5),
                                ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFD4EAD5),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(
                            _statusLabel(profile),
                            style: const TextStyle(
                              color: Color(0xFF17652F),
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 1.08,
                    children: [
                      if (DedaBackend.normalizeAdminRole(profile['role']) ==
                          'general_manager')
                        _dashboardCard(
                          icon: Icons.groups_2_outlined,
                          title: t(
                            'إدارة الفريق والصلاحيات',
                            'Team & permissions',
                          ),
                          subtitle: t(
                            'إضافة الأعضاء وتحديد أدوارهم',
                            'Members, roles and access',
                          ),
                          onTap: () => _open(DedaAdminTeamPage(
                            isArabic: ar,
                            currentAdmin: profile,
                          )),
                        ),
                      if (DedaBackend.adminHasPermission(
                        profile,
                        'viewPlaceRequests',
                      ))
                        _dashboardCard(
                          icon: Icons.storefront_outlined,
                          title: t('طلبات الأماكن', 'Place requests'),
                          subtitle: t(
                            'المراجعة والاعتماد حسب الصلاحية',
                            'Review according to permission',
                          ),
                          onTap: () => _open(_AdminRequestsPage(
                            isArabic: ar,
                            adminProfile: profile,
                            collection: 'place_requests',
                          )),
                        ),
                      if (DedaBackend.adminHasPermission(profile, 'supportRead'))
                        _dashboardCard(
                          icon: Icons.support_agent,
                          title: t('الدعم', 'Support'),
                          subtitle: t(
                            'رسائل المستخدمين والردود',
                            'User messages and replies',
                          ),
                          onTap: () => _open(_AdminRequestsPage(
                            isArabic: ar,
                            adminProfile: profile,
                            collection: 'support_requests',
                          )),
                        ),
                      if (DedaBackend.adminHasPermission(profile, 'viewUsers'))
                        _dashboardCard(
                          icon: Icons.people_alt_outlined,
                          title: t('المستخدمون', 'Users'),
                          subtitle: t('قراءة فقط', 'Read only'),
                          onTap: () => _open(
                            DedaAdminUsersPage(isArabic: ar),
                          ),
                        ),
                      if (DedaBackend.adminHasPermission(
                        profile,
                        'viewReports',
                      ))
                        _dashboardCard(
                          icon: Icons.report_gmailerrorred_outlined,
                          title: t('البلاغات', 'Reports'),
                          subtitle: t(
                            'بلاغات الطريق الحالية',
                            'Current road reports',
                          ),
                          onTap: () => _open(DedaAdminRoadReportsPage(
                            isArabic: ar,
                            adminProfile: profile,
                          )),
                        ),
                      if (DedaBackend.adminHasPermission(
                        profile,
                        'viewGovernorates',
                      ))
                        _dashboardCard(
                          icon: Icons.map_outlined,
                          title: t('المحافظات', 'Governorates'),
                          subtitle: t(
                            'نطاق عمل الوكلاء',
                            'Agent coverage',
                          ),
                          onTap: () => _open(DedaGovernoratesPage(
                            isArabic: ar,
                            adminProfile: profile,
                          )),
                        ),
                      if (DedaBackend.adminHasPermission(
                        profile,
                        'viewReports',
                      ))
                        _dashboardCard(
                          icon: Icons.analytics_outlined,
                          title: t('التقارير', 'Analytics'),
                          subtitle: t(
                            'ملخص تشغيلي سريع',
                            'Quick operations summary',
                          ),
                          onTap: () => _open(DedaAdminReportsPage(
                            isArabic: ar,
                            adminProfile: profile,
                          )),
                        ),
                      if (DedaBackend.adminHasPermission(profile, 'viewAudit') &&
                          DedaBackend.normalizeAdminRole(profile['role']) !=
                              'province_agent')
                        _dashboardCard(
                          icon: Icons.fact_check_outlined,
                          title: t('السجل الإداري', 'Audit log'),
                          subtitle: t(
                            'من قام بماذا ومتى',
                            'Who did what and when',
                          ),
                          onTap: () => _open(
                            DedaAdminAuditPage(isArabic: ar),
                          ),
                        ),
                      _dashboardCard(
                        icon: Icons.settings_outlined,
                        title: t('الإعدادات', 'Settings'),
                        subtitle: t(
                          'بيانات حسابك الإداري',
                          'Your admin account',
                        ),
                        onTap: () => _open(DedaAdminSettingsPage(
                          isArabic: ar,
                          profile: profile,
                        )),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }
}

class _AdminRequestsPage extends StatelessWidget {
  final bool isArabic;
  final Map<String, dynamic> adminProfile;
  final String collection;

  const _AdminRequestsPage({
    required this.isArabic,
    required this.adminProfile,
    required this.collection,
  });

  @override
  Widget build(BuildContext context) {
    final isSupport = collection == 'support_requests';
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF2),
      appBar: AppBar(
        title: Text(
          isSupport
              ? (isArabic ? 'الدعم' : 'Support')
              : (isArabic ? 'طلبات الأماكن' : 'Place requests'),
        ),
      ),
      body: _RequestList(
        isArabic: isArabic,
        collection: collection,
        adminProfile: adminProfile,
        stream: isSupport
            ? DedaBackend.supportRequestsForAdmin(adminProfile)
            : DedaBackend.placeRequestsForAdmin(adminProfile),
      ),
    );
  }
}

class DedaAdminInboxPage extends StatefulWidget {
  final bool isArabic;

  const DedaAdminInboxPage({super.key, required this.isArabic});

  @override
  State<DedaAdminInboxPage> createState() => _DedaAdminInboxPageState();
}

class _DedaAdminInboxPageState extends State<DedaAdminInboxPage> {
  String t(String ar, String en) => widget.isArabic ? ar : en;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAF2),
        appBar: AppBar(
          title: Text(t('صندوق إدارة DEDA', 'DEDA admin inbox')),
          actions: [
            IconButton(
              tooltip: t('تسجيل خروج الإدارة', 'Admin sign out'),
              onPressed: () async {
                await DedaBackend.signOutAdmin();
                if (context.mounted) Navigator.pop(context);
              },
              icon: const Icon(Icons.logout),
            ),
          ],
          bottom: TabBar(
            tabs: [
              Tab(text: t('الدعم', 'Support')),
              Tab(text: t('طلبات الأماكن', 'Places')),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _RequestList(
              isArabic: widget.isArabic,
              collection: 'support_requests',
              stream: DedaBackend.supportRequests(),
            ),
            _RequestList(
              isArabic: widget.isArabic,
              collection: 'place_requests',
              stream: DedaBackend.placeRequests(),
            ),
          ],
        ),
      ),
    );
  }
}

class _RequestList extends StatefulWidget {
  final bool isArabic;
  final String collection;
  final Stream<QuerySnapshot<Map<String, dynamic>>> stream;

  const _RequestList({
    required this.isArabic,
    required this.collection,
    required this.stream,
  });

  @override
  State<_RequestList> createState() => _RequestListState();
}

class _RequestListState extends State<_RequestList> {
  String? _expandedId;
  String _section = 'current';

  String t(String ar, String en) => widget.isArabic ? ar : en;

  String statusLabel(String status) {
    switch (status) {
      case 'pending':
        return t('قيد الانتظار', 'Pending');
      case 'reviewing':
        return t('قيد المراجعة', 'Under review');
      case 'approved':
        return t('معتمد', 'Approved');
      case 'needs_changes':
        return t('يحتاج تعديل', 'Needs changes');
      case 'rejected':
        return t('مرفوض', 'Rejected');
      case 'new':
        return t('جديد', 'New');
      case 'in_progress':
        return t('قيد المعالجة', 'In progress');
      case 'replied':
        return t('تم الرد', 'Replied');
      case 'closed':
        return t('تم الحل / مغلق', 'Resolved / closed');
      default:
        return status;
    }
  }

  String _text(dynamic value) => value?.toString().trim() ?? '';

  String _supportTypeLabel(String type) {
    switch (type) {
      case 'problem':
        return t('تبليغ عن مشكلة', 'Report a problem');
      case 'case':
        return t('شرح عن حالة', 'Explain a case');
      case 'photo':
        return t('إرسال صورة', 'Send a photo');
      default:
        return t(
          'التواصل مع الشركة مباشرة',
          'Contact company directly',
        );
    }
  }

  String _placeType(Map<String, dynamic> data) {
    final custom = _text(data['otherCategoryText']);
    if (custom.isNotEmpty) return custom;
    final detailed = _text(
      data[widget.isArabic ? 'otherCategoryLabelAr' : 'otherCategoryLabelEn'],
    );
    if (detailed.isNotEmpty) return detailed;
    return _text(
      data[widget.isArabic ? 'categoryLabelAr' : 'categoryLabelEn'] ??
          data['category'],
    );
  }

  String _roleLabel(dynamic value) {
    final raw = _text(value);
    switch (raw.toLowerCase()) {
      case 'manager':
      case 'director':
      case 'admin':
        return t('المدير', 'Manager');
      case 'assistant':
      case 'assistant_manager':
      case 'assistant-manager':
      case 'deputy_manager':
        return t('مساعد المدير', 'Assistant manager');
      default:
        return raw.isEmpty ? t('الإدارة', 'Administration') : raw;
    }
  }

  String _formatTimestamp(dynamic value) {
    DateTime? date;
    if (value is Timestamp) {
      date = value.toDate();
    } else if (value is DateTime) {
      date = value;
    } else if (value != null) {
      date = DateTime.tryParse(value.toString());
    }
    if (date == null) return '';
    final local = date.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  Widget _detailRow(String label, dynamic value, {bool ltr = false}) {
    final text = _text(value);
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
              textDirection:
                  ltr ? TextDirection.ltr : Directionality.of(context),
              child: SelectableText(
                text.isEmpty ? t('غير محدد', 'Not provided') : text,
                textAlign: ltr ? TextAlign.left : TextAlign.start,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _auditDetails(Map<String, dynamic> data) {
    final firstViewedAt = _formatTimestamp(data['firstViewedAt']);
    final firstViewedByName = _text(data['firstViewedByName']);
    final firstViewedByRole = _roleLabel(data['firstViewedByRole']);
    final status = _text(data['status']);
    final hasDecision = status == 'approved' || status == 'rejected';
    final decisionAt = _formatTimestamp(data['decisionAt']);
    final decisionByName = _text(data['decisionByName']);
    final decisionByRole = _roleLabel(data['decisionByRole']);
    final decisionNote = _text(data['decisionNote']);

    if (firstViewedAt.isEmpty && !hasDecision) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5EF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFC9D5C7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.verified_user_outlined,
                color: Color(0xFF17652F),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  t('السجل الإداري', 'Administrative record'),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (firstViewedAt.isNotEmpty) ...[
            _detailRow(
              t('أول مشاهدة بواسطة', 'First viewed by'),
              firstViewedByName.isEmpty
                  ? firstViewedByRole
                  : '$firstViewedByRole • $firstViewedByName',
            ),
            _detailRow(
              t('وقت أول مشاهدة', 'First viewed at'),
              firstViewedAt,
              ltr: true,
            ),
          ],
          if (hasDecision) ...[
            _detailRow(
              status == 'approved'
                  ? t('الاعتماد الإلكتروني', 'Electronic approval')
                  : t('قرار الرفض', 'Rejection decision'),
              decisionByName.isEmpty
                  ? decisionByRole
                  : '$decisionByRole • $decisionByName',
            ),
            if (decisionAt.isNotEmpty)
              _detailRow(
                t('وقت القرار', 'Decision time'),
                decisionAt,
                ltr: true,
              ),
            if (decisionNote.isNotEmpty)
              _detailRow(
                t('ملاحظة الإدارة', 'Admin note'),
                decisionNote,
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _openMap({
    required double latitude,
    required double longitude,
    required String placeName,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DedaAdminPlaceMapPage(
          isArabic: widget.isArabic,
          latitude: latitude,
          longitude: longitude,
          placeName: placeName,
        ),
      ),
    );
  }

  // DEDA 10-point fixes v1: support workflow and read-only account review.
  Widget _liveAvailability(Map<String, dynamic> data, String requestId) {
    final fallback = data['isAvailableNow'] == true;
    if (_text(data['status']) != 'approved') {
      return _detailRow(
        t('حالة التواجد', 'Availability'),
        fallback
            ? t('متواجد الآن', 'Available now')
            : t('غير متواجد حاليًا', 'Not available now'),
      );
    }
    final original = _text(data['originalPlaceId']);
    final publishedId = original.isNotEmpty ? original : requestId;
    return StreamBuilder<Map<String, dynamic>?>(
      stream: DedaBackend.publishedPlaceStream(publishedId),
      builder: (context, snapshot) {
        final live = snapshot.data?['isAvailableNow'];
        final available = live is bool ? live : fallback;
        return _detailRow(
          t('حالة التواجد', 'Availability'),
          available
              ? t('متواجد الآن', 'Available now')
              : t('غير متواجد حاليًا', 'Not available now'),
        );
      },
    );
  }

  Future<String?> _askSupportReply() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(t('الرد على المستخدم', 'Reply to user')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              spacing: 6,
              children: [
                ActionChip(
                  label: Text(t('جاري المراجعة', 'Under review')),
                  onPressed: () => controller.text = t(
                    'جاري مراجعة المشكلة وسنوافيك بالتحديث.',
                    'We are reviewing the issue and will update you.',
                  ),
                ),
                ActionChip(
                  label: Text(t('تم حل المشكلة', 'Issue resolved')),
                  onPressed: () => controller.text = t(
                    'تم حل المشكلة. شكرًا لتواصلك مع DEDA.',
                    'The issue has been resolved. Thank you for contacting DEDA.',
                  ),
                ),
                ActionChip(
                  label: Text(t('نحتاج معلومات إضافية', 'Need more information')),
                  onPressed: () => controller.text = t(
                    'نحتاج معلومات إضافية حتى نكمل معالجة طلبك.',
                    'We need additional information to continue handling your request.',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              minLines: 3,
              maxLines: 7,
              decoration: InputDecoration(
                labelText: t('رد الإدارة', 'Administration reply'),
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(t('إلغاء', 'Cancel')),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            icon: const Icon(Icons.send_outlined),
            label: Text(t('إرسال الرد', 'Send reply')),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _replySupport(String id) async {
    final message = await _askSupportReply();
    if (message == null || message.trim().isEmpty) return;
    try {
      await DedaBackend.replyToSupport(id: id, message: message);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('تم إرسال الرد للمستخدم.', 'Reply sent to the user.'))),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('تعذر إرسال الرد الآن.', 'Could not send the reply now.'))),
      );
    }
  }

  Future<void> _setSupportStatus(String id, String status) async {
    try {
      await DedaBackend.updateSupportStatus(id: id, status: status);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('تعذر تحديث حالة الدعم.', 'Could not update support status.'))),
      );
    }
  }

  Widget _supportActions({required String status, required String id}) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          onPressed: status == 'in_progress'
              ? null
              : () => _setSupportStatus(id, 'in_progress'),
          icon: const Icon(Icons.hourglass_top),
          label: Text(t('قيد المعالجة', 'In progress')),
        ),
        FilledButton.icon(
          onPressed: () => _replySupport(id),
          icon: const Icon(Icons.reply),
          label: Text(t('إرسال رد', 'Send reply')),
        ),
        OutlinedButton.icon(
          onPressed: status == 'closed'
              ? null
              : () => _setSupportStatus(id, 'closed'),
          icon: const Icon(Icons.task_alt),
          label: Text(t('تم الحل / إغلاق', 'Resolve / close')),
        ),
      ],
    );
  }

  Future<void> _showUserAccount({
    required String ownerUid,
    required String sourceId,
  }) async {
    if (ownerUid.isEmpty) return;
    try {
      final snapshot = await DedaBackend.adminUserSnapshot(
        ownerUid: ownerUid,
        sourceCollection: widget.collection,
        sourceId: sourceId,
      );
      if (!mounted) return;
      final profile = Map<String, dynamic>.from(
        snapshot['profile'] as Map? ?? const <String, dynamic>{},
      );
      final places = (snapshot['publishedPlaces'] as List? ?? const []);
      final requests = (snapshot['placeRequests'] as List? ?? const []);
      final support = (snapshot['supportRequests'] as List? ?? const []);
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.visibility_outlined),
              const SizedBox(width: 8),
              Expanded(child: Text(t('حساب المستخدم • قراءة فقط', 'User account • read only'))),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _detailRow(t('الاسم', 'Name'), profile['name']),
                _detailRow(t('الهاتف', 'Phone'), profile['phone'], ltr: true),
                _detailRow(t('نوع الحساب', 'Account type'), profile['accountType']),
                const Divider(),
                _detailRow(t('الأماكن المعتمدة', 'Approved places'), places.length),
                _detailRow(t('طلبات الأماكن', 'Place requests'), requests.length),
                _detailRow(t('رسائل الدعم', 'Support messages'), support.length),
                if (places.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(t('أماكن المستخدم', 'User places'), style: const TextStyle(fontWeight: FontWeight.bold)),
                  ...places.take(10).map((raw) {
                    final item = Map<String, dynamic>.from(raw as Map);
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.storefront_outlined),
                      title: Text(_text(item['placeName'])),
                      subtitle: Text(_text(item['approvalNumber'])),
                    );
                  }),
                ],
                const SizedBox(height: 8),
                Text(
                  t(
                    'لا يمكن تعديل بيانات المستخدم من هذه النافذة. تم تسجيل هذه المشاهدة في السجل الإداري.',
                    'User data cannot be edited here. This review was recorded in the admin audit log.',
                  ),
                  style: const TextStyle(fontSize: 12.5, color: Color(0xFF5B665D)),
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
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('تعذر فتح حساب المستخدم الآن.', 'Could not open the user account now.'))),
      );
    }
  }

  Future<String?> _askDecisionNote(String status) async {
    final controller = TextEditingController();
    final isReject = status == 'rejected';
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          isReject
              ? t('تأكيد رفض الطلب', 'Confirm rejection')
              : t('الطلب يحتاج تعديل', 'Request changes'),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isReject
                  ? t(
                      'اكتب سبب الرفض أو الملاحظة التي ستصل لصاحب المكان.',
                      'Enter the rejection reason or note that will reach the place owner.',
                    )
                  : t(
                      'اكتب التعديل المطلوب بوضوح ليصل إلى صاحب المكان.',
                      'Clearly describe the required changes for the place owner.',
                    ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              minLines: 2,
              maxLines: 5,
              decoration: InputDecoration(
                labelText: isReject
                    ? t('سبب الرفض', 'Rejection reason')
                    : t('التعديل المطلوب', 'Required change'),
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(t('إلغاء', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            style: isReject
                ? FilledButton.styleFrom(backgroundColor: const Color(0xFFB3261E))
                : null,
            child: Text(isReject ? t('تأكيد الرفض', 'Reject') : t('إرسال الملاحظة', 'Send note')),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<String?> _editApprovalMessage(Map<String, dynamic> prepared) async {
    final controller = TextEditingController(text: prepared['message']?.toString() ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(t('رسالة اعتماد المكان', 'Place approval message')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                t(
                  'جهّز DEDA البيانات تلقائياً. راجع الرسالة، وعدّلها فقط إذا وجدت خطأ، ثم اضغط إرسال.',
                  'DEDA generated the details automatically. Review the message, edit only if needed, then press Send.',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                minLines: 5,
                maxLines: 8,
                decoration: const InputDecoration(border: OutlineInputBorder()),
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
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            icon: const Icon(Icons.send_outlined),
            label: Text(t('إرسال واعتماد', 'Send & approve')),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _approveAndNotify(String id) async {
    try {
      final prepared = await DedaBackend.preparePlaceApproval(id);
      if (!mounted) return;
      final message = await _editApprovalMessage(prepared);
      if (message == null) return;
      await DedaBackend.finalizePlaceApproval(id: id, message: message);
      if (!mounted) return;
      setState(() => _expandedId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            t(
              'تم اعتماد المكان وإرسال الرد لصاحب المكان.',
              'The place was approved and the reply was sent to the owner.',
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
              'تعذر اعتماد الطلب. تأكد من اكتمال البيانات وحاول مرة أخرى.',
              'Could not approve the request. Check the details and try again.',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _changeStatus({
    required String id,
    required String status,
  }) async {
    if (status == 'approved') {
      await _approveAndNotify(id);
      return;
    }

    String? note;
    if (status == 'rejected' || status == 'needs_changes') {
      note = await _askDecisionNote(status);
      if (note == null) return;
    }

    try {
      await DedaBackend.updateRequestStatus(
        collection: widget.collection,
        id: id,
        status: status,
        note: note,
      );
      if (!mounted) return;
      setState(() => _expandedId = null);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            t(
              'تعذر تحديث الطلب. تأكد من اكتمال بياناته وحاول مرة أخرى.',
              'Could not update the request. Check that its details are complete and try again.',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _markViewed(String id) async {
    try {
      await DedaBackend.markRequestViewed(
        collection: widget.collection,
        id: id,
      );
    } catch (_) {
      // Keep the unread indicator if the server could not save the view.
    }
  }

  Widget _requestDetails(Map<String, dynamic> data, String id) {
    final commonAudit = _auditDetails(data);

    if (widget.collection == 'support_requests') {
      final imageUrl = _text(data['imageUrl']);
      final imageBase64 = _text(data['imageBase64']);
      final linkedPlaceId = _text(data['linkedPlaceId']);
      final linkedPlaceName = _text(data['linkedPlaceName']);
      final linkedLatitude = (data['linkedLatitude'] as num?)?.toDouble();
      final linkedLongitude = (data['linkedLongitude'] as num?)?.toDouble();
      final reply = _text(data['adminReply']);
      final ownerUid = _text(data['ownerUid']);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _detailRow(
            t('نوع التواصل', 'Contact type'),
            _supportTypeLabel(_text(data['type'])),
          ),
          _detailRow(t('الاسم', 'Name'), data['name']),
          _detailRow(t('الهاتف', 'Phone'), data['phone'], ltr: true),
          _detailRow(t('الرسالة', 'Message'), data['message']),
          if (imageUrl.isNotEmpty || imageBase64.isNotEmpty) ...[
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: imageUrl.isNotEmpty
                  ? Image.network(
                      imageUrl,
                      height: 190,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        height: 70,
                        alignment: Alignment.center,
                        color: const Color(0xFFEAF4E7),
                        child: Text(t('تعذر عرض الصورة.', 'Could not display image.')),
                      ),
                    )
                  : Image.memory(
                      base64Decode(imageBase64),
                      height: 190,
                      fit: BoxFit.cover,
                    ),
            ),
          ],
          if (linkedPlaceId.isNotEmpty) ...[
            const SizedBox(height: 12),
            Card(
              elevation: 0,
              color: const Color(0xFFEAF4E7),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${t('المكان المرتبط', 'Linked place')}: ${linkedPlaceName.isEmpty ? linkedPlaceId : linkedPlaceName}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    if (_text(data['linkedApprovalNumber']).isNotEmpty)
                      Text('${t('رقم الاعتماد', 'Approval number')}: ${_text(data['linkedApprovalNumber'])}'),
                    if (linkedLatitude != null && linkedLongitude != null)
                      OutlinedButton.icon(
                        onPressed: () => _openMap(
                          latitude: linkedLatitude,
                          longitude: linkedLongitude,
                          placeName: linkedPlaceName,
                        ),
                        icon: const Icon(Icons.map_outlined),
                        label: Text(t('فتح المكان مباشرة', 'Open linked place')),
                      ),
                  ],
                ),
              ),
            ),
          ],
          if (reply.isNotEmpty) ...[
            const SizedBox(height: 10),
            _detailRow(t('رد الإدارة', 'Administration reply'), reply),
          ],
          if (ownerUid.isNotEmpty)
            OutlinedButton.icon(
              onPressed: () => _showUserAccount(ownerUid: ownerUid, sourceId: id),
              icon: const Icon(Icons.visibility_outlined),
              label: Text(t('عرض حساب المستخدم • قراءة فقط', 'View user account • read only')),
            ),
          commonAudit,
        ],
      );
    }

    final latitude = (data['latitude'] as num?)?.toDouble();
    final longitude = (data['longitude'] as num?)?.toDouble();
    final placeName = _text(data['placeName']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _detailRow(t('نوع المكان', 'Place type'), _placeType(data)),
        _detailRow(t('الهاتف', 'Phone'), data['phone'], ltr: true),
        _detailRow(t('المحافظة', 'Governorate'), data['governorate']),
        _detailRow(t('العنوان', 'Address'), data['address']),
        _detailRow(t('أوقات العمل', 'Opening hours'), data['openingHours']),
        _detailRow(t('الوصف', 'Description'), data['description']),
        _liveAvailability(data, id),
        _detailRow(
          t('الإحداثيات', 'Coordinates'),
          latitude == null || longitude == null
              ? ''
              : '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}',
          ltr: true,
        ),
        if (latitude != null && longitude != null)
          OutlinedButton.icon(
            onPressed: () => _openMap(
              latitude: latitude,
              longitude: longitude,
              placeName: placeName,
            ),
            icon: const Icon(Icons.map_outlined),
            label: Text(
              t('فتح الموقع على الخريطة', 'Open location on map'),
            ),
          ),
        commonAudit,
      ],
    );
  }

  Widget _statusButton({
    required String currentStatus,
    required String targetStatus,
    required String id,
    required String arLabel,
    required String enLabel,
    Color selectedColor = const Color(0xFF17652F),
  }) {
    final selected = currentStatus == targetStatus;
    return OutlinedButton(
      onPressed: selected
          ? null
          : () => _changeStatus(id: id, status: targetStatus),
      style: OutlinedButton.styleFrom(
        backgroundColor: selected ? selectedColor : null,
        foregroundColor: selected ? Colors.white : null,
        disabledBackgroundColor: selected ? selectedColor : null,
        disabledForegroundColor: selected ? Colors.white : null,
      ),
      child: Text(t(arLabel, enLabel)),
    );
  }

  bool _matchesSection(String status) {
    if (widget.collection == 'support_requests') {
      switch (_section) {
        case 'approved':
          return status == 'replied';
        case 'rejected':
          return status == 'closed';
        default:
          return status == 'new' || status == 'in_progress';
      }
    }
    switch (_section) {
      case 'approved':
        return status == 'approved';
      case 'rejected':
        return status == 'rejected';
      default:
        return status != 'approved' && status != 'rejected';
    }
  }

  int _countSection(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    String section,
  ) {
    return docs.where((doc) {
      final status = _text(doc.data()['status']);
      if (widget.collection == 'support_requests') {
        if (section == 'approved') return status == 'replied';
        if (section == 'rejected') return status == 'closed';
        return status == 'new' || status == 'in_progress';
      }
      if (section == 'approved') return status == 'approved';
      if (section == 'rejected') return status == 'rejected';
      return status != 'approved' && status != 'rejected';
    }).length;
  }

  Widget _sectionChip({
    required String value,
    required String arLabel,
    required String enLabel,
    required int count,
  }) {
    return ChoiceChip(
      selected: _section == value,
      selectedColor: const Color(0xFFDDEDDD),
      label: Text('${t(arLabel, enLabel)} ($count)'),
      onSelected: (_) {
        setState(() {
          _section = value;
          _expandedId = null;
        });
      },
    );
  }

  Widget _actionsForStatus({
    required String status,
    required String id,
  }) {
    if (widget.collection == 'support_requests') {
      return _supportActions(status: status, id: id);
    }
    if (status == 'approved' || status == 'rejected') {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _statusButton(
            currentStatus: status,
            targetStatus: 'reviewing',
            id: id,
            arLabel: 'إعادة للمراجعة',
            enLabel: 'Return to review',
          ),
        ],
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _statusButton(
          currentStatus: status,
          targetStatus: 'reviewing',
          id: id,
          arLabel: 'قيد المراجعة',
          enLabel: 'Under review',
        ),
        _statusButton(
          currentStatus: status,
          targetStatus: 'needs_changes',
          id: id,
          arLabel: 'يحتاج تعديل',
          enLabel: 'Needs changes',
          selectedColor: const Color(0xFFB26A00),
        ),
        _statusButton(
          currentStatus: status,
          targetStatus: 'approved',
          id: id,
          arLabel: 'اعتماد',
          enLabel: 'Approve',
        ),
        _statusButton(
          currentStatus: status,
          targetStatus: 'rejected',
          id: id,
          arLabel: 'رفض',
          enLabel: 'Reject',
          selectedColor: const Color(0xFFB3261E),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: widget.stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text(t('تعذر تحميل الطلبات.', 'Could not load requests.')),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final allDocuments = snapshot.data!.docs;
        final currentCount = _countSection(allDocuments, 'current');
        final approvedCount = _countSection(allDocuments, 'approved');
        final rejectedCount = _countSection(allDocuments, 'rejected');
        final documents = allDocuments.where((doc) {
          final status = _text(doc.data()['status']);
          return _matchesSection(status);
        }).toList();

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _sectionChip(
                      value: 'current',
                      arLabel: 'الحالية',
                      enLabel: 'Current',
                      count: currentCount,
                    ),
                    const SizedBox(width: 8),
                    _sectionChip(
                      value: 'approved',
                      arLabel: widget.collection == 'support_requests' ? 'تم الرد' : 'المعتمدات',
                      enLabel: widget.collection == 'support_requests' ? 'Replied' : 'Approved',
                      count: approvedCount,
                    ),
                    const SizedBox(width: 8),
                    _sectionChip(
                      value: 'rejected',
                      arLabel: widget.collection == 'support_requests' ? 'المغلقة' : 'المرفوضات',
                      enLabel: widget.collection == 'support_requests' ? 'Closed' : 'Rejected',
                      count: rejectedCount,
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: documents.isEmpty
                  ? Center(
                      child: Text(
                        _section == 'approved'
                            ? t(
                                'لا توجد طلبات معتمدة في هذا القسم.',
                                'There are no approved requests in this section.',
                              )
                            : _section == 'rejected'
                                ? t(
                                    'لا توجد طلبات مرفوضة في هذا القسم.',
                                    'There are no rejected requests in this section.',
                                  )
                                : t(
                                    'لا توجد طلبات حالية.',
                                    'There are no current requests.',
                                  ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: documents.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final doc = documents[index];
                        final data = doc.data();
                        final title = (data['name'] ??
                                data['placeName'] ??
                                t('طلب جديد', 'New request'))
                            .toString();
                        final status = (data['status'] ?? 'new').toString();
                        final expanded = _expandedId == doc.id;
                        final unread = data['firstViewedAt'] == null &&
                            status != 'approved' &&
                            status != 'rejected';

                        return Card(
                          clipBehavior: Clip.antiAlias,
                          color: expanded ? const Color(0xFFEAF4E7) : null,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(
                              color: expanded
                                  ? const Color(0xFF17652F)
                                  : Colors.transparent,
                              width: expanded ? 2 : 0,
                            ),
                          ),
                          child: ExpansionTile(
                            key: ValueKey('${doc.id}-$expanded'),
                            initiallyExpanded: expanded,
                            onExpansionChanged: (isExpanded) {
                              setState(
                                () => _expandedId =
                                    isExpanded ? doc.id : null,
                              );
                              if (isExpanded && data['firstViewedAt'] == null) {
                                _markViewed(doc.id);
                              }
                            },
                            shape: const RoundedRectangleBorder(
                              side: BorderSide.none,
                            ),
                            collapsedShape: const RoundedRectangleBorder(
                              side: BorderSide.none,
                            ),
                            leading: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Icon(
                                  widget.collection == 'support_requests'
                                      ? Icons.support_agent
                                      : Icons.storefront,
                                  color: const Color(0xFF17652F),
                                ),
                                if (unread)
                                  Positioned(
                                    right: -7,
                                    top: -5,
                                    child: Container(
                                      width: 11,
                                      height: 11,
                                      decoration: const BoxDecoration(
                                        color: Color(0xFFD62828),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            title: Text(
                              title,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              '${t('الحالة', 'Status')}: '
                              '${statusLabel(status)}',
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (expanded) ...[
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFD4E8D4),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      t('مفتوح الآن', 'Open now'),
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF17652F),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                ],
                                Icon(
                                  expanded
                                      ? Icons.keyboard_arrow_up
                                      : Icons.keyboard_arrow_down,
                                ),
                              ],
                            ),
                            childrenPadding:
                                const EdgeInsets.fromLTRB(16, 0, 16, 14),
                            children: [
                              _requestDetails(data, doc.id),
                              const SizedBox(height: 12),
                              _actionsForStatus(
                                status: status,
                                id: doc.id,
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
    );
  }
}
