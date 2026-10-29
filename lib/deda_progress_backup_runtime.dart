import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';

import 'deda_cross_device_restore.dart';
import 'deda_legacy_progress_capture.dart';
import 'deda_legacy_purchase_evidence.dart';
import 'deda_owner_session_firebase_port.dart';
import 'deda_progress_backup_coordinator.dart';
import 'deda_progress_evidence_store.dart';
import 'deda_session_transition_gate.dart';
import 'deda_second_phone_link_client.dart';

const dedaProgressBackupPilot = bool.fromEnvironment(
  'DEDA_STABILITY_PROGRESS_BACKUP_PILOT', defaultValue: false);

/// Selection intent, not authentication. Every begin invalidates A -> B -> A,
/// including a second selection of A. Failed/stale saves cannot re-arm it.
class DedaProgressBackupAccount extends ChangeNotifier {
  int _epoch = 0;
  String? _accountKey;
  int get epoch => _epoch;
  String? get accountKey => _accountKey;
  int begin() {
    _accountKey = null;
    ++_epoch;
    notifyListeners();
    return _epoch;
  }
  void complete(int token, String? accountKey) {
    if (token != _epoch) return;
    if (accountKey != null && !RegExp(r'^[0-9]+$').hasMatch(accountKey)) {
      throw ArgumentError('invalid-backup-selection');
    }
    _accountKey = accountKey;
    notifyListeners();
  }
}
final dedaProgressBackupAccount = DedaProgressBackupAccount();

enum DedaProgressBackupStatus { idle, running, saved, unchanged, blocked }

abstract class DedaProgressBackupDriver {
  bool get ready;
  bool get busy;
  Object? get principal;
  Future<bool> backup(String accountKey, bool Function() isCurrent);
  Future<void> dispose();
}

