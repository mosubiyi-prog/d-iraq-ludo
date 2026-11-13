import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'deda_backend.dart';
import 'deda_pin_auth.dart';

/// User-initiated, read-only diagnostic. No UID/phone/email/PIN is shown,
/// logged, transmitted to an extra endpoint or used to change auth state.
enum DedaProbeKind { firebaseMissing, signedOut, anonymous, linked, changed }
enum DedaProbeMatch { sameUid, differentUid, unavailable, signedOut }

class DedaSessionProbeReport {
  const DedaSessionProbeReport(this.kind, this.original, this.directory,
      this.google, this.password, {this.sessionFingerprint});
  final DedaProbeKind kind;
  final DedaProbeMatch original;
  final DedaProbeMatch directory;
  final bool google;
  final bool password;
  /// A short diagnostic hash, NOT identity, login or owner proof. Never raw UID.
  final String? sessionFingerprint;
}

class DedaSessionDiagnosticReadOnly {
  const DedaSessionDiagnosticReadOnly._();

  /// Only a detached anonymous Firebase principal may be offered a NEW,
  /// explicitly separate Google link. A matching, unverified or unavailable
  /// historical owner route must NEVER be silently taken over by Google.
  /// This does NOT authorize restoration of the old DEDA phone/ID/wallet.
  static bool mayOfferDetachedGoogleLink(DedaSessionProbeReport report) =>
      report.kind == DedaProbeKind.anonymous &&
      report.original == DedaProbeMatch.differentUid &&
      report.directory == DedaProbeMatch.differentUid &&
      !report.google && !report.password;

  /// Read-only routing hint for an ORIGINAL anonymous DEDA session.
  /// This is NOT owner authorization: the existing confirmation button must
  /// still verify PIN, immutable routing, archival receipt, and same UID.
  /// Any split, missing server document or signed-out session stays HOLD.
  static bool mayOfferOriginalAnonymousConfirmation(
      DedaSessionProbeReport report) =>
      report.kind == DedaProbeKind.anonymous &&
      report.original == DedaProbeMatch.sameUid &&
      report.directory == DedaProbeMatch.sameUid &&
      !report.google && !report.password;

  /// Stable 64-bit fingerprint to compare a CURRENT device Firebase UID with
  /// historic A/B/C server references. No raw UID, phone, PIN or token is
  /// displayed/sent/logged. Not an authorization factor or cryptographic proof.
  static String fingerprintOfUid(String uid) {
    if (uid.isEmpty) throw ArgumentError('empty-firebase-uid');
    var hash = BigInt.parse('cbf29ce484222325', radix: 16);
    final mask = BigInt.parse('ffffffffffffffff', radix: 16);
    final multiplier = BigInt.parse('100000001b3', radix: 16);
    for (final byte in utf8.encode('DEDA-UID-DIAG-v1|$uid')) {
      hash = ((hash ^ BigInt.from(byte)) * multiplier) & mask;
    }
    return hash.toRadixString(16).padLeft(16, '0').toUpperCase();
  }

  static Future<DedaSessionProbeReport> inspect(String phone) async {
    if (Firebase.apps.isEmpty) {
      return const DedaSessionProbeReport(DedaProbeKind.firebaseMissing,
          DedaProbeMatch.unavailable, DedaProbeMatch.unavailable, false, false);
    }
    final current = FirebaseAuth.instance.currentUser;
    if (current == null) {
      return const DedaSessionProbeReport(DedaProbeKind.signedOut,
          DedaProbeMatch.signedOut, DedaProbeMatch.signedOut, false, false);
    }
    final uid = current.uid;
    final kind = current.isAnonymous ? DedaProbeKind.anonymous : DedaProbeKind.linked;
    final google = current.providerData.any((p) => p.providerId == 'google.com');
    final password = current.providerData.any((p) => p.providerId == 'password');
    final key = DedaPinAuth.accountKeyForPhone(phone);
    final original = DedaBackend.personalShareIdForPhone(phone);
    var originalStatus = DedaProbeMatch.unavailable;
    var directoryStatus = DedaProbeMatch.unavailable;
    if (RegExp(r'^[0-9]{8,16}$').hasMatch(key) &&
        RegExp(r'^@DEDA-[A-Z0-9]{6}$').hasMatch(original)) {
      final store = FirebaseFirestore.instance;
      try {
        final doc = await store.collection('deda_share_ids').doc(original)
            .get(const GetOptions(source: Source.server));
        final d = doc.data();
        if (doc.exists && !doc.metadata.isFromCache &&
            !doc.metadata.hasPendingWrites && d?['publicId'] == original &&
            d?['kind'] == 'personal' && d?['active'] == true) {
          originalStatus = d?['ownerUid'] == uid
              ? DedaProbeMatch.sameUid : DedaProbeMatch.differentUid;
        }
      } catch (_) {
        originalStatus = DedaProbeMatch.unavailable;
      }
      if (FirebaseAuth.instance.currentUser?.uid != uid) {
        return const DedaSessionProbeReport(DedaProbeKind.changed,
            DedaProbeMatch.unavailable, DedaProbeMatch.unavailable, false, false);
      }
      try {
        final doc = await store.collection('deda_account_directory').doc(key)
            .get(const GetOptions(source: Source.server));
        final d = doc.data();
        if (doc.exists && !doc.metadata.isFromCache &&
            !doc.metadata.hasPendingWrites &&
            d?['accountKey'] == key && d?['active'] == true) {
          directoryStatus = d?['createdUid'] == uid
              ? DedaProbeMatch.sameUid : DedaProbeMatch.differentUid;
        }
      } catch (_) {
        directoryStatus = DedaProbeMatch.unavailable;
      }
    }
    if (FirebaseAuth.instance.currentUser?.uid != uid) {
      return const DedaSessionProbeReport(DedaProbeKind.changed,
          DedaProbeMatch.unavailable, DedaProbeMatch.unavailable, false, false);
    }
    return DedaSessionProbeReport(kind, originalStatus, directoryStatus,
        google, password, sessionFingerprint: fingerprintOfUid(uid));
  }
}

