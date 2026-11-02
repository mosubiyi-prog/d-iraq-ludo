import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import 'deda_backend.dart';

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
        return t('بانتظار مراجعة الإدارة', 'Waiting for admin review');
      case 'review':
        return t('قيد المراجعة', 'Under review');
      case 'ready':
        return t('تم إصدار رمز جديد', 'New code issued');
      case 'rejected':
        return t('مرفوض', 'Rejected');
      default:
        return status;
    }
  }

  String _formatTime(dynamic value) {
    if (value is! Timestamp) return '';
    final date = value.toDate().toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${date.year} '
        '${two(date.hour)}:${two(date.minute)}';
  }

  String _normalizeName(String value) =>
      value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

  Future<void> _approve(
    BuildContext context,
    String id,
    Map<String, dynamic> data,
  ) async {
    // All mutations belong to the privileged server callable. The former
    // client Firestore batch changed only legacy credentials and stranded
    // the original Firebase Auth UID on its old six-digit password.
    // Never create a second user or expose a code until BOTH stores agree.
    final accountKey = (data['accountKey'] ?? '').toString().trim();
    if (FirebaseAuth.instance.currentUser == null ||
        accountKey.isEmpty || id.trim().isEmpty) return;
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('dedaApproveLinkedPinRecovery')
          .call(<String, dynamic>{'requestId': id});
      final payload = result.data;
      if (payload is! Map || payload['status'] != 'ready' ||
          payload['linkedUidPreserved'] != true) {
        throw StateError('recovery-pin-sync-not-confirmed');
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(t(
          'تم اعتماد طلب استرجاع الرمز للحساب الأصلي. '
          'ظهر الرمز بعد تأكيد تحديث Firebase ونفس الهوية.',
          'Original account recovery approved. New PIN issued only '
          'after same-UID Firebase and credential synchronization.',
        )),
      ));
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(t(
          'لم يتم تأكيد إصدار الرمز الجديد. '
          'بقي الحساب الأصلي محفوظاً؛ أعد المحاولة أو راجع الطلب.',
          'New PIN was not confirmed. Original account preserved; '
          'retry the same request or review its status.',
        )),
      ));
    }
  }

  Future<void> _reject(BuildContext context, String id) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(t('رفض طلب الاسترجاع', 'Reject recovery request')),
        content: TextField(
          controller: controller,
          minLines: 2,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: t('سبب الرفض', 'Reason for rejection'),
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
            child: Text(t('تأكيد الرفض', 'Confirm rejection')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (reason == null || reason.isEmpty) return;

    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return;

    try {
      final firestore = FirebaseFirestore.instance;
      final adminProfile = await DedaBackend.currentAdminProfile();
      final batch = firestore.batch();
      final requestRef = firestore.collection('recovery_requests').doc(id);
      final auditRef = firestore.collection('admin_audit').doc();

      batch.update(requestRef, <String, dynamic>{
        'status': 'rejected',
        'rejectedBy': uid,
        'rejectedAt': FieldValue.serverTimestamp(),
        'rejectionReason': reason,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      batch.set(auditRef, <String, dynamic>{
        'action': 'recovery_rejected',
        'adminUid': uid,
        'adminName': (adminProfile['displayName'] ?? '').toString(),
        'adminRole': DedaBackend.normalizeAdminRole(adminProfile['role']),
        'sourceCollection': 'recovery_requests',
        'sourceId': id,
        'reason': reason,
        'createdAt': FieldValue.serverTimestamp(),
      });
      await batch.commit();
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

  Widget _badge(String text, {required bool warning}) {
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

  Widget _registeredAccountInfo(Map<String, dynamic> requestData) {
    final accountKey = (requestData['accountKey'] ?? '').toString().trim();
    if (accountKey.isEmpty) {
      return _badge(t('رقم الحساب غير مكتمل', 'Account key missing'),
          warning: true);
    }

    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance
          .collection('deda_account_profiles')
          .doc(accountKey)
          .get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Text(
            t('جارٍ مطابقة بيانات الحساب...', 'Checking account data...'),
            style: const TextStyle(fontSize: 12),
          );
        }

        final profile = snapshot.data?.data();
        if (profile == null) {
          return _badge(
            t('الحساب موجود لكن ملفه القديم غير مكتمل',
                'Account exists but its old profile is incomplete'),
            warning: true,
          );
        }

        final registeredName = (profile['name'] ?? '').toString().trim();
        final requestedName = (requestData['fullName'] ?? '').toString().trim();
        final matches = registeredName.isNotEmpty &&
            _normalizeName(registeredName) == _normalizeName(requestedName);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${t('الاسم المسجل', 'Registered name')}: $registeredName',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: _badge(
                matches
                    ? t('الاسم مطابق', 'Name matches')
                    : t('الاسم يحتاج تدقيق', 'Name needs review'),
                warning: !matches,
              ),
            ),
          ],
        );
      },
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
                        _badge(
                          _statusLabel(status),
                          warning: canDecide || status == 'rejected',
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
                    const SizedBox(height: 10),
                    _registeredAccountInfo(data),
                    if (canDecide) ...[
                      const SizedBox(height: 14),
                      Text(
                        t(
                          'راجع الاسم ورقم الهاتف، ثم اعتمد الطلب فقط إذا تأكدت من صاحب الحساب.',
                          'Review the name and phone number, then approve only after confirming the account owner.',
                        ),
                        style: const TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () => _approve(context, doc.id, data),
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
