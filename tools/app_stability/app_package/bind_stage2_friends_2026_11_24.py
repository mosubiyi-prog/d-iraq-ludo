"""Stage2: finish the existing friends section in the disposable assembled app.
No new identity, friendship collection, page, Firebase deployment or migration.
"""
import argparse
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MARK = 'DEDA_STAGE2_FRIENDS_CANONICAL_KEY_OWNER_UID_SEPARATED'


def one(src, old, new, label):
    if src.count(old) != 1:
        raise ValueError('FRIENDS_SOURCE_STOP:' + label + ':' + str(src.count(old)))
    return src.replace(old, new, 1)


def region(src, start, end, patch):
    if src.count(start) != 1:
        raise ValueError('FRIENDS_SOURCE_STOP:' + start)
    a = src.index(start)
    z = src.index(end, a + len(start))
    return src[:a] + patch(src[a:z]) + src[z:]


def patch_friends_page(body):
    if MARK in body or 'DEDA_100441_FRIENDS_RETRY_FIX' not in body:
        raise ValueError('FRIENDS_SOURCE_STOP:original-retry-required')
    body = one(body, 'liveUid != verified.uid',
        '!verified.belongsToFirebaseOwner(liveUid)', 'retry-owner-vs-relation-key')
    body = one(body, 'FirebaseAuth.instance.currentUser?.uid != session.uid) return;',
        '!session.belongsToFirebaseOwner(FirebaseAuth.instance.currentUser?.uid)) return;',
        'count-owner-vs-relation-key')
    body = one(body, '    if (_loadingFriends) return;',
        '    // ' + MARK + '\n'
        '    if (!dedaSectionCurrent || _loadingFriends) return;\n'
        '    final accountEpoch = DedaPreferences.stabilityAccountEpoch;',
        'existing-retry-entry')
    body = one(body, '      await _prepareOriginal();\n      if (!mounted || generation != _friendsGeneration) return;',
        '      final principal = DedaAuthRuntime.capture();\n'
        '      await _prepareOriginal();\n'
        '      if (!dedaSectionCurrent || generation != _friendsGeneration ||\n'
        '          accountEpoch != DedaPreferences.stabilityAccountEpoch) return;\n'
        '      DedaAuthRuntime.checkSnapshot(principal);',
        'same-session-after-existing-loader')
    body = one(body, 'if (!mounted || _loadingFriends || !dedaSessionRescueStage3Enabled) return;',
        'if (!dedaSectionCurrent || _loadingFriends || !dedaSessionRescueStage3Enabled) return;',
        'existing-readiness-listener')
    # The protected relation key remains verified.uid for watchRelations.
    if body.count('DedaSocialService.watchRelations(verified.uid)') != 1:
        raise ValueError('FRIENDS_SOURCE_STOP:canonical-watch-route')
    return body


def patch_add_page(body):
    body = one(body, '  String? _resultMessage;',
        '  String? _resultMessage;\n  String? _resultQuery;', 'search-result-query')
    body = one(body, '    final session = _session;\n    if (session == null) {',
        '    if (_searching || _sending || !dedaSectionCurrent) return;\n'
        '    final session = _session;\n    if (session == null) {', 'search-entry')
    body = one(body, '    final id = DedaSocialService.normalizePublicId(_idController.text);',
        '    final searchSession = _session;\n'
        '    if (searchSession == null || !searchSession.belongsToFirebaseOwner(\n'
        '        FirebaseAuth.instance.currentUser?.uid)) return;\n'
        '    final id = DedaSocialService.normalizePublicId(_idController.text);',
        'search-owner')
    body = one(body, '      if (found != null && found.ownerUid == _session?.uid) {',
        '      if (!identical(searchSession, _session) ||\n'
        '          !searchSession.belongsToFirebaseOwner(FirebaseAuth.instance.currentUser?.uid) ||\n'
        '          DedaSocialService.normalizePublicId(_idController.text) != id) return;\n'
        '      if (found != null && searchSession.isSelfProfile(found)) {',
        'search-current-query-and-self')
    body = one(body, '        _result = found;',
        '        _result = found;\n        _resultQuery = found == null ? null : id;',
        'bind-result-to-query')
    body = one(body, '    if (sender == null || target == null || _sending) return;',
        '    if (sender == null || target == null || _sending || _searching ||\n'
        '        !sender.belongsToFirebaseOwner(FirebaseAuth.instance.currentUser?.uid) ||\n'
        '        sender.isSelfProfile(target) ||\n'
        '        _resultQuery != DedaSocialService.normalizePublicId(_idController.text)) return;',
        'send-current-verified-result')
    return body


