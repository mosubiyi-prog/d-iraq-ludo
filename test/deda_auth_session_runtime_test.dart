import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:d_iraq_ludo/deda_auth_session_runtime.dart';
import 'package:d_iraq_ludo/deda_session_transition_gate.dart';
import 'package:d_iraq_ludo/deda_backend.dart';
import 'package:d_iraq_ludo/deda_pin_auth.dart';
import 'package:d_iraq_ludo/main.dart' as app;

const explicit = DedaSessionTransitionOrigin.userAction;
class Harness {
  Harness({Duration timeout = const Duration(seconds: 12)}) {
    runtime = DedaAuthSessionController(current: () => live, timeout: timeout);
  }
  DedaAuthSnapshot live = const DedaAuthSnapshot('owner', DedaSessionAuthKind.anonymous, 1);
  late final DedaAuthSessionController runtime;
  Future<T> run<T>(Future<T> Function() action, {bool Function()? isCurrent}) => runtime.run(
    kind: DedaSessionTransitionKind.ownerLogin, origin: explicit, action: action, isCurrent: isCurrent);
  void change(String? uid, DedaSessionAuthKind kind) => live = DedaAuthSnapshot(uid,kind,live.epoch+1);
}
Future<void> flush() => Future<void>.delayed(Duration.zero);

