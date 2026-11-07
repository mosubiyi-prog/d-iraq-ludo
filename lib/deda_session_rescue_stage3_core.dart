import 'dart:async';

import 'package:flutter/foundation.dart';

import 'deda_session_recovery_coordinator.dart';

class DedaRescueStage3Result {
  const DedaRescueStage3Result({
    required this.status,
    required this.uid,
    required this.originalId,
    this.verifiedDisplayId,
  });

  final DedaRescueStatus status;
  final String? uid;
  final String originalId;

  /// A server-verified Stage71 presentation value (4..12 alias chars).
  /// Null means UNKNOWN, never "replace it with the old displayed ID".
  final String? verifiedDisplayId;

  bool get ownerReady => status == DedaRescueStatus.ready;

  /// Must be checked again by the old admin_entry_access flow. Not access.
  bool get mayRecheckAdminGateway => ownerReady;

  /// Must be checked again by the original Google owner-link guard. Not link.
  bool get mayRecheckGoogleCard => ownerReady;
}

/// The presentation port never signs in, signs out, writes a gift or changes
/// the canonical identifier used for recipient, friend and league routing.
abstract class DedaRescueStage3Port {
  DedaRescueSnapshot? capture();
  Future<DedaRescueResult> verifyOwner(String accountKey, String originalId);
  Future<String?> readVerifiedOwnerDisplay(String uid, String originalId);
  void notifyVerifiedOwnerViews();
}

/// Isolated staging coordinator, injectable for no-Firebase tests. One
/// in-flight refresh per complete session; no recurring timer or polling.
class DedaRescueStage3Controller {
  DedaRescueStage3Controller(this.port);

  final DedaRescueStage3Port port;
  final ValueNotifier<DedaRescueStage3Result?> updates =
      ValueNotifier<DedaRescueStage3Result?>(null);

  Future<DedaRescueStage3Result>? _active;
  String? _key;

  static final RegExp _original = RegExp(r'^@DEDA-[A-Z0-9]{6}$');
  static final RegExp _display = RegExp(r'^@DEDA-[A-Z0-9]{4,12}$');

  bool _still(DedaRescueSnapshot before) {
    final current = port.capture();
    return current != null && before.sameAs(current);
  }

  Future<DedaRescueStage3Result> rescue({
    required String accountKey,
    required String originalId,
  }) {
    final before = port.capture();
    if (before == null) {
      return Future.value(DedaRescueStage3Result(
        status: DedaRescueStatus.firebaseNotReady,
        uid: null, originalId: originalId,
      ));
    }
    if (before.uid == null || before.uid!.isEmpty) {
      // There is no Firebase principal: NEVER create a replacement UID.
      return Future.value(DedaRescueStage3Result(
        status: DedaRescueStatus.signedOut,
        uid: null, originalId: originalId,
      ));
    }
    if (!RegExp(r'^[0-9]{8,16}$').hasMatch(accountKey) ||
        !_original.hasMatch(originalId)) {
      return Future.value(DedaRescueStage3Result(
        status: DedaRescueStatus.ownerProofRequired,
        uid: before.uid, originalId: originalId,
      ));
    }
    final key = before.uid! + '|' + before.epoch.toString() +
        '|' + before.anonymous.toString() + '|' + accountKey + '|' + originalId;
    final active = _active;
    if (active != null) {
      if (_key == key) return active;
      return Future.value(DedaRescueStage3Result(
        status: DedaRescueStatus.temporarilyBusy,
        uid: before.uid, originalId: originalId,
      ));
    }
    final work = _run(before, accountKey, originalId);
    _key = key;
    _active = work;
    unawaited(work.then<void>((_) {
      if (identical(_active, work)) {
        _active = null;
        _key = null;
      }
    }, onError: (Object _, StackTrace __) {
      if (identical(_active, work)) {
        _active = null;
        _key = null;
      }
    }));
    return work;
  }

  Future<DedaRescueStage3Result> _run(
      DedaRescueSnapshot before, String accountKey, String originalId) async {
    var status = DedaRescueStatus.ownerProofRequired;
    try {
      final proof = await port.verifyOwner(accountKey, originalId);
      status = proof.status;
    } catch (_) {
      status = DedaRescueStatus.temporarilyOffline;
    }
    if (!_still(before)) {
      return DedaRescueStage3Result(
        status: DedaRescueStatus.uidChanged,
        uid: before.uid, originalId: originalId,
      );
    }
    String? display;
    if (status == DedaRescueStatus.ready) {
      try {
        final verified = await port.readVerifiedOwnerDisplay(
            before.uid!, originalId);
        if (!_still(before)) {
          return DedaRescueStage3Result(
            status: DedaRescueStatus.uidChanged,
            uid: before.uid, originalId: originalId,
          );
        }
        if (verified == originalId || verified != null &&
            _display.hasMatch(verified)) {
          display = verified;
        }
      } catch (_) {
        // A failed alias read never invalidates an already verified OWNER,
        // but it cannot claim an old or new visible ID is authoritative.
      }
      if (!_still(before)) {
        return DedaRescueStage3Result(
          status: DedaRescueStatus.uidChanged,
          uid: before.uid, originalId: originalId,
        );
      }
      port.notifyVerifiedOwnerViews();
    }
    final result = DedaRescueStage3Result(
      status: status,
      uid: before.uid,
      originalId: originalId,
      verifiedDisplayId: display,
    );
    if (_still(before)) updates.value = result;
    return result;
  }
}

