import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:d_iraq_ludo/deda_legacy_progress_capture.dart';

const _account = '07700000000';
const _task = 'deda_task_points_state_v1_$_account';
const _social = 'deda_social_progress_v1_$_account';
const _diamonds = 'deda_diamonds_wallet_v1_$_account';
class _Store implements DedaLegacyProgressReadStore {
  final records = <String,String?>{
    _task:' {"version":1,"awards":{"reserve":{"points":-5000}},"completions":{"day|task":true},"ledger":[{"id":"reserve","points":-5000}]} ',
    _social:'{"coins":17,"xp":3020,"taskClaims":["day|task"]}',
    _diamonds:'{"balance":9,"viewsToday":3,"day":"2026-10-23"}',
  };
  List<String>? requested;
  Completer<void>? hold;
  Object? error;
  @override
  Future<Map<String,String?>> readStrings(List<String> keys) async {
    requested = keys;
    if (hold != null) await hold!.future;
    if (error != null) throw error!;
    return Map.of(records);
  }
}
Future<DedaLegacyProgressCapture> _read(_Store store) => DedaLegacyProgressReader(store)
  .capture(accountKey:_account,isCurrent:()=>true);
String _envelope(Object? records,{String account = _account,Object? format = 1}) =>
  jsonEncode({'format':format,'accountKey':account,'records':records});
