import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:d_iraq_ludo/deda_step2_recovery_intent_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('explicit recovery gets one stable 24-byte random intent across retries',
      () async {
    SharedPreferences.setMockInitialValues(<String,Object>{});
    final first = await DedaStep2RecoveryIntentStore
        .getOrCreate('07712345678');
    final second = await DedaStep2RecoveryIntentStore
        .getOrCreate('07712345678');
    expect(first, second);
    expect(RegExp(r'^recover_[0-9a-f]{48}$').hasMatch(first), true);
    final persisted = await SharedPreferences.getInstance();
    expect(persisted.getString(
      DedaStep2RecoveryIntentStore.keyFor('07712345678')), first);
  });

  test('simultaneous recovery requests reuse one persisted intent', () async {
    SharedPreferences.setMockInitialValues(<String,Object>{});
    final calls = List<Future<String>>.generate(
      25, (_) => DedaStep2RecoveryIntentStore.getOrCreate('07712345678'));
    final results = await Future.wait(calls);
    expect(results.toSet().length, 1);
    final prefs = await SharedPreferences.getInstance();
    final key = DedaStep2RecoveryIntentStore.keyFor('07712345678');
    expect(prefs.getString(key), results.first);
    final retry = await DedaStep2RecoveryIntentStore.getOrCreate('07712345678');
    expect(retry, results.first);
  });

  test('concurrent invalid intents fail without minting replacements', () async {
    final key = DedaStep2RecoveryIntentStore.keyFor('07712345678');
    SharedPreferences.setMockInitialValues(<String,Object>{
      key: 'broken-old-intent',
    });
    final calls = List<Future<String>>.generate(
      12, (_) => DedaStep2RecoveryIntentStore.getOrCreate('07712345678'));
    final outcomes = await Future.wait(calls.map((future) async {
      try {
        await future;
        return false;
      } on StateError {
        return true;
      }
    }));
    expect(outcomes.every((failed) => failed), true);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(key), 'broken-old-intent');
  });

  test('another account cannot silently share a recovery intent', () async {
    SharedPreferences.setMockInitialValues(<String,Object>{});
    final first = await DedaStep2RecoveryIntentStore
        .getOrCreate('07712345678');
    final other = await DedaStep2RecoveryIntentStore
        .getOrCreate('07798765432');
    expect(other, isNot(first));
  });

  test('corrupt saved intent fails closed without replacement', () async {
    final key = DedaStep2RecoveryIntentStore
        .keyFor('07712345678');
    SharedPreferences.setMockInitialValues(<String,Object>{
      key:'recover-not-valid',
    });
    await expectLater(DedaStep2RecoveryIntentStore
        .getOrCreate('07712345678'),throwsStateError);
    final persisted = await SharedPreferences.getInstance();
    expect(persisted.getString(key),'recover-not-valid');
  });

  test('invalid phone does not create a local recovery intent', () async {
    SharedPreferences.setMockInitialValues(<String,Object>{});
    expect(() => DedaStep2RecoveryIntentStore.keyFor('../admin'),
        throwsFormatException);
    await expectLater(DedaStep2RecoveryIntentStore
        .getOrCreate('../admin'),throwsFormatException);
  });
}
