import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'deda_legacy_progress_capture.dart';
import 'deda_legacy_purchase_evidence.dart';
import 'deda_session_flow_prototype.dart';
import 'deda_progress_evidence_store.dart';
import 'deda_session_transition_gate.dart';

class DedaProgressBackupBusy implements Exception {
  const DedaProgressBackupBusy();
}
class DedaProgressBackupOriginChanged implements Exception {
  const DedaProgressBackupOriginChanged();
}

/// An untrusted, immutable pending archive request, never a balance receipt.
class DedaProgressBackupIntent {
  DedaProgressBackupIntent({required this.captureId,required this.capture,
    required this.sourceUid,required this.installId,this.purchaseCapture,
    bool purchaseCaptureObserved=false}) : purchaseCaptureObserved=purchaseCaptureObserved || purchaseCapture!=null {
    if(!RegExp(r'^[A-Za-z0-9_-]{20,80}$').hasMatch(captureId) ||
        sourceUid.isEmpty || installId.isEmpty || installId.length > 128) {
      throw const FormatException('invalid-backup-intent');
    }
    if(purchaseCapture!=null && purchaseCapture!.accountKey!=capture.accountKey) {
      throw const FormatException('purchase-backup-account-conflict');
    }
  }
  final String captureId,sourceUid,installId;
  final DedaLegacyProgressCapture capture;
  final DedaLegacyPurchaseCapture? purchaseCapture;
  final bool purchaseCaptureObserved;
  String encode() => jsonEncode({'format':purchaseCaptureObserved?2:1,'captureId':captureId,
    'accountKey':capture.accountKey,'sourceUid':sourceUid,'installId':installId,
    'capture':capture.encode(),
    if(purchaseCaptureObserved) 'purchaseCapture':purchaseCapture?.encode()});
  static DedaProgressBackupIntent decode(String text,String accountKey) {
    final dynamic value=jsonDecode(text);
    final keys={'format','captureId','accountKey','sourceUid','installId','capture',
      if(value is Map && value['format']==2) 'purchaseCapture'};
    if(value is! Map || value.length != keys.length || !keys.every(value.containsKey) ||
        ![1,2].contains(value['format']) || value['accountKey'] != accountKey ||
        ['captureId','sourceUid','installId','capture'].any((key)=>value[key] is! String)) {
      throw const FormatException('invalid-backup-journal');
    }
    final dynamic purchase=value['purchaseCapture'];
    if(purchase!=null && purchase is! String) throw const FormatException('invalid-purchase-backup-journal');
    DedaLegacyPurchaseCapture? purchaseCapture;
    if(purchase is String) {
      final dynamic decoded=jsonDecode(purchase);
      if(decoded is! Map || decoded['originalId'] is! String) throw const FormatException('invalid-purchase-backup-journal');
      purchaseCapture=DedaLegacyPurchaseCapture.decode(purchase,accountKey:accountKey,originalId:decoded['originalId'] as String);
      if(purchaseCapture.encode()!=purchase) throw const FormatException('noncanonical-purchase-backup-journal');
    }
    return DedaProgressBackupIntent(captureId:value['captureId'] as String,
      purchaseCapture:purchaseCapture,purchaseCaptureObserved:value['format']==2,
      sourceUid:value['sourceUid'] as String,installId:value['installId'] as String,
      capture:DedaLegacyProgressCapture.decodeForAccount(value['capture'] as String,
        expectedAccountKey:accountKey));
  }
}

abstract class DedaProgressBackupJournal {
  Future<String?> read(String accountKey);
  Future<void> writeOnce(String accountKey,String encoded,void Function() check);
  Future<bool> removeIfSame(String accountKey,String encoded,void Function() check);
}

/// Same-isolate mutation exclusion spans all instances. Use ONE application
/// isolate; SharedPreferences cannot provide a cross-isolate/process CAS.
/// Only the private pending key is written/removed. Source progress stays intact.
class DedaSharedPreferencesBackupJournal implements DedaProgressBackupJournal {
  static final Set<String> _mutating={};
  String _key(String account) {
    if(!RegExp(r'^[0-9]+$').hasMatch(account)) throw ArgumentError('invalid-backup-account');
    return 'deda_progress_backup_pending_v1_$account';
  }
  @override
  Future<String?> read(String accountKey) async {
    final key=_key(accountKey);
    return (await SharedPreferences.getInstance()).getString(key);
  }
  Future<T> _change<T>(String account,Future<T> Function(String key) action) async {
    final key=_key(account);
    if(!_mutating.add(key)) throw const DedaProgressBackupBusy();
    try { return await action(key); } finally { _mutating.remove(key); }
  }
  @override
  Future<void> writeOnce(String accountKey,String encoded,void Function() check) =>
    _change(accountKey,(key) async {
      check();
      final prefs=await SharedPreferences.getInstance();check();
      final old=prefs.getString(key);
      if(old != null) {
        if(old != encoded) throw const DedaProgressEvidenceConflict();
        return;
      }
      if(!await prefs.setString(key,encoded)) throw StateError('backup-journal-not-saved');
      check();
      if(prefs.getString(key) != encoded) throw const DedaProgressEvidenceConflict();
    });
  @override
  Future<bool> removeIfSame(String accountKey,String encoded,void Function() check) =>
    _change(accountKey,(key) async {
      check();
      final prefs=await SharedPreferences.getInstance();check();
      if(prefs.getString(key) != encoded) return false;
      final removed=await prefs.remove(key);check();
      return removed && prefs.getString(key) == null;
    });
}

