import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'deda_100430_owner_uid_continuity.dart';
import 'deda_auth_session_runtime.dart';
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
    // Widget tests, first launch and a failed Firebase bootstrap may have
    // no default Firebase app. Refresh must never touch FirebaseAuth then.
    final live = Firebase.apps.isNotEmpty
        ? FirebaseAuth.instance.currentUser : null;
    final googleOnCurrent = live != null && !live.isAnonymous &&
        live.providerData.any((p) => p.providerId == 'google.com');
    if (mounted) setState(() {
      _verified = valid;
      _linkedCurrentOnly = !valid && googleOnCurrent;
    });
  }

  Future<void> _link() async {
    if (_busy || _verified || _linkedCurrentOnly || !_active) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final auth = FirebaseAuth.instance;
      final owner = auth.currentUser;
      final startingUid = owner?.uid;
      final account = DedaPinAuth.accountKeyForPhone(widget.phone);
      // Only the EXISTING, server-proved DEDA owner may select Google.
      // Never offer a detached anonymous Google session as a replacement
      // for this phone's historical DEDA account.
      if (startingUid == null || owner!.isAnonymous ||
          !await DedaLinkedOwnerSessionPolicy.verified(owner, account) ||
          auth.currentUser?.uid != startingUid) {
        throw StateError('deda-original-owner-confirmation-required');
      }
      if (!mounted) return;

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
      final linkedUid =
          await DedaOwnerUidContinuity.linkGoogleToConfirmedOriginalUid(
        phone: widget.phone,
        originalId: widget.originalId,
        googleCredential: credential,
      );
      if (linkedUid != startingUid ||
          auth.currentUser?.uid != startingUid ||
          !await _serverConfirmedLink()) {
        throw StateError('google-uid-readback-not-confirmed');
      }
      if (mounted) {
        setState(() {
          _verified = true;
          _linkedCurrentOnly = false;
          _message = null;
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
          : _t('تعذر تأكيد ربط Google؛ تحقق من حالة البطاقة قبل إعادة المحاولة.',
              'Google link not confirmed; check its status before retrying.'));
    } catch (_) {
      if (mounted) {
        setState(() => _message =
            'تعذر تأكيد ربط Google بالحساب الأصلي. قد تكون العملية اكتملت '
            'في Firebase؛ أعد فتح الإعدادات للتحقق قبل المحاولة مرة ثانية. '
            'لم ننشئ حساب DEDA بديلاً.');
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
