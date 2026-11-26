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
    final accountEpoch = DedaPreferences.stabilityAccountEpoch;
    bool current() {
      if (owner == null || FirebaseAuth.instance.currentUser?.uid != owner) return false;
      try {
        DedaAuthRuntime.checkSnapshot(principal);
        return DedaPreferences.isLoggedIn &&
            DedaPreferences.stabilityAccountEpoch == accountEpoch;
      }
      catch (_) { return false; }
    }
    Stream<List<DedaFriendshipRecord>> direction(String field) => _db
        .collection('deda_friendships')
        .where(field, isEqualTo: uid)
        .snapshots(includeMetadataChanges: true)
        .where((snapshot) => !snapshot.metadata.isFromCache && !snapshot.metadata.hasPendingWrites)
        .map((snapshot) {
          // DEDA_STAGE2_FRIEND_ACCEPTED_TASK_SIGNAL_RETAINED
          // Restore the original 100383 sender-side accepted-today event.
          // This is a completion signal only; the existing task engine owns
          // all award keys and deduplication.
          final today = DateTime.now().toLocal();
          if (current() && snapshot.docs.any((doc) {
            final data = doc.data();
            final when = data['respondedAt'];
            if (data['status'] != 'accepted' || when is! Timestamp ||
                (data['requesterPublicId'] != uid && data['recipientPublicId'] != uid)) return false;
            final day = when.toDate().toLocal();
            return day.year == today.year && day.month == today.month && day.day == today.day;
          })) {
            unawaited(DedaTaskSignalBridge.friendAccepted());
          }
          return snapshot.docs.map(DedaFriendshipRecord.fromDoc).toList();
        });
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
    for dependency in ("import 'main.dart' show DedaPreferences;", "import 'deda_task_signal_bridge.dart';"):
        if dependency not in src:
            src = dependency + '\n' + src
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


