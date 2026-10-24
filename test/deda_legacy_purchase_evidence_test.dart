import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:d_iraq_ludo/deda_legacy_purchase_evidence.dart';
import 'package:d_iraq_ludo/deda_progress_evidence_store.dart';
import 'package:d_iraq_ludo/deda_owner_session_firebase_port.dart';
import 'package:d_iraq_ludo/deda_session_flow_prototype.dart';
import 'package:d_iraq_ludo/deda_session_transition_gate.dart';

const account = '07700000000', original = '@DEDA-ABC123';
const parentId = 'progress_capture_origin_00001', captureId = 'purchase_capture_origin_00001';
const purchasePath = 'deda_purchase_evidence/$account/captures/$captureId';
String journal(String frame) => 'deda_native_frame_pending_v1_${original}_$frame';
const inventoryKey = 'deda_style_inventory_v1_$account';
class _Read implements DedaLegacyPurchaseReadStore {
  final values = <String, Object?>{inventoryKey: ' {"owned":["frame_3"],"activeBadges":[]} ',
    for (final frame in dedaLegacyPurchaseFrames) journal(frame): null};
  List<String>? keys;
  Completer<void>? hold;
  @override
  Future<Map<String, Object?>> readValues(List<String> keys) async {
    this.keys = keys;
    if (hold != null) await hold!.future;
    return Map.of(values);
  }
}
class _Io implements DedaProgressEvidenceIo {
  _Io() { user('old-device'); }
  @override
  bool ready = true;
  @override
  DedaFlowSdkUser? currentUser;
  int epoch = 0, writes = 0;
  String install = 'old-install';
  final docs = <String, Map<String, dynamic>>{};
  final overrides = <String, DedaOwnerServerDocument>{};
  final holds = <String, Completer<void>>{};
  final failures = <String, Object>{};
  final visits = <String>[];
  void user(String uid, {DedaSessionAuthKind kind = DedaSessionAuthKind.anonymous}) {
    currentUser = DedaFlowSdkUser(uid, kind, ++epoch);
    docs['deda_sessions/$uid'] = {'uid': uid, 'accountKey': account, 'installId': install};
    docs['users/$uid'] = {'accountKey': account, 'sharePersonalId': original};
    docs['deda_share_ids/$original'] = {'publicId': original, 'kind': 'personal', 'active': true, 'ownerUid': 'old-device'};
    docs.putIfAbsent('deda_progress_evidence/$account/captures/$parentId', () => {
      'format': 1, 'kind': 'legacy-local-evidence', 'accountKey': account,
      'sourceUid': 'old-device', 'installId': 'old-install', 'captureId': parentId,
      'records': {'taskPoints': null, 'socialCoinsAndXp': null, 'earnedDiamonds': null},
      'createdAt': Timestamp.fromMillisecondsSinceEpoch(1000)});
  }
  Future<void> visit(String name) async {
    visits.add(name);
    if (holds[name] != null) await holds[name]!.future;
    if (failures[name] != null) throw failures[name]!;
  }
  @override
  Future<String> installId(void Function() check) async { await visit('install'); check(); return install; }
  @override
  Future<DedaOwnerServerDocument> readServer(String path) async {
    await visit(path); return overrides[path] ?? DedaOwnerServerDocument(docs[path]);
  }
  @override
  Future<List<DedaListedProgressEvidence>> listServer(String path, {required int limit}) async => throw UnimplementedError();
  @override
  Object serverTimestamp() => Timestamp.fromMillisecondsSinceEpoch(2000);
  @override
  Future<void> writeOnce(String path, Map<String, dynamic> fields, void Function() check) async {
    check(); await visit('transaction.read'); check();
    final old = docs[path];
    if (old != null) {
      for (final key in ['format', 'kind', 'accountKey', 'sourceUid', 'installId', 'captureId']) {
        if (old[key] != fields[key]) throw const DedaProgressEvidenceConflict();
      }
      if (jsonEncode(old['records']) != jsonEncode(fields['records'])) throw const DedaProgressEvidenceConflict();
      return;
    }
    check(); await visit('transaction.dispatch'); check(); docs[path] = Map.of(fields); writes++;
  }
}
Future<DedaLegacyPurchaseCapture> capture(_Read read, {bool Function()? current}) =>
  DedaLegacyPurchaseReader(read).capture(accountKey: account, originalId: original, isCurrent: current ?? () => true);
