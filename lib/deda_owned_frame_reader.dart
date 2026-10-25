import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'deda_auth_session_runtime.dart';
import 'deda_owner18_original_account_proof.dart';
import 'deda_section_operation_context.dart';

class DedaOwnedFramePair {
  const DedaOwnedFramePair(this.receipt,this.ownership,{this.fromCache=false,this.pendingWrites=false});
  final Map<String,dynamic>? receipt,ownership;
  final bool fromCache,pendingWrites;
}
abstract class DedaOwnedFrameReadIo {
  Object? get principal;
  Future<String> verifyOriginalOwner(String original);
  Future<DedaOwnedFramePair> readPair(String original,String frame);
}

/// Uses the established PIN-account original-ID proof, including a new SDK UID.
/// No login, grant, purchase, debit, refund, preferences write or role change.
class DedaFirebaseOwnedFrameReadIo implements DedaOwnedFrameReadIo {
  @override
  Object? get principal {
    final observed=DedaAuthRuntime.capture();
    return (FirebaseAuth.instance.currentUser?.uid,observed?.kind,observed?.epoch);
  }
  @override
  Future<String> verifyOriginalOwner(String original) => DedaOwner18OriginalAccountProof.verify(original);
  @override
  Future<DedaOwnedFramePair> readPair(String original,String frame) async {
    final db=FirebaseFirestore.instance;
    final pair=await Future.wait([
      db.doc('deda_lab_frame_receipts/$original/frames/$frame').get(const GetOptions(source:Source.server)),
      db.doc('deda_lab_owned_frames/$original/frames/$frame').get(const GetOptions(source:Source.server)),
    ]);
    return DedaOwnedFramePair(pair[0].data(),pair[1].data(),
      fromCache:pair.any((d)=>d.metadata.isFromCache),pendingWrites:pair.any((d)=>d.metadata.hasPendingWrites));
  }
}

class DedaOwnedFrameReader {
  DedaOwnedFrameReader(this.io,{required Set<String> frameIds,this.deadline=const Duration(seconds:12)})
    : frameIds=Set.unmodifiable(frameIds) {
    if(frameIds.isEmpty || frameIds.any((id)=>!RegExp(r'^FRAME_[0-9]{2}$').hasMatch(id)) || deadline<=Duration.zero) {
      throw ArgumentError('invalid-owned-frame-reader');
    }
  }
  final DedaOwnedFrameReadIo io;
  final Set<String> frameIds;
  final Duration deadline;
  void _original(String id) {if(!RegExp(r'^@DEDA-[A-Z0-9]{6}$').hasMatch(id)) throw ArgumentError('original-account-id-required');}
  void _check(Object? principal) {
    DedaSectionOperationContext.checkCurrent();
    if(principal!=io.principal) throw StateError('account-changed-during-frame-inventory');
  }
  bool _valid(DedaOwnedFramePair p,String original,String frame) {
    if(p.fromCache || p.pendingWrites) throw StateError('frame-server-proof-required');
    final r=p.receipt,o=p.ownership;
    return r!=null && o!=null && r['kind']=='lab_frame' && r['publicId']==original &&
      r['frameId']==frame && r['cost']==1000 && o['publicId']==original &&
      o['frameId']==frame && o['receiptId']=='${original}_$frame';
  }
  Future<DedaOwnedFramePair> _read(String original,String frame,Object? principal) async {
    _check(principal);
    final p=await io.readPair(original,frame).timeout(deadline);_check(principal);
    return p;
  }
  Future<bool> isOwned(String original,String frame) async {
    _original(original);if(!frameIds.contains(frame)) throw ArgumentError('unknown-paid-frame');
    final principal=io.principal;_check(principal);
    await io.verifyOriginalOwner(original).timeout(deadline);_check(principal);
    final pair=await _read(original,frame,principal);
    if(pair.fromCache || pair.pendingWrites) throw StateError('frame-server-proof-required');
    if(pair.receipt==null && pair.ownership==null) return false;
    if(!_valid(pair,original,frame)) throw StateError('partial-or-forged-frame-ownership');
    return true;
  }
  Future<Set<String>> owned(String original) async {
    _original(original);final principal=io.principal;_check(principal);
    await io.verifyOriginalOwner(original).timeout(deadline);_check(principal);
    final ids=frameIds.toList()..sort();
    // Transport/permission failures propagate. They must never become a
    // successful empty inventory that could hide already-purchased items.
    final found=await Future.wait<String?>(ids.map((frame) async {
      final pair=await _read(original,frame,principal);
      return _valid(pair,original,frame)?frame:null;
    }));
    _check(principal);return Set.unmodifiable(found.whereType<String>());
  }
}