# 04/02 reuses original presentation widgets and the Stage03 account projection.
# Explicit lab mode only; all legacy source remains byte-for-byte otherwise.
LAB_MARK = 'DEDA_STAGE04_FRIENDS_UID_SOURCE'
LAB_HELPERS = r'''
  static const stage04LabMode = bool.fromEnvironment('DEDA_STAGE04_FRIENDS_LAB');
  static Future<DedaSocialSession> readLabSession() async {
    final read = await DedaStage03LabStorage.readFriends();
    final p = read.requireProfile();
    // Legacy presentation session is only an interface adapter: the key used
    // by its existing row widgets is the public ID, never an Auth principal.
    // The cosmetic fields are unused in this adapter; peer appearance is held
    // unless independently verified. No public profile is written.
    return DedaSocialSession(uid:p.originalId, publicId:p.originalId,
      profile:DedaSocialProfile(publicId:p.originalId,ownerUid:p.uid,
        displayName:p.displayName,avatarStyle:0,frameStyle:0,
        backgroundStyle:0,level:1,badges:const []), stage04Read:read);
  }

  static List<DedaFriendshipRecord> labPresentationRows(DedaStage04FriendsRead opening) {
    final p=opening.requireProfile(), view=opening.requireCurrent();
    return List.unmodifiable(view.rows.map((r) {
      final a=r.incoming?r.peerPublicId:p.originalId;
      final b=r.incoming?p.originalId:r.peerPublicId;
      // These two fields are the OLD renderer's directional lookup keys.
      // The authoritative row ID remains the canonical UID pair.
      return DedaFriendshipRecord(id:r.pairKey,members:[a,b],
        requesterUid:a,recipientUid:b,requesterPublicId:a,recipientPublicId:b,
        requesterName:r.incoming?r.peerName:p.displayName,
        recipientName:r.incoming?p.displayName:r.peerName,status:r.status);
    }));
  }

  static Stream<List<DedaFriendshipRecord>> _watchLabRelations(String key) async* {
    final opening=await DedaStage03LabStorage.readFriends();
    final p=opening.requireProfile();
    if(key!=p.originalId)throw StateError('friends-lab-key-mismatch');
    yield labPresentationRows(opening);
    var revision=p.accountRevision;
    // Observe only the existing owner projection. Revalidate through the
    // same central transaction before publishing any changed revision.
    await for(final signal in _db.doc('deda_lab_uid_authority/'+p.uid+'/account/current')
        .snapshots(includeMetadataChanges:true)) {
      opening.requireCurrent();
      if(signal.metadata.isFromCache || signal.metadata.hasPendingWrites)continue;
      if(!signal.exists)throw StateError('friends-lab-source-missing');
      final value=signal.data()?['revision'];
      if(value==revision)continue;
      final fresh=await DedaStage03LabStorage.readFriends();
      opening.requireCurrent();
      final next=fresh.requireCurrent();
      if(next.uid!=p.uid || next.originalId!=key || next.revision<revision)
        throw StateError('friends-lab-stale-revision');
      revision=next.revision;
      yield labPresentationRows(fresh);
    }
  }

  // Read the existing directory and public profile only if they agree on
  // the canonical ID and actual peer UID. No Functions or phone lookup.
  // Current live lab rules can deny these paths; denial stays an error.
  static Future<DedaSocialProfile?> readLabPublicProfile(String raw) async {
    final opening=await DedaStage03LabStorage.readFriends();
    final owner=opening.requireProfile();
    final requested=normalizePublicId(raw);
    if(!RegExp(r'^@DEDA-[A-Z0-9]{4,12}$').hasMatch(requested))
      throw StateError('friends-lab-invalid-id');
    if(requested==owner.originalId || requested==owner.activeId)
      throw StateError('social-self-request');
    Future<Map<String,dynamic>?> read(String path) async {
      final row=await _db.doc(path).get(const GetOptions(source:Source.server));
      opening.requireCurrent();
      if(row.metadata.isFromCache || row.metadata.hasPendingWrites)
        throw StateError('friends-lab-unconfirmed-directory');
      return row.data();
    }
    var original=requested;
    var route=await read('deda_share_ids/'+original);
    if(route==null) {
      final alias=await read('deda_public_alias_routes/'+requested);
      if(alias==null)return null;
      final candidate=alias['originalId'];
      if(alias['aliasId']!=requested || candidate is! String ||
          !RegExp(r'^@DEDA-[A-Z0-9]{6}$').hasMatch(candidate))
        throw StateError('friends-lab-alias-unproven');
      original=candidate;
      final active=await read('deda_public_active_aliases/'+original);
      final selection=await read('deda_stage71_active_identifier/'+original);
      if(active==null || selection==null || active['originalId']!=original ||
          selection['originalId']!=original || active['activeId']!=requested ||
          selection['activeId']!=requested || active['baseColor']!=alias['baseColor'])
        throw StateError('friends-lab-alias-unproven');
      route=await read('deda_share_ids/'+original);
    }
    final peer=route?['ownerUid'];
    if(route==null || route['publicId']!=original || route['kind']!='personal' ||
        route['active']!=true || peer is! String || peer.isEmpty ||
        peer==owner.uid || original==owner.originalId)
      throw StateError('friends-lab-directory-owner-unproven');
    final data=await read('deda_social_profiles/'+original);
    if(data==null || data['publicId']!=original || data['ownerUid']!=peer ||
        data['displayName'] is! String || (data['displayName'] as String).trim().isEmpty ||
        ['avatarStyle','frameStyle','backgroundStyle','level'].any((k)=>data[k] is! int) ||
        data['badges'] is! List || !(data['badges'] as List).every((v)=>v is String))
      throw StateError('friends-lab-public-profile-unproven');
    for(final relation in opening.requireCurrent().rows) {
      if(relation.peerPublicId==original && relation.peerUid!=peer)
        throw StateError('friends-lab-peer-owner-conflict');
    }
    return DedaSocialProfile.fromMap(data);
  }
'''