Future<DedaStoredPurchaseEvidence> save(_Io io, DedaLegacyPurchaseCapture data, {bool Function()? current}) =>
  DedaLegacyPurchaseEvidenceStore(DedaProgressEvidenceStore(io)).save(captureId: captureId,
    progressCaptureId: parentId, capture: data, isCurrent: current ?? () => true);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('reads exactly existing 13 original frame journals and account inventory, preserving raw strings', () async {
    final read = _Read(); read.values[journal('FRAME_03')] = 'paid'; read.values[journal('FRAME_05')] = 'charging';
    final data = await capture(read);
    expect(read.keys, [inventoryKey, for (final frame in dedaLegacyPurchaseFrames) journal(frame)]);
    expect(data.inventory, read.values[inventoryKey]); expect(data.journals['FRAME_03'], 'paid'); expect(data.journals['FRAME_05'], 'charging');
    expect(data.journals['FRAME_06'], isNull);
    expect(DedaLegacyPurchaseCapture.decode(data.encode(), accountKey: account, originalId: original).encode(), data.encode());
  });
  for (final value in [true, 123, 1.25, <String>['paid'], '', ' PAID ', 'future-state', '{broken']) {
    test('unexpected native value retained without converting to paid/absent: $value', () async {
      final read = _Read(); read.values[journal('FRAME_03')] = value; read.values[inventoryKey] = value;
      final data = await capture(read); expect(data.inventory, value); expect(data.journals['FRAME_03'], value);
      expect(DedaLegacyPurchaseCapture.decode(data.encode(), accountKey: account, originalId: original).journals['FRAME_03'], value);
    });
  }
  test('empty new phone contains explicit absence and no fabricated zero or ownership', () async {
    final read = _Read(); read.values.updateAll((key, value) => null); final data = await capture(read);
    expect(data.inventory, isNull); expect(data.journals.values, everyElement(isNull));
  });
  test('real preferences adapter reads typed values and leaves all preferences unchanged', () async {
    final values = {inventoryKey: ' {broken ', journal('FRAME_03'): 'paid', journal('FRAME_05'): true, 'unrelated': 998965};
    SharedPreferences.setMockInitialValues(values); final prefs = await SharedPreferences.getInstance();
    final before = {for (final key in prefs.getKeys()) key: prefs.get(key)};
    final data = await DedaLegacyPurchaseReader(DedaSharedPreferencesPurchaseReadStore())
      .capture(accountKey: account, originalId: original, isCurrent: () => true);
    expect(data.journals['FRAME_05'], true);
    expect({for (final key in prefs.getKeys()) key: prefs.get(key)}, before);
  });
  test('incomplete or unrelated preference read rejected without guessing missing journals', () async {
    final read = _Read(); read.values.remove(journal('FRAME_03'));
    await expectLater(capture(read), throwsFormatException);
    read.values['unrelated'] = 'paid'; await expectLater(capture(read), throwsFormatException);
  });
  test('account intent A-B-A change while read waits rejects old capture', () async {
    final read = _Read()..hold = Completer<void>(); var epoch = 1;
    final future = capture(read, current: () => epoch == 1); epoch = 3; read.hold!.complete();
    await expectLater(future, throwsA(isA<DedaStaleSessionTransition>()));
  });
  test('unsupported value and oversized evidence fail without modifying original preferences', () async {
    final read = _Read(); read.values[inventoryKey] = <String, int>{'not-native': 1};
    await expectLater(capture(read), throwsFormatException);
    read.values[inventoryKey] = 'ع' * 100001; await expectLater(capture(read), throwsFormatException);
  });
  test('snapshot cannot be reassigned to a different account or premium alias', () async {
    final data = await capture(_Read());
    expect(() => DedaLegacyPurchaseCapture.decode(data.encode(), accountKey: '07700000001', originalId: original), throwsFormatException);
    expect(() => DedaLegacyPurchaseCapture.decode(data.encode(), accountKey: account, originalId: '@DEDA-PREMIUM'), throwsFormatException);
  });
  test('save creates only separate purchase archive and retains parent evidence, raw journals and original origin', () async {
    final read = _Read(); read.values[journal('FRAME_03')] = 'paid'; final data = await capture(read), io = _Io();
    final parent = Map.of(io.docs['deda_progress_evidence/$account/captures/$parentId']!);
    final saved = await save(io, data); expect(saved.sourceUid, 'old-device'); expect(saved.installId, 'old-install');
    expect(saved.progressCaptureId, parentId); expect(saved.capture.encode(), data.encode()); expect(io.writes, 1);
    expect(io.docs['deda_progress_evidence/$account/captures/$parentId'], parent);
    expect(read.values[journal('FRAME_03')], 'paid');
  });
  test('same immutable capture retries without changing timestamp or creating another archive', () async {
    final io = _Io(), data = await capture(_Read()); await save(io, data); final first = Map.of(io.docs[purchasePath]!);
    await save(io, data); expect(io.writes, 1); expect(io.docs[purchasePath], first);
  });
  test('same capture ID with changed payload conflicts rather than overwriting original journal evidence', () async {
    final io = _Io(), read = _Read(); final first = await capture(read); await save(io, first);
    read.values[journal('FRAME_03')] = 'paid'; await expectLater(save(io, await capture(read)), throwsA(isA<DedaProgressEvidenceConflict>()));
    expect(io.writes, 1); expect(io.docs[purchasePath]!['records']['localSnapshot'], first.encode());
  });
  test('new device can read original archive without claiming old UID or install as its own', () async {
    final io = _Io(); await save(io, await capture(_Read())); io.install = 'new-install'; io.user('new-device');
    final saved = await DedaLegacyPurchaseEvidenceStore(DedaProgressEvidenceStore(io))
      .read(accountKey: account, captureId: captureId, isCurrent: () => true);
    expect(saved.sourceUid, 'old-device'); expect(saved.installId, 'old-install');
    await expectLater(save(io, await capture(_Read())), throwsA(isA<DedaSessionProofRejected>())); expect(io.writes, 1);
  });
  for (final bad in ['foreign-parent', 'foreign-install', 'wrong-original', 'missing-parent']) {
    test('save rejects $bad before any purchase archive write', () async {
      final io = _Io(), data = await capture(_Read()); final parent = 'deda_progress_evidence/$account/captures/$parentId';
      if (bad == 'foreign-parent') io.docs[parent]!['sourceUid'] = 'other-device';
      if (bad == 'foreign-install') io.docs[parent]!['installId'] = 'other-install';
      if (bad == 'wrong-original') io.docs['users/old-device']!['sharePersonalId'] = '@DEDA-OTHER1';
      if (bad == 'missing-parent') io.docs.remove(parent);
      await expectLater(save(io, data), throwsA(anyOf(isA<DedaSessionProofRejected>(), isA<DedaProgressEvidenceMissing>()))); expect(io.writes, 0);
    });
  }
  for (final mode in ['cache', 'pending']) {
    test('rejects $mode user proof rather than treating cache as owner authority', () async {
      final io = _Io(); io.overrides['users/old-device'] = DedaOwnerServerDocument(io.docs['users/old-device'], fromCache: mode == 'cache', pendingWrites: mode == 'pending');
      await expectLater(save(io, await capture(_Read())), throwsA(isA<DedaSessionProofRejected>())); expect(io.writes, 0);
    });
  }
  test('SDK A-B-A epoch change while transaction waits prevents dispatch', () async {
    final io = _Io(); final hold = Completer<void>(); io.holds['transaction.read'] = hold;
    final future = save(io, await capture(_Read()));
    while (!io.visits.contains('transaction.read')) { await Future<void>.delayed(Duration.zero); }
    io.user('other-device'); io.user('old-device'); hold.complete();
    await expectLater(future, throwsA(isA<DedaStaleSessionTransition>())); expect(io.writes, 0);
  });
  test('network failure does not create a new capture or clear any original paid journal', () async {
    final io = _Io(); io.failures['transaction.read'] = StateError('offline'); final read = _Read(); read.values[journal('FRAME_03')] = 'paid';
    await expectLater(save(io, await capture(read)), throwsStateError); expect(io.writes, 0); expect(read.values[journal('FRAME_03')], 'paid');
  });
  test('password admin session is rejected by passive evidence transport without auth mutation', () async {
    final io = _Io(); io.user('manager', kind: DedaSessionAuthKind.authenticated);
    await expectLater(save(io, await capture(_Read())), throwsA(isA<DedaStaleSessionTransition>())); expect(io.currentUser!.uid, 'manager'); expect(io.writes, 0);
  });
}
