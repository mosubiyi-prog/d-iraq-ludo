"""Scope original notification subscriptions/counts to their account lifetime."""
def once(source, before, after):
    if source.count(before) != 1:
        raise ValueError('Social lifecycle source anchor changed')
    return source.replace(before, after, 1)


def bind(source):
    if '_authAccountEpoch' not in source or 'DedaIncomingRequestLifecycle' in source:
        raise ValueError('Social lifecycle requires auth binding and one application')
    source = once(source,
        'class DedaSocialFriendCount {\n  static final ValueNotifier<int> notifier = ValueNotifier<int>(0);',
        'class DedaSocialFriendCount {\n  static int generation = 0;\n  static final ValueNotifier<int> notifier = ValueNotifier<int>(0);')
    start = source.index('class DedaIncomingRequestNotifications {')
    end = source.index('\nFuture<DedaSocialSession> dedaPrepareSocialSectionEntry(', start)
    original = source[start:end]
    if 'await prefs.setStringList(_prefsKey(_scope)' not in original or original.count('static Future<void> start()') != 1:
        raise ValueError('Original notification lifecycle changed')
    replacement = '''class DedaIncomingRequestNotifications {
  static final ValueNotifier<int> unseenNotifier = ValueNotifier<int>(0);
  static String _prefsKey(String scope) => 'deda_social_seen_incoming_v1_$scope';
  static final _lifecycle = DedaIncomingRequestLifecycle(
    onCount: (count) => unseenNotifier.value = count,
    loadSeen: (scope) async {
      final prefs = await SharedPreferences.getInstance();
      return (prefs.getStringList(_prefsKey(scope)) ?? const <String>[]).toSet();
    },
    saveSeen: (scope, ids) async {
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setStringList(_prefsKey(scope), ids)) {
        throw StateError('incoming-seen-not-saved');
      }
    },
  );

  static Future<void> start() async {
    final account = DedaBackend.accountKeyForPhone(DedaPreferences.phone).trim();
    final epoch = DedaPreferences._authAccountEpoch;
    bool current() => DedaPreferences.isLoggedIn && account.isNotEmpty &&
        epoch == DedaPreferences._authAccountEpoch &&
        account == DedaBackend.accountKeyForPhone(DedaPreferences.phone).trim();
    await _lifecycle.start(isCurrent: current, prepare: () async {
      final session = await dedaPrepareSocialSectionEntry(current);
      final principal = DedaAuthRuntime.capture();
      bool samePrincipal() {
        if (!current()) return false;
        try { DedaAuthRuntime.checkSnapshot(principal); return true; }
        catch (_) { return false; }
      }
      return DedaIncomingRequestFeed(scope: account, isCurrent: samePrincipal,
        watch: () => DedaSocialService.watchRelations(session.uid).map((relations) =>
          relations.where((item) => item.status == 'pending' &&
            item.recipientPublicId == session.publicId).map((item) => item.id).toSet()),
      );
    });
  }

  static Future<void> markCurrentIncomingSeen() async {
    try { await _lifecycle.markSeen(); } catch (_) {
      // Preserve the visible badge when the local write fails.
    }
  }

  static Future<void> stop() async {
    try { await _lifecycle.stop(); } catch (_) {}
  }

  static void accountChanged() {
    // stop invalidates synchronously before its first cancellation await.
    unawaited(stop());
    ++DedaSocialFriendCount.generation;
    DedaSocialFriendCount.notifier.value = 0;
  }
}
'''
    source = source[:start] + replacement + source[end:]
    start = source.index('Future<void> dedaRefreshFriendCount() async {')
    end = source.index('\nclass DedaFriendsPage ', start)
    original = source[start:end]
    if 'watchRelations(session.uid).first' not in original:
        raise ValueError('Original friend count refresh changed')
    source = source[:start] + '''Future<void> dedaRefreshFriendCount() async {
  final generation = ++DedaSocialFriendCount.generation;
  final epoch = DedaPreferences._authAccountEpoch;
  final account = DedaBackend.accountKeyForPhone(DedaPreferences.phone).trim();
  bool current() => generation == DedaSocialFriendCount.generation &&
      epoch == DedaPreferences._authAccountEpoch && DedaPreferences.isLoggedIn &&
      account.isNotEmpty && account == DedaBackend.accountKeyForPhone(DedaPreferences.phone).trim();
  try {
    if (!current()) return;
    final session = await dedaPrepareSocialSectionEntry(current);
    if (!current()) return;
    final principal = DedaAuthRuntime.capture();
    final relations = await DedaSocialService.watchRelations(session.uid)
        .timeout(const Duration(seconds: 12)).first;
    if (!current()) return;
    DedaAuthRuntime.checkSnapshot(principal);
    DedaSocialFriendCount.notifier.value =
        relations.where((item) => item.status == 'accepted').length;
  } catch (_) {}
}
''' + source[end:]
    hook = '    if (DedaAuthRuntime.enabled) ++_authAccountEpoch;'
    if source.count(hook) != 3:
        raise ValueError('Account selection epoch hooks changed')
    source = source.replace(hook, '''    if (DedaAuthRuntime.enabled) {
      ++_authAccountEpoch;
      DedaIncomingRequestNotifications.accountChanged();
    }''')
    first = source.index('import ')
    return source[:first] + "import 'deda_incoming_request_lifecycle.dart';\n" + source[first:]
