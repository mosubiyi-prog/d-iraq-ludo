import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'deda_100430_owner_uid_continuity.dart';
import 'deda_100431_linked_owner_session_policy.dart';
import 'deda_pin_auth.dart';
import 'deda_step2_visual_prefs_continuity.dart';
import 'deda_step2_owner_place_local_archive.dart';
import 'deda_step2_owner_place_backup_journal.dart';

/// DEDA 100433: explicit user action and non-persistent PIN entry only.
/// This is NOT password reset, not Google Sign-In and does not transfer money.
class DedaOwnerPinPrompt {
  const DedaOwnerPinPrompt._();

  static Future<String?> ask(
    BuildContext context, {
    required String title,
    required String explanation,
  }) => showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _DedaOwnerPinDialog(
      title: title, explanation: explanation),
  );
}

class _DedaOwnerPinDialog extends StatefulWidget {
  const _DedaOwnerPinDialog({
    required this.title, required this.explanation,
  });
  final String title, explanation;
  @override
  State<_DedaOwnerPinDialog> createState() => _DedaOwnerPinDialogState();
}

class _DedaOwnerPinDialogState extends State<_DedaOwnerPinDialog> {
  final controller = TextEditingController();
  @override
  void dispose() {
    controller.clear();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(widget.explanation),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('deda-owner-pin-input'),
          controller: controller,
          autofocus: true,
          obscureText: true,
          enableSuggestions: false,
          autocorrect: false,
          keyboardType: TextInputType.number,
          textDirection: TextDirection.ltr,
          maxLength: 6,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: 'رمز الحساب / Account PIN',
            border: OutlineInputBorder(),
          ),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('إلغاء / Cancel'),
      ),
      FilledButton(
        key: const ValueKey('deda-owner-pin-submit'),
        onPressed: () {
          final value = controller.text;
          if (RegExp(r'^\d{6}$').hasMatch(value)) {
            Navigator.pop(context, value);
          }
        },
        child: const Text('تأكيد / Confirm'),
      ),
    ],
  );
}

/// Visible above Sign out ONLY when owner explicitly opts into the private
/// build's separately reviewed account confirmation feature.
class DedaOwnerConfirmButton extends StatefulWidget {
  const DedaOwnerConfirmButton({
    super.key,
    required this.phone,
    required this.originalId,
    this.forTesting = false,
    this.confirm,
  });

  final String phone;
  final String originalId;
  final bool forTesting;
  final Future<String> Function(String phone,String pin,String originalId)? confirm;

  @override
  State<DedaOwnerConfirmButton> createState() => _DedaOwnerConfirmButtonState();
}

class _DedaOwnerConfirmButtonState extends State<DedaOwnerConfirmButton> {
  bool _running = false;