def patch_lab_service(src):
    if LAB_MARK in src:
        raise ValueError('FRIENDS_LAB_ALREADY_BOUND')
    src = "import 'deda_stage03_lab_uid_storage_2026_11_25.dart';\n" + src
    def session(body):
        body=one(body,'    required this.profile,','    required this.profile,\n    this.stage04Read,','lab-session-ctor')
        return one(body,'  final DedaSocialProfile profile;',
            '  final DedaSocialProfile profile;\n  final DedaStage04FriendsRead? stage04Read;\n'
            '  bool get stage04Current {\n    try { stage04Read?.requireCurrent(); return stage04Read!=null; }\n'
            '    catch (_) { return false; }\n  }','lab-session-guard')
    src=region(src,'class DedaSocialSession {','class DedaSocialService {',session)
    src=one(src,'class DedaSocialService {','class DedaSocialService {\n  // '+LAB_MARK+'\n'+LAB_HELPERS,'lab-service')
    src=one(src,'  static Stream<List<DedaFriendshipRecord>> watchRelations(String uid) {',
        '  static Stream<List<DedaFriendshipRecord>> watchRelations(String uid) {\n'
        '    if(stage04LabMode)return _watchLabRelations(uid);','lab-relations')
    # Never let original writer/phone preparation run under the new lab UID.
    for start,end,guard in [
        ('  static Future<DedaSocialSession> ensurePersonalSession(', '  static Future<DedaSocialProfile?> findByPublicId(',
         'if(stage04LabMode)return readLabSession();'),
        ('  static Future<DedaSocialProfile?> findByPublicId(', '  static Stream<List<DedaFriendshipRecord>> watchRelations(',
         'if(stage04LabMode)return readLabPublicProfile(raw);'),
        ('  static Future<String> sendFriendRequest(', '  static Future<void> respondToRequest(',
         "if(stage04LabMode)throw StateError('friends-lab-authority-held');"),
        ('  static Future<void> respondToRequest(', '  static Future<void> removeRelation(',
         "if(stage04LabMode)throw StateError('friends-lab-authority-held');"),
        ('  static Future<void> removeRelation(', '  static Future<DedaSocialProfile?> profileForFriend(',
         "if(stage04LabMode)throw StateError('friends-lab-authority-held');"),
    ]:
        def patch(body):
            return one(body,'async {\n','async {\n    '+guard+'\n','lab-method-'+start)
        src=region(src,start,end,patch)
    return src

