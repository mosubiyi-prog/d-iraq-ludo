import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'deda_verified_identifier_ink.dart';

/// Stage48, private-only: a verified *active* identifier's immutable ink.
/// This is a read response DTO, NOT evidence of an earned/purchased entitlement
/// unless it came from an authenticated, AppCheck-enforced server callable.
class DedaStage48ActiveInkProof {
  final String accountUid;
  final String originalId;
  final String activeId;
  final String? permanentColor;
  const DedaStage48ActiveInkProof({
    required this.accountUid,
    required this.originalId,
    required this.activeId,
    required this.permanentColor,
  });

  static final _original = RegExp(r'^@DEDA-[A-Z0-9]{6}$');
  static final _premium = RegExp(r'^@DEDA-[A-Z0-9]{4,12}$');
  static const _palette = {'gold', 'diamond', 'royal', 'pink'};

  static DedaStage48ActiveInkProof parse(
      Object? raw, String expectedUid, String expectedOriginal) {
    if (raw is! Map) throw StateError('unverified-active-identifier');
    final m = Map<String, dynamic>.from(raw);
    if (m.length != 5 ||
        m['serverConfirmed'] != true ||
        m['accountUid'] != expectedUid ||
        !_original.hasMatch(expectedOriginal) ||
        m['originalId'] != expectedOriginal ||
        m['activeId'] is! String ||
        !_premium.hasMatch(m['activeId'] as String) ||
        (m['permanentColor'] != null &&
            !_palette.contains(m['permanentColor']))) {
      throw StateError('unverified-active-identifier');
    }
    final active = m['activeId'] as String;
    final color = m['permanentColor'] as String?;
    if (active == expectedOriginal && color != null) {
      throw StateError('original-id-cannot-inherit-exclusive-color');
    }
    return DedaStage48ActiveInkProof(
      accountUid: expectedUid,
      originalId: expectedOriginal,
      activeId: active,
      permanentColor: color,
    );
  }
}

class DedaStage48ActiveInkBridge {
  // Both compilation switches must be explicitly approved. Existing 100359
  // installs have neither; legacy profile behavior remains untouched.
  static const bool enabled = bool.fromEnvironment(
        'DEDA_PREMIUM_IDS_SERVER_LIVE',
        defaultValue: false,
      ) &&
      bool.fromEnvironment(
        'DEDA_STAGE48_ACTIVE_INK_READ_LIVE',
        defaultValue: false,
      );

  static Future<DedaStage48ActiveInkProof> read(
      String uid, String originalId) async {
    if (!enabled || FirebaseAuth.instance.currentUser?.uid != uid) {
      throw StateError('stage48-server-read-off');
    }
    final result = await FirebaseFunctions.instance
        .httpsCallable('dedaPremiumReadActiveIdentifierInk',
            options: HttpsCallableOptions(
                timeout: const Duration(seconds: 40)))
        .call<Map<String, dynamic>>(<String, dynamic>{});
    if (FirebaseAuth.instance.currentUser?.uid != uid) {
      throw StateError('stage48-auth-changed');
    }
    return DedaStage48ActiveInkProof.parse(
        result.data, uid, originalId);
  }
}

/// A ready-to-use premium card needs the ORIGINAL foil artwork. The caller
/// supplies its original DedaPremiumIdCard, not a second imitation renderer.
typedef DedaStage48OriginalFoilBuilder = Widget Function(
    String identifier, String permanentColor, VoidCallback onCopy);

/// Replaces only the profile ID slot in a reconstructed QA build. The 100359
/// slot remains the exact fallback whenever server verification is unavailable.
class DedaStage48ActiveInkProfileSlot extends StatefulWidget {
  final String originalId;
  final Widget fallback;
  final double width;
  final bool compact;
  final DedaStage48OriginalFoilBuilder premiumFoil;

  const DedaStage48ActiveInkProfileSlot({
    super.key,
    required this.originalId,
    required this.fallback,
    required this.width,
    required this.compact,
    required this.premiumFoil,
  });

  @override
  State<DedaStage48ActiveInkProfileSlot> createState() =>
      _DedaStage48ActiveInkProfileSlotState();
}

class _DedaStage48ActiveInkProfileSlotState
    extends State<DedaStage48ActiveInkProfileSlot> {
  DedaStage48ActiveInkProof? _proof;
  StreamSubscription<User?>? _authSubscription;
  String? _ownerUid;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    if (!DedaStage48ActiveInkBridge.enabled) return;
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (!mounted || user?.uid == _ownerUid) return;
      _generation++;
      setState(() {
        _ownerUid = user?.uid;
        _proof = null;
      });
      _read();
    });
    _read();
  }

  @override
  void didUpdateWidget(covariant DedaStage48ActiveInkProfileSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.originalId != widget.originalId) {
      _generation++;
      _proof = null;
      _read();
    }
  }

  Future<void> _read() async {
    if (!DedaStage48ActiveInkBridge.enabled || !mounted) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final original = widget.originalId;
    final ticket = ++_generation;
    if (uid == null) {
      setState(() {
        _ownerUid = null;
        _proof = null;
      });
      return;
    }
    _ownerUid = uid;
    try {
      final proof = await DedaStage48ActiveInkBridge.read(uid, original);
      if (!mounted || ticket != _generation ||
          FirebaseAuth.instance.currentUser?.uid != uid ||
          widget.originalId != original) return;
      setState(() => _proof = proof);
    } catch (_) {
      if (mounted && ticket == _generation &&
          FirebaseAuth.instance.currentUser?.uid == uid) {
        setState(() => _proof = null);
      }
    }
  }

  @override
  void dispose() {
    _generation++;
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uid = DedaStage48ActiveInkBridge.enabled
        ? FirebaseAuth.instance.currentUser?.uid : null;
    final p = _proof;
    if (!DedaStage48ActiveInkBridge.enabled || p == null ||
        p.accountUid != uid || p.originalId != widget.originalId) {
      return widget.fallback;
    }
    final activeId = p.activeId;
    void copyActiveId() {
      // Only the id returned by the current verified account can be copied.
      if (FirebaseAuth.instance.currentUser?.uid == p.accountUid &&
          widget.originalId == p.originalId) {
        Clipboard.setData(ClipboardData(text: activeId));
      }
    }
    if (p.permanentColor != null) {
      return SizedBox(
        width: widget.width,
        height: 50,
        child: widget.premiumFoil(
          activeId, p.permanentColor!, copyActiveId),
      );
    }
    // Group002 purchases can have separate cosmetic styles. We deliberately
    // do not infer paid foil ownership from absence of a GM color receipt.
    return SizedBox(
      width: widget.width,
      height: 50,
      child: Material(
        color: const Color(0xFF142D41),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: copyActiveId,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13),
            child: Row(
              children: [
                Expanded(
                  child: DedaVerifiedIdentifierText(
                    identifier: activeId,
                    serverConfirmed: true,
                    permanentColor: null,
                    style: TextStyle(
                      fontSize: widget.compact ? 15 : 17,
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.copy_rounded,
                    color: Colors.white70, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
