import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'deda_stage48_verified_active_profile_ink.dart';
import 'deda_verified_identifier_ink.dart';

/// Stage49 — visual-only premium identifier beside the existing ORIGINAL QR.
/// The canonical QR, copy, WhatsApp message, friend lookup and location-sharing
/// routes MUST remain bound to the original ID until a separately verified,
/// owner-approved alias migration. Never infer color from a local card preview.
class DedaStage49VerifiedShareIdBadge extends StatefulWidget {
  final String originalId;
  final bool isArabic;

  const DedaStage49VerifiedShareIdBadge({
    super.key,
    required this.originalId,
    required this.isArabic,
  });

  @override
  State<DedaStage49VerifiedShareIdBadge> createState() =>
      _DedaStage49VerifiedShareIdBadgeState();
}

class _DedaStage49VerifiedShareIdBadgeState
    extends State<DedaStage49VerifiedShareIdBadge> {
  DedaStage48ActiveInkProof? _proof;
  StreamSubscription<User?>? _subscription;
  int _epoch = 0;
  String? _uid;

  @override
  void initState() {
    super.initState();
    if (!DedaStage48ActiveInkBridge.enabled) return;
    _subscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (!mounted || user?.uid == _uid) return;
      _epoch++;
      setState(() {
        _uid = user?.uid;
        _proof = null;
      });
      _fetch();
    });
    _fetch();
  }

  @override
  void didUpdateWidget(covariant DedaStage49VerifiedShareIdBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.originalId != widget.originalId) {
      _epoch++;
      _proof = null;
      _fetch();
    }
  }

  Future<void> _fetch() async {
    if (!mounted || !DedaStage48ActiveInkBridge.enabled) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final original = widget.originalId;
    final epoch = ++_epoch;
    if (uid == null) {
      setState(() {
        _uid = null;
        _proof = null;
      });
      return;
    }
    _uid = uid;
    try {
      final proof = await DedaStage48ActiveInkBridge.read(uid, original);
      if (!mounted || epoch != _epoch ||
          widget.originalId != original ||
          FirebaseAuth.instance.currentUser?.uid != uid) return;
      setState(() => _proof = proof);
    } catch (_) {
      if (mounted && epoch == _epoch &&
          FirebaseAuth.instance.currentUser?.uid == uid) {
        setState(() => _proof = null);
      }
    }
  }

  @override
  void dispose() {
    _epoch++;
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!DedaStage48ActiveInkBridge.enabled) {
      return const SizedBox.shrink();
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return DedaStage49VerifiedShareIdPreview(
      originalId: widget.originalId,
      currentUid: uid,
      verified: _proof,
      isArabic: widget.isArabic,
    );
  }
}

/// Pure view so no synthetic owner ID or simulated entitlement reaches the app.
/// No "Share premium" CTA — until alias compatibility is proven, only the old
/// registered original ID may be copied, sent or encoded into a QR.
class DedaStage49VerifiedShareIdPreview extends StatelessWidget {
  final String originalId;
  final String? currentUid;
  final DedaStage48ActiveInkProof? verified;
  final bool isArabic;

  const DedaStage49VerifiedShareIdPreview({
    super.key,
    required this.originalId,
    required this.currentUid,
    required this.verified,
    required this.isArabic,
  });

  @override
  Widget build(BuildContext context) {
    final proof = verified;
    if (proof == null || currentUid == null ||
        proof.accountUid != currentUid ||
        proof.originalId != originalId ||
        proof.activeId == originalId ||
        proof.permanentColor == null ||
        DedaVerifiedIdentifierInk.resolve(
          identifier: proof.activeId,
          serverConfirmed: true,
          permanentColor: proof.permanentColor,
        ) == null) {
      return const SizedBox.shrink();
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 9),
        Text(
          isArabic ? 'معرّفي المميّز' : 'My premium identifier',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: DedaVerifiedIdentifierText(
            identifier: proof.activeId,
            serverConfirmed: true,
            permanentColor: proof.permanentColor,
            textAlign: TextAlign.center,
            maxLines: 1,
            style: const TextStyle(
              color: Color(0xFF1F2937),
              fontSize: 19,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(height: 5),
        Text(
          isArabic
              ? 'المشاركة والرمز أعلاه يستخدمان معرّفك الأصلي حالياً.'
              : 'Sharing and the QR above still use your original ID.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFF516273), fontSize: 10.5),
        ),
      ],
    );
  }
}
