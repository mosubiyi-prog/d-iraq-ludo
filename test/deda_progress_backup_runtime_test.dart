import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:d_iraq_ludo/deda_progress_backup_runtime.dart';
import 'package:d_iraq_ludo/main.dart' as app;

class Driver implements DedaProgressBackupDriver {
  @override
  bool ready = true;
  @override
  bool busy = false;
  @override
  Object? principal = ('uid-a', 1);
  int calls = 0, disposals = 0;
  String? key;
  bool Function()? guard;
  Future<bool> Function()? action;
  @override
  Future<bool> backup(String accountKey, bool Function() isCurrent) {
    calls++;
    key = accountKey;
    guard = isCurrent;
    return action?.call() ?? Future.value(true);
  }
  @override
  Future<void> dispose() async { disposals++; }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DedaProgressBackupAccount account;
  late Driver driver;
  late DedaProgressBackupRuntime runtime;
  String? live;
  int factories = 0;
  void select(String? key) {
    live = key;
    account.complete(account.begin(), key);
  }
  setUp(() {
    account = DedaProgressBackupAccount();
    driver = Driver();
    live = '07700000000';
    account.complete(account.begin(), live);
    factories = 0;
    runtime = DedaProgressBackupRuntime(account: account,
      currentAccount: () => live, enabled: true,
      driverFactory: () { factories++; return driver; });
  });
  tearDown(() async { await runtime.dispose(); account.dispose(); });

  test('selection tokens invalidate A B A and reject old completion', () {
    final a = account.begin();
    final b = account.begin();
    account.complete(a, '07700000000');
    expect(account.accountKey, isNull);
    account.complete(b, '07700000001');
    final c = account.begin();
    account.complete(c, '07700000000');
    expect(c, greaterThan(a));
    expect(account.accountKey, '07700000000');
  });
  test('malformed canonical selection is rejected', () {
    expect(() => account.complete(account.epoch, '+964 77'), throwsArgumentError);
  });
  test('disabled runtime never creates driver or dispatches', () async {
    await runtime.dispose();
    runtime = DedaProgressBackupRuntime(account: account,
      currentAccount: () => live, enabled: false,
      driverFactory: () { factories++; return driver; });
    await runtime.request(); await runtime.resume(); select(live);
    expect(factories, 0); expect(driver.calls, 0);
  });
  test('null or mismatched local account cannot dispatch', () async {
    live = '07700000001'; await runtime.request();
    live = null; await runtime.request();
    expect(factories, 0);
  });
  test('server-capable driver is shared over repeated requests', () async {
    await runtime.request(); await runtime.request();
    expect(factories, 1); expect(driver.calls, 2);
    expect(driver.key, '07700000000');
    expect(runtime.status, DedaProgressBackupStatus.saved);
  });
  test('missing Firebase is rearmed only by later trigger', () async {
    await runtime.dispose();
    var available = false;
    runtime = DedaProgressBackupRuntime(account: account,
      currentAccount: () => live, enabled: true,
      driverFactory: () => available ? driver : null);
    await runtime.request(); expect(driver.calls, 0);
    available = true; await runtime.resume(); expect(driver.calls, 1);
  });
  test('not ready, admin and absent principals never dispatch', () async {
    driver.ready = false; await runtime.request();
    driver.ready = true; driver.principal = null; await runtime.request();
    expect(driver.calls, 0);
  });
  test('driver transport busy after UI timeout prevents another dispatch', () async {
    driver.busy = true; await runtime.request();
    expect(driver.calls, 0);
    driver.busy = false; await runtime.resume(); expect(driver.calls, 1);
  });
  test('rapid requests never overlap or queue', () async {
    final pending = Completer<bool>(); driver.action = () => pending.future;
    final first = runtime.request(); await runtime.request(); await runtime.request();
    expect(driver.calls, 1);
    pending.complete(true); await first;
    expect(driver.calls, 1);
  });
  test('A B A during pending operation revokes original guard', () async {
    final pending = Completer<bool>(); driver.action = () => pending.future;
    final first = runtime.request();
    final original = driver.guard!;
    select('07700000001'); select('07700000000');
    expect(original(), isFalse);
    pending.complete(true); await first;
    expect(runtime.status, isNot(DedaProgressBackupStatus.saved));
    expect(driver.calls, 1);
  });
  test('local account change without notification still revokes guard', () async {
    final pending = Completer<bool>(); driver.action = () => pending.future;
    final first = runtime.request(); live = '07700000001';
    expect(driver.guard!(), isFalse);
    pending.complete(true); await first;
    expect(runtime.status, isNot(DedaProgressBackupStatus.saved));
  });
  test('SDK identity revision A B A revokes original guard', () async {
    final pending = Completer<bool>(); driver.action = () => pending.future;
    final first = runtime.request(); driver.principal = ('uid-a', 3);
    expect(driver.guard!(), isFalse);
    pending.complete(true); await first;
    expect(runtime.status, isNot(DedaProgressBackupStatus.saved));
  });
  test('pause and resume cannot revive in-flight guard', () async {
    final pending = Completer<bool>(); driver.action = () => pending.future;
    final first = runtime.request(); final old = driver.guard!;
    runtime.pause(); await runtime.resume(); expect(old(), isFalse);
    pending.complete(true); await first;
    expect(driver.calls, 1);
    expect(runtime.status, isNot(DedaProgressBackupStatus.saved));
  });
  test('pause suppresses new work until resumed', () async {
    runtime.pause(); await runtime.request(); expect(driver.calls, 0);
    await runtime.resume(); expect(driver.calls, 1);
  });
  test('network or permission failure is blocked without automatic retry', () async {
    driver.action = () => Future.error(StateError('synthetic failure'));
    await runtime.request(); await Future<void>.delayed(Duration.zero);
    expect(driver.calls, 1); expect(runtime.status, DedaProgressBackupStatus.blocked);
  });
  test('unchanged acknowledgement is distinguished from a new upload', () async {
    driver.action = () => Future.value(false);
    await runtime.request(); expect(runtime.status, DedaProgressBackupStatus.unchanged);
  });
  test('dispose invalidates pending work and disposes shared observer once', () async {
    final pending = Completer<bool>(); driver.action = () => pending.future;
    final first = runtime.request(); await runtime.dispose();
    expect(driver.guard!(), isFalse);
    pending.complete(true); await first; await runtime.dispose();
    expect(driver.disposals, 1); await runtime.request(); expect(driver.calls, 1);
  });
  test('completed selection triggers once; logout intent triggers nothing', () async {
    select('07700000001'); await Future<void>.delayed(Duration.zero);
    expect(driver.key, '07700000001'); expect(driver.calls, 1);
    account.begin(); await Future<void>.delayed(Duration.zero);
    expect(driver.calls, 1); expect(runtime.status, DedaProgressBackupStatus.idle);
  });