/// No auth mutation is called by this adapter. The shared session IO is used
/// solely for principal observation/install ID; archive rechecks server proof.
class DedaFirebaseProgressBackupDriver implements DedaProgressBackupDriver {
  DedaFirebaseProgressBackupDriver._(this.session, this.coordinator,
      this._dispose, this._linkClient);
  DedaFirebaseProgressBackupDriver.forTesting({required this.session,
    required this.coordinator, required Future<void> Function() dispose,
    DedaSecondPhoneLinkClient? linkClient})
      : _dispose = dispose, _linkClient = linkClient;
  factory DedaFirebaseProgressBackupDriver.create() {
    final session = DedaFirebaseOwnerSessionIo(
      auth: FirebaseAuth.instance, firestore: FirebaseFirestore.instance);
    final archive = DedaProgressEvidenceStore(DedaFirebaseProgressEvidenceIo(
      session: session, firestore: FirebaseFirestore.instance));
    final linkTransport = DedaFirebaseSecondPhoneLinkTransport.forPrivateQa();
    return DedaFirebaseProgressBackupDriver._(session,
      DedaProgressBackupCoordinator(
        reader: DedaLegacyProgressReader(DedaSharedPreferencesProgressReadStore()),
        archive: archive, journal: DedaSharedPreferencesBackupJournal(),
        purchaseReader: DedaLegacyPurchaseReader(DedaSharedPreferencesPurchaseReadStore()),
        purchaseArchive: DedaLegacyPurchaseEvidenceStore(archive)),
      session.dispose,
      linkTransport == null ? null : DedaSecondPhoneLinkClient(linkTransport));
  }
  final DedaOwnerSessionIo session;
  final Future<void> Function() _dispose;
  final DedaSecondPhoneLinkClient? _linkClient;
  DedaVerifiedReadonlyProgress? _lastVerifiedRecovery;
  /// Server-verified values for QA inspection only. Never a spendable wallet,
  /// task engine state, restored premium ID or weekly league input.
  DedaVerifiedReadonlyProgress? get verifiedRecoveryReadOnly =>
      _lastVerifiedRecovery;
  final DedaProgressBackupCoordinator coordinator;
  String? _lastAccount, _lastAcknowledged, _lastPurchaseAcknowledged;
  bool _lastPurchaseObserved=false;
  @override
  bool get ready => session.ready;
  @override
  bool get busy => coordinator.busy;
  @override
  Object? get principal {
    final user = session.currentUser;
    return user == null || user.kind != DedaSessionAuthKind.anonymous
      ? null : (user.uid, user.kind, user.revision);
  }
  String _id() {
    final random = Random.secure();
    return List.generate(24, (_) => random.nextInt(256)
      .toRadixString(16).padLeft(2, '0')).join();
  }
  @override
  Future<bool> backup(String accountKey, bool Function() isCurrent) async {
    // A new session must never reuse another account's verified snapshot.
    _lastVerifiedRecovery = null;
    // ALWAYS consult verified SERVER history BEFORE any archive upload.
    // Fresh phones may already have local zero/default preferences, so
    // hasAnyLocalRecord alone is NOT reliable evidence of an old device.
    // Neither restore financially nor overwrite historical state.
    // The entire host stays opt-in until stronger auth and backend settlement.
    final recovery = DedaCrossDeviceRestore(
      archive: coordinator.archive,
      local: DedaRecoverySharedPreferences(),
      purchaseArchive: coordinator.purchaseArchive,
    );
    final prior = await recovery.stage(
        accountKey: accountKey, isCurrent: isCurrent);
    if (!isCurrent()) throw const DedaStaleSessionTransition();
    if (prior.status != DedaRecoveryStageStatus.noPreviousDeviceArchive) {
      // Explicit QA-emulator handshake, never from client-supplied UID, PIN,
      // account, XP or purchased items. Linking the canonical account does
      // not settle historical wallets: do NOT upload zero/default values.
      final linkClient = _linkClient;
      if (linkClient != null &&
          (prior.status == DedaRecoveryStageStatus.priorAccountWithoutArchive ||
           prior.status == DedaRecoveryStageStatus.stagedAwaitingServerReconciliation ||
           prior.status == DedaRecoveryStageStatus.alreadyStaged)) {
        final link = await linkClient.linkAndReadVerifiedProgress(
            isCurrent: isCurrent);
        if (!isCurrent()) throw const DedaStaleSessionTransition();
        _lastVerifiedRecovery = link.progress;
      }
      // Even if private QA link succeeds, financial restoration is blocked.
      throw StateError('cross-device-historical-data-needs-reconciliation');
    }
    final currentLocal = await coordinator.reader.capture(
        accountKey: accountKey, isCurrent: isCurrent);
    if (!isCurrent()) throw const DedaStaleSessionTransition();
    if (!currentLocal.hasAnyLocalRecord) return false;

    // This fast path only suppresses an unchanged capture within this process.
    // A pending journal always wins, including uncertain writes after restart.
    // No server ordering or financial authority is inferred from this cache.
    if (_lastAccount == accountKey && _lastAcknowledged != null) {
      await coordinator.archive.verifyCurrentOwner(
        accountKey: accountKey, isCurrent: isCurrent);
      final pending = await coordinator.journal.read(accountKey);
      if (!isCurrent()) throw const DedaStaleSessionTransition();
      if (pending == null) {
        final local = await coordinator.reader.capture(
          accountKey: accountKey, isCurrent: isCurrent);
        if (local.encode() == _lastAcknowledged) {
          if(coordinator.purchaseReader==null) return false;
          final purchase=await coordinator.capturePurchase(accountKey:accountKey,isCurrent:isCurrent);
          if(!isCurrent()) throw const DedaStaleSessionTransition();
          if(_lastPurchaseObserved && purchase?.encode()==_lastPurchaseAcknowledged) return false;
        }
      }
    }
    final intent = await coordinator.prepare(accountKey: accountKey,
      captureId: _id(), isCurrent: isCurrent);
    if (!isCurrent()) throw const DedaStaleSessionTransition();
    final result = await coordinator.uploadPending(
      accountKey: accountKey, isCurrent: isCurrent);
    if (!isCurrent()) throw const DedaStaleSessionTransition();
    if (result.journalCleared) {
      _lastAccount = accountKey;
      _lastAcknowledged = intent.capture.encode();
      _lastPurchaseObserved=result.purchaseCaptureObserved;
      _lastPurchaseAcknowledged=result.purchaseEvidence?.capture.encode();
    }
    return true;
  }
  @override
  Future<void> dispose() async {
    _lastVerifiedRecovery = null;
    await _dispose();
  }
}