Map<String,Object?> _emptyRecords() => {for(final p in DedaLegacyProgressPart.values) p.name:null};
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('reader captures only three canonical account keys and preserves raw debits and claims', () async {
    final store = _Store();
    final capture = await _read(store);
    expect(store.requested,[_task,_social,_diamonds]);
    expect(capture.raw[DedaLegacyProgressPart.taskPoints],store.records[_task]);
    expect(capture.raw[DedaLegacyProgressPart.socialCoinsAndXp],store.records[_social]);
    expect(capture.raw[DedaLegacyProgressPart.earnedDiamonds],store.records[_diamonds]);
    expect(capture.hasAnyLocalRecord,isTrue);
    expect(capture.hasObjectPayload(DedaLegacyProgressPart.taskPoints),isTrue);
  });
  test('same-account encode/decode roundtrip preserves every raw byte and missing marker', () async {
    final store = _Store();
    store.records[_social] = null;
    final capture = await _read(store);
    final decoded = DedaLegacyProgressCapture.decodeForAccount(capture.encode(),expectedAccountKey:_account);
    expect(decoded.raw,capture.raw);
    expect(decoded.accountKey,_account);
  });
  test('empty new phone remains explicit absence and never invents a zero record', () async {
    final store = _Store();
    store.records.updateAll((key,value)=>null);
    final capture = await _read(store);
    expect(capture.hasAnyLocalRecord,isFalse);
    expect(capture.raw.values,everyElement(isNull));
    expect(jsonDecode(capture.encode())['records'],_emptyRecords());
  });
  for(final raw in ['','{broken','[]','null','0']) {
    test('malformed or non-object legacy payload is preserved exactly: $raw', () async {
      final store = _Store(); store.records[_task] = raw;
      final capture = await _read(store);
      expect(capture.hasObjectPayload(DedaLegacyProgressPart.taskPoints),isFalse);
      expect(capture.raw[DedaLegacyProgressPart.taskPoints],raw);
      final decoded = DedaLegacyProgressCapture.decodeForAccount(capture.encode(),expectedAccountKey:_account);
      expect(decoded.raw[DedaLegacyProgressPart.taskPoints],raw);
      expect(decoded.hasAnyLocalRecord,isTrue);
    });
  }
  test('returned snapshot and requested key list are immutable copies', () async {
    final store = _Store(); final capture = await _read(store);
    expect(()=>store.requested!.clear(),throwsUnsupportedError);
    expect(()=>capture.raw.clear(),throwsUnsupportedError);
    final original = capture.raw[DedaLegacyProgressPart.earnedDiamonds];
    store.records[_diamonds] = 'changed';
    expect(capture.raw[DedaLegacyProgressPart.earnedDiamonds],original);
  });
  test('different canonical account cannot decode another account capture', () async {
    final capture = await _read(_Store());
    expect(()=>DedaLegacyProgressCapture.decodeForAccount(capture.encode(),expectedAccountKey:'07700000001'),throwsFormatException);
  });
  for(final invalid in ['','0770 0000000','../account','@DEDA-ABC123']) {
    test('invalid canonical key is rejected before preference read: $invalid', () async {
      final store = _Store();
      await expectLater(DedaLegacyProgressReader(store).capture(accountKey:invalid,isCurrent:()=>true),throwsArgumentError);
      expect(store.requested,isNull);
    });
  }
  for(final invalid in ['missing','extra']) {
    test('incomplete or cross-account preference response is rejected: $invalid', () async {
      final store = _Store();
      if(invalid == 'missing') { store.records.remove(_social); } else { store.records['other-account'] = 'private'; }
      await expectLater(_read(store),throwsFormatException);
    });
  }
  test('stale intent before capture never reads preferences', () async {
    final store = _Store();
    await expectLater(DedaLegacyProgressReader(store).capture(accountKey:_account,isCurrent:()=>false),
      throwsA(isA<DedaLegacyProgressCaptureStale>()));
    expect(store.requested,isNull);
  });
  test('A B A intent generation prevents delayed capture even with same final account', () async {
    final store = _Store()..hold = Completer<void>();
    var epoch = 1;
    final future = DedaLegacyProgressReader(store).capture(accountKey:_account,isCurrent:()=>epoch == 1);
    final outcome = expectLater(future,throwsA(isA<DedaLegacyProgressCaptureStale>()));
    epoch = 3; store.hold!.complete(); await outcome;
  });
  test('storage failure propagates and cannot create an empty successful snapshot', () async {
    final error = StateError('fixture-read-failed');
    final store = _Store()..error = error;
    await expectLater(_read(store),throwsA(same(error)));
  });
  for(final invalid in ['format','missing-record','extra-record','wrong-type','extra-top-field']) {
    test('unsupported or corrupted capture envelope is rejected: $invalid', () {
      final records = _emptyRecords();
      if(invalid == 'missing-record') records.remove('taskPoints');
      if(invalid == 'extra-record') records['credential'] = 'never-read';
      if(invalid == 'wrong-type') records['taskPoints'] = 1000;
      var encoded = _envelope(records,format:invalid == 'format' ? 2 : 1);
      if(invalid == 'extra-top-field') {
        final map = jsonDecode(encoded) as Map<String,dynamic>;
        map['unrecognized'] = true; encoded = jsonEncode(map);
      }
      expect(()=>DedaLegacyProgressCapture.decodeForAccount(encoded,expectedAccountKey:_account),throwsFormatException);
    });
  }
  test('native read adapter leaves local progress, unrelated accounts and install id unchanged', () async {
    final original = <String,Object>{
      _task:'{"ledger":[{"points":-5000}]}',_social:'{"coins":17,"xp":3020}',
      _diamonds:'{"balance":9}','deda_install_id_v1':'fixture-install',
      'deda_task_points_state_v1_07700000001':'other-account',
    };
    SharedPreferences.setMockInitialValues(original);
    final capture = await DedaLegacyProgressReader(DedaSharedPreferencesProgressReadStore())
      .capture(accountKey:_account,isCurrent:()=>true);
    expect(capture.raw[DedaLegacyProgressPart.taskPoints],original[_task]);
    final prefs = await SharedPreferences.getInstance();
    expect({for(final key in prefs.getKeys()) key:prefs.get(key)},original);
  });
  test('native missing local keys remain missing after read', () async {
    SharedPreferences.setMockInitialValues({});
    final capture = await DedaLegacyProgressReader(DedaSharedPreferencesProgressReadStore())
      .capture(accountKey:_account,isCurrent:()=>true);
    expect(capture.hasAnyLocalRecord,isFalse);
    expect((await SharedPreferences.getInstance()).getKeys(),isEmpty);
  });
  test('wrong native preference type fails without overwriting the old record', () async {
    SharedPreferences.setMockInitialValues({_task:1000});
    await expectLater(DedaLegacyProgressReader(DedaSharedPreferencesProgressReadStore())
      .capture(accountKey:_account,isCurrent:()=>true),throwsA(isA<TypeError>()));
    expect((await SharedPreferences.getInstance()).getInt(_task),1000);
  });
}
