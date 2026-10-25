import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import '../lib/deda_incoming_request_lifecycle.dart';
import '../lib/main.dart' as app;

class Harness {
  final counts = <int>[];
  final saved = <(String, List<String>)>[];
  final loads = <String>[];
  final streams = <String, StreamController<Set<String>>>{};
  Future<Set<String>> Function(String)? read;
  Future<void> Function(String, List<String>)? write;
  late final lifecycle = DedaIncomingRequestLifecycle(
    onCount: counts.add,
    loadSeen: (scope) async {
      loads.add(scope);
      final reader = read;
      if (reader == null) return <String>{};
      return await reader(scope);
    },
    saveSeen: (scope, ids) async { saved.add((scope, List.of(ids))); await write?.call(scope, ids); },
  );
  DedaIncomingRequestFeed feed(String scope, {bool Function()? current}) =>
    DedaIncomingRequestFeed(scope: scope, isCurrent: current ?? () => true,
      watch: () => streams.putIfAbsent(scope, () => StreamController<Set<String>>()).stream);
  Future<void> start(String scope) => lifecycle.start(isCurrent: () => true, prepare: () async => feed(scope));
  Future<void> emit(String scope, Set<String> ids) async {
    streams[scope]!.add(ids); await Future<void>.delayed(Duration.zero);
  }
  Future<void> close() async {
    await lifecycle.stop();
    for (final stream in streams.values) { await stream.close(); }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('stopping during session preparation never loads or subscribes later', () async {
    final h = Harness(), pending = Completer<DedaIncomingRequestFeed>();
    final start = h.lifecycle.start(isCurrent: () => true, prepare: () => pending.future);
    await Future<void>.delayed(Duration.zero); await h.lifecycle.stop();
    pending.complete(h.feed('A')); await start;
    expect(h.loads, isEmpty); expect(h.streams, isEmpty); expect(h.counts.last, 0);
    await h.close();
  });
  test('an older cancellation finishing after a newer start cannot attach or detach its feed', () async {
    final h = Harness(), cancel = Completer<void>();
    h.streams['A'] = StreamController<Set<String>>(onCancel: () => cancel.future);
    await h.start('A');
    var obsoletePreparations = 0;
    final second = h.lifecycle.start(isCurrent: () => true, prepare: () async {
      obsoletePreparations++; return h.feed('B');
    });
    await Future<void>.delayed(Duration.zero);
    await h.start('C'); cancel.complete(); await second;
    await h.emit('C', {'new'});
    expect(obsoletePreparations, 0); expect(h.loads, ['A', 'C']); expect(h.counts.last, 1);
    await h.close();
  });
  test('A to B to A local account epoch rejects the old preparation', () async {
    final h = Harness(), pending = Completer<DedaIncomingRequestFeed>(); var epoch = 1;
    final start = h.lifecycle.start(isCurrent: () => epoch == 1, prepare: () => pending.future);
    await Future<void>.delayed(Duration.zero); epoch = 3;
    pending.complete(h.feed('A')); await start;
    expect(h.loads, isEmpty); expect(h.streams, isEmpty); await h.close();
  });
  test('leaving while preferences load prevents a late subscription', () async {
    final h = Harness(), loaded = Completer<Set<String>>(); h.read = (_) => loaded.future;
    final start = h.start('A'); await Future<void>.delayed(Duration.zero);
    await h.lifecycle.stop(); loaded.complete({}); await start;
    expect(h.streams, isEmpty); expect(h.counts.last, 0); await h.close();
  });
  test('changed SDK principal suppresses old stream data and seen writes', () async {
    final h = Harness(); var current = true;
    await h.lifecycle.start(isCurrent: () => true, prepare: () async => h.feed('A', current: () => current));
    await h.emit('A', {'one'}); expect(h.counts.last, 1);
    current = false; await h.emit('A', {'one', 'two'}); await h.lifecycle.markSeen();
    expect(h.counts.last, 1); expect(h.saved, isEmpty); await h.close();
  });
  test('incoming request during a seen-state write remains unseen after it completes', () async {
    final h = Harness(), saved = Completer<void>(); h.write = (_, __) => saved.future;
    await h.start('A'); await h.emit('A', {'one'});
    final marking = h.lifecycle.markSeen(); await Future<void>.delayed(Duration.zero);
    await h.emit('A', {'one', 'two'}); saved.complete(); await marking;
    expect(h.saved.single.$1, 'A'); expect(h.saved.single.$2, ['one']); expect(h.counts.last, 1); await h.close();
  });
  test('in-flight A write keeps its A key and cannot clear B badge', () async {
    final h = Harness(), saved = Completer<void>(); h.write = (_, __) => saved.future;
    await h.start('A'); await h.emit('A', {'old'});
    final marking = h.lifecycle.markSeen(); await Future<void>.delayed(Duration.zero);
    await h.start('B'); await h.emit('B', {'new'});
    saved.complete(); await marking;
    expect(h.saved.single.$1, 'A'); expect(h.counts.last, 1); await h.close();
  });
  test('overlapping seen requests serialize and merge instead of losing a newer stored ID', () async {
    final h = Harness(), saved = Completer<void>(); var writes = 0;
    h.write = (_, __) async { if (++writes == 1) await saved.future; };
    await h.start('A'); await h.emit('A', {'one'});
    final first = h.lifecycle.markSeen(); await Future<void>.delayed(Duration.zero);
    await h.emit('A', {'one', 'two'}); final second = h.lifecycle.markSeen();
    await Future<void>.delayed(Duration.zero); expect(h.saved, hasLength(1));
    saved.complete(); await first; await second;
    expect(h.saved.last.$1, 'A'); expect(h.saved.last.$2, ['one', 'two']); expect(h.counts.last, 0); await h.close();
  });
  test('returning to A waits for its pending write before reading seen history', () async {
    final h = Harness(), pending = Completer<void>();
    final disk = <String, Set<String>>{};
    h.read = (scope) async => Set<String>.of(disk[scope] ?? <String>{});
    h.write = (scope, ids) async {
      await pending.future;
      disk[scope] = ids.toSet();
    };
    await h.start('A'); await h.emit('A', {'old'});
    final marking = h.lifecycle.markSeen();
    await Future<void>.delayed(Duration.zero);
    final toB = h.start('B');
    await toB;
    await h.emit('B', {'b-unseen'});
    expect(h.counts.last, 1);
    h.streams['A'] = StreamController<Set<String>>();
    final backToA = h.start('A');
    await Future<void>.delayed(Duration.zero);
    expect(h.loads, ['A', 'B']);
    pending.complete(); await marking; await toB; await backToA;
    expect(h.loads, ['A', 'B', 'A']);
    await h.emit('A', {'old', 'new'});
    expect(h.counts.last, 1);
    await h.lifecycle.markSeen();
    expect(disk['A'], {'old', 'new'});
    expect(h.saved.last.$2, ['new', 'old']);
    await h.close();
  });
  test('failed local write keeps unseen state and does not poison the next explicit mark', () async {
    final h = Harness(); h.write = (_, __) async { throw StateError('disk unavailable'); };
    await h.start('A'); await h.emit('A', {'one'});
    await expectLater(h.lifecycle.markSeen(), throwsStateError); expect(h.counts.last, 1);
    h.write = null; await h.lifecycle.markSeen(); expect(h.counts.last, 0); await h.close();
  });
  test('stream read failure preserves badge instead of reporting no requests', () async {
    final h = Harness(); await h.start('A'); await h.emit('A', {'one'});
    h.streams['A']!.addError(StateError('offline')); await Future<void>.delayed(Duration.zero);
    expect(h.counts.last, 1); await h.close();
  });
  test('seen history retains original 250-ID bound and scope', () async {
    final h = Harness(); await h.start('A');
    await h.emit('A', Set.from(List.generate(300, (i) => 'id-$i')));
    await h.lifecycle.markSeen(); expect(h.saved.single.$1, 'A'); expect(h.saved.single.$2, hasLength(250));
    await h.close();
  });
  test('actual app notification API clears old badge and exits signed-out start without Firebase setup', () async {
    app.DedaPreferences.isLoggedIn = false; app.DedaPreferences.phone = '';
    app.DedaIncomingRequestNotifications.unseenNotifier.value = 7;
    await app.DedaIncomingRequestNotifications.start();
    expect(app.DedaIncomingRequestNotifications.unseenNotifier.value, 0);
    await app.DedaIncomingRequestNotifications.markCurrentIncomingSeen();
    await app.DedaIncomingRequestNotifications.stop();
  });
}