class DedaProgressBackupResult {
  const DedaProgressBackupResult(this.evidence,{required this.journalCleared,
    this.purchaseEvidence,this.purchaseCaptureObserved=false});
  final DedaStoredProgressEvidence evidence;
  final bool journalCleared;
  final DedaStoredPurchaseEvidence? purchaseEvidence;
  final bool purchaseCaptureObserved;
}

/// Composes the real local capture, pending journal and server archive APIs.
/// NOT connected to app lifecycle/auth/reward callsites. No automatic retry,
/// restore/overwrite of preferences, wallet reconciliation or session mutation.
/// Share ONE instance and pass an account-intent epoch (A -> B -> A invalidates).
class DedaProgressBackupCoordinator {
  DedaProgressBackupCoordinator({required this.reader,required this.archive,
    required this.journal,this.purchaseReader,this.purchaseArchive,
    this.timeout=const Duration(seconds:20)}) {
    if((purchaseReader==null)!=(purchaseArchive==null)) throw ArgumentError('purchase-reader-and-archive-required-together');
    if(purchaseArchive!=null && !identical(purchaseArchive!.progress,archive)) throw ArgumentError('purchase-archive-must-share-progress-proof');
    if(timeout <= Duration.zero) throw ArgumentError('invalid-backup-timeout');
  }
  final DedaLegacyProgressReader reader;
  final DedaProgressEvidenceStore archive;
  final DedaProgressBackupJournal journal;
  final DedaLegacyPurchaseReader? purchaseReader;
  final DedaLegacyPurchaseEvidenceStore? purchaseArchive;
  final Duration timeout;
  bool _busy=false;
  bool get busy => _busy;

  /// A UI timeout expires permission to dispatch subsequent steps, but keeps
  /// the lane held until the original transport Future actually settles.
  Future<T> _run<T>(bool Function() isCurrent,
    Future<T> Function(void Function() check) action) {
    if(_busy) return Future<T>.error(const DedaProgressBackupBusy());
    _busy=true;
    var expired=false;
    final result=Completer<T>();
    void check() {
      if(expired || !isCurrent()) throw const DedaStaleSessionTransition();
    }
    final timer=Timer(timeout,() {
      expired=true;
      if(!result.isCompleted) result.completeError(TimeoutException('backup-wait-expired',timeout));
    });
    Future<void> drive() async {
      try {
        check();final value=await action(check);check();
        if(!result.isCompleted) result.complete(value);
      } catch(error,stack) {
        if(!result.isCompleted) result.completeError(error,stack);
      } finally { timer.cancel();_busy=false; }
    }
    unawaited(drive());return result.future;
  }
  void Function() _bound(DedaProgressEvidenceOwner owner,void Function() check) => () {
    check();
    final live=archive.io.currentUser;
    if(!archive.io.ready || live == null || live.uid != owner.user.uid ||
        live.kind != owner.user.kind || live.revision != owner.user.revision) {
      throw const DedaStaleSessionTransition();
    }
  };
  bool Function() _current(void Function() check) => () {check();return true;};

  Future<DedaLegacyPurchaseCapture?> _capturePurchase(String accountKey,
    DedaProgressEvidenceOwner owner,void Function() bound) async {
    final reader=purchaseReader;
    if(reader==null) return null;
    bound();
    final doc=await archive.io.readServer('users/${owner.user.uid}');bound();
    if(doc.fromCache || doc.pendingWrites || doc.data==null || doc.data!['accountKey']!=accountKey) {
      throw const DedaSessionProofRejected();
    }
    final original=doc.data!['sharePersonalId'];
    // Never guess a canonical ID from an equipped premium alias or local name.
    // An account with no canonical ID keeps progress backup, with explicit
    // purchaseCaptureObserved=true and purchaseCapture=null, not zero purchases.
    if(original==null) return null;
    if(original is! String || !RegExp(r'^@DEDA-[A-Z0-9]{6}$').hasMatch(original)) {
      throw const DedaSessionProofRejected();
    }
    final capture=await reader.capture(accountKey:accountKey,originalId:original,isCurrent:_current(bound));
    bound();return capture;
  }
  Future<DedaLegacyPurchaseCapture?> capturePurchase({required String accountKey,
    required bool Function() isCurrent}) => _run(isCurrent,(check) async {
      final owner=await archive.verifyCurrentOwner(accountKey:accountKey,isCurrent:_current(check));
      final bound=_bound(owner,check);bound();
      return _capturePurchase(accountKey,owner,bound);
    });

