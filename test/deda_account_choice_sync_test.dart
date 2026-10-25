import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import '../lib/deda_account_choice_sync.dart';

const account='07700000000',original='@DEDA-ABC123';
class Server {final values=<String,DedaChoiceRevision>{};int writes=0;}
class MemoryIo implements DedaAccountChoiceIo {
  MemoryIo(this.server,{this.legacy});
  final Server server;String? legacy;String? journal;
  bool offline=false,deny=false,loseReply=false,failJournal=false;
  int ids=0,proofs=0;Future<void> Function()? beforeRead,beforeWrite;
  Future<void> Function(String)? beforeLegacyWrite;
  @override String newMutationId() => (++ids).toRadixString(16).padLeft(48,'0');
  @override Future<String?> readJournal(String a,String o) async => journal;
  @override Future<void> writeJournal(String a,String o,String s) async {
    if(failJournal) throw StateError('disk');journal=s;
  }
  @override Future<String?> readLegacyChoice(String o) async => legacy;
  @override Future<void> writeLegacyChoice(String o,String v) async {await beforeLegacyWrite?.call(v);legacy=v;}
  @override Future<void> verifyOwner(String a,String o,void Function() check) async {
    check();proofs++;if(offline||deny) throw StateError('unavailable');check();
  }
  @override Future<DedaChoiceRevision> readServer(String a,String o,void Function() check) async {
    check();await beforeRead?.call();check();
    if(offline) throw StateError('network');
    return server.values['$a/$o']??const DedaChoiceRevision(0,null,null);
  }
  @override Future<DedaChoiceRevision> compareAndSet(String a,String o,DedaChoiceRevision base,
    String value,String id,void Function() check) async {
    check();await beforeWrite?.call();check();
    if(offline) throw StateError('network');
    final key='$a/$o',old=server.values[key]??const DedaChoiceRevision(0,null,null);
    if(old.mutationId==id && old.value==value) return old;
    if(old.version!=base.version) throw DedaChoiceConflict(old);
    final next=DedaChoiceRevision(old.version+1,value,id);server.values[key]=next;server.writes++;
    if(loseReply) {loseReply=false;throw StateError('reply-lost');}
    return next;
  }
}
Future<DedaChoiceResult> restore(MemoryIo io,{bool Function()? current}) =>
  DedaAccountChoiceSync(io).restore(account:account,original:original,isCurrent:current??()=>true);
Future<DedaChoiceResult> choose(MemoryIo io,String value,{bool Function()? current}) =>
  DedaAccountChoiceSync(io).use(account:account,original:original,value:value,isCurrent:current??()=>true);

