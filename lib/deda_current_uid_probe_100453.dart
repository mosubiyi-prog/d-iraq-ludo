import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'deda_session_diagnostic_readonly_100441.dart';

/// QA-only opt-in check of the ALREADY existing app FirebaseAuth principal.
/// Never displays a raw UID and never reads or modifies an account record.
/// The old 100441 diagnostic SETTINGS CARD stays deleted.
const bool dedaCurrentUidProbe100453Qa = bool.fromEnvironment(
  'DEDA_CURRENT_UID_PROBE_100453_QA', defaultValue: false);

enum DedaCurrentUidProbeKind {
  firebaseUnavailable,
  noSession,
  unreadable,
  anonymous,
  linked,
}

class DedaCurrentUidProbeReport {
  const DedaCurrentUidProbeReport(this.kind, this.fingerprint);

  final DedaCurrentUidProbeKind kind;

  /// Same 64-bit diagnostic fingerprint as historical A/B/C server audit.
  /// It is NOT a login token, human ownership proof or security credential.
  final String? fingerprint;
}

/// No Firebase sign-in, sign-out, link, network call, Firestore, cache write
/// or PIN access; the entire operation is a synchronous snapshot read.
class DedaCurrentUidProbe100453 {
  const DedaCurrentUidProbe100453._();

  static DedaCurrentUidProbeReport classify({
    required bool firebaseReady,
    required String? uid,
    required bool? isAnonymous,
  }) {
    if (!firebaseReady) {
      return const DedaCurrentUidProbeReport(
        DedaCurrentUidProbeKind.firebaseUnavailable, null);
    }
    if (uid == null) {
      return const DedaCurrentUidProbeReport(
        DedaCurrentUidProbeKind.noSession, null);
    }
    if (uid.isEmpty || isAnonymous == null) {
      return const DedaCurrentUidProbeReport(
        DedaCurrentUidProbeKind.unreadable, null);
    }
    return DedaCurrentUidProbeReport(
      isAnonymous ? DedaCurrentUidProbeKind.anonymous
          : DedaCurrentUidProbeKind.linked,
      DedaSessionDiagnosticReadOnly.fingerprintOfUid(uid),
    );
  }

  static DedaCurrentUidProbeReport current() {
    if (Firebase.apps.isEmpty) {
      return classify(firebaseReady: false, uid: null, isAnonymous: null);
    }
    try {
      final user = FirebaseAuth.instance.currentUser;
      return classify(
        firebaseReady: true,
        uid: user?.uid,
        isAnonymous: user?.isAnonymous,
      );
    } catch (_) {
      // Observer, SDK, or platform failure must NEVER prompt a login.
      return const DedaCurrentUidProbeReport(
        DedaCurrentUidProbeKind.unreadable, null);
    }
  }

  static String message(DedaCurrentUidProbeKind kind, bool ar) {
    switch (kind) {
      case DedaCurrentUidProbeKind.firebaseUnavailable:
        return ar ? 'Firebase غير جاهز للفحص' : 'Firebase unavailable';
      case DedaCurrentUidProbeKind.noSession:
        return ar ? 'لا توجد جلسة Firebase حالياً'
            : 'No current Firebase session';
      case DedaCurrentUidProbeKind.unreadable:
        return ar ? 'تعذرت قراءة الجلسة دون تغييرها'
            : 'Session unreadable; left unchanged';
      case DedaCurrentUidProbeKind.anonymous:
        return ar ? 'جلسة Firebase مجهولة موجودة'
            : 'Existing anonymous Firebase session';
      case DedaCurrentUidProbeKind.linked:
        return ar ? 'جلسة Firebase غير مجهولة موجودة'
            : 'Existing non-anonymous Firebase session';
    }
  }

  /// A temporary QA action only, not a persistent settings card, service or
  /// startup hook. When the flag is OFF, no control exists in the interface.
  static Future<void> open(BuildContext context) async {
    if (!dedaCurrentUidProbe100453Qa) return;
    final report = current();
    if (!context.mounted) return;
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(ar ? 'فحص UID الحالي — قراءة فقط'
            : 'Current UID check — read only'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message(report.kind, ar)),
            if (report.fingerprint != null) ...[
              const SizedBox(height: 14),
              SelectableText(
                (ar ? 'بصمة الجلسة: ' : 'Session fingerprint: ') +
                    report.fingerprint!,
              ),
            ],
            const SizedBox(height: 12),
            Text(ar
                ? 'البصمة للمقارنة مع A وB وC فقط، وليست إثبات ملكية. '
                  'الفحص لا ينشئ حساباً ولا يسجل خروجاً أو يغيّر التقدم.'
                : 'Fingerprint only distinguishes A, B and C. '
                  'Not proof of ownership. No login, logout or data change.',
              style: Theme.of(dialogContext).textTheme.bodySmall),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(ar ? 'إغلاق' : 'Close'),
          ),
        ],
      ),
    );
  }
}