def patch_requests_page(body):
    body = one(body, '  DedaSocialSession? _session;',
        '  DedaSocialSession? _session;\n'
        '  Stream<List<DedaFriendshipRecord>>? _requestsStream;\n'
        '  bool _preparingRequests = false;', 'requests-single-stream')
    body = one(body, '    if (dedaSectionCurrent) setState(() => _entryError = null);',
        '    if (!dedaSectionCurrent || _preparingRequests) return;\n'
        '    _preparingRequests = true;\n'
        '    setState(() {\n'
        '      _entryError = null;\n      _session = null;\n      _requestsStream = null;\n'
        '    });', 'requests-load-entry')
    body = one(body, '      if (dedaSectionCurrent) setState(() => _session = value);',
        '      if (!dedaSectionCurrent) return;\n'
        '      if (!value.belongsToFirebaseOwner(FirebaseAuth.instance.currentUser?.uid)) {\n'
        "        throw StateError('social-session-changed');\n"
        '      }\n'
        '      final stream = DedaSocialService.watchRelations(value.uid);\n'
        '      setState(() {\n        _session = value;\n        _requestsStream = stream;\n      });',
        'requests-current-owner-and-stream')
    body = one(body, '      if (dedaSectionCurrent) setState(() => _entryError = error);\n    }',
        '      if (dedaSectionCurrent) setState(() => _entryError = error);\n'
        '    } finally {\n      _preparingRequests = false;\n    }',
        'requests-load-finally')
    body = one(body, '              stream: DedaSocialService.watchRelations(session.uid),',
        '              stream: _requestsStream,', 'requests-stable-builder-stream')
    body = one(body, '                final all = snapshot.data ?? const <DedaFriendshipRecord>[];',
        '                if (snapshot.hasError) {\n'
        '                  return Center(child: FilledButton.icon(\n'
        '                    onPressed: _prepare,\n'
        '                    icon: const Icon(Icons.refresh_rounded),\n'
        "                    label: Text(dedaText('إعادة المحاولة', 'Retry')),\n"
        '                  ));\n                }\n'
        '                if (!snapshot.hasData) {\n'
        '                  return const Center(child: CircularProgressIndicator());\n                }\n'
        '                final all = snapshot.data!;',
        'requests-not-empty-on-error')
    body = one(body, '  Future<void> _respond(DedaFriendshipRecord relation, bool accept) async {',
        '  Future<void> _respond(DedaFriendshipRecord relation, bool accept) async {\n'
        '    final selected = _session;\n'
        '    if (!dedaSectionCurrent || selected == null ||\n'
        '        !selected.belongsToFirebaseOwner(FirebaseAuth.instance.currentUser?.uid) ||\n'
        "        relation.status != 'pending' || relation.recipientPublicId != selected.publicId) return;",
        'requests-only-current-recipient')
    return body


def patch_main(main):
    main = region(main, 'class _DedaFriendsPageState', 'class _DedaFriendCompactCard', patch_friends_page)
    main = region(main, 'class _DedaAddFriendPageState', 'class DedaFriendRequestsPage', patch_add_page)
    return region(main, 'class _DedaFriendRequestsPageState', 'class DedaFriendPublicProfilePage', patch_requests_page)