def patch_lab_main(main):
    def friends(body):
        anchor='  Future<void> _prepare({bool ownerProofAlreadyReady = false}) async {'
        body=one(body,anchor,anchor+'''
    if(DedaSocialService.stage04LabMode) {
      if(!mounted || _loadingFriends)return;
      final generation=++_friendsGeneration;
      setState(() { _loadingFriends=true; _session=null; _relationsStream=null; _error=null; });
      try {
        final session=await DedaSocialService.readLabSession();
        if(!mounted || generation!=_friendsGeneration || !session.stage04Current)return;
        setState(() { _session=session; _relationsStream=DedaSocialService.watchRelations(session.uid); });
      } catch(error) {
        if(mounted && generation==_friendsGeneration)setState(() => _error=error);
      } finally {
        if(mounted && generation==_friendsGeneration)setState(() => _loadingFriends=false);
      }
      return;
    }''','lab-friends-entry')
        body=one(body,'  void _onRescueReady() {','  void _onRescueReady() {\n    if(DedaSocialService.stage04LabMode)return;','lab-no-phone-retry')
        body=one(body,'                  if (DedaSocialFriendCount.notifier.value != verifiedCount) {',
            '                  if(DedaSocialService.stage04LabMode)return;\n'
            '                  if (DedaSocialFriendCount.notifier.value != verifiedCount) {','lab-no-old-count-write')
        body=one(body,'  Future<void> _remove(DedaFriendshipRecord relation) async {',
            '  Future<void> _remove(DedaFriendshipRecord relation) async {\n'
            '    if(DedaSocialService.stage04LabMode) {\n'
            "      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(dedaText('معاملة العلاقة بانتظار اعتماد المصدر الموحد.','Relationship transaction awaits unified authority.'))));\n"
            '      return;\n    }','lab-remove-held')
        body=one(body,'  Future<void> _openProfile(DedaFriendshipRecord relation) async {',
            '  Future<void> _openProfile(DedaFriendshipRecord relation) async {\n'
            '    if(DedaSocialService.stage04LabMode) {\n'
            "      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(dedaText('عرض الصديق بانتظار اعتماد الدليل العام.','Friend preview awaits verified public directory.'))));\n"
            '      return;\n    }','lab-preview-held')
        return body
    def add(body):
        anchor='  Future<void> _prepare() async {'
        body=one(body,anchor,anchor+'''
    if(DedaSocialService.stage04LabMode) {
      try {
        final session=await DedaSocialService.readLabSession();
        if(mounted && session.stage04Current)setState(() => _session=session);
      } catch(_) {
        if(mounted)setState(() { _session=null; _result=null;
          _resultMessage=dedaText('تعذر التحقق من الحساب الموحد.','Unified account verification failed.'); });
      }
      return;
    }''','lab-add-entry')
        body=one(body,'  Future<void> _copyMyId() async {','''  Future<void> _copyMyId() async {
    if(DedaSocialService.stage04LabMode) {
      try {
        final read=await DedaStage03LabStorage.readProfile();
        if(!mounted)return;
        await Clipboard.setData(ClipboardData(text:read.requireCurrent().activeId));
        read.requireCurrent();
      } catch(_) {}
      return;
    }''','lab-copy-own-id')
        body=one(body,'final found = await DedaStage51FriendSearch.findByUserInput(id);',
            'final found = await (DedaSocialService.stage04LabMode ? DedaSocialService.readLabPublicProfile(id) : DedaStage51FriendSearch.findByUserInput(id));','lab-search')
        return body
    def requests(body):
        body=one(body,'    unawaited(DedaIncomingRequestNotifications.markCurrentIncomingSeen());',
            '    if(!DedaSocialService.stage04LabMode)unawaited(DedaIncomingRequestNotifications.markCurrentIncomingSeen());','lab-no-old-notification')
        anchor='  Future<void> _prepare() async {'
        body=one(body,anchor,anchor+'''
    if(DedaSocialService.stage04LabMode) {
      if(!mounted || _preparingRequests)return;
      _preparingRequests=true;
      setState(() { _session=null; _requestsStream=null; _entryError=null; });
      try {
        final value=await DedaSocialService.readLabSession();
        if(!mounted || !value.stage04Current)return;
        setState(() { _session=value; _requestsStream=DedaSocialService.watchRelations(value.uid); });
      } catch(error) {
        if(mounted)setState(() => _entryError=error);
      } finally { _preparingRequests=false; }
      return;
    }''','lab-request-entry')
        return body
    main=region(main,'class _DedaFriendsPageState','class _DedaFriendCompactCard',friends)
    main=region(main,'class _DedaAddFriendPageState','class DedaFriendRequestsPage',add)
    return region(main,'class _DedaFriendRequestsPageState','class DedaFriendPublicProfilePage',requests)

def bind_lab(project):
    project=Path(project).resolve()
    if project == ROOT or ROOT in project.parents or project in ROOT.parents:
        raise ValueError('FRIENDS_LAB_DISPOSABLE_REQUIRED')
    m,s=project/'lib/main.dart',project/'lib/deda_social_service.dart'
    main,service=m.read_text(),s.read_text()
    verify(main,service)
    if 'DEDA_STAGE04_PROFILE_UID_READ_ONLY' not in main:
        raise ValueError('FRIENDS_LAB_PROFILE_BIND_REQUIRED')
    new_main,new_service=patch_lab_main(main),patch_lab_service(service)
    # Only disposable assembled source, all anchors before any write.
    m.write_text(new_main)
    s.write_text(new_service)
    print('PASS_STAGE04_FRIENDS_ORIGINAL_LIST_REQUESTS_UID_SOURCE_NO_LEGACY_WRITES')



if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('project', type=Path)
    parser.add_argument('--verify-only', action='store_true')
    parser.add_argument('--stage04-lab', action='store_true')
    args = parser.parse_args()
    if args.stage04_lab:
        if args.verify_only: raise ValueError('lab and verify-only are exclusive')
        bind_lab(args.project)
    else:
        bind(args.project, args.verify_only)
