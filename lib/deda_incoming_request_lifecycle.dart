import 'dart:async';

/// The account proof/session remains in the caller's original preparation.
/// This feed only scopes subscription lifetime and local seen-state writes.
class DedaIncomingRequestFeed {
  const DedaIncomingRequestFeed({required this.scope,
    required this.isCurrent, required this.watch});
  final String scope;
  final bool Function() isCurrent;
  final Stream<Set<String>> Function() watch;
}

class DedaIncomingRequestLifecycle {
  DedaIncomingRequestLifecycle({required this.loadSeen,
    required this.saveSeen, required this.onCount});
  final Future<Set<String>> Function(String scope) loadSeen;
  final Future<void> Function(String scope, List<String> ids) saveSeen;
  final void Function(int count) onCount;
  int _generation = 0;
  StreamSubscription<Set<String>>? _subscription;
  DedaIncomingRequestFeed? _feed;
  Set<String> _seen = {}, _incoming = {};
  Future<void> _writes = Future<void>.value();

  Future<void> start({required bool Function() isCurrent,
    required Future<DedaIncomingRequestFeed> Function() prepare}) async {
    final generation = ++_generation;
    final old = _subscription;
    _subscription = null;
    _feed = null; _seen = {}; _incoming = {}; onCount(0);
    bool current() => generation == _generation && isCurrent();
    try {
      await old?.cancel();
      if (!current()) return;
      final feed = await prepare();
      if (!current() || !feed.isCurrent() || feed.scope.isEmpty) return;
      final seen = await loadSeen(feed.scope);
      if (!current() || !feed.isCurrent()) return;
      _feed = feed; _seen = Set.of(seen);
      _subscription = feed.watch().listen((incoming) {
        if (!current() || !feed.isCurrent()) return;
        _incoming = Set.of(incoming);
        onCount(_incoming.difference(_seen).length);
      }, onError: (Object _, StackTrace stack) {
        // Preserve the current badge on a read failure; no false zero.
      });
    } catch (_) {
      // Original notification setup is optional. No detached failure or retry.
    }
  }

  Future<void> markSeen() {
    final generation = _generation, feed = _feed;
    if (feed == null || !feed.isCurrent()) return Future<void>.value();
    final requested = Set<String>.of(_incoming);
    if (requested.isEmpty) return Future<void>.value();
    bool current() => generation == _generation && identical(feed, _feed) && feed.isCurrent();
    // Serialize local writes across generations too: an already-issued A write
    // must settle before a later A -> B -> A write to that same preference key.
    final operation = _writes.then((_) async {
      if (!current()) return;
      var next = {..._seen, ...requested};
      if (next.length > 250) next = next.skip(next.length - 250).toSet();
      final ids = next.toList()..sort();
      await saveSeen(feed.scope, ids);
      if (!current()) return;
      _seen = next;
      // Requests arriving during persistence remain unseen, rather than being
      // erased by the old unconditional zero after an await.
      onCount(_incoming.difference(_seen).length);
    });
    _writes = operation.then<void>((_) {}, onError: (Object _, StackTrace stack) {});
    return operation;
  }

  Future<void> stop() async {
    ++_generation;
    final old = _subscription;
    _subscription = null;
    _feed = null; _seen = {}; _incoming = {}; onCount(0);
    await old?.cancel();
  }
}