FEED = '''  /// Both existing directions must finish their first server snapshot before
  /// an empty/count/list result is meaningful. Reuse the original key/schema.
  static Stream<List<DedaFriendshipRecord>> watchRelations(String uid) {
    if (uid.isEmpty) return Stream.error(StateError('social-personal-id-missing'));
    final owner = FirebaseAuth.instance.currentUser?.uid;
    final principal = DedaAuthRuntime.capture();
    bool current() {
      if (owner == null || FirebaseAuth.instance.currentUser?.uid != owner) return false;
      try { DedaAuthRuntime.checkSnapshot(principal); return true; }
      catch (_) { return false; }
    }
    Stream<List<DedaFriendshipRecord>> direction(String field) => _db
        .collection('deda_friendships')
        .where(field, isEqualTo: uid)
        .snapshots(includeMetadataChanges: true)
        .where((snapshot) => !snapshot.metadata.isFromCache && !snapshot.metadata.hasPendingWrites)
        .map((snapshot) => snapshot.docs.map(DedaFriendshipRecord.fromDoc).toList());
    return mergeRelationFeeds(uid, direction('requesterPublicId'),
        direction('recipientPublicId'), isCurrent: current);
  }

  /// No Firestore access in this combiner; the actual two feed readers above
  /// and the UI both use this same code. No partial first emission.
  static Stream<List<DedaFriendshipRecord>> mergeRelationFeeds(
      String uid, Stream<List<DedaFriendshipRecord>> sent,
      Stream<List<DedaFriendshipRecord>> received, {
      required bool Function() isCurrent,
      Duration firstDeadline = const Duration(seconds: 12),
  }) {
    late final StreamController<List<DedaFriendshipRecord>> controller;
    StreamSubscription<List<DedaFriendshipRecord>>? sentSub, receivedSub;
    Timer? deadline;
    var generation = 0;
    List<DedaFriendshipRecord>? outgoing, incoming;
    void stop() {
      ++generation;
      deadline?.cancel();
      deadline = null;
      final oldSent = sentSub, oldReceived = receivedSub;
      sentSub = null;
      receivedSub = null;
      outgoing = null;
      incoming = null;
      if (oldSent != null) unawaited(oldSent.cancel().catchError((Object _) {}));
      if (oldReceived != null) unawaited(oldReceived.cancel().catchError((Object _) {}));
    }
    bool active(int run) => run == generation && controller.hasListener;
    void emit(int run) {
      if (!active(run)) return;
      if (!isCurrent()) {
        controller.addError(StateError('social-session-changed'));
        stop();
        return;
      }
      if (outgoing == null || incoming == null) return;
      deadline?.cancel();
      final items = <String,DedaFriendshipRecord>{
        for (final row in outgoing!) row.id: row,
        for (final row in incoming!) row.id: row,
      }.values.where((row) =>
          row.requesterPublicId == uid || row.recipientPublicId == uid).toList();
      items.sort((a, b) => a.otherName(uid).compareTo(b.otherName(uid)));
      controller.add(items);
    }
    void fail(int run, bool fromSent, Object error, StackTrace stack) {
      if (!active(run)) return;
      if (fromSent) { outgoing = null; } else { incoming = null; }
      deadline?.cancel();
      controller.addError(error, stack);
    }
    controller = StreamController<List<DedaFriendshipRecord>>.broadcast(
      onListen: () {
        final run = ++generation;
        if (!isCurrent()) {
          controller.addError(StateError('social-session-changed'));
          return;
        }
        deadline = Timer(firstDeadline, () {
          if (active(run) && (outgoing == null || incoming == null)) {
            controller.addError(TimeoutException('social-relations-not-ready', firstDeadline));
          }
        });
        sentSub = sent.listen((rows) {
          if (!active(run)) return;
          outgoing = rows;
          emit(run);
        }, onError: (Object error, StackTrace stack) => fail(run, true, error, stack));
        receivedSub = received.listen((rows) {
          if (!active(run)) return;
          incoming = rows;
          emit(run);
        }, onError: (Object error, StackTrace stack) => fail(run, false, error, stack));
      },
      onCancel: stop,
    );
    return controller.stream;
  }

'''


