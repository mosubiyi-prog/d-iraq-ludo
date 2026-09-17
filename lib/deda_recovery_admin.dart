import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class DedaRecoveryAdminList extends StatelessWidget {
  final bool isArabic;

  const DedaRecoveryAdminList({
    super.key,
    required this.isArabic,
  });

  String t(String ar, String en) => isArabic ? ar : en;

  String _statusLabel(String status) {
    switch (status) {
      case 'new':
        return t('جديد', 'New');
      case 'review':
        return t('يحتاج تدقيق', 'Needs review');
      case 'low_risk':
        return t('منخفض الخطورة', 'Low risk');
      case 'approved':
        return t('جارٍ إصدار رمز جديد', 'Issuing new code');
      case 'ready':
        return t('تم إصدار رمز جديد', 'New code issued');
      case 'rejected':
        return t('مرفوض', 'Rejected');
      case 'error':
        return t('تعذر التنفيذ', 'Processing failed');
      default:
        return status;
    }
  }

  String _riskLabel(Map<String, dynamic> data) {
    final risk = (data['riskLevel'] ?? '').toString();
    if (risk == 'low') return t('منخفض الخطورة', 'Low risk');
    if (risk == 'review') return t('يحتاج تدقيق', 'Needs review');
    return t('بانتظار فحص النظام', 'Waiting for system check');
  }

  String _formatTime(dynamic value) {
    if (value is! Timestamp) return '';
    final date = value.toDate().toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${date.year} '
        '${two(date.hour)}:${two(date.minute)}';
  }

  Future<void> _approve(BuildContext context, String id) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    try {
      await FirebaseFirestore.instance
          .collection('recovery_requests')
          .doc(id)
          .update(<String, dynamic>{
        'status': 'approved',
        'approvedBy': uid,
        'approvedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            t(
              'تم اعتماد الطلب. النظام سيصدر رمزًا جديدًا للمستخدم.',
              'Request approved. The system will issue a new code.',
            ),
          ),
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            t(
              'تعذر اعتماد الطلب الآن.',
              'Could not approve the request now.',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _reject(BuildContext context, String id) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    try {
      await FirebaseFirestore.instance
          .collection('recovery_requests')
          .doc(id)
          .update(<String, dynamic>{
        'status': 'rejected',
        'rejectedBy': uid,
        'rejectedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            t('تعذر رفض الطلب الآن.', 'Could not reject the request now.'),
          ),
        ),
      );
    }
  }

  Widget _flag(String text, {required bool warning}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: warning
            ? const Color(0xFFFFF0E2)
            : const Color(0xFFEAF6EC),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: warning
              ? const Color(0xFFE4A45B)
              : const Color(0xFF82B88B),
        ),
      ),
      child: Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('recovery_requests')
          .orderBy('createdAt', descending: true)
          .limit(100)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                t(
                  'تعذر تحميل طلبات استرجاع الدخول.',
                  'Could not load sign-in recovery requests.',
                ),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return Center(
            child: Text(
              t(
                'لا توجد طلبات استرجاع حاليًا.',
                'There are no recovery requests.',
              ),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data();
            final status = (data['status'] ?? 'new').toString();
            final sameDevice = data['sameDevice'] == true;
            final nameMatches = data['nameMatches'] == true;
            final classified = data.containsKey('riskLevel');
            final canDecide = status == 'new' || status == 'review';

            return Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.lock_reset,
                          color: Color(0xFF17652F),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            (data['fullName'] ?? '').toString(),
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 17,
                            ),
                          ),
                        ),
                        _flag(
                          _riskLabel(data),
                          warning: data['riskLevel'] != 'low',
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SelectableText(
                      '${t('الهاتف', 'Phone')}: ${(data['phone'] ?? '').toString()}',
                      textDirection: TextDirection.ltr,
                    ),
                    if (_formatTime(data['createdAt']).isNotEmpty)
                      Text(
                        '${t('وقت الطلب', 'Requested')}: ${_formatTime(data['createdAt'])}',
                      ),
                    const SizedBox(height: 8),
                    Text(
                      '${t('الحالة', 'Status')}: ${_statusLabel(status)}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    if (classified) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _flag(
                            sameDevice
                                ? t('جهاز معروف', 'Known device')
                                : t('جهاز جديد', 'New device'),
                            warning: !sameDevice,
                          ),
                          _flag(
                            nameMatches
                                ? t('الاسم مطابق', 'Name matches')
                                : t('الاسم غير مطابق', 'Name mismatch'),
                            warning: !nameMatches,
                          ),
                        ],
                      ),
                    ],
                    if ((data['processingError'] ?? '')
                        .toString()
                        .trim()
                        .isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        t(
                          'تعذر إصدار الرمز آليًا. راجع إعدادات النظام.',
                          'Automatic code issuance failed. Check system settings.',
                        ),
                        style: const TextStyle(color: Colors.red),
                      ),
                    ],
                    if (canDecide) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () => _approve(context, doc.id),
                              icon: const Icon(Icons.check_circle_outline),
                              label: Text(
                                t(
                                  'اعتماد وإصدار رمز جديد',
                                  'Approve and issue new code',
                                ),
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF17652F),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: () => _reject(context, doc.id),
                            icon: const Icon(Icons.close),
                            label: Text(t('رفض', 'Reject')),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