  test('bound preference load invalidates before await and completes canonical account', () async {
    SharedPreferences.setMockInitialValues({'deda_logged_in_v1':true,
      'deda_user_name_v1':'Synthetic Owner','deda_phone_v1':'+964 770 000 0000',
      'deda_account_type_v1':'user'});
    final epoch = dedaProgressBackupAccount.epoch;
    final loading = app.DedaPreferences.load();
    expect(dedaProgressBackupAccount.epoch, greaterThan(epoch));
    expect(dedaProgressBackupAccount.accountKey, isNull);
    await loading;
    expect(dedaProgressBackupAccount.accountKey, '9647700000000');
  });
  test('bound saveLogin revokes previous intent and publishes canonical account after persistence', () async {
    SharedPreferences.setMockInitialValues({});
    final epoch = dedaProgressBackupAccount.epoch;
    final saving = app.DedaPreferences.saveLogin(name: 'Synthetic Owner',
      normalizedPhone: '07700000000', type: app.DedaAccountType.user);
    expect(dedaProgressBackupAccount.epoch, greaterThan(epoch));
    expect(dedaProgressBackupAccount.accountKey, isNull);
    await saving;
    expect(dedaProgressBackupAccount.accountKey, '07700000000');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('deda_logged_in_v1'), isTrue);
    await Future<void>.delayed(Duration.zero);
  });
  test('bound failed login preference read leaves previous intent revoked', () async {
    SharedPreferences.setMockInitialValues({'deda_phone_v1': 123});
    dedaProgressBackupAccount.complete(dedaProgressBackupAccount.begin(), '07700000000');
    await expectLater(app.DedaPreferences.saveLogin(name: 'Synthetic Owner',
      normalizedPhone: '07700000001', type: app.DedaAccountType.user), throwsA(isA<TypeError>()));
    expect(dedaProgressBackupAccount.accountKey, isNull);
  });
  test('bound invalid preference load stays signed out for backup', () async {
    SharedPreferences.setMockInitialValues({'deda_logged_in_v1':true,
      'deda_phone_v1':'07700000000'});
    await app.DedaPreferences.load(); expect(dedaProgressBackupAccount.accountKey, isNull);
  });
  test('bound logout revokes intent before any preference or Firebase await', () async {
    SharedPreferences.setMockInitialValues({});
    dedaProgressBackupAccount.complete(dedaProgressBackupAccount.begin(), '07700000000');
    final pending = app.DedaPreferences.logout();
    expect(dedaProgressBackupAccount.accountKey, isNull);
    await pending; expect(dedaProgressBackupAccount.accountKey, isNull);
  });
  testWidgets('enabled root dispatches at first frame and resume, pauses and disposes', (tester) async {
    await tester.pumpWidget(DedaProgressBackupHost.forTesting(currentAccount: () => live,
      runtime: runtime, child: const SizedBox()));
    await tester.pump(); expect(driver.calls, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await runtime.request(); expect(driver.calls, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(); expect(driver.calls, 2);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(); expect(driver.disposals, 1);
  });
  testWidgets('root child rebuild does not recreate driver or start another capture', (tester) async {
    Widget root(Widget child) => DedaProgressBackupHost.forTesting(
      currentAccount: () => live, runtime: runtime, child: child);
    await tester.pumpWidget(root(const SizedBox())); await tester.pump();
    await tester.pumpWidget(root(const SizedBox(width: 10))); await tester.pump();
    expect(factories, 1); expect(driver.calls, 1);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('bound root host preserves child and disabled path accesses no SDK', (tester) async {
    await tester.pumpWidget(DedaProgressBackupHost(currentAccount: () => '07700000000',
      child: const Directionality(textDirection: TextDirection.ltr, child: Text('DEDA root'))));
    await tester.pump(); expect(find.text('DEDA root'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