class FailingPreferencesStore extends InMemorySharedPreferencesStore {
  FailingPreferencesStore(Map<String,Object> values):super.withData(values);
  String? failKey;
  int failAt=1,calls=0;
  bool throwFailure=false;
  @override
  Future<bool> setValue(String type,String key,Object value) async {
    if(key==failKey && ++calls==failAt) {
      if(throwFailure) throw StateError('fixture-storage-failure');
      return false;
    }
    return super.setValue(type,key,value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('one logical owner flow delegates helpers without nested gate entry', () async {
    final h=Harness(); final events=<String>[];
    await h.run(() async {
      events.add('owner');
      await h.runtime.run(kind:DedaSessionTransitionKind.sessionInspection,origin:explicit,
        action:() async { await h.runtime.wait(() async { events.add('profile'); }); });
      events.add('local-selection');
    });
    expect(events,['owner','profile','local-selection']);
    expect(h.runtime.gate.diagnostics['started'],1);
    expect(h.runtime.gate.diagnostics['succeeded'],1);
  });
  test('admin cannot overtake an unfinished owner flow after SDK login completed', () async {
    final h=Harness(); final hold=Completer<void>(); var entered=false;
    final first=h.run(() async { await h.runtime.wait(()=>hold.future); });
    await flush();
    await expectLater(h.runtime.run(kind:DedaSessionTransitionKind.adminLogin,origin:explicit,
      action:() async { entered=true; }),throwsA(isA<DedaSessionTransitionBusy>()));
    expect(entered,isFalse); hold.complete(); await first;
  });
  for(final phase in ['SDK','intent','ABA','signed-out-ABA']) {
    test('late $phase proof cannot dispatch a following write', () async {
      final h=Harness(); final hold=Completer<void>(); var current=true,wrote=false;
      if(phase=='signed-out-ABA') h.change(null,DedaSessionAuthKind.none);
      final result=h.run(() async {
        await h.runtime.wait(()=>hold.future);
        await h.runtime.wait(() async { wrote=true; });
      },isCurrent:()=>current);
      final outcome=expectLater(result,throwsA(isA<DedaStaleSessionTransition>()));
      await flush();
      if(phase=='intent') { current=false; }
      else if(phase=='ABA') { h.change('B',DedaSessionAuthKind.authenticated);h.change('owner',DedaSessionAuthKind.anonymous); }
      else if(phase=='signed-out-ABA') { h.change('B',DedaSessionAuthKind.anonymous);h.change(null,DedaSessionAuthKind.none); }
      else { h.change('new-admin',DedaSessionAuthKind.authenticated); }
      hold.complete(); await outcome; expect(wrote,isFalse);
    });
  }
  test('timeout retains the original SDK future and blocks retries until it settles', () async {
    final h=Harness(timeout:const Duration(milliseconds:30));
    final hold=Completer<String>(); var writes=0;
    final result=h.run(() async {
      await h.runtime.transition(kind:DedaSessionTransitionKind.ownerLogin,
        action:()=>hold.future,accepts:(value,live)=>value==live.uid);
      await h.runtime.wait(() async { writes++; });
    });
    await expectLater(result,throwsA(isA<TimeoutException>()));
    await expectLater(h.run(() async {}),throwsA(isA<DedaSessionTransitionBusy>()));
    h.change('later',DedaSessionAuthKind.anonymous);hold.complete('later');await flush();
    expect(writes,0);expect(h.runtime.gate.diagnostics['inFlight'],0);
    expect(h.runtime.gate.diagnostics['succeeded'],0);
  });
  test('expected SDK login identity is adopted then bound through following work', () async {
    final h=Harness();
    await h.run(() async {
      await h.runtime.transition<String>(kind:DedaSessionTransitionKind.adminLogin,
        action:() async { h.change('admin',DedaSessionAuthKind.authenticated);return 'admin'; },
        accepts:(uid,live)=>uid==live.uid);
      await h.runtime.wait(() async { expect(h.live.uid,'admin'); });
    });
    expect(h.runtime.gate.diagnostics['succeeded'],1);
  });
  test('SDK result for a different live identity is rejected without cleanup', () async {
    final h=Harness();var cleanup=false;
    await expectLater(h.run(() async {
      await h.runtime.transition<String>(kind:DedaSessionTransitionKind.adminLogin,
        action:() async { h.change('newer',DedaSessionAuthKind.authenticated);return 'old'; },
        accepts:(uid,live)=>uid==live.uid);
      cleanup=true;
    }),throwsA(isA<DedaStaleSessionTransition>()));
    expect(cleanup,isFalse);expect(h.live.uid,'newer');
  });
  test('active section can inspect admin gateway but cannot replace or log out admin', () async {
    final h=Harness();h.change('admin',DedaSessionAuthKind.authenticated);var called=false;
    await expectLater(h.runtime.run(kind:DedaSessionTransitionKind.sessionInspection,
      origin:DedaSessionTransitionOrigin.activeSection,action:() async {
        await h.runtime.transition<void>(kind:DedaSessionTransitionKind.logout,
          action:() async { called=true; },accepts:(_,live)=>true);
      }),throwsA(isA<DedaSessionTransitionDenied>()));
    expect(called,isFalse);expect(h.live.uid,'admin');
  });
  test('background mutation is rejected before work', () async {
    final h=Harness();var called=false;
    await expectLater(h.runtime.run(kind:DedaSessionTransitionKind.sessionInspection,
      origin:DedaSessionTransitionOrigin.background,action:() async {called=true;}),
      throwsA(isA<DedaSessionTransitionDenied>()));
    expect(called,isFalse);
  });
  test('SDK mutation outside the shared lane is refused', () async {
    final h=Harness();var called=false;
    await expectLater(h.runtime.transition<void>(kind:DedaSessionTransitionKind.logout,
      action:() async {called=true;},accepts:(_,live)=>true),throwsStateError);
    expect(called,isFalse);
  });
  test('expired parent context cannot be reused by late delegated helpers', () async {
    final h=Harness();late Future<void> Function() lateHelper;
    await h.run(() async {
      final zone=Zone.current;
      lateHelper=()=>zone.run(()=>h.runtime.run<void>(kind:DedaSessionTransitionKind.logout,
        origin:explicit,action:() async {fail('late logout dispatched');}));
    });
    await expectLater(lateHelper(),throwsA(isA<DedaStaleSessionTransition>()));
  });
  test('password dialog snapshot rejects changed identity without holding a lane', () async {
    final h=Harness();final before=h.live;
    await h.run(() async {});
    expect(h.runtime.gate.diagnostics['inFlight'],0);
    h.change('other-admin',DedaSessionAuthKind.authenticated);
    expect(()=>h.runtime.checkSnapshot(before),throwsA(isA<DedaStaleSessionTransition>()));
  });
  test('original transport error is observed once without retry', () async {
    final h=Harness();var calls=0;final error=StateError('fixture');
    await expectLater(h.run(()=>h.runtime.wait<void>(() async {calls++;throw error;})),throwsA(same(error)));
    expect(calls,1);expect(h.runtime.gate.diagnostics['inFlight'],0);
  });

  group('personal logout confirmation uses the original account', () {
    const first='07700000010',second='07700000011';
    Future<void> select(String phone) async {
      final prefs=await SharedPreferences.getInstance();
      await prefs.setString('deda_phone_v1',phone);
      await prefs.setString('deda_account_phone_v1',phone);
      await prefs.setString('deda_user_name_v1','Fixture $phone');
      await prefs.setString('deda_account_type_v1','user');
      await prefs.setBool('deda_logged_in_v1',true);
      await app.DedaPreferences.load();
    }
    Future<void> unchanged(String phone) async {
      final prefs=await SharedPreferences.getInstance();
      expect(app.DedaPreferences.phone,phone);
      expect(app.DedaPreferences.isLoggedIn,isTrue);
      expect(prefs.getString('deda_phone_v1'),phone);
      expect(prefs.getBool('deda_logged_in_v1'),isTrue);
      expect(prefs.getString('deda_task_points_state_v1_$first'),'keep raw points');
      expect(prefs.getString('deda_diamonds_wallet_v1_$second'),'keep raw diamonds');
    }
    setUp(() async {
      SharedPreferences.setMockInitialValues({
        'deda_language_v1':'en',
        'deda_task_points_state_v1_$first':'keep raw points',
        'deda_diamonds_wallet_v1_$second':'keep raw diamonds',
      });
      await select(first);
      app.DedaLanguageState.current=app.DedaLanguage.en;
    });
    for(final path in ['different account','A-B-A','same account reloaded']) {
      test('$path invalidates the open confirmation before any cleanup', () async {
        final intent=app.DedaPersonalLogoutIntent();
        if(path!='same account reloaded') await select(second);
        if(path!='different account') await select(first);
        await expectLater(intent.commit(isCurrent:()=>true),
          throwsA(isA<DedaStaleSessionTransition>()));
        await unchanged(path=='different account'?second:first);
      },skip:!dedaAuthSessionRuntimeEnabled);
    }
    test('an unmounted confirmation cannot dispatch logout', () async {
      final intent=app.DedaPersonalLogoutIntent();
      await expectLater(intent.commit(isCurrent:()=>false),
        throwsA(isA<DedaStaleSessionTransition>()));
      await unchanged(first);
    },skip:!dedaAuthSessionRuntimeEnabled);
    test('confirmation does not hold the lane and busy admission does not clean preferences', () async {
      final intent=app.DedaPersonalLogoutIntent();
      expect(DedaAuthRuntime.controller.gate.diagnostics['inFlight'],0);
      final hold=Completer<void>();
      final active=DedaAuthRuntime.run<void>(kind:DedaSessionTransitionKind.ownerLogin,
        action:()=>hold.future);
      await flush();
      try {
        await expectLater(intent.commit(isCurrent:()=>true),
          throwsA(isA<DedaSessionTransitionBusy>()));
        await unchanged(first);
      } finally {hold.complete();await active;}
    },skip:!dedaAuthSessionRuntimeEnabled);
    test('unchanged confirmation logs out once and preserves all account progress', () async {
      final firstIntent=app.DedaPersonalLogoutIntent();
      final duplicate=app.DedaPersonalLogoutIntent();
      await firstIntent.commit(isCurrent:()=>true);
      final prefs=await SharedPreferences.getInstance();
      expect(app.DedaPreferences.isLoggedIn,isFalse);
      expect(app.DedaPreferences.phone,isEmpty);
      expect(prefs.getBool('deda_logged_in_v1'),isFalse);
      expect(prefs.getString('deda_phone_v1'),isNull);
      expect(prefs.getString('deda_task_points_state_v1_$first'),'keep raw points');
      expect(prefs.getString('deda_diamonds_wallet_v1_$second'),'keep raw diamonds');
      await expectLater(duplicate.commit(isCurrent:()=>true),
        throwsA(isA<DedaStaleSessionTransition>()));
    },skip:!dedaAuthSessionRuntimeEnabled);
    testWidgets('Settings confirmation rejects a changed account and stays on Settings', (tester) async {
      await tester.pumpWidget(const MaterialApp(home:app.DedaSettingsPage()));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Sign out'));
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog),findsOneWidget);
      await select(second);
      await tester.tap(find.widgetWithText(FilledButton,'Sign out'));
      await tester.pumpAndSettle();
      await unchanged(second);
      expect(find.byType(app.DedaSettingsPage),findsOneWidget);
      expect(find.byType(app.LoginPage),findsNothing);
      expect(find.text('The account changed during confirmation. Open sign out again.'),findsOneWidget);
      expect(tester.takeException(),isNull);
    },skip:!dedaAuthSessionRuntimeEnabled);
    testWidgets('cancelling the Settings confirmation leaves the account selected', (tester) async {
      await tester.pumpWidget(const MaterialApp(home:app.DedaSettingsPage()));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Sign out'));
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton,'Cancel'));
      await tester.pumpAndSettle();
      await unchanged(first);
      expect(find.byType(AlertDialog),findsNothing);
      expect(tester.takeException(),isNull);
    },skip:!dedaAuthSessionRuntimeEnabled);
  });

  group('local account commit failures', () {
    const first='07700000010',second='07700000011';
    late FailingPreferencesStore store;
    setUp(() async {
      final initial=<String,Object>{
        'deda_logged_in_v1':true,'deda_user_name_v1':'First owner',
        'deda_phone_v1':first,'deda_account_phone_v1':first,
        'deda_account_type_v1':'user',
        'deda_task_points_state_v1_$first':'keep raw points',
        'deda_diamonds_wallet_v1_$second':'keep raw diamonds',
      };
      SharedPreferences.setMockInitialValues(initial);
      store=FailingPreferencesStore(initial.map((key,value)=>MapEntry('flutter.$key',value)));
      SharedPreferencesStorePlatform.instance=store;
      await app.DedaPreferences.load();
    });
    Future<void> preservesProgress() async {
      final disk=await store.getAll();
      expect(disk['flutter.deda_task_points_state_v1_$first'],'keep raw points');
      expect(disk['flutter.deda_diamonds_wallet_v1_$second'],'keep raw diamonds');
    }
    test('successful local commit publishes all selected identity fields together', () async {
      await app.DedaPreferences.saveLogin(name:'Second owner',normalizedPhone:second,
        type:app.DedaAccountType.placeOwner);
      expect(app.DedaPreferences.isLoggedIn,isTrue);
      expect(app.DedaPreferences.phone,second);
      expect(app.DedaPreferences.accountPhone,second);
      expect(app.DedaPreferences.userName,'Second owner');
      expect(app.DedaPreferences.accountType,app.DedaAccountType.placeOwner);
      final disk=await store.getAll();
      expect(disk['flutter.deda_logged_in_v1'],isTrue);
      expect(disk['flutter.deda_phone_v1'],second);
      expect(disk['flutter.deda_user_name_v1'],'Second owner');
      expect(disk['flutter.deda_account_type_v1'],'placeOwner');
      await preservesProgress();await flush();
    },skip:!dedaAuthSessionRuntimeEnabled);
    for(final key in ['deda_user_name_v1','deda_phone_v1','deda_account_phone_v1','deda_account_type_v1']) {
      test('failed $key does not publish a new account or leave a committed login', () async {
        store.failKey='flutter.$key';
        await expectLater(app.DedaPreferences.saveLogin(name:'Second owner',normalizedPhone:second,
          type:app.DedaAccountType.user),throwsStateError);
        expect(app.DedaPreferences.isLoggedIn,isFalse);
        expect(app.DedaPreferences.phone,first);
        expect(app.DedaPreferences.userName,'First owner');
        await preservesProgress();
        final prefs=await SharedPreferences.getInstance();
        await prefs.reload();await app.DedaPreferences.load();
        expect(app.DedaPreferences.isLoggedIn,isFalse);
        expect((await store.getAll())['flutter.deda_logged_in_v1'],isFalse);
      },skip:!dedaAuthSessionRuntimeEnabled);
    }
    test('failure to close the previous login marker blocks publication and preserves previous identity', () async {
      store.failKey='flutter.deda_logged_in_v1';
      await expectLater(app.DedaPreferences.saveLogin(name:'Second owner',normalizedPhone:second,
        type:app.DedaAccountType.user),throwsStateError);
      expect(app.DedaPreferences.isLoggedIn,isFalse);
      expect(app.DedaPreferences.phone,first);
      expect((await store.getAll())['flutter.deda_phone_v1'],first);
      await preservesProgress();
    },skip:!dedaAuthSessionRuntimeEnabled);
    test('failure of the final login marker stays uncommitted after native reload', () async {
      store.failKey='flutter.deda_logged_in_v1';store.failAt=2;
      await expectLater(app.DedaPreferences.saveLogin(name:'Second owner',normalizedPhone:second,
        type:app.DedaAccountType.user),throwsStateError);
      expect(app.DedaPreferences.isLoggedIn,isFalse);
      expect(app.DedaPreferences.phone,first);
      final prefs=await SharedPreferences.getInstance();
      await prefs.reload();await app.DedaPreferences.load();
      expect(app.DedaPreferences.isLoggedIn,isFalse);
      await preservesProgress();
    },skip:!dedaAuthSessionRuntimeEnabled);
    test('a native identity write exception does not publish the new identity', () async {
      store.failKey='flutter.deda_phone_v1';store.throwFailure=true;
      await expectLater(app.DedaPreferences.saveLogin(name:'Second owner',normalizedPhone:second,
        type:app.DedaAccountType.user),throwsStateError);
      expect(app.DedaPreferences.isLoggedIn,isFalse);
      expect(app.DedaPreferences.phone,first);
      expect((await store.getAll())['flutter.deda_logged_in_v1'],isFalse);
      await preservesProgress();
    },skip:!dedaAuthSessionRuntimeEnabled);
    test('failed logout marker does not clear the selected identity', () async {
      store.failKey='flutter.deda_logged_in_v1';
      await expectLater(app.DedaPreferences.logout(),throwsStateError);
      expect(app.DedaPreferences.isLoggedIn,isTrue);
      expect(app.DedaPreferences.phone,first);
      expect(app.DedaPreferences.userName,'First owner');
      final disk=await store.getAll();
      expect(disk['flutter.deda_logged_in_v1'],isTrue);
      expect(disk['flutter.deda_phone_v1'],first);
      await preservesProgress();
    },skip:!dedaAuthSessionRuntimeEnabled);
  });

  // These checks invoke the actual transformed 100380 entrypoints, not ports.
  group('bound original source entrypoints', () {
    setUp(() { SharedPreferences.setMockInitialValues({'sentinel':'keep'}); });
    final calls=<String,Future<void> Function()>{
      'owner PIN':() async { await DedaPinAuth.signIn(phone:'07700000000',pin:'123456'); },
      'owner create':() async { await DedaPinAuth.createAccount(phone:'07700000000',fullName:'Fixture',pin:'123456'); },
      'trusted restore':() async { await DedaPinAuth.restoreTrustedSessionForAccountKey('07700000000'); },
      'account lookup':() async { await DedaPinAuth.accountExists('07700000000'); },
      'recovery':() async { await DedaPinAuth.requestRecovery(phone:'07700000000',fullName:'Fixture'); },
      'admin login':() async { await DedaBackend.signInAdmin(email:'fixture@example.invalid',password:'fixture'); },
      'invitation':() async { await DedaBackend.activateAdminInvitation(inviteId:'fixture',activationCode:'12345678',email:'fixture@example.invalid',password:'fixturepass'); },
      'admin password':()=>DedaBackend.changeCurrentAdminPassword('fixturepass'),
      'admin logout':DedaBackend.signOutAdmin,
      'Firebase logout':DedaPinAuth.signOutFirebase,
      'preferences logout':app.DedaPreferences.logout,
      'preferences load':app.DedaPreferences.load,
      'preferences selection':()=>app.DedaPreferences.saveLogin(name:'Fixture',normalizedPhone:'07700000000',type:app.DedaAccountType.user),
      'phone gateway match':() async { await DedaBackend.currentAdminSessionMatchesDedaEntry(phone:'07700000000'); },
    };
    for(final entry in calls.entries) {
      test('${entry.key} cannot bypass an active complete-flow lane', () async {
        final hold=Completer<void>();
        final active=DedaAuthRuntime.run<void>(kind:DedaSessionTransitionKind.ownerLogin,action:()=>hold.future);
        await flush();
        try {
          await expectLater(entry.value(),throwsA(isA<DedaSessionTransitionBusy>()));
          final prefs=await SharedPreferences.getInstance();expect(prefs.getKeys(),{'sentinel'});
          expect(prefs.getString('sentinel'),'keep');
        } finally {hold.complete();await active;}
      },skip:!dedaAuthSessionRuntimeEnabled);
    }
  });
}
