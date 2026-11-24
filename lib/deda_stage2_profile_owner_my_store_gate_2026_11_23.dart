import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'deda_100377_my_store_page_staged.dart';
import 'deda_section_state.dart' show DedaSectionAccountChanges;

/// Account-rotation guard in front of the ONE original My Store renderer.
/// This does not authenticate an account or grant any paid inventory.
/// The original page is created only while the same public owner remains.
class DedaStage2ProfileOwnerBoundMyStore extends StatefulWidget {
  const DedaStage2ProfileOwnerBoundMyStore({
    super.key,
    required this.originalId,
    required this.items,
    required this.initialUid,
    required this.ownerStillCurrent,
    this.isArabic = true,
    this.onOpenIdentifierShop,
    this.onOpenEditProfile,
  });

  final String originalId;
  final List<DedaMyStoreItem> items;
  final String? initialUid;
  final bool Function() ownerStillCurrent;
  final bool isArabic;
  final VoidCallback? onOpenIdentifierShop;
  final VoidCallback? onOpenEditProfile;

  @override
  State<DedaStage2ProfileOwnerBoundMyStore> createState() =>
      _DedaStage2ProfileOwnerBoundMyStoreState();
}

class _DedaStage2ProfileOwnerBoundMyStoreState
    extends State<DedaStage2ProfileOwnerBoundMyStore> {
  StreamSubscription<User?>? _auth;
  // A route snapshot can never become valid again after an account rotation.
  bool _expired = false;

  bool _ownerCurrent() {
    final ownerStillCurrent = widget.ownerStillCurrent;
    try {
      if (!ownerStillCurrent()) return false;
      final uid = Firebase.apps.isEmpty
          ? null : FirebaseAuth.instance.currentUser?.uid;
      return uid == widget.initialUid;
    } catch (_) {
      return false;
    }
  }

  void _expire() {
    if (_expired || !mounted) return;
    setState(() => _expired = true);
  }

  void _onAuthChanged(User? user) {
    // Inspect the event itself, not only the live UID: A -> B -> A can be
    // delivered before a single rebuild. The first mismatched event is final.
    if (user?.uid != widget.initialUid || !_ownerCurrent()) _expire();
  }

  @override
  void initState() {
    super.initState();
    _expired = !_ownerCurrent();
    // Reuse the existing account-selection epoch, including same-UID changes.
    DedaSectionAccountChanges.epoch.addListener(_expire);
    try {
      if (Firebase.apps.isNotEmpty) {
        _auth = FirebaseAuth.instance.authStateChanges().listen(
          _onAuthChanged, onError: (Object _) => _expire(), onDone: _expire,
        );
      }
    } catch (_) {
      _expired = true;
    }
  }

  @override
  void didUpdateWidget(covariant DedaStage2ProfileOwnerBoundMyStore oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialUid != widget.initialUid ||
        oldWidget.originalId != widget.originalId || !_ownerCurrent()) {
      _expired = true;
    }
  }

  VoidCallback? _guarded(VoidCallback? action) {
    if (action == null) return null;
    return () {
      if (!mounted || _expired) return;
      if (!_ownerCurrent()) {
        _expire();
        return;
      }
      action();
    };
  }

  @override
  void dispose() {
    DedaSectionAccountChanges.epoch.removeListener(_expire);
    unawaited(_auth?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ownerCurrent()) _expired = true;
    if (_expired) {
      return Scaffold(
        appBar: AppBar(title: const Text('متجري')),
        body: const Center(
          child: Text('تغيّر الحساب. أعد فتح متجري من الملف الحالي.',
              textAlign: TextAlign.center),
        ),
      );
    }
    return DedaMyStorePage(
      originalId: widget.originalId,
      items: widget.items,
      isArabic: widget.isArabic,
      onOpenIdentifierShop: _guarded(widget.onOpenIdentifierShop),
      onOpenEditProfile: _guarded(widget.onOpenEditProfile),
    );
  }
}
