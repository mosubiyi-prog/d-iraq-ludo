import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'deda_verified_identifier_ink.dart';

/// Stage50 DTO. Only canonical original ID lookup is accepted by a friend
/// profile. No client may supply a purchased card color or a target UID.
class DedaStage50PublicIdStyle {
  final String requestedId;
  final String displayId;
  final String? permanentColor;

  const DedaStage50PublicIdStyle({
    required this.requestedId,
    required this.displayId,
    required this.permanentColor,
  });

  static final _identifier = RegExp(r'^@DEDA-[A-Z0-9]{4,12}$');
  static final _original = RegExp(r'^@DEDA-[A-Z0-9]{6}$');
  static const _colors = {'gold', 'diamond', 'royal', 'pink'};

  static DedaStage50PublicIdStyle? parse(Object? raw, String expectedOriginal) {
    if (!_original.hasMatch(expectedOriginal) || raw is! Map) {
      throw StateError('unverified-public-identifier-style');
    }
    final data = Map<String, dynamic>.from(raw);
    if (data.length != 4 ||
        data['requestedId'] != expectedOriginal ||
        data['serverConfirmed'] is! bool ||
        (data['permanentColor'] != null &&
            !_colors.contains(data['permanentColor']))) {
      throw StateError('unverified-public-identifier-style');
    }
    if (data['serverConfirmed'] == false) {
      if (data['displayId'] != null || data['permanentColor'] != null) {
        throw StateError('unverified-public-identifier-style');
      }
      return null;
    }
    final displayId = data['displayId'];
    if (displayId is! String || !_identifier.hasMatch(displayId)) {
      throw StateError('unverified-public-identifier-style');
    }
    final color = data['permanentColor'] as String?;
    if (displayId == expectedOriginal && color != null) {
      throw StateError('original-public-id-must-not-borrow-gm-ink');
    }
    return DedaStage50PublicIdStyle(
      requestedId: expectedOriginal, displayId: displayId,
      permanentColor: color,
    );
  }
}

/// Build-time feature locks default OFF until owner approves real Functions
/// and AppCheck on the signed APK. This is NOT a public release activation.
class DedaStage50PublicIdStyleBridge {
  static const bool enabled = bool.fromEnvironment(
        'DEDA_PREMIUM_IDS_SERVER_LIVE', defaultValue: false) &&
      bool.fromEnvironment(
        'DEDA_STAGE50_PUBLIC_IDENTIFIER_STYLE_LIVE', defaultValue: false);

  static Future<DedaStage50PublicIdStyle?> read(
      String requesterUid, String originalId) async {
    if (!enabled || FirebaseAuth.instance.currentUser?.uid != requesterUid) {
      throw StateError('public-id-style-server-off');
    }
    final response = await FirebaseFunctions.instance
        .httpsCallable('dedaPremiumReadPublicIdentifierStyle',
            options: HttpsCallableOptions(
                timeout: const Duration(seconds: 30)))
        .call<Map<String, dynamic>>({
          'identifier': originalId,
        });
    if (FirebaseAuth.instance.currentUser?.uid != requesterUid) {
      throw StateError('friend-id-requester-changed');
    }
    return DedaStage50PublicIdStyle.parse(response.data, originalId);
  }
}

/// Show identifier GLYPHS on a friend profile after SERVER receipt check.
/// No add-friend, following, search or live-location lookup is changed.
class DedaStage50VerifiedFriendInkBadge extends StatefulWidget {
  final String originalId;
  final Widget fallback;
  // Only the public profile supplies this. Compact/search rows remain tiny.
  final Widget Function(DedaStage50PublicIdStyle verified)? premiumCardBuilder;
  const DedaStage50VerifiedFriendInkBadge({
    super.key, required this.originalId, required this.fallback,
    this.premiumCardBuilder,
  });

  @override
  State<DedaStage50VerifiedFriendInkBadge> createState() =>
      _DedaStage50VerifiedFriendInkBadgeState();
}