/// One controller/driver for the application root. No retries, queues, timers,
/// login/session restoration, reward application or local balance overwrite.
class DedaProgressBackupRuntime {
  DedaProgressBackupRuntime({required this.account, required this.currentAccount,
    required this.driverFactory, this.enabled = dedaProgressBackupPilot}) {
    account.addListener(_selectionChanged);
  }
  final DedaProgressBackupAccount account;
  final String? Function() currentAccount;
  final DedaProgressBackupDriver? Function() driverFactory;
  final bool enabled;
  DedaProgressBackupDriver? _driver;
  bool _disposed = false, _active = true, _running = false;
  int _lifecycleEpoch = 0;
  DedaProgressBackupStatus status = DedaProgressBackupStatus.idle;

  void _selectionChanged() {
    if (account.accountKey == null) {
      status = DedaProgressBackupStatus.idle;
    } else {
      unawaited(request());
    }
  }
  void pause() {
    _active = false;
    ++_lifecycleEpoch;
    status = DedaProgressBackupStatus.idle;
  }
  Future<void> resume() {
    _active = true;
    ++_lifecycleEpoch;
    return request();
  }
  Future<void> request() async {
    if (!enabled || _disposed || !_active || _running) return;
    final key = account.accountKey;
    if (key == null || key != currentAccount()) return;
    final epoch = account.epoch, lifecycle = _lifecycleEpoch;
    Object? principal;
    bool current() {
      try {
        return !_disposed && _active && epoch == account.epoch &&
          lifecycle == _lifecycleEpoch && key == account.accountKey &&
          key == currentAccount() && _driver?.ready == true &&
          principal != null && _driver?.principal == principal;
      } catch (_) {
        return false;
      }
    }
    _running = true;
    try {
      _driver ??= driverFactory();
      final driver = _driver;
      if (driver == null || !driver.ready || driver.busy) return;
      principal = driver.principal;
      if (!current()) return;
      status = DedaProgressBackupStatus.running;
      final saved = await driver.backup(key, current);
      if (current()) status = saved ? DedaProgressBackupStatus.saved
        : DedaProgressBackupStatus.unchanged;
    } catch (_) {
      // Fixed in-memory state only; no exception, UID, phone or raw data logs.
      if (current()) status = DedaProgressBackupStatus.blocked;
    } finally {
      if (status == DedaProgressBackupStatus.running) status = DedaProgressBackupStatus.idle;
      _running = false;
    }
  }
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    ++_lifecycleEpoch;
    account.removeListener(_selectionChanged);
    await _driver?.dispose();
  }
}

/// Root wrapper survives route changes. No UI, network or preference access
/// while the compile-time pilot is disabled. Re-arm late Firebase on resume.
class DedaProgressBackupHost extends StatefulWidget {
  const DedaProgressBackupHost({super.key, required this.currentAccount,
    required this.child}) : _testingRuntime = null;
  const DedaProgressBackupHost.forTesting({super.key, required this.currentAccount,
    required this.child, required DedaProgressBackupRuntime runtime})
      : _testingRuntime = runtime;
  final DedaProgressBackupRuntime? _testingRuntime;
  final String? Function() currentAccount;
  final Widget child;
  @override
  State<DedaProgressBackupHost> createState() => _DedaProgressBackupHostState();
}
class _DedaProgressBackupHostState extends State<DedaProgressBackupHost>
    with WidgetsBindingObserver {
  late final DedaProgressBackupRuntime _runtime;
  @override
  void initState() {
    super.initState();
    _runtime = widget._testingRuntime ?? DedaProgressBackupRuntime(account: dedaProgressBackupAccount,
      currentAccount: () => widget.currentAccount(),
      driverFactory: () => Firebase.apps.isEmpty ? null
        : DedaFirebaseProgressBackupDriver.create());
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_runtime.request());
    });
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_runtime.resume());
    } else if (state != AppLifecycleState.inactive) {
      _runtime.pause();
    }
  }
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_runtime.dispose());
    super.dispose();
  }
  @override
  Widget build(BuildContext context) => widget.child;
}
