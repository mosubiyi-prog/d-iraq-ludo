import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'deda_100430_owner_uid_continuity.dart';
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
    if (mounted) setState(() => _verified = valid);
  }

  Future<void> _link() async {
    if (_busy || _verified || !_active) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final auth = FirebaseAuth.instance;
      final startingUid = auth.currentUser?.uid;
      final account = DedaPinAuth.accountKeyForPhone(widget.phone);

      // Confirm the original owner BEFORE opening any Google UI.
      // For older anonymous installations the separate pre-link archive and
      // account confirmation must finish first, without deleting local data.
      if (startingUid == null ||
          !await DedaLinkedOwnerSessionPolicy.verified(
              auth.currentUser, account)) {
        throw StateError('deda-owner-confirmation-required-before-google');
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
      final linkedUid = await DedaOwnerUidContinuity
          .linkGoogleToConfirmedOriginalUid(
            phone: widget.phone,
            originalId: widget.originalId,
            googleCredential: credential,
          );
      if (linkedUid != startingUid || !await _serverConfirmedLink()) {
        throw StateError('google-original-owner-readback-not-confirmed');
      }
      if (mounted) {
        setState(() {
          _verified = true;
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
          : _t('تعذر إتمام الربط بأمان؛ لم تتغير بيانات حسابك.',
              'Secure linking failed; your account data was not changed.'));
    } catch (_) {
      if (mounted) {
        setState(() => _message = _t(
          'لم يتأكد الربط. تأكد من تأكيد الحساب الأصلي وتهيئة جوجل.',
          'Link not verified. Confirm the original account and Google setup.',
        ));
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
            leading: const Icon(Icons.account_circle_outlined, color: green),
            title: Text(_t('ربط الحساب بجوجل', 'Link with Google')),
            subtitle: Text(_verified
                ? _t('مرتبط ومؤكد', 'Linked and verified')
                : _t('احفظ هوية حسابك لتفتحها على هاتف آخر.',
                    'Keep your account identity for another phone.')),
            trailing: _busy
                ? const SizedBox(width: 22, height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : _verified
                    ? const Icon(Icons.check_circle, color: green,
                        key: ValueKey('deda-google-link-verified'))
                    : const Icon(Icons.chevron_right),
            onTap: _busy || _verified ? null : _link,
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
