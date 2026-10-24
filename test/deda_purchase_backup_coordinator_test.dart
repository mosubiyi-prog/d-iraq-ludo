import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_legacy_progress_capture.dart';
import 'package:d_iraq_ludo/deda_legacy_purchase_evidence.dart';
import 'package:d_iraq_ludo/deda_progress_backup_coordinator.dart';
import 'package:d_iraq_ludo/deda_progress_backup_runtime.dart';
import 'package:d_iraq_ludo/deda_progress_evidence_store.dart';

import 'deda_progress_backup_coordinator_test.dart' as fixture;
import 'deda_progress_backup_driver_test.dart' as drivers;

const account=fixture.account,id=fixture.captureId,original='@DEDA-ABC123';
const parentPath=fixture.path,purchasePath='deda_purchase_evidence/$account/captures/$id';
class PurchaseRead implements DedaLegacyPurchaseReadStore {
  String paid='paid',inventory=' {"owned":["frame_3"]} ';
  int reads=0;
  @override
  Future<Map<String,Object?>> readValues(List<String> keys) async {
    reads++;
    return {for(final key in keys) key:key.startsWith('deda_style_inventory')?inventory:
      key.endsWith('FRAME_03')?paid:key.endsWith('FRAME_05')?'charging':null};
  }
}
class PurchaseIo extends fixture.Io {
  bool losePurchaseAck=false;
  @override
  Future<void> writeOnce(String path,Map<String,dynamic> fields,void Function() check) async {
    await super.writeOnce(path,fields,check);
    if(losePurchaseAck && path.startsWith('deda_purchase_evidence/'))throw StateError('purchase-response-lost');
  }
}
class H {
  H(){io.docs['users/old-device']!['sharePersonalId']=original;}
  final io=PurchaseIo(),source=fixture.Source(),journal=fixture.Journal(),read=PurchaseRead();
  late final archive=DedaProgressEvidenceStore(io);
  late final sidecar=DedaLegacyPurchaseEvidenceStore(archive);
  DedaProgressBackupCoordinator fresh({bool purchases=true})=>DedaProgressBackupCoordinator(
    reader:DedaLegacyProgressReader(source),archive:archive,journal:journal,
    purchaseReader:purchases?DedaLegacyPurchaseReader(read):null,purchaseArchive:purchases?sidecar:null);
  late final backup=fresh();
  Future<DedaProgressBackupIntent> prepare()=>backup.prepare(accountKey:account,captureId:id,isCurrent:()=>true);
  Future<DedaProgressBackupResult> upload({DedaProgressBackupCoordinator? via})=>
    (via??backup).uploadPending(accountKey:account,isCurrent:()=>true);
  DedaFirebaseProgressBackupDriver driver()=>DedaFirebaseProgressBackupDriver.forTesting(
    session:drivers.ObservedSession(io),coordinator:fresh(),dispose:() async {});
}
void main(){
  TestWidgetsFlutterBinding.ensureInitialized();
  test('prepare persists one v2 intent containing progress and exact paid/charging snapshot before either upload',() async {
    final h=H(),intent=await h.prepare();final encoded=h.journal.values[account]!;
    expect(jsonDecode(encoded)['format'],2);expect(intent.purchaseCapture!.journals['FRAME_03'],'paid');
    expect(intent.purchaseCapture!.journals['FRAME_05'],'charging');expect(h.io.writes,0);
    expect(DedaProgressBackupIntent.decode(encoded,account).encode(),encoded);
  });
  test('successful upload confirms both immutable archives before retiring only the combined intent',() async {
    final h=H(),intent=await h.prepare();final r=await h.upload();
    expect(r.journalCleared,isTrue);expect(r.purchaseCaptureObserved,isTrue);
    expect(r.purchaseEvidence!.capture.encode(),intent.purchaseCapture!.encode());
    expect(r.purchaseEvidence!.progressCaptureId,id);expect(h.io.writes,2);expect(h.journal.removes,1);
    expect(h.read.paid,'paid');expect(h.source.points,intent.capture.raw[DedaLegacyProgressPart.taskPoints]);
  });
  test('recreated coordinator uses original combined intent rather than recapturing a changed journal',() async {
    final h=H(),intent=await h.prepare();h.read.paid='charging';h.source.points='newer';
    final r=await h.upload(via:h.fresh());expect(r.purchaseEvidence!.capture.encode(),intent.purchaseCapture!.encode());
    expect(r.evidence.capture.encode(),intent.capture.encode());expect(h.read.reads,1);
  });
  test('lost sidecar response keeps complete intent after both commits; restart reads before any resubmission',() async {
    final h=H();await h.prepare();final pending=h.journal.values[account];h.io.losePurchaseAck=true;
    await expectLater(h.upload(),throwsStateError);expect(h.io.writes,2);expect(h.journal.values[account],pending);
    h.io.losePurchaseAck=false;final r=await h.upload(via:h.fresh());expect(r.journalCleared,isTrue);expect(h.io.writes,2);
  });
  test('failed sidecar read does not fall through to write or retire already uploaded parent intent',() async {
    final h=H();await h.prepare();final pending=h.journal.values[account];h.io.failures[purchasePath]=StateError('offline');
    await expectLater(h.upload(),throwsStateError);expect(h.io.writes,1);expect(h.journal.values[account],pending);
    h.io.failures.clear();final r=await h.upload();expect(r.journalCleared,isTrue);expect(h.io.writes,2);
  });
  test('new SDK UID/install resolves both existing old-origin archives without relabeling or writing',() async {
    final h=H();await h.prepare();h.io.losePurchaseAck=true;await expectLater(h.upload(),throwsStateError);
    h.io.losePurchaseAck=false;h.io.install='new-install';h.io.user('new-device');
    final r=await h.upload(via:h.fresh());expect(r.journalCleared,isTrue);expect(r.purchaseEvidence!.sourceUid,'old-device');
    expect(r.purchaseEvidence!.installId,'old-install');expect(h.io.writes,2);
  });
  test('new origin cannot manufacture missing old sidecar after parent committed; complete intent survives',() async {
    final h=H();await h.prepare();final pending=h.journal.values[account];h.io.failures[purchasePath]=StateError('offline');
    await expectLater(h.upload(),throwsStateError);h.io.failures.clear();h.io.install='new-install';h.io.user('new-device');
    await expectLater(h.upload(),throwsA(isA<DedaProgressBackupOriginChanged>()));expect(h.journal.values[account],pending);
    expect(h.io.docs[purchasePath],isNull);expect(h.io.writes,1);
  });
  test('missing configured sidecar transport cannot discard an older combined intent',() async {
    final h=H();await h.prepare();final pending=h.journal.values[account];
    await expectLater(h.upload(via:h.fresh(purchases:false)),throwsStateError);
    expect(h.journal.values[account],pending);expect(h.io.docs[parentPath],isNotNull);expect(h.io.docs[purchasePath],isNull);
  });
  test('old v1 intent remains byte compatible and clears without inventing a purchase snapshot',() async {
    final h=H(),legacy=h.fresh(purchases:false);
    final intent=await legacy.prepare(accountKey:account,captureId:id,isCurrent:()=>true);expect(jsonDecode(intent.encode())['format'],1);
    final r=await h.upload();expect(r.journalCleared,isTrue);expect(r.purchaseCaptureObserved,isFalse);expect(r.purchaseEvidence,isNull);
    expect(h.io.docs[purchasePath],isNull);
  });
  test('account without canonical original keeps progress while marking purchase capture unavailable, not zero',() async {
    final h=H();h.io.docs['users/old-device']!.remove('sharePersonalId');final intent=await h.prepare();
    expect(intent.purchaseCaptureObserved,isTrue);expect(intent.purchaseCapture,isNull);expect(jsonDecode(intent.encode()).containsKey('purchaseCapture'),isTrue);
    final r=await h.upload();expect(r.purchaseCaptureObserved,isTrue);expect(r.purchaseEvidence,isNull);expect(h.io.writes,1);
  });
  test('unchanged progress cannot hide journal-only or inventory-only change in real driver composition',() async {
    final h=H(),driver=h.driver();expect(await driver.backup(account,()=>true),isTrue);expect(h.io.writes,2);
    expect(await driver.backup(account,()=>true),isFalse);expect(h.io.writes,2);
    h.read.paid='charging';expect(await driver.backup(account,()=>true),isTrue);expect(h.io.writes,4);
    expect(await driver.backup(account,()=>true),isFalse);
    h.read.inventory=' {"owned":["frame_3","badge_gold"]} ';
    expect(await driver.backup(account,()=>true),isTrue);expect(h.io.writes,6);expect(h.source.points,contains('spent'));
  });
  test('driver backfills sidecar after resolving legacy intent before suppressing unchanged progress',() async {
    final h=H(),legacy=h.fresh(purchases:false);await legacy.prepare(accountKey:account,captureId:id,isCurrent:()=>true);
    final driver=h.driver();expect(await driver.backup(account,()=>true),isTrue);expect(h.io.writes,1);
    expect(await driver.backup(account,()=>true),isTrue);expect(h.io.writes,3);
    expect(await driver.backup(account,()=>true),isFalse);expect(h.io.writes,3);
  });
  test('missing canonical ID becoming available later is observed even with unchanged balance',() async {
    final h=H();h.io.docs['users/old-device']!.remove('sharePersonalId');final driver=h.driver();
    expect(await driver.backup(account,()=>true),isTrue);expect(h.io.writes,1);
    expect(await driver.backup(account,()=>true),isFalse);
    h.io.docs['users/old-device']!['sharePersonalId']=original;
    expect(await driver.backup(account,()=>true),isTrue);expect(h.io.writes,3);
  });
  test('malformed or cross-account purchase payload in combined journal is rejected without fallback',() async {
    final h=H(),intent=await h.prepare();final map=jsonDecode(intent.encode()) as Map<String,dynamic>;
    map['purchaseCapture']=7;expect(()=>DedaProgressBackupIntent.decode(jsonEncode(map),account),throwsFormatException);
    map['purchaseCapture']=jsonEncode({'format':1,'accountKey':'07700000001','originalId':original,'inventory':null,
      'frameJournals':{for(final frame in dedaLegacyPurchaseFrames) frame:null}});
    expect(()=>DedaProgressBackupIntent.decode(jsonEncode(map),account),throwsFormatException);
  });
}
