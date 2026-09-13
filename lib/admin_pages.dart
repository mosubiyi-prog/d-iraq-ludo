import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

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

class DedaAdminInboxPage extends StatelessWidget {
  final bool isArabic;

  const DedaAdminInboxPage({super.key, required this.isArabic});

  String t(String ar, String en) => isArabic ? ar : en;

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
          bottom: TabBar(tabs: [Tab(text: t('الدعم', 'Support')), Tab(text: t('طلبات الأماكن', 'Places'))]),
        ),
        body: TabBarView(
          children: [
            _RequestList(isArabic: isArabic, collection: 'support_requests', stream: DedaBackend.supportRequests()),
            _RequestList(isArabic: isArabic, collection: 'place_requests', stream: DedaBackend.placeRequests()),
          ],
        ),
      ),
    );
  }
}

class _RequestList extends StatelessWidget {
  final bool isArabic;
  final String collection;
  final Stream<QuerySnapshot<Map<String, dynamic>>> stream;

  const _RequestList({required this.isArabic, required this.collection, required this.stream});

  String t(String ar, String en) => isArabic ? ar : en;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
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
            final details = collection == 'support_requests'
                ? (data['message'] ?? '').toString()
                : '${data[isArabic ? 'categoryLabelAr' : 'categoryLabelEn'] ?? data['category'] ?? ''}\n${data['governorate'] ?? ''} — ${data['address'] ?? ''}';
            return Card(
              child: ExpansionTile(
                leading: Icon(collection == 'support_requests' ? Icons.support_agent : Icons.storefront, color: const Color(0xFF17652F)),
                title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('${t('الحالة', 'Status')}: $status'),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                children: [
                  Align(alignment: AlignmentDirectional.centerStart, child: SelectableText(details)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton(onPressed: () => DedaBackend.updateRequestStatus(collection: collection, id: doc.id, status: 'reviewing'), child: Text(t('قيد المراجعة', 'Reviewing'))),
                      FilledButton(onPressed: () => DedaBackend.updateRequestStatus(collection: collection, id: doc.id, status: 'approved'), child: Text(t('اعتماد', 'Approve'))),
                      TextButton(onPressed: () => DedaBackend.updateRequestStatus(collection: collection, id: doc.id, status: 'rejected'), child: Text(t('رفض', 'Reject'))),
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
