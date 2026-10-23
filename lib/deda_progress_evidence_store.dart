import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'deda_legacy_progress_capture.dart';
import 'deda_owner_session_firebase_port.dart';
import 'deda_session_flow_prototype.dart';
import 'deda_session_transition_gate.dart';

class DedaProgressEvidenceConflict implements Exception {
  const DedaProgressEvidenceConflict();
}
class DedaProgressEvidenceMissing implements Exception {
  const DedaProgressEvidenceMissing();
}

bool _sameEvidence(Map<String,dynamic> a,Map<String,dynamic> b) =>
  a['format'] == b['format'] && a['kind'] == b['kind'] && a['accountKey'] == b['accountKey'] &&
  a['sourceUid'] == b['sourceUid'] && a['installId'] == b['installId'] && a['captureId'] == b['captureId'] &&
  a['records'] is Map && b['records'] is Map &&
  (a['records'] as Map).length == (b['records'] as Map).length &&
  (a['records'] as Map).keys.every((key)=>(a['records'] as Map)[key] == (b['records'] as Map)[key]);

class DedaListedProgressEvidence {
  const DedaListedProgressEvidence(this.id,this.document);
  final String id;
  final DedaOwnerServerDocument document;
}

abstract class DedaProgressEvidenceIo {
  bool get ready;
  DedaFlowSdkUser? get currentUser;
  Future<String> installId(void Function() check);
  Future<DedaOwnerServerDocument> readServer(String path);
  Future<List<DedaListedProgressEvidence>> listServer(String path,{required int limit});
  /// Fixed ID, immutable content, no outer retry. check runs after every
  /// transaction read and BEFORE set, including SDK transaction re-evaluation.
  Future<void> writeOnce(String path,Map<String,dynamic> fields,void Function() check);
  Object serverTimestamp();
}

/// Real Firestore transport, UNWIRED. Share the existing SDK epoch observer.
class DedaFirebaseProgressEvidenceIo implements DedaProgressEvidenceIo {
  DedaFirebaseProgressEvidenceIo({required this.session,required this.firestore});
  final DedaFirebaseOwnerSessionIo session;
  final FirebaseFirestore firestore;
  @override
  bool get ready => session.ready;
  @override
  DedaFlowSdkUser? get currentUser => session.currentUser;
  @override
  Future<String> installId(void Function() check) => session.installId(check);
  @override
  Future<DedaOwnerServerDocument> readServer(String path) =>
    DedaFirebaseOwnerFirestoreAccess(firestore).read(path,const GetOptions(source:Source.server));
  @override
  Future<List<DedaListedProgressEvidence>> listServer(String path,{required int limit}) async {
    final rows = await firestore.collection(path).orderBy('createdAt',descending:true)
      .limit(limit).get(const GetOptions(source:Source.server));
    return [for(final doc in rows.docs) DedaListedProgressEvidence(doc.id,
      DedaOwnerServerDocument(doc.data(),fromCache:rows.metadata.isFromCache || doc.metadata.isFromCache,
        pendingWrites:rows.metadata.hasPendingWrites || doc.metadata.hasPendingWrites))];
  }
  @override
  Object serverTimestamp() => FieldValue.serverTimestamp();
  @override
  Future<void> writeOnce(String path,Map<String,dynamic> fields,void Function() check) async {
    check();
    final ref = firestore.doc(path);
    await firestore.runTransaction<void>((tx) async {
      check();
      final old = await tx.get(ref);
      check();
      if(old.exists) {
        if(!_sameEvidence(old.data() ?? {},fields)) throw const DedaProgressEvidenceConflict();
        return;
      }
      check();
      tx.set(ref,fields);
    });
    check();
  }
}

/// Returned evidence is still UNTRUSTED legacy data, never a spendable total.
class DedaStoredProgressEvidence {
  const DedaStoredProgressEvidence({required this.captureId,required this.capture,
    required this.sourceUid,required this.installId,required this.createdAt});
  final String captureId,sourceUid,installId;
  final DedaLegacyProgressCapture capture;
  final Timestamp createdAt;
}