/// Settings only. Does not automatically run on app launch or account change.
class DedaSessionDiagnosticReadOnlyTile extends StatelessWidget {
  const DedaSessionDiagnosticReadOnlyTile({super.key, required this.phone});
  final String phone;

  static String _kind(DedaProbeKind v, bool ar) {
    switch (v) {
      case DedaProbeKind.firebaseMissing:
        return ar ? 'Firebase غير جاهز' : 'Firebase not ready';
      case DedaProbeKind.signedOut:
        return ar ? 'لا توجد جلسة' : 'No session';
      case DedaProbeKind.anonymous:
        return ar ? 'جلسة مجهولة' : 'Anonymous session';
      case DedaProbeKind.linked:
        return ar ? 'جلسة غير مجهولة' : 'Non-anonymous session';
      case DedaProbeKind.changed:
        return ar ? 'تغيّرت الجلسة أثناء الفحص' : 'Session changed during check';
    }
  }

  static String _match(DedaProbeMatch v, bool ar) {
    switch (v) {
      case DedaProbeMatch.sameUid:
        return ar ? 'مطابق' : 'Matches';
      case DedaProbeMatch.differentUid:
        return ar ? 'مختلف' : 'Different';
      case DedaProbeMatch.unavailable:
        return ar ? 'تعذر التحقق من الخادم' : 'Server check unavailable';
      case DedaProbeMatch.signedOut:
        return ar ? 'لا توجد جلسة للمقارنة' : 'No session to compare';
    }
  }

  @override
  Widget build(BuildContext context) {
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    return ListTile(
      leading: const Icon(Icons.verified_user_outlined),
      title: Text(ar ? 'فحص جلسة Firebase (قراءة فقط)' : 'Firebase session check'),
      subtitle: Text(ar ? 'حالة الجلسة وتطابق الحساب دون عرض هويتك'
          : 'Session and account comparison without revealing IDs'),
      onTap: () {
        final task = DedaSessionDiagnosticReadOnly.inspect(phone);
        showDialog<void>(
          context: context,
          builder: (dialog) => AlertDialog(
            title: Text(ar ? 'تشخيص جلسة ديدا' : 'DEDA session diagnostic'),
            content: FutureBuilder<DedaSessionProbeReport>(
              future: task,
              builder: (ctx, snapshot) {
                if (!snapshot.hasData) {
                  if (snapshot.hasError) {
                    return Text(ar ? 'تعذّر الفحص. لم نغيّر الحساب.'
                        : 'Check unavailable. Account was not changed.');
                  }
                  return const SizedBox(
                    width: 230, height: 70,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final v = snapshot.data!;
                return ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 300),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text((ar ? 'الجلسة: ' : 'Session: ') + _kind(v.kind, ar)),
                      if (v.sessionFingerprint != null) ...[
                        const SizedBox(height: 8),
                        SelectableText(
                          (ar ? 'بصمة UID الحالية: ' : 'Current UID fingerprint: ') +
                          v.sessionFingerprint!,
                        ),
                        const SizedBox(height: 4),
                        Text(ar
                            ? 'بصمة تشخيصية فقط، لا تثبت ملكية الحساب.'
                            : 'Diagnostic only; not account ownership proof.',
                            style: Theme.of(ctx).textTheme.bodySmall),
                      ],
                      const SizedBox(height: 8),
                      Text((ar ? 'الآيدي الأصلي: ' : 'Original UID: ') +
                          _match(v.original, ar)),
                      const SizedBox(height: 8),
                      Text((ar ? 'دليل الرقم: ' : 'Account directory: ') +
                          _match(v.directory, ar)),
                      const SizedBox(height: 8),
                      Text((ar ? 'Google مرتبط: ' : 'Google linked: ') +
                          (v.google ? (ar ? 'نعم' : 'Yes') : (ar ? 'لا' : 'No'))),
                      const SizedBox(height: 8),
                      Text((ar ? 'البريد مرتبط: ' : 'Password linked: ') +
                          (v.password ? (ar ? 'نعم' : 'Yes') : (ar ? 'لا' : 'No'))),
                      const SizedBox(height: 12),
                      Text(ar ? 'قراءة فقط، ولا تعني استرجاع كل البيانات.'
                          : 'Read only; not proof of recovered data.',
                        style: Theme.of(ctx).textTheme.bodySmall),
                    ],
                  ),
                );
              },
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialog).pop(),
                child: Text(ar ? 'إغلاق' : 'Close'),
              ),
            ],
          ),
        );
      },
    );
  }
}
