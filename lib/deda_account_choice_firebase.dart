import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'deda_account_choice_sync.dart';
import 'deda_owner18_original_account_proof.dart';

/// Real SDK adapter. Only the four free decorative card colors are writable;
/// this namespace has no identifier ownership, balance or purchase fields.
class DedaFirebaseAccountChoiceIo implements DedaAccountChoiceIo {
  String _key(String account,String original) => 'deda_free_card_sync_v1_${account}_$original';
  DocumentReference<Map<String,dynamic>> _ref(String account,String original) =>
    FirebaseFirestore.instance.doc('deda_free_card_choices/$account/cards/$original');
  @override
  String newMutationId() {
    final random=Random.secure();
    return List.generate(24,(_)=>random.nextInt(256).toRadixString(16).padLeft(2,'0')).join();
  }
  @override
  Future<String?> readJournal(String account,String original) async =>
    (await SharedPreferences.getInstance()).getString(_key(account,original));
  @override
  Future<void> writeJournal(String account,String original,String encoded) async {
    if(!await (await SharedPreferences.getInstance()).setString(_key(account,original),encoded)) {
      throw StateError('choice-journal-not-saved');
    }
  }
  @override
  Future<String?> readLegacyChoice(String original) async =>
    (await SharedPreferences.getInstance()).getString('deda_stage71_free_card_choice_v1_$original');
  @override
  Future<void> writeLegacyChoice(String original,String value) async {
    if(!await (await SharedPreferences.getInstance()).setString('deda_stage71_free_card_choice_v1_$original',value)) {
      throw StateError('choice-local-not-saved');
    }
  }
  @override
  Future<void> verifyOwner(String account,String original,void Function() check) async {
    check();final uid=await DedaOwner18OriginalAccountProof.verify(original);check();
    final db=FirebaseFirestore.instance;
    final user=await db.doc('users/$uid').get(const GetOptions(source:Source.server));check();
    final session=await db.doc('deda_sessions/$uid').get(const GetOptions(source:Source.server));check();
    if(FirebaseAuth.instance.currentUser?.uid!=uid ||
      user.metadata.isFromCache || user.metadata.hasPendingWrites ||
      session.metadata.isFromCache || session.metadata.hasPendingWrites ||
      user.data()?['accountKey']!=account || user.data()?['sharePersonalId']!=original ||
      session.data()?['accountKey']!=account || session.data()?['uid']!=uid) {
      throw StateError('choice-owner-not-proven');
    }
  }
  DedaChoiceRevision _decode(DocumentSnapshot<Map<String,dynamic>> snapshot,
    String account,String original) {
    if(snapshot.metadata.isFromCache || snapshot.metadata.hasPendingWrites) {
      throw StateError('choice-server-read-required');
    }
    if(!snapshot.exists) return const DedaChoiceRevision(0,null,null);
    final d=snapshot.data();
    const keys={'format','accountKey','originalId','version','choice','mutationId','sourceUid','updatedAt'};
    if(d==null || d.length!=keys.length || !keys.every(d.containsKey) ||
      d['format']!=1 || d['accountKey']!=account || d['originalId']!=original ||
      d['version'] is! int || d['choice'] is! String || d['mutationId'] is! String ||
      d['sourceUid'] is! String || (d['sourceUid'] as String).isEmpty || d['updatedAt'] is! Timestamp) {
      throw const FormatException('invalid-server-choice');
    }
    final value=DedaChoiceRevision(d['version'] as int,d['choice'] as String,d['mutationId'] as String);
    value.validate();return value;
  }
  @override
  Future<DedaChoiceRevision> readServer(String account,String original,void Function() check) async {
    check();final snap=await _ref(account,original).get(const GetOptions(source:Source.server));check();
    return _decode(snap,account,original);
  }
  @override
  Future<DedaChoiceRevision> compareAndSet(String account,String original,
    DedaChoiceRevision base,String value,String mutationId,void Function() check) async {
    check();final ref=_ref(account,original);final uid=FirebaseAuth.instance.currentUser?.uid;
    if(uid==null) throw StateError('choice-owner-required');
    final result=await FirebaseFirestore.instance.runTransaction<DedaChoiceRevision>((tx) async {
      check();final snap=await tx.get(ref);check();final old=_decode(snap,account,original);
      if(old.mutationId==mutationId) {
        if(old.value!=value) throw const FormatException('choice-mutation-conflict');
        return old;
      }
      if(old.version!=base.version) throw DedaChoiceConflict(old);
      final next=DedaChoiceRevision(old.version+1,value,mutationId);next.validate();check();
      if(FirebaseAuth.instance.currentUser?.uid!=uid) throw const DedaChoiceStale();
      tx.set(ref,{'format':1,'accountKey':account,'originalId':original,'version':next.version,
        'choice':value,'mutationId':mutationId,'sourceUid':uid,'updatedAt':FieldValue.serverTimestamp()});
      return next;
    });
    check();return result;
  }
}
