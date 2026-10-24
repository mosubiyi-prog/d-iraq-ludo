import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