  Future<void> _submit() async {
    if (_running) return;
    final pin = await DedaOwnerPinPrompt.ask(
      context,
      title: 'تأكيد حساب DEDA / Confirm account',
      explanation: 'أدخل رمز حسابك على الهاتف الأصلي فقط. '
        'لا تسجل خروجك أو تحذف التطبيق قبل نجاح فحص الهاتف الثاني. '
        'هذه الخطوة لا تسترجع الماسات أو النقاط تلقائياً.',
    );
    if (pin == null || !mounted) return;
    setState(() => _running = true);
    try {
      // On a separately owner-approved private build ONLY: persist the
      // original phone's FREE appearance preferences BEFORE UID linking.
      // If this archive is missing or denied, leave the original anonymous
      // account intact, rather than linking and claiming a complete backup.
      // This never reads or credits paid frames, gems, points or prizes.
      if (dedaStep2VisualPrefsMigrationEnabled) {
        final originalUid = FirebaseAuth.instance.currentUser?.uid;
        if (originalUid == null || originalUid.isEmpty ||
            FirebaseAuth.instance.currentUser?.isAnonymous != true) {
          throw StateError('original-phone-session-required-for-visual-backup');
        }
        await DedaStep2VisualPrefsContinuity.firebase().saveOriginalPhone(
          accountKey: DedaPinAuth.accountKeyForPhone(widget.phone),
          originalId: widget.originalId,
          originalUid: originalUid,
          isCurrent: () => mounted &&
              FirebaseAuth.instance.currentUser?.uid == originalUid &&
              FirebaseAuth.instance.currentUser?.isAnonymous == true,
        );
        if (!mounted || FirebaseAuth.instance.currentUser?.uid != originalUid) {
          return;
        }
      }
      final confirmed = widget.confirm ??
          (phone,pin,originalId) => DedaOwnerUidContinuity.linkExistingOriginalUid(
                phone:phone,pin:pin,originalId:originalId);
      final uid = await confirmed(widget.phone,pin,widget.originalId);
      if (!mounted) return;
      if (uid.isEmpty) throw StateError('owner-link-failed');
      // PRIVATE QA ONLY. The original place archive requires a *linked*
      // (nonanonymous) owner UID, so it must run AFTER successful UID
      // linking, never before. A backup failure must not falsely claim
      // that the UID link itself failed or log out the original phone.
      var placeSourceConfirmed = false;
      var placeSourceUnconfirmed = false;
      if (dedaStep2OwnerPlaceLocalArchiveEnabled) {
        try {
          final profile =
              await DedaOwnerUidContinuity.verifiedProfileForLinkedOwner(
            phone: widget.phone, originalId: widget.originalId,
            expectedUid: uid,
          );
          if (profile.accountType == 'placeOwner') {
            final account = DedaPinAuth.accountKeyForPhone(widget.phone);
            final original = FirebaseAuth.instance.currentUser;
            if (original?.uid != uid || original?.isAnonymous != false) {
              throw const DedaStep2OwnerPlaceArchiveHold(
                  'original-linked-session-changed');
            }
            final current = () => mounted &&
                FirebaseAuth.instance.currentUser?.uid == uid &&
                FirebaseAuth.instance.currentUser?.isAnonymous == false;
            final local = await DedaStep2OwnerPlaceSource.readOriginal(
              const DedaStep2OwnerPlaceSharedLocal(),
              accountKey: account, isCurrent: current,
            );
            if (local.hasAnyEvidence) {
              final backup = DedaStep2OwnerPlaceDurableBackup(
                archive: DedaStep2OwnerPlaceLocalArchive.firebase(),
                journal: const DedaStep2OwnerPlacePrefsJournal(),
              );
              await backup.prepare(accountKey: account,
                  originalUid: uid, isCurrent: current);
              final proof = await backup.uploadPending(
                  accountKey: account, originalUid: uid,
                  isCurrent: current);
              if (!proof.journalCleared) {
                throw const DedaStep2OwnerPlaceArchiveHold(
                    'old-place-backup-journal-still-pending');
              }
              placeSourceConfirmed = true;
            }
          }
        } catch (_) {
          placeSourceUnconfirmed = true;
        }
      }
      // Existing widget's injected confirmation path is still testable
      // without Firebase bootstrapping. A LIVE private place-backup pilot,
      // however, must retain the exact verified linked owner UID.
      if (!mounted ||
          (dedaStep2OwnerPlaceLocalArchiveEnabled &&
              FirebaseAuth.instance.currentUser?.uid != uid)) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(placeSourceUnconfirmed
          ? 'تم ربط الحساب الأصلي، لكن نسخ بيانات إدارة المكان لم يتأكد. '
            'لا تحذف التطبيق من الهاتف الأصلي؛ يلزم إعادة محاولة الحفظ.'
          : placeSourceConfirmed
            ? 'تم ربط الحساب وحفظ مصدر إدارة المكان للفحص. '
              'لا تحذف التطبيق الأصلي قبل استرجاع جميع البيانات.'
            : 'تم ربط معرّف Firebase الأصلي. '
              'احتفظ بالتطبيق على هذا الهاتف لحين فحص الاسترجاع.'),
      ));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('تعذر تأكيد الحساب بأمان. لم يتم استرجاع أو نقل أي رصيد.'),
      ));
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!dedaLinkedOwnerCompatEnabled && !widget.forTesting) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: OutlinedButton.icon(
        key: const ValueKey('deda-owner-confirm-action'),
        onPressed: _running ? null : _submit,
        icon: const Icon(Icons.verified_user_outlined),
        label: const Text('تأكيد الحساب / Confirm account'),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
        ),
      ),
    );
  }
}
