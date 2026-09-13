import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

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
        setState(() => _error = t('هذا الحساب ليس مديرًا معتمدًا.', 'This is not an approved admin account.'));
        return;
      }
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => DedaAdminInboxPage(isArabic: widget.isArabic),
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(() => _error = t('تعذر تسجيل الدخول. تحقق من البيانات واتصال الإنترنت.', 'Sign-in failed. Check the details and internet connection.'));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
                const Icon(Icons.admin_panel_settings, size: 72, color: Color(0xFF17652F)),
                const SizedBox(height: 18),
                Text(t('دخول الإدارة المحمي', 'Protected admin sign-in'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 25, fontWeight: FontWeight.bold)),
                const SizedBox(height: 22),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(labelText: t('البريد الإلكتروني الإداري', 'Admin email'), prefixIcon: const Icon(Icons.email_outlined), border: const OutlineInputBorder()),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _password,
                  obscureText: true,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(labelText: t('كلمة المرور', 'Password'), prefixIcon: const Icon(Icons.lock_outline), border: const OutlineInputBorder()),
                  onSubmitted: (_) => _login(),
                ),
                if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red))),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: _loading ? null : _login,
                  icon: _loading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.login),
                  label: Text(t('دخول', 'Sign in')),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56), backgroundColor: const Color(0xFF17652F)),
                ),
              ],
            ),
          ),
        ),
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

  Future<bool> _leaveAdmin() async {
    await DedaBackend.signOutAdmin();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _leaveAdmin,
      child: DefaultTabController(
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
      ),
    );
  }
}

class _RequestList extends StatefulWidget {
  final bool isArabic;
  final String collection;
  final Stream<QuerySnapshot<Map<String, dynamic>>> stream;

  const _RequestList({required this.isArabic, required this.collection, required this.stream});

  @override
  State<_RequestList> createState() => _RequestListState();
}

class _RequestListState extends State<_RequestList> {
  String? _expandedId;

  String t(String ar, String en) => widget.isArabic ? ar : en;

  String statusLabel(String status) {
    switch (status) {
      case 'pending':
        return t('قيد الانتظار', 'Pending');
      case 'reviewing':
        return t('قيد المراجعة', 'Under review');
      case 'approved':
        return t('معتمد', 'Approved');
      case 'rejected':
        return t('مرفوض', 'Rejected');
      case 'new':
        return t('جديد', 'New');
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
        return t('التواصل مع الشركة مباشرة', 'Contact company directly');
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

  Widget _detailRow(String label, dynamic value, {bool ltr = false}) {
    final text = _text(value);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w700)),
          Expanded(
            child: Directionality(
              textDirection: ltr ? TextDirection.ltr : Directionality.of(context),
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

  Future<void> _openMap(double latitude, double longitude) async {
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$latitude,$longitude',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _changeStatus({
    required String id,
    required String status,
  }) async {
    try {
      await DedaBackend.updateRequestStatus(
        collection: widget.collection,
        id: id,
        status: status,
      );
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

  Widget _requestDetails(Map<String, dynamic> data) {
    if (widget.collection == 'support_requests') {
      final imageUrl = _text(data['imageUrl']);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _detailRow(t('نوع التواصل', 'Contact type'), _supportTypeLabel(_text(data['type']))),
          _detailRow(t('الاسم', 'Name'), data['name']),
          _detailRow(t('الهاتف', 'Phone'), data['phone'], ltr: true),
          _detailRow(t('الرسالة', 'Message'), data['message']),
          if (imageUrl.isNotEmpty) ...[
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.network(
                imageUrl,
                height: 190,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  height: 70,
                  alignment: Alignment.center,
                  color: const Color(0xFFEAF4E7),
                  child: Text(t('تعذر عرض الصورة.', 'Could not display image.')),
                ),
              ),
            ),
          ],
        ],
      );
    }

    final latitude = (data['latitude'] as num?)?.toDouble();
    final longitude = (data['longitude'] as num?)?.toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _detailRow(t('نوع المكان', 'Place type'), _placeType(data)),
        _detailRow(t('الهاتف', 'Phone'), data['phone'], ltr: true),
        _detailRow(t('المحافظة', 'Governorate'), data['governorate']),
        _detailRow(t('العنوان', 'Address'), data['address']),
        _detailRow(t('أوقات العمل', 'Opening hours'), data['openingHours']),
        _detailRow(t('الوصف', 'Description'), data['description']),
        _detailRow(
          t('حالة التواجد', 'Availability'),
          data['isAvailableNow'] == true
              ? t('متواجد الآن', 'Available now')
              : t('غير متواجد حاليًا', 'Not available now'),
        ),
        _detailRow(
          t('الإحداثيات', 'Coordinates'),
          latitude == null || longitude == null
              ? ''
              : '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}',
          ltr: true,
        ),
        if (latitude != null && longitude != null)
          OutlinedButton.icon(
            onPressed: () => _openMap(latitude, longitude),
            icon: const Icon(Icons.map_outlined),
            label: Text(t('فتح الموقع على الخريطة', 'Open location on map')),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: widget.stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text(t('تعذر تحميل الطلبات.', 'Could not load requests.')));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final documents = snapshot.data!.docs;
        if (documents.isEmpty) return Center(child: Text(t('لا توجد طلبات حاليًا.', 'No requests yet.')));
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: documents.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final doc = documents[index];
            final data = doc.data();
            final title = (data['name'] ?? data['placeName'] ?? t('طلب جديد', 'New request')).toString();
            final status = (data['status'] ?? 'new').toString();
            final isFinal = status == 'approved' || status == 'rejected';
            return Card(
              clipBehavior: Clip.antiAlias,
              child: ExpansionTile(
                key: ValueKey('${doc.id}-${_expandedId == doc.id}'),
                initiallyExpanded: _expandedId == doc.id,
                onExpansionChanged: (expanded) {
                  setState(() => _expandedId = expanded ? doc.id : null);
                },
                shape: const RoundedRectangleBorder(side: BorderSide.none),
                collapsedShape: const RoundedRectangleBorder(side: BorderSide.none),
                leading: Icon(widget.collection == 'support_requests' ? Icons.support_agent : Icons.storefront, color: const Color(0xFF17652F)),
                title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('${t('الحالة', 'Status')}: ${statusLabel(status)}'),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                children: [
                  _requestDetails(data),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: isFinal || status == 'reviewing'
                            ? null
                            : () => _changeStatus(id: doc.id, status: 'reviewing'),
                        child: Text(t('قيد المراجعة', 'Under review')),
                      ),
                      FilledButton(
                        onPressed: isFinal
                            ? null
                            : () => _changeStatus(id: doc.id, status: 'approved'),
                        child: Text(t('اعتماد', 'Approve')),
                      ),
                      TextButton(
                        onPressed: isFinal
                            ? null
                            : () => _changeStatus(id: doc.id, status: 'rejected'),
                        child: Text(t('رفض', 'Reject')),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