void main() {
  test('new handset reads the same account choice without writing or granting anything',() async {
    final server=Server();
    final phone=MemoryIo(server);await choose(phone,'gold');
    final fresh=MemoryIo(server),result=await restore(fresh);
    expect(result.value,'gold');expect(result.status,DedaChoiceSyncStatus.saved);
    expect(server.writes,1);expect(fresh.legacy,'gold');
  });
  test('absent choice is not a default choice or a cloud write',() async {
    final io=MemoryIo(Server());final result=await restore(io);
    expect(result.value,isNull);expect(io.server.writes,0);
  });
  test('same-ID legacy choice bootstraps only after verified server absence',() async {
    final io=MemoryIo(Server(),legacy:'pink');await restore(io);
    expect(io.server.writes,1);expect((await restore(io)).value,'pink');expect(io.server.writes,1);
  });
  test('an old unjournaled choice cannot overwrite the newer server choice',() async {
    final server=Server();await choose(MemoryIo(server),'royal');
    final old=MemoryIo(server,legacy:'gold');expect((await restore(old)).value,'royal');
    expect(server.writes,1);expect(jsonDecode(old.journal!)['legacy'],'gold');
  });
  test('offline explicit choice stays pending and survives a process restart',() async {
    final io=MemoryIo(Server())..offline=true;final first=await choose(io,'diamond');
    expect(first.value,'diamond');expect(first.status,DedaChoiceSyncStatus.pending);
    final id=jsonDecode(io.journal!)['pendingId'];io.offline=false;
    final next=await restore(io);expect(next.status,DedaChoiceSyncStatus.saved);
    expect(io.server.values['$account/$original']!.mutationId,id);expect(io.server.writes,1);
  });
  test('a committed write with a lost reply is reconciled without a second mutation',() async {
    final io=MemoryIo(Server())..loseReply=true;
    expect((await choose(io,'pink')).status,DedaChoiceSyncStatus.pending);
    expect((await restore(io)).status,DedaChoiceSyncStatus.saved);expect(io.server.writes,1);
  });
  test('old pending handset does not automatically replace another handset edit',() async {
    final server=Server();
    final old=MemoryIo(server);await choose(old,'gold');old.offline=true;await choose(old,'pink');
    final fresh=MemoryIo(server)..ids=30;await choose(fresh,'royal');old.offline=false;
    expect((await restore(old)).status,DedaChoiceSyncStatus.conflict);
    expect(server.values['$account/$original']!.value,'royal');expect(server.writes,2);
    expect(jsonDecode(old.journal!)['pending'],'pink');
    expect((await choose(old,'pink')).status,DedaChoiceSyncStatus.saved);expect(server.writes,3);
  });
  test('concurrent devices at the same base cannot both overwrite it',() async {
    final server=Server();
    final one=MemoryIo(server),two=MemoryIo(server)..ids=40;
    final barrier=Completer<void>();var arrivals=0;
    Future<void> hold() async {arrivals++;if(arrivals==2)barrier.complete();await barrier.future;}
    one.beforeWrite=hold;two.beforeWrite=hold;
    final results=await Future.wait([choose(one,'gold'),choose(two,'pink')]);
    expect(results.where((r)=>r.status==DedaChoiceSyncStatus.saved).length,1);
    expect(results.where((r)=>r.status==DedaChoiceSyncStatus.conflict).length,1);expect(server.writes,1);
  });
  for(final stage in ['read','write']) {
    test('account/principal expiry during $stage prevents continuation',() async {
      final io=MemoryIo(Server());var current=true;
      if(stage=='read') {io.beforeRead=() async {current=false;};}
      else {io.beforeWrite=() async {current=false;};}
      await expectLater(choose(io,'royal',current:()=>current),throwsA(isA<DedaChoiceStale>()));
      expect(io.server.writes,0);expect(io.legacy,isNull);
    });
  }
  test('initially expired intent reads or writes nothing',() async {
    final io=MemoryIo(Server());await expectLater(restore(io,current:()=>false),throwsA(isA<DedaChoiceStale>()));
    expect(io.journal,isNull);expect(io.proofs,0);
  });
  test('missing ownership proof retains a selection locally but never writes server',() async {
    final io=MemoryIo(Server())..deny=true;final result=await choose(io,'gold');
    expect(result.status,DedaChoiceSyncStatus.pending);expect(io.server.writes,0);expect(io.legacy,'gold');
  });
  test('journal persistence failure prevents the cloud mutation',() async {
    final io=MemoryIo(Server())..failJournal=true;
    await expectLater(choose(io,'gold'),throwsStateError);expect(io.server.writes,0);expect(io.legacy,isNull);
  });
  test('malformed journal is preserved rather than reset and uploaded',() async {
    final io=MemoryIo(Server(),legacy:'gold')..journal='{broken';
    await expectLater(restore(io),throwsFormatException);expect(io.journal,'{broken');expect(io.server.writes,0);
  });
  test('a journal for another account or original ID is rejected',() async {
    final io=MemoryIo(Server());await choose(io,'gold');final raw=jsonDecode(io.journal!) as Map;
    for(final field in ['account','original']) {
      final altered=Map.of(raw)..[field]='foreign';io.journal=jsonEncode(altered);
      await expectLater(restore(io),throwsFormatException);
    }
    expect(io.server.writes,1);
  });
  test('a regressed or deleted server revision does not erase known data',() async {
    final io=MemoryIo(Server());await choose(io,'gold');final journal=io.journal;
    io.server.values.clear();await expectLater(restore(io),throwsFormatException);
    expect(io.journal,journal);expect(io.legacy,'gold');expect(io.server.writes,1);
  });
  test('same-revision changed server payload is rejected',() async {
    final io=MemoryIo(Server());await choose(io,'gold');
    io.server.values['$account/$original']=DedaChoiceRevision(1,'pink',List.filled(48,'f').join());
    await expectLater(restore(io),throwsFormatException);expect(io.legacy,'gold');
  });
  test('multiple local UI actions are serialized and the last explicit choice survives',() async {
    final io=MemoryIo(Server());
    final actual=DedaAccountChoiceSync(io);
    final results=await Future.wait(['gold','pink','royal'].map((v)=>actual.use(account:account,original:original,value:v,isCurrent:()=>true)));
    expect(results.every((r)=>r.status==DedaChoiceSyncStatus.saved),isTrue);
    expect(io.legacy,'royal');expect(io.server.writes,3);
  });
  test('a delayed local cache write cannot finish after a later selection',() async {
    final io=MemoryIo(Server());
    final sync=DedaAccountChoiceSync(io),started=Completer<void>(),release=Completer<void>();
    io.beforeLegacyWrite=(value) async {if(value=='gold') {started.complete();await release.future;}};
    final first=sync.use(account:account,original:original,value:'gold',isCurrent:()=>true);
    await started.future;
    final second=sync.use(account:account,original:original,value:'pink',isCurrent:()=>true);
    await Future<void>.delayed(Duration.zero);expect(io.server.writes,1);
    release.complete();await Future.wait([first,second]);expect(io.legacy,'pink');
  });
  test('tampered revision or financial fields cannot enter the journal',() async {
    final io=MemoryIo(Server());await choose(io,'gold');final raw=jsonDecode(io.journal!) as Map;
    for(final change in [<String,dynamic>{'version':1.5},<String,dynamic>{'balance':1000000},<String,dynamic>{'pending':'VIP'}]) {
      io.journal=jsonEncode({...raw,...change});await expectLater(restore(io),throwsFormatException);
    }
    expect(io.server.writes,1);
  });
  test('invalid lookup/choice is refused before any storage IO',() async {
    final io=MemoryIo(Server()),sync=DedaAccountChoiceSync(MemoryIo(Server()));
    expect(()=>DedaAccountChoiceSync(io).use(account:account,original:original,value:'paid',isCurrent:()=>true),throwsArgumentError);
    await expectLater(sync.restore(account:'foreign',original:original,isCurrent:()=>true),throwsArgumentError);
    expect(io.journal,isNull);
  });
}