/// No app callsites, automatic restore, local overwrite, mint or wallet merge.
/// Caller retains a stable captureId for a single save intent. On UI timeout
/// its isCurrent/permit must expire while the ORIGINAL Future stays observed.
class DedaProgressEvidenceStore {
  DedaProgressEvidenceStore(this.io);
  final DedaProgressEvidenceIo io;
  void _account(String account) {
    if(!RegExp(r'^[0-9]+$').hasMatch(account)) throw ArgumentError('invalid-progress-account');
  }
  void _id(String id) {
    if(!RegExp(r'^[A-Za-z0-9_-]{20,80}$').hasMatch(id)) throw ArgumentError('invalid-progress-capture-id');
  }
  void _check(DedaFlowSdkUser user,bool Function() isCurrent) {
    if(!isCurrent() || !io.ready) throw const DedaStaleSessionTransition();
    final live = io.currentUser;
    if(live == null || user.kind != DedaSessionAuthKind.anonymous ||
      live.uid != user.uid || live.kind != user.kind || live.revision != user.revision) {
      throw const DedaStaleSessionTransition();
    }
  }
  Map<String,dynamic> _server(DedaOwnerServerDocument document) {
    if(document.data == null) throw const DedaProgressEvidenceMissing();
    if(document.fromCache || document.pendingWrites) throw const DedaSessionProofRejected();
    return document.data!;
  }
  Future<(DedaFlowSdkUser,String)> _owner(String account,bool Function() isCurrent) async {
    _account(account);
    if(!io.ready) throw StateError('firebase-not-ready');
    final user = io.currentUser;
    if(user == null) throw const DedaSessionProofRejected();
    _check(user,isCurrent);
    final install = await io.installId(()=>_check(user,isCurrent));
    _check(user,isCurrent);
    if(install.isEmpty || install.length > 128) throw const DedaSessionProofRejected();
    final session = _server(await io.readServer('deda_sessions/${user.uid}'));
    _check(user,isCurrent);
    if(session['uid'] != user.uid || session['accountKey'] != account || session['installId'] != install) {
      throw const DedaSessionProofRejected();
    }
    return (user,install);
  }
  String _path(String account,String id) => 'deda_progress_evidence/$account/captures/$id';
  void _records(DedaLegacyProgressCapture capture) {
    for(final text in capture.raw.values) {
      if(text != null && utf8.encode(text).length > 200000) {
        throw ArgumentError('legacy-evidence-too-large');
      }
    }
  }
  DedaStoredProgressEvidence _decode(String account,String id,Map<String,dynamic> data) {
    const keys = {'format','kind','accountKey','sourceUid','installId','captureId','records','createdAt'};
    if(data.length != keys.length || !keys.every(data.containsKey) ||
      data['format'] != 1 || data['kind'] != 'legacy-local-evidence' ||
      data['accountKey'] != account || data['captureId'] != id ||
      data['sourceUid'] is! String || (data['sourceUid'] as String).isEmpty ||
      data['installId'] is! String || (data['installId'] as String).isEmpty ||
      (data['installId'] as String).length > 128 || data['createdAt'] is! Timestamp) {
      throw const FormatException('invalid-progress-evidence');
    }
    final capture = DedaLegacyProgressCapture.decodeForAccount(jsonEncode({
      'format':1,'accountKey':account,'records':data['records'],
    }),expectedAccountKey:account);
    _records(capture);
    return DedaStoredProgressEvidence(captureId:id,capture:capture,
      sourceUid:data['sourceUid'] as String,installId:data['installId'] as String,
      createdAt:data['createdAt'] as Timestamp);
  }
  Future<DedaStoredProgressEvidence> save({required String captureId,
    required DedaLegacyProgressCapture capture,required bool Function() isCurrent}) async {
    _id(captureId); _records(capture);
    final (user,install) = await _owner(capture.accountKey,isCurrent);
    final fields = <String,dynamic>{
      'format':1,'kind':'legacy-local-evidence','accountKey':capture.accountKey,
      'sourceUid':user.uid,'installId':install,'captureId':captureId,
      'records':{for(final part in DedaLegacyProgressPart.values) part.name:capture.raw[part]},
      'createdAt':io.serverTimestamp(),
    };
    _check(user,isCurrent);
    await io.writeOnce(_path(capture.accountKey,captureId),fields,()=>_check(user,isCurrent));
    _check(user,isCurrent);
    final data = _server(await io.readServer(_path(capture.accountKey,captureId)));
    _check(user,isCurrent);
    if(!_sameEvidence(data,fields)) throw const DedaProgressEvidenceConflict();
    return _decode(capture.accountKey,captureId,data);
  }
  Future<DedaStoredProgressEvidence> read({required String accountKey,
    required String captureId,required bool Function() isCurrent}) async {
    _id(captureId);
    final (user,_) = await _owner(accountKey,isCurrent);
    final data = _server(await io.readServer(_path(accountKey,captureId)));
    _check(user,isCurrent);
    return _decode(accountKey,captureId,data);
  }
  /// Candidate history only; never apply the newest arrival as a balance.
  Future<List<DedaStoredProgressEvidence>> list({required String accountKey,
    required bool Function() isCurrent,int limit = 20}) async {
    if(limit < 1 || limit > 50) throw ArgumentError('invalid-evidence-list-limit');
    final (user,_) = await _owner(accountKey,isCurrent);
    final rows = await io.listServer('deda_progress_evidence/$accountKey/captures',limit:limit);
    _check(user,isCurrent);
    return List.unmodifiable(rows.map((row) {
      _id(row.id);
      return _decode(accountKey,row.id,_server(row.document));
    }));
  }

}
