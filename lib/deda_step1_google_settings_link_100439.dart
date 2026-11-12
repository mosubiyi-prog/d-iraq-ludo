import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'deda_100430_owner_uid_continuity.dart';
import 'deda_auth_session_runtime.dart';
import 'deda_session_transition_gate.dart' show DedaSessionAuthKind;
import 'deda_session_diagnostic_readonly_100441.dart';
import 'deda_100431_linked_owner_session_policy.dart';
import 'deda_pin_auth.dart';

/// Isolated owner-only Google link card; never activated in protected 100439.
/// The Google account chooser requires Google OAuth configuration and a
/// separately approved private build. No Cloud Functions or financial writes.
class DedaGoogleSettingsLinkCard extends StatefulWidget {
  const DedaGoogleSettingsLinkCard({
    super.key,
    required this.phone,
    required this.originalId,
    required this.isArabic,
  });

  final String phone;
  final String originalId;
  final bool isArabic;

  @override
  State<DedaGoogleSettingsLinkCard> createState() =>
      _DedaGoogleSettingsLinkCardState();
}

class _DedaGoogleSettingsLinkCardState
    extends State<DedaGoogleSettingsLinkCard> {
  bool _busy = false;
  bool _verified = false;
  // A Google link on a detached anonymous UID is NOT recovery of DEDA's
  // historical phone account. Never display the original-owner green tick.
  bool _linkedCurrentOnly = false;
  String? _message;
  bool get _active => dedaStep1GoogleOwnerLinkEnabled &&
      dedaLinkedOwnerCompatEnabled && Firebase.apps.isNotEmpty;

  String _t(String ar, String en) => widget.isArabic ? ar : en;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<bool> _serverConfirmedLink() async {
    if (!_active) return false;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous ||
        !user.providerData.any((p) => p.providerId == 'google.com')) {
      return false;
    }
    final account = DedaPinAuth.accountKeyForPhone(widget.phone);
    return DedaLinkedOwnerSessionPolicy.verified(user, account);
  }

  Future<void> _refresh() async {
    bool valid = false;
    try {
      valid = await _serverConfirmedLink();
    } catch (_) {
      valid = false;
    }
    final live = FirebaseAuth.instance.currentUser;
    final googleOnCurrent = live != null && !live.isAnonymous &&
        live.providerData.any((p) => p.providerId == 'google.com');
    if (mounted) setState(() {
      _verified = valid;
      _linkedCurrentOnly = !valid && googleOnCurrent;
    });
  }

  // User-requested alternative: attach Google only to the anonymous Firebase
  // UID ALREADY open on this device. This is deliberately a NEW, separate
  // Google-backed session; it never adopts phone records, the original ID,
  // admin access, wallets, or A/B/C. Requires an explicit UI confirmation.
  Future<String> _linkDetachedAnonymous({
    required FirebaseAuth auth,
    required String originalUid,
    required AuthCredential credential,
  }) async {
    if (!DedaAuthRuntime.enabled) {
      throw StateError('google-link-requires-shared-auth-transition-guardian');
    }
    final linked = await DedaAuthRuntime.run<UserCredential>(
      kind: DedaSessionTransitionKind.credentialChange,
      origin: DedaSessionTransitionOrigin.userAction,
      action: () => DedaAuthRuntime.controller.transition<UserCredential>(
        kind: DedaSessionTransitionKind.credentialChange,
        action: () {
          final live = auth.currentUser;
          if (live == null || live.uid != originalUid || !live.isAnonymous) {
            throw StateError('detached-google-principal-changed');
          }
          return live.linkWithCredential(credential);
        },
        accepts: (result, live) =>
            result.user?.uid == originalUid && live.uid == originalUid &&
            live.kind == DedaSessionAuthKind.authenticated,
      ),
    );
    if (linked.user?.uid != originalUid ||
        auth.currentUser?.uid != originalUid) {
      throw StateError('detached-google-uid-not-preserved');
    }
    await auth.currentUser!.reload();
    final updated = auth.currentUser;
    if (updated == null || updated.uid != originalUid ||
        updated.isAnonymous ||
        !updated.providerData.any((p) => p.providerId == 'google.com')) {
      throw StateError('detached-google-provider-not-verified');
    }
    return originalUid;
  }

  Future<void> _link() async {
    if (_busy || _verified || _linkedCurrentOnly || !_active) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    bool linkDetached = false;
    try {
      final auth = FirebaseAuth.instance;
      final startingUid = auth.currentUser?.uid;
      final account = DedaPinAuth.accountKeyForPhone(widget.phone);
      if (startingUid == null) {
        throw StateError('deda-explicit-session-required-for-google');
      }

      // First use the existing, fully verified original-owner route.
      final originalVerified = !auth.currentUser!.isAnonymous &&
          await DedaLinkedOwnerSessionPolicy.verified(
              auth.currentUser, account);
      if (!originalVerified) {
        // Do not claim the old DEDA account on an unrelated Firebase UID.
        // Only offer a SEPARATE link when both canonical server owner
        // references explicitly differ from this anonymous principal.
        if (auth.currentUser?.uid != startingUid ||
            auth.currentUser?.isAnonymous != true) {
          throw StateError('deda-original-owner-confirmation-required');
        }
        final report = await DedaSessionDiagnosticReadOnly.inspect(widget.phone);
        if (!DedaSessionDiagnosticReadOnly
            .mayOfferDetachedGoogleLink(report) ||
            auth.currentUser?.uid != startingUid ||
            auth.currentUser?.isAnonymous != true) {
          throw StateError('deda-detached-link-safety-check-not-passed');
        }
        if (!mounted) return;
        final consent = await showDialog<bool>(
          context: context,
          builder: (dialog) => AlertDialog(
            title: const Text('ربط Google بهذه الجلسة فقط'),
            content: const Text(
              'جلسة Firebase الحالية لا تطابق حساب DEDA القديم. '
              'يمكن ربط Google بهذه الجلسة الحالية فقط، بنفس UID الحالي، '
              'لكن هذا لن يسترجع الآيدي أو الماسات أو الأصدقاء أو الهدايا '
              'من الحساب القديم. لا يُحذف أو يُدمج أي حساب قديم. '
              'إذا تريد استرجاع حسابك القديم، اختر إلغاء. '
              'هل توافق على ربط هذه الجلسة المنفصلة فقط؟',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialog).pop(false),
                child: const Text('إلغاء'),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialog).pop(true),
                child: const Text('ربط هذه الجلسة فقط'),
              ),
            ],
          ),
        );
        if (consent != true || !mounted) return;
        if (auth.currentUser?.uid != startingUid ||
            auth.currentUser?.isAnonymous != true) {
          throw StateError('deda-detached-session-changed-before-google');
        }
        linkDetached = true;
      }
      if (!mounted || auth.currentUser?.uid != startingUid) return;

      // Opens the signed-in Google account chooser/consent UI where available.
      // Does not ask DEDA to collect an email or Google password.
      final chosen = await GoogleSignIn(scopes: <String>['email']).signIn();
      if (chosen == null) return; // user cancelled, no auth or account changes
      final tokens = await chosen.authentication;
      if (tokens.idToken == null || tokens.idToken!.isEmpty) {
        throw StateError('google-id-token-unavailable');
      }
      if (auth.currentUser?.uid != startingUid) {
        throw StateError('owner-session-changed-during-google-consent');
      }

      final credential = GoogleAuthProvider.credential(
        accessToken: tokens.accessToken,
        idToken: tokens.idToken,
      );
      final linkedUid = linkDetached
          ? await _linkDetachedAnonymous(
              auth: auth, originalUid: startingUid,
              credential: credential)
          : await DedaOwnerUidContinuity.linkGoogleToConfirmedOriginalUid(
              phone: widget.phone,
              originalId: widget.originalId,
              googleCredential: credential,
            );
      if (linkedUid != startingUid ||
          (!linkDetached && !await _serverConfirmedLink())) {
        throw StateError('google-uid-readback-not-confirmed');
      }
      if (mounted) {
        setState(() {
          _verified = !linkDetached;
          _linkedCurrentOnly = linkDetached;
          _message = linkDetached
              ? 'تم ربط Google بالجلسة الحالية فقط. '
                  'حساب DEDA الأصلي وممتلكاته لم يتم استرجاعها.'
              : null;
        });
      }
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      final conflict = <String>{
        'credential-already-in-use', 'account-exists-with-different-credential',
        'provider-already-linked',
      }.contains(error.code);
      setState(() => _message = conflict
          ? _t('حساب جوجل مرتبط مسبقاً؛ لم يتم دمج الحسابات.',
              'Google account already linked elsewhere; no accounts merged.')
          : _t('تعذر إتمام الربط بأمان؛ لم تتغير بيانات حسابك.',
              'Secure linking failed; your account data was not changed.'));
    } catch (_) {
      if (mounted) {
        setState(() => _message = linkDetached
          ? 'لم نتمكن من تأكيد ربط Google لهذه الجلسة. '
              'قد تكون العملية اكتملت في Firebase؛ أعد فتح الإعدادات '
              'للتحقق قبل أي محاولة أخرى.'
          : 'الجلسة الحالية غير مثبتة كصاحب حساب DEDA الأصلي، '
              'أو لم تكتمل تهيئة Google. لم يتم تجاوز حارس ملكية الحساب.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_active) return const SizedBox.shrink();
    const green = Color(0xFF17652F);
    return Card(
      key: const ValueKey('deda-google-link-settings-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            key: const ValueKey('deda-google-link-settings-action'),
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 5),
            leading: const CircleAvatar(
              backgroundColor: Color(0xFFE8F2E8),
              child: Text('G', style: TextStyle(
                fontSize: 23, fontWeight: FontWeight.w800, color: green)),
            ),
            title: Text(_t('ربط الحساب بجوجل', 'Link with Google')),
            subtitle: Text(_verified
                ? _t('مرتبط ومؤكد بالحساب الأصلي',
                    'Linked to verified original account')
                : _linkedCurrentOnly
                    ? _t('Google مرتبط بهذه الجلسة فقط؛ '
                        'الحساب القديم غير مسترجع.',
                        'Google linked to this session only; '
                        'old account not restored.')
                    : _t('احفظ هوية حسابك لتفتحها على هاتف آخر.',
                        'Keep your account identity for another phone.')),
            trailing: _busy
                ? const SizedBox(width: 22, height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : _verified
                    ? const Icon(Icons.check_circle, color: green,
                        key: ValueKey('deda-google-link-verified'))
                    : _linkedCurrentOnly
                        ? const Icon(Icons.info_outline,
                            key: ValueKey('deda-google-session-only'))
                        : const Icon(Icons.chevron_right),
            onTap: _busy || _verified || _linkedCurrentOnly ? null : _link,
          ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(_message!,
                  style: const TextStyle(color: Color(0xFF8B3B2D))),
            ),
        ],
      ),
    );
  }
}