  Future<DedaProgressBackupIntent> prepare({required String accountKey,
    required String captureId,required bool Function() isCurrent}) =>
    _run(isCurrent,(check) async {
      if(!RegExp(r'^[A-Za-z0-9_-]{20,80}$').hasMatch(captureId)) {
        throw ArgumentError('invalid-backup-capture-id');
      }
      final owner=await archive.verifyCurrentOwner(accountKey:accountKey,isCurrent:_current(check));
      final bound=_bound(owner,check);bound();
      final old=await journal.read(accountKey);bound();
      // Never replace a previous uncertain request with a newer local snapshot.
      if(old != null) return DedaProgressBackupIntent.decode(old,accountKey);
      final capture=await reader.capture(accountKey:accountKey,isCurrent:_current(bound));bound();
      final purchaseCapture=await _capturePurchase(accountKey,owner,bound);bound();
      final intent=DedaProgressBackupIntent(captureId:captureId,capture:capture,
        purchaseCapture:purchaseCapture,purchaseCaptureObserved:purchaseReader!=null,
        sourceUid:owner.user.uid,installId:owner.installId);
      await journal.writeOnce(accountKey,intent.encode(),bound);bound();
      final persisted=await journal.read(accountKey);bound();
      if(persisted != intent.encode()) throw const DedaProgressEvidenceConflict();
      return intent;
    });

  Future<DedaProgressBackupResult> uploadPending({required String accountKey,
    required bool Function() isCurrent}) => _run(isCurrent,(check) async {
      final owner=await archive.verifyCurrentOwner(accountKey:accountKey,isCurrent:_current(check));
      final bound=_bound(owner,check);bound();
      final encoded=await journal.read(accountKey);bound();
      if(encoded == null) throw const DedaProgressEvidenceMissing();
      final intent=DedaProgressBackupIntent.decode(encoded,accountKey);
      DedaStoredProgressEvidence evidence;
      try {
        // Resolve an uncertain earlier write first, including after a restart
        // or new UID. Cache/network/security failure MUST NOT trigger a save.
        evidence=await archive.read(accountKey:accountKey,captureId:intent.captureId,
          isCurrent:_current(bound));bound();
      } on DedaProgressEvidenceMissing {
        bound();
        if(owner.user.uid != intent.sourceUid || owner.installId != intent.installId) {
          throw const DedaProgressBackupOriginChanged();
        }
        evidence=await archive.save(captureId:intent.captureId,capture:intent.capture,
          isCurrent:_current(bound));bound();
      }
      if(evidence.capture.encode() != intent.capture.encode() ||
          evidence.sourceUid != intent.sourceUid || evidence.installId != intent.installId) {
        throw const DedaProgressEvidenceConflict();
      }
      DedaStoredPurchaseEvidence? purchaseEvidence;
      final purchaseCapture=intent.purchaseCapture;
      if(purchaseCapture!=null) {
        final purchaseStore=purchaseArchive;
        if(purchaseStore==null) throw StateError('purchase-archive-required-for-pending-intent');
        DedaStoredPurchaseEvidence savedPurchase;
        try {
          savedPurchase=await purchaseStore.read(accountKey:accountKey,captureId:intent.captureId,isCurrent:_current(bound));bound();
        } on DedaProgressEvidenceMissing {
          bound();
          if(owner.user.uid!=intent.sourceUid || owner.installId!=intent.installId) {
            throw const DedaProgressBackupOriginChanged();
          }
          savedPurchase=await purchaseStore.save(captureId:intent.captureId,progressCaptureId:intent.captureId,
            capture:purchaseCapture,isCurrent:_current(bound));bound();
        }
        if(savedPurchase.capture.encode()!=purchaseCapture.encode() ||
          savedPurchase.progressCaptureId!=intent.captureId || savedPurchase.sourceUid!=intent.sourceUid ||
          savedPurchase.installId!=intent.installId) throw const DedaProgressEvidenceConflict();
        purchaseEvidence=savedPurchase;
      }
      // Only the exact pending journal entry is retired, AFTER verified server
      // readback. Never delete the source progress keys or another pending entry.
      final cleared=await journal.removeIfSame(accountKey,encoded,bound);bound();
      return DedaProgressBackupResult(evidence,journalCleared:cleared,
        purchaseEvidence:purchaseEvidence,purchaseCaptureObserved:intent.purchaseCaptureObserved);
    });
}