class _DedaStage50VerifiedFriendInkBadgeState
    extends State<DedaStage50VerifiedFriendInkBadge>
    with WidgetsBindingObserver {
  DedaStage50PublicIdStyle? _style;
  StreamSubscription<User?>? _authChanges;
  String? _requesterUid;
  int _epoch = 0;

  @override
  void initState() {
    super.initState();
    if (!DedaStage50PublicIdStyleBridge.enabled) return;
    WidgetsBinding.instance.addObserver(this);
    _authChanges = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (!mounted || user?.uid == _requesterUid) return;
      _epoch++;
      setState(() {
        _style = null;
        _requesterUid = user?.uid;
      });
      _load();
    });
    _load();
  }

  @override
  void didUpdateWidget(covariant DedaStage50VerifiedFriendInkBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.originalId != widget.originalId) {
      _epoch++;
      _style = null;
      _load();
    }
  }

  Future<void> _load() async {
    if (!mounted || !DedaStage50PublicIdStyleBridge.enabled) return;
    final requester = FirebaseAuth.instance.currentUser?.uid;
    final original = widget.originalId;
    final epoch = ++_epoch;
    if (requester == null) {
      setState(() {
        _requesterUid = null;
        _style = null;
      });
      return;
    }
    _requesterUid = requester;
    try {
      final proof = await DedaStage50PublicIdStyleBridge.read(requester, original);
      if (!mounted || epoch != _epoch || widget.originalId != original ||
          FirebaseAuth.instance.currentUser?.uid != requester) return;
      setState(() => _style = proof);
    } catch (_) {
      if (mounted && epoch == _epoch &&
          FirebaseAuth.instance.currentUser?.uid == requester) {
        setState(() => _style = null);
      }
    }
  }

  // DEDA_QA32_REVERIFY_OTHER_USER_ALIAS_ON_RESUME_READ_ONLY_NO_DEPLOY
  // A friend's alias/foil may have changed while the app was backgrounded.
  // Clear stale visible alias immediately and re-fetch SERVER-owned proof.
  // When the callable is not approved/live, do not touch Firebase.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed ||
        !DedaStage50PublicIdStyleBridge.enabled || !mounted) return;
    _epoch++;
    setState(() => _style = null);
    _load();
  }

  @override
  void dispose() {
    _epoch++;
    WidgetsBinding.instance.removeObserver(this);
    _authChanges?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!DedaStage50PublicIdStyleBridge.enabled) return widget.fallback;
    final style = _style;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid != _requesterUid ||
        style == null || style.requestedId != widget.originalId ||
        style.displayId == widget.originalId) return widget.fallback;
    if (widget.premiumCardBuilder != null) {
      return DedaStage50PremiumPublicCard(
        originalId: widget.originalId,
        verified: style,
        fallback: widget.fallback,
        builder: widget.premiumCardBuilder!,
      );
    }
    return DedaStage50FriendIdInkText(
      originalId: widget.originalId, verified: style,
      fallback: widget.fallback,
    );
  }
}

/// Use the SAME full Crown/Jewel ID artwork as the owner's profile, but only
/// for a public server-verified granted/claimed and currently active alias.
/// No local frame choice, raw preference or unverified ID becomes premium.
class DedaStage50PremiumPublicCard extends StatelessWidget {
  final String originalId;
  final DedaStage50PublicIdStyle? verified;
  final Widget fallback;
  final Widget Function(DedaStage50PublicIdStyle proof) builder;

  const DedaStage50PremiumPublicCard({
    super.key, required this.originalId, required this.verified,
    required this.fallback, required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    final untrusted = verified;
    if (untrusted == null) return fallback;
    DedaStage50PublicIdStyle? proof;
    try {
      proof = DedaStage50PublicIdStyle.parse({
        'requestedId': untrusted.requestedId,
        'displayId': untrusted.displayId,
        'permanentColor': untrusted.permanentColor,
        'serverConfirmed': true,
      }, originalId);
    } catch (_) {
      return fallback;
    }
    if (proof == null || proof.displayId == originalId ||
        proof.permanentColor == null) return fallback;
    return builder(proof);
  }
}

class DedaStage50FriendIdInkText extends StatelessWidget {
  final String originalId;
  final DedaStage50PublicIdStyle? verified;
  final Widget fallback;
  const DedaStage50FriendIdInkText({
    super.key, required this.originalId,
    required this.verified, required this.fallback,
  });

  @override
  Widget build(BuildContext context) {
    final proof = verified;
    if (proof == null || proof.requestedId != originalId ||
        proof.displayId == originalId) return fallback;
    return DedaVerifiedIdentifierText(
      identifier: proof.displayId,
      serverConfirmed: true,
      permanentColor: proof.permanentColor,
      maxLines: 1, overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontWeight: FontWeight.w900,
        color: Color(0xFF273B52),
        fontSize: 14,
      ),
    );
  }
}
