import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import '../lib/deda_section_operation_context.dart';
import '../lib/deda_auth_session_runtime.dart';
import '../lib/deda_session_transition_gate.dart';

class ScopeHarness {
  final owner = Object();
  String account = 'A';
  int epoch = 0;
  bool mounted = true;
  Object principal = ('uid-a', 0);
  Future<T> run<T>(Future<T> Function() action) {
    final expectedAccount = account;
    final expectedEpoch = epoch;
    return DedaSectionOperationContext.run(owner: owner,
      isCurrent: () => mounted && account == expectedAccount && epoch == expectedEpoch,
      principal: () => principal, action: action);
  }
  Future<void> event(Future<void> Function() action) {
    final expectedAccount = account;
    final expectedEpoch = epoch;
    return DedaSectionOperationContext.runVoid(owner: owner,
      isCurrent: () => mounted && account == expectedAccount && epoch == expectedEpoch,
      principal: () => principal, action: action);
  }
}

void main() {
  test('ordinary awaits retain their exact result and do not retry', () async {
    final h=ScopeHarness(); var calls=0;
    expect(await h.run(() => DedaSectionOperationContext.wait(() async {
      calls++; return 17;
    })),17); expect(calls,1);
  });
  for (final change in ['account','epoch','dispose','principal']) {
    test('late $change result cannot continue into a write', () async {
      final h=ScopeHarness(), hold=Completer<int>(); var writes=0;
      final pending=h.run(() async {
        await DedaSectionOperationContext.wait(() => hold.future);
        writes++; return true;
      });
      final assertion=expectLater(pending,throwsA(isA<DedaSectionOperationExpired>()));
      switch(change) {
        case 'account': h.account='B'; break;
        case 'epoch': h.account='B'; h.epoch++; h.account='A'; h.epoch++; break;
        case 'dispose': h.mounted=false; break;
        case 'principal': h.principal=('uid-b',1); break;
      }
      hold.complete(1); await assertion; expect(writes,0);
    });
  }
  test('stale scope refuses the callback before starting an SDK request', () async {
    final h=ScopeHarness(); var calls=0;
    await expectLater(h.run(() async {
      h.epoch++;
      return DedaSectionOperationContext.wait(() async {calls++;return 1;});
    }), throwsA(isA<DedaSectionOperationExpired>()));
    expect(calls,0);
  });
  test('completed ordinary errors are preserved without replay', () async {
    final h=ScopeHarness();var calls=0;final error=StateError('network');
    await expectLater(h.run(() => DedaSectionOperationContext.wait<int>(() async {
      calls++;throw error;
    })), throwsA(same(error)));expect(calls,1);
  });
  test('an error received after account change is treated as stale', () async {
    final h=ScopeHarness(), hold=Completer<int>();
    final result=h.run(() => DedaSectionOperationContext.wait(() => hold.future));
    final assertion=expectLater(result,throwsA(isA<DedaSectionOperationExpired>()));
    h.account='B';hold.completeError(StateError('old network failure'));await assertion;
  });
  test('top-level expired UI event finishes without an unhandled future', () async {
    final h=ScopeHarness(),hold=Completer<int>();var writes=0;
    final event=h.event(() async {
      await DedaSectionOperationContext.wait(() => hold.future);writes++;
    });
    h.account='B';hold.complete(1);await event;expect(writes,0);
  });
  test('nested void event must throw before its caller can continue', () async {
    final h=ScopeHarness();var writes=0;
    await h.event(() async {
      await h.event(() async {
        h.account='B';DedaSectionOperationContext.checkCurrent();
      });
      writes++;
    });
    expect(writes,0);
  });
  test('UI event does not swallow a real operation failure', () async {
    final h=ScopeHarness(); final error=StateError('denied');
    await expectLater(h.event(() async {throw error;}),throwsA(same(error)));
  });
  test('observing detached work preserves the error for its original await', () async {
    final pending=Completer<int>(),error=StateError('original failure');
    final original=pending.future;
    expect(identical(DedaSectionOperationContext.observe(original),original),isTrue);
    pending.completeError(error);
    await expectLater(original,throwsA(same(error)));
  });
  test('verified own principal transition can continue the same account', () async {
    final h=ScopeHarness();
    expect(await h.run(() async {
      h.principal=('restored-a',1);
      DedaSectionOperationContext.adoptVerifiedPrincipal();
      return DedaSectionOperationContext.wait(() async => 7);
    }),7);
  });
  test('principal adoption cannot conceal a changed account intent', () async {
    final h=ScopeHarness();
    await expectLater(h.run(() async {
      h.epoch++; h.principal=('restored-a',1);
      DedaSectionOperationContext.adoptVerifiedPrincipal();return 7;
    }),throwsA(isA<DedaSectionOperationExpired>()));
  });
  test('concurrent page operations do not share principal adoption', () async {
    final a=ScopeHarness(),b=ScopeHarness(),hold=Completer<int>();
    final pending=a.run(() => DedaSectionOperationContext.wait(() => hold.future));
    expect(await b.run(() async {
      b.principal=('restored-b',2);DedaSectionOperationContext.adoptVerifiedPrincipal();return 9;
    }),9);
    a.principal=('external-a',2);
    final assertion=expectLater(pending,throwsA(isA<DedaSectionOperationExpired>()));
    hold.complete(1);await assertion;
  });
  test('a verified child-page restoration preserves its same-account caller', () async {
    var live=('uid-a',0);final outer=Object(),inner=Object();
    expect(await DedaSectionOperationContext.run(owner:outer,isCurrent:()=>true,
      principal:()=>live,action:() async {
        await DedaSectionOperationContext.run(owner:inner,isCurrent:()=>true,
          principal:()=>live,action:() async {
            live=('uid-a-restored',1);DedaSectionOperationContext.adoptVerifiedPrincipal();
          });
        return DedaSectionOperationContext.wait(() async => 11);
      }),11);
  });
  test('a stale parent cannot start another page operation', () async {
    final h=ScopeHarness();var calls=0;
    await expectLater(h.run(() async {
      h.account='B';
      return DedaSectionOperationContext.run(owner:Object(),isCurrent:()=>true,
        principal:()=>h.principal,action:() async {calls++;return 1;});
    }),throwsA(isA<DedaSectionOperationExpired>()));
    expect(calls,0);
  });
  test('stream continuation cancels the old subscription after account change', () async {
    final h=ScopeHarness(),stream=StreamController<int>();var cancellations=0;
    stream.onCancel=() {cancellations++;};
    final received=<int>[];
    final pending=h.run(() async {
      await for(final value in DedaSectionOperationContext.guardStream(stream.stream)) {
        received.add(value);
      }
      return received;
    });
    stream.add(1);await Future<void>.delayed(Duration.zero);
    expect(received,[1]);h.epoch++;
    final assertion=expectLater(pending,throwsA(isA<DedaSectionOperationExpired>()));
    stream.add(2);await assertion;expect(received,[1]);expect(cancellations,1);
    await stream.close();
  });
  test('existing auth lane adopts only its verified own SDK transition', () async {
    var live=const DedaAuthSnapshot(null,DedaSessionAuthKind.none,0);
    final controller=DedaAuthSessionController(current:()=>live);
    final owner=Object();
    final value=await DedaSectionOperationContext.run(owner:owner,isCurrent:()=>true,
      principal:()=>(live.uid,live.kind,live.epoch),action:()=>controller.run(
        kind:DedaSessionTransitionKind.anonymousPreparation,
        origin:DedaSessionTransitionOrigin.activeSection,
        action:() async {
          await controller.transition<bool>(kind:DedaSessionTransitionKind.anonymousPreparation,
            action:() async {live=const DedaAuthSnapshot('uid',DedaSessionAuthKind.anonymous,1);return true;},
            accepts:(result,current)=>result&&current.uid=='uid');
          return controller.wait(() async => 23);
        }));
    expect(value,23);
  });
}
