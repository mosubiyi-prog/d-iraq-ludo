import 'dart:async';
import 'dart:convert';

const dedaAccountChoiceSyncEnabled = bool.fromEnvironment(
  'DEDA_STABILITY_FREE_CARD_SYNC', defaultValue: false);

const dedaFreeCardChoices = {'gold', 'diamond', 'royal', 'pink'};

class DedaChoiceConflict implements Exception {
  const DedaChoiceConflict(this.current);
  final DedaChoiceRevision current;
}
class DedaChoiceStale implements Exception { const DedaChoiceStale(); }

class DedaChoiceRevision {
  const DedaChoiceRevision(this.version, this.value, this.mutationId);
  final int version;
  final String? value;
  final String? mutationId;
  void validate() {
    if (version < 0 || version > 9007199254740990 ||
        (version == 0 && (value != null || mutationId != null)) ||
        (version > 0 && (value == null || !dedaFreeCardChoices.contains(value) ||
          mutationId == null || !RegExp(r'^[a-f0-9]{48}$').hasMatch(mutationId!)))) {
      throw const FormatException('invalid-choice-revision');
    }
  }
}

abstract class DedaAccountChoiceIo {
  Future<String?> readJournal(String account, String original);
  Future<void> writeJournal(String account, String original, String encoded);
  Future<String?> readLegacyChoice(String original);
  Future<void> writeLegacyChoice(String original, String value);
  /// Must prove the selected account AND its canonical original ID. No login,
  /// session replacement, reward or ownership grant is permitted here.
  Future<void> verifyOwner(String account, String original, void Function() check);
  Future<DedaChoiceRevision> readServer(String account, String original, void Function() check);
  Future<DedaChoiceRevision> compareAndSet(String account, String original,
    DedaChoiceRevision base, String value, String mutationId, void Function() check);
  String newMutationId();
}

enum DedaChoiceSyncStatus { local, saved, pending, conflict, unavailable }
class DedaChoiceResult {
  const DedaChoiceResult(this.value, this.status);
  final String? value;
  final DedaChoiceSyncStatus status;
}

class _Journal {
  _Journal(this.base, {this.pending, this.id, this.legacy});
  DedaChoiceRevision base;
  String? pending, id, legacy;
  String encode(String account, String original) => jsonEncode({
    'format':1,'account':account,'original':original,'version':base.version,
    'value':base.value,'mutationId':base.mutationId,
    'pending':pending,'pendingId':id,'legacy':legacy,
  });
  static _Journal decode(String text, String account, String original) {
    final d=jsonDecode(text);
    const keys={'format','account','original','version','value','mutationId','pending','pendingId','legacy'};
    if(d is! Map || d.length!=keys.length || !keys.every(d.containsKey) ||
      d['format']!=1 || d['account']!=account || d['original']!=original ||
      d['version'] is! int || (d['value']!=null && d['value'] is! String) ||
      (d['mutationId']!=null && d['mutationId'] is! String) ||
      (d['pending']!=null && !dedaFreeCardChoices.contains(d['pending'])) ||
      (d['legacy']!=null && !dedaFreeCardChoices.contains(d['legacy'])) ||
      ((d['pending']==null)!=(d['pendingId']==null)) ||
      (d['pendingId']!=null && (d['pendingId'] is! String ||
        !RegExp(r'^[a-f0-9]{48}$').hasMatch(d['pendingId'] as String)))) {
      throw const FormatException('invalid-choice-journal');
    }
    final base=DedaChoiceRevision(d['version'] as int,d['value'] as String?,d['mutationId'] as String?);
    base.validate();
    return _Journal(base,pending:d['pending'] as String?,id:d['pendingId'] as String?,legacy:d['legacy'] as String?);
  }
}

/// One serialized local journal per account/original ID. A saved pending intent
/// keeps its SAME mutation ID after timeout/restart. A remote conflict is never
/// silently rebased. A new explicit Use action may choose against a fresh read.
/// Only a cosmetic color is handled. No balance/ID ownership/quiz state enters.
class DedaAccountChoiceSync {
  DedaAccountChoiceSync(this.io);
  final DedaAccountChoiceIo io;
  final Map<String,Future<void>> _lanes={};