def patch_service(src):
    if 'uid: publicId,' not in src or 'ownerUid: user.uid,' not in src:
        raise ValueError('FRIENDS_SOURCE_STOP:canonical-session-schema')
    if 'mergeRelationFeeds(' in src:
        raise ValueError('FRIENDS_SOURCE_STOP:duplicate-feed')
    a = src.index('class DedaSocialSession {')
    z = src.index('class DedaSocialService {', a)
    session = src[a:z]
    session = one(session, '  final DedaSocialProfile profile;\n',
        '  final DedaSocialProfile profile;\n\n'
        '  // uid is the original social relationship key, not the Firebase UID.\n'
        '  bool belongsToFirebaseOwner(String? liveUid) =>\n'
        '      liveUid != null && liveUid.isNotEmpty && uid == publicId &&\n'
        '      profile.publicId == publicId && profile.ownerUid == liveUid;\n\n'
        '  bool isSelfProfile(DedaSocialProfile target) =>\n'
        '      target.publicId == publicId ||\n'
        '      (profile.ownerUid.isNotEmpty && target.ownerUid == profile.ownerUid);\n',
        'explicit-owner-separation')
    src = src[:a] + session + src[z:]
    imp = "import 'deda_auth_session_runtime.dart';"
    if imp not in src:
        src = imp + '\n' + src
    def feeds(old):
        for required in ("'requesterPublicId'", "'recipientPublicId'", 'StreamController', 'sentSub', 'receivedSub'):
            if required not in old:
                raise ValueError('FRIENDS_SOURCE_STOP:original-feed:' + required)
        return FEED
    src = region(src, '  static Stream<List<DedaFriendshipRecord>> watchRelations(',
                 '  static Future<String> sendFriendRequest(', feeds)
    return src


def verify(main, service):
    for marker in (
        MARK, '!verified.belongsToFirebaseOwner(liveUid)',
        'DedaSocialService.watchRelations(verified.uid)',
        'session.belongsToFirebaseOwner(FirebaseAuth.instance.currentUser?.uid)',
        'DedaAuthRuntime.checkSnapshot(principal);', 'searchSession.isSelfProfile(found)',
        '_resultQuery != DedaSocialService.normalizePublicId(_idController.text)',
        'stream: _requestsStream,', 'relation.recipientPublicId != selected.publicId',
        'DedaSocialService.respondToRequest(', 'DedaSocialService.removeRelation(',
        'DedaSocialService.profileForFriend(', 'DedaStage51FriendSearch.findByUserInput(id)',
        'DedaIncomingRequestNotifications.markCurrentIncomingSeen()',
        'DedaFriendIdCopy100411(', 'DedaFriendPublicProfilePage(profile: profile)',
        'DedaStage50VerifiedFriendInkBadge(', 'DedaQa32PublicRecipientResolver.resolveActiveAlias(',
    ):
        if marker not in main:
            raise ValueError('FRIENDS_VERIFY_MAIN:' + marker)
    for marker in (
        'uid: publicId,', 'profile.ownerUid == liveUid', 'uid == publicId',
        "direction('requesterPublicId')", "direction('recipientPublicId')",
        'if (outgoing == null || incoming == null) return;',
        '!snapshot.metadata.isFromCache && !snapshot.metadata.hasPendingWrites',
        "final pairKey = _pairKey(sender.publicId, target.publicId);",
        "'members': <String>[sender.publicId, target.publicId]",
        "'requesterUid': sender.publicId", "'recipientUid': target.publicId",
        'social-historical-owner-preserved', 'sender.profile.ownerUid',
        'principalAtEntry', 'social-request-not-owned', 'social-relation-not-owned',
    ):
        if marker not in service:
            raise ValueError('FRIENDS_VERIFY_SERVICE:' + marker)
    if 'liveUid != verified.uid' in main or 'found.ownerUid == _session?.uid' in main:
        raise ValueError('FRIENDS_VERIFY:uid-key-mismatch')
    return True


def bind(project, verify_only=False):
    project = Path(project).resolve()
    if project == ROOT or ROOT in project.parents or project in ROOT.parents:
        raise ValueError('FRIENDS_DO_NOT_MODIFY_REPOSITORY')
    m, s = project/'lib/main.dart', project/'lib/deda_social_service.dart'
    main, service = m.read_text(), s.read_text()
    if not verify_only:
        main, service = patch_main(main), patch_service(service)
    verify(main, service)
    if not verify_only:
        m.write_text(main)
        s.write_text(service)
    print('PASS_STAGE2_FRIENDS_ORIGINAL_RELATIONS_OWNER_UID_SEARCH_REQUESTS_COPY_SHARE_NO_DEPLOY')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('project', type=Path)
    parser.add_argument('--verify-only', action='store_true')
    args = parser.parse_args()
    bind(args.project, args.verify_only)