  Future<DedaChoiceResult> restore({required String account, required String original,
    required bool Function() isCurrent}) => _run(account,original,isCurrent,null);
  Future<DedaChoiceResult> use({required String account, required String original,
    required String value, required bool Function() isCurrent}) {
    if(!dedaFreeCardChoices.contains(value)) throw ArgumentError('invalid-free-card-choice');
    return _run(account,original,isCurrent,value);
  }
  Future<DedaChoiceResult> _run(String account,String original,bool Function() current,String? selected) async {
    if(!RegExp(r'^[0-9]+$').hasMatch(account) ||
      !RegExp(r'^@DEDA-[A-Z0-9]{6}$').hasMatch(original)) throw ArgumentError('invalid-choice-owner');
    void check() {if(!current()) throw const DedaChoiceStale();}
    check();
    final key='$account/$original', previous=_lanes['$account/$original'];
    final completed=Completer<void>();_lanes[key]=completed.future;
    try {
      if(previous!=null) await previous;
      check();
      final raw=await io.readJournal(account,original);check();
      final legacy=await io.readLegacyChoice(original);check();
      if(legacy!=null && !dedaFreeCardChoices.contains(legacy)) throw const FormatException('invalid-legacy-choice');
      final journal=raw==null?_Journal(const DedaChoiceRevision(0,null,null),legacy:legacy):_Journal.decode(raw,account,original);
      Future<void> save() async {
        check();final encoded=journal.encode(account,original);
        _Journal.decode(encoded,account,original);
        await io.writeJournal(account,original,encoded);check();
      }
      Future<DedaChoiceResult> result(DedaChoiceSyncStatus status) async {
        check();final value=journal.pending??journal.base.value??journal.legacy;
        if(value!=null) {await io.writeLegacyChoice(original,value);check();}
        return DedaChoiceResult(value,status);
      }
      // Store an explicit selection durably BEFORE network work. It must not
      // disappear if verification/read/write fails or the process is killed.
      if(selected!=null) {
        journal.pending=selected;journal.id=io.newMutationId();await save();
      }
      try {
        await io.verifyOwner(account,original,check);check();
        final remote=await io.readServer(account,original,check);check();remote.validate();
        if(remote.version<journal.base.version || (remote.version==journal.base.version &&
          (remote.value!=journal.base.value || remote.mutationId!=journal.base.mutationId))) {
          throw const FormatException('choice-server-version-regressed');
        }
        if(journal.pending!=null && remote.mutationId==journal.id) {
          if(remote.value!=journal.pending) throw const FormatException('choice-mutation-conflict');
          journal.base=remote;journal.pending=null;journal.id=null;await save();
          return await result(DedaChoiceSyncStatus.saved);
        }
        if(journal.pending!=null && selected==null && remote.version!=journal.base.version) {
          return await result(DedaChoiceSyncStatus.conflict);
        }
        if(selected!=null || journal.pending==null) journal.base=remote;
        // Bootstrap ONLY this proven original ID's old local cosmetic choice,
        // and ONLY when the server confirms absence. Never replace a remote
        // selection merely because an old handset's local preference differs.
        if(journal.pending==null && remote.version==0 && journal.legacy!=null) {
          journal.pending=journal.legacy;journal.id=io.newMutationId();
        }
        await save();
        if(journal.pending==null) return await result(DedaChoiceSyncStatus.saved);
        final next=await io.compareAndSet(account,original,journal.base,
          journal.pending!,journal.id!,check);check();next.validate();
        if(next.value!=journal.pending || next.mutationId!=journal.id ||
          next.version!=journal.base.version+1) throw const FormatException('choice-write-not-confirmed');
        journal.base=next;journal.pending=null;journal.id=null;await save();
        return await result(DedaChoiceSyncStatus.saved);
      } on DedaChoiceConflict {
        check();return await result(DedaChoiceSyncStatus.conflict);
      } on DedaChoiceStale {rethrow;}
      on FormatException {rethrow;}
      catch (_) {
        check();return await result(journal.pending!=null?DedaChoiceSyncStatus.pending:DedaChoiceSyncStatus.unavailable);
      }
    } finally {
      completed.complete();if(identical(_lanes[key],completed.future)) _lanes.remove(key);
    }
  }
}
