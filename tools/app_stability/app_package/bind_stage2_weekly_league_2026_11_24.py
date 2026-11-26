"""Stage2: retain the approved weekly competition, isolate current owner and reads.
Apply only to the complete temporary source, never the repo or production.
No prize payouts, new score keys, task changes, or altered wallet math.
"""
import argparse
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MARK = 'DEDA_STAGE2_WEEKLY_OWNER_AND_VERIFIED_RANK'


def one(s, old, new, label):
    if s.count(old) != 1:
        raise ValueError('WEEKLY_SOURCE_STOP:' + label + ':' + str(s.count(old)))
    return s.replace(old, new, 1)


def patch_direct(s):
    if MARK in s or 'standingRefresh' not in s:
        raise ValueError('WEEKLY_SOURCE_STOP:expected-single-existing-100406-bridge')
    s = one(s, "import 'deda_weekly_league_clock.dart';",
        "import 'deda_weekly_league_clock.dart';\n"
        "import 'deda_auth_session_runtime.dart';\n"
        "import 'deda_backend.dart';\n"
        "import 'main.dart' show DedaPreferences;", 'shared-owner-imports')
    s = one(s, '  static final Set<String> _retrying = <String>{};',
        '  static final Set<String> _retrying = <String>{};\n'
        '  // ' + MARK + '\n'
        '  static const maxRankedParticipants = 5000;\n'
        '  static const _server = GetOptions(source: Source.server);\n'
        '  static bool completeRankingSnapshot(int count) =>\n'
        '      count >= 0 && count <= maxRankedParticipants;\n\n'
        '  static bool Function() _ownerFence(String accountKey, String uid) {\n'
        '    final epoch = DedaPreferences.stabilityAccountEpoch;\n'
        '    final principal = DedaAuthRuntime.capture();\n'
        '    return () {\n'
        '      try {\n'
        '        DedaAuthRuntime.checkSnapshot(principal);\n'
        '        return DedaPreferences.isLoggedIn &&\n'
        '            DedaPreferences.stabilityAccountEpoch == epoch &&\n'
        '            DedaBackend.accountKeyForPhone(DedaPreferences.phone).trim() == accountKey &&\n'
        '            FirebaseAuth.instance.currentUser?.uid == uid;\n'
        '      } catch (_) { return false; }\n'
        '    };\n'
        '  }\n', 'reuse-selected-owner-epoch')
    s = one(s, '    final uid = user.uid;\n    final ownerDocs = await Future.wait([',
        '    final uid = user.uid;\n'
        '    final current = _ownerFence(accountKey, uid);\n'
        '    if (!current()) return null;\n'
        '    final ownerDocs = await Future.wait([', 'identity-capture')
    for collection in ('deda_sessions', 'users'):
        a = "db.collection('" + collection + "').doc(uid).get(),"
        s = one(s, a, a.replace('.get()', '.get(_server).timeout(const Duration(seconds: 12))'),
                'server-owner-' + collection)
    s = one(s, '    final sess = ownerDocs[0];',
        '    if (!current() || ownerDocs.any((doc) =>\n'
        '        doc.metadata.isFromCache || doc.metadata.hasPendingWrites)) return null;\n'
        '    final sess = ownerDocs[0];', 'owner-no-cache-or-pending')
    s = one(s, "final p = await db.collection('deda_account_profiles').doc(accountKey).get();",
        "final p = await db.collection('deda_account_profiles').doc(accountKey).get(_server)\n"
        "          .timeout(const Duration(seconds: 12));\n"
        "      if (!current() || p.metadata.isFromCache || p.metadata.hasPendingWrites) return null;",
        'name-fallback-owner')
    s = one(s, '    if (FirebaseAuth.instance.currentUser?.uid != uid) return null;',
        '    if (!current()) return null;', 'identity-return-fence')
    s = one(s, '      String task, String day) async {\n    if (FirebaseAuth.instance.currentUser?.uid != uid) return false;',
        '      String task, String day, bool Function() stillCurrent) async {\n'
        '    if (!stillCurrent() || FirebaseAuth.instance.currentUser?.uid != uid) return false;',
        'score-owner-entry')
    s = one(s, '    if (person == null || person.uid != uid) return false;',
        '    bool currentWeekOwner() {\n'
        '      final live = DateTime.now().toUtc();\n'
        '      return stillCurrent() && DedaWeeklyLeagueClock.at(live).canAccumulate &&\n'
        '          week(live).id == w.id && DedaWeeklyCommunityOutbox.dayAllowedInCurrentWeek(day, live);\n'
        '    }\n'
        '    if (person == null || person.uid != uid || !currentWeekOwner()) return false;',
        'score-boundary-before-write')
    s = one(s, 'alreadyBound = (await owner.get()).exists;',
        'final ownerDoc = await owner.get(_server).timeout(const Duration(seconds: 12));\n'
        '      if (!currentWeekOwner() || ownerDoc.metadata.isFromCache ||\n'
        '          ownerDoc.metadata.hasPendingWrites) return false;\n'
        '      alreadyBound = ownerDoc.exists;',
        'server-account-binding')
    s = one(s, '    if (!alreadyBound) {\n      try {',
        '    if (!currentWeekOwner()) return false;\n    if (!alreadyBound) {\n      try {',
        'owner-write-current')
    s = one(s, '    final ref = scores(w.id).doc(person.id);',
        '    if (!currentWeekOwner()) return false;\n    final ref = scores(w.id).doc(person.id);',
        'score-current-before-transaction')
    s = one(s, '        final previous = await tx.get(ref);\n        final old = previous.data();',
        '        if (!currentWeekOwner()) return false;\n'
        '        final previous = await tx.get(ref);\n'
        '        if (!currentWeekOwner()) return false;\n'
        '        final old = previous.data();',
        'transaction-current-after-read')
    s = one(s, '        claimed.add(key);\n        tx.set(ref,',
        '        claimed.add(key);\n        if (!currentWeekOwner()) return false;\n        tx.set(ref,',
        'transaction-current-before-write')
    s = one(s, '      return await DedaWeeklyCommunityOutbox.recordAndSend(',
        '      final current = _ownerFence(accountKey, user.uid);\n'
        '      if (!current()) return false;\n'
        '      return await DedaWeeklyCommunityOutbox.recordAndSend(',
        'claim-capture-before-journal')
    s = one(s, 'send: (task, day) => _send(accountKey, user.uid, task, day),',
        'send: (task, day) => _send(accountKey, user.uid, task, day, current),',
        'claim-reuse-fence')
    s = one(s, "    if (me == null || !sameViewer()) throw StateError('league-account-missing');",
        "    if (me == null || !sameViewer()) throw StateError('league-account-missing');\n"
        "    final ownerCurrent = _ownerFence(accountKey, me.uid);\n"
        "    bool currentViewer() => sameViewer() && ownerCurrent();\n"
        "    if (!currentViewer()) throw StateError('league-account-switched');",
        'reader-and-retry-owner')
    s = one(s, 'send: (task, day) => _send(accountKey, me.uid, task, day),',
        'send: (task, day) => _send(accountKey, me.uid, task, day, currentViewer),',
        'retry-same-original-receipt')
    s = one(s, 'if (sameViewer()) standingRefresh.value += 1;',
        'if (currentViewer()) standingRefresh.value += 1;', 'late-refresh-fence')
    s = one(s, "    if (!sameViewer() ||\n        FirebaseAuth.instance.currentUser?.uid != me.uid) {",
        "    if (!currentViewer() || week(DateTime.now().toUtc()).id != w.id) {",
        'reader-no-old-week-or-owner')
    # One server snapshot, not multiple pages taken at different instants.
    # 5000 is the existing decoder's rank ceiling. Never label a truncated
    # set verified. The previous 100-document cap silently gave false ranks.
    s = one(s, '    final snap = await scores(id).limit(100).get();',
        '    final snap = await scores(id).limit(maxRankedParticipants + 1).get(_server)\n'
        '        .timeout(const Duration(seconds: 12));\n'
        '    if (snap.metadata.isFromCache || snap.metadata.hasPendingWrites ||\n'
        '        !completeRankingSnapshot(snap.docs.length)) {\n'
        "      throw StateError('league-complete-server-ranking-required');\n"
        '    }', 'full-server-ranking-not-first-100')
    s = one(s, "          xp != tasks * 20) continue;",
        "          xp != tasks * 20 || row['weekId'] != id ||\n"
        "          row['updatedAt'] is! Timestamp) continue;",
        'verified-week-and-tie-timestamp')
    return s


def patch_gate(s):
    s = one(s, '    this.refreshSignal,\n    this.startsAt,',
        '    this.refreshSignal,\n    this.readAccountEpoch,\n'
        '    this.readAuthEpoch,\n    this.accountChanges,\n    this.startsAt,',
        'optional-existing-runtime-inputs')
    s = one(s, '  final Listenable? refreshSignal;',
        '  final Listenable? refreshSignal;\n'
        '  final int Function()? readAccountEpoch;\n'
        '  final int? Function()? readAuthEpoch;\n'
        '  final Listenable? accountChanges;', 'gate-inputs')
    s = one(s, '  String? _boundUid;',
        '  String? _boundUid;\n  int? _boundAccountEpoch;\n'
        '  int? _boundAuthEpoch;\n  late final int? _openingAccountEpoch;',
        'gate-epoch-storage')
    s = one(s, '  bool _sameViewer() =>\n      _bound &&\n      !_revoked &&\n      _readAccount() == _boundAccount &&\n      _readUid() == _boundUid;',
        '  bool _sameViewer() {\n'
        '    try {\n'
        '      return _bound && !_revoked && _readAccount() == _boundAccount &&\n'
        '          _readUid() == _boundUid &&\n'
        '          widget.readAccountEpoch?.call() == _boundAccountEpoch &&\n'
        '          widget.readAuthEpoch?.call() == _boundAuthEpoch;\n'
        '    } catch (_) { return false; }\n'
        '  }\n\n'
        '  void _revoke() {\n'
        '    if (!mounted || _revoked) return;\n'
        '    setState(() => _revoked = true);\n'
        '    _poll?.cancel();\n    _poll = null;\n'
        '  }\n', 'same-viewer-epoch')
    s = one(s, '    if (!mounted || _revoked) return;\n    final account = _readAccount();',
        '    if (!mounted || _revoked) return;\n'
        '    if (widget.readAccountEpoch?.call() != _openingAccountEpoch) {\n'
        '      _revoke(); return;\n    }\n'
        '    final account = _readAccount();', 'account-rotation-before-binding')
    s = one(s, '          _boundUid = uid;',
        '          _boundUid = uid;\n'
        '          _boundAccountEpoch = widget.readAccountEpoch?.call();\n'
        '          _boundAuthEpoch = widget.readAuthEpoch?.call();',
        'capture-bound-owner')
    s = one(s, '    if (account != _boundAccount || uid != _boundUid) {\n      setState(() => _revoked = true);\n      _poll?.cancel();\n      _poll = null;\n      return;\n    }',
        '    if (!_sameViewer()) {\n      _revoke(); return;\n    }', 'revoke-rotated-owner')
    s = one(s, '      onError: (Object _) => _onAuthEvent(null),',
        '      onError: (Object _) { if (_bound) _revoke(); },\n'
        '      onDone: () { if (_bound) _revoke(); },', 'auth-error-not-proof')
    s = one(s, '    super.initState();\n    _attachAuth();',
        '    super.initState();\n'
        '    _openingAccountEpoch = widget.readAccountEpoch?.call();\n'
        '    widget.accountChanges?.addListener(_refreshSession);\n'
        '    _attachAuth();', 'listen-shared-account-changes')
    s = one(s, '    if (oldWidget.refreshSignal != widget.refreshSignal) {',
        '    if (oldWidget.accountChanges != widget.accountChanges) {\n'
        '      oldWidget.accountChanges?.removeListener(_refreshSession);\n'
        '      widget.accountChanges?.addListener(_refreshSession);\n'
        '    }\n'
        '    if (oldWidget.refreshSignal != widget.refreshSignal) {',
        'account-listener-rebind')
    s = one(s, '    widget.refreshSignal?.removeListener(_refreshSession);\n    super.dispose();',
        '    widget.refreshSignal?.removeListener(_refreshSession);\n'
        '    widget.accountChanges?.removeListener(_refreshSession);\n    super.dispose();',
        'account-listener-cleanup')
    return s


def patch_main(s):
    a = '        authEvents: FirebaseAuth.instance.authStateChanges(),\n'
    if s.count(a) != 2:
        raise ValueError('WEEKLY_SOURCE_STOP:both-original-home-routes')
    return s.replace(a, a +
        '        readAccountEpoch: () => DedaPreferences.stabilityAccountEpoch,\n'
        '        readAuthEpoch: () => DedaAuthRuntime.capture()?.epoch,\n'
        '        accountChanges: DedaSectionAccountChanges.epoch,\n')


def patch_prize(s):
    # Public read only; leave GM increase() and prize minima unchanged.
    a = s.index('class DedaWeeklyPrizeAmount extends StatelessWidget')
    z = s.index('class DedaAdminLeaguePrizeSummary', a)
    public = s[a:z]
    public = one(public, 'DedaWeeklyPrizePlan.ref(DedaWeeklyPrizePlan.thisWeekId).snapshots(),',
        'DedaWeeklyPrizePlan.ref(DedaWeeklyPrizePlan.thisWeekId).snapshots(includeMetadataChanges: true),',
        'public-plan-server-metadata')
    public = one(public, 'snapshot.hasData &&\n            !snapshot.data!.metadata.hasPendingWrites;',
        'snapshot.hasData && !snapshot.hasError &&\n'
        '            !snapshot.data!.metadata.isFromCache &&\n'
        '            !snapshot.data!.metadata.hasPendingWrites;',
        'public-plan-not-cached')
    public = one(public, '        final values = trusted\n'
        '            ? DedaWeeklyPrizePlan.amounts(snapshot.data!.data())\n'
        '            : DedaWeeklyPrizePlan.minimum;',
        '        if (!trusted) {\n'
        "          return Text('💎 …', style: TextStyle(color: color, fontSize: fontSize));\n"
        '        }\n'
        '        final values = DedaWeeklyPrizePlan.amounts(snapshot.data!.data());',
        'do-not-display-guessed-current-prize')
    return s[:a] + public + s[z:]


def patch_maintenance(s):
    s = one(s, ".doc('active').snapshots(),",
        ".doc('active').snapshots(includeMetadataChanges: true),", 'control-metadata')
    return one(s, '        if (!snapshot.hasData) {',
        '        if (!snapshot.hasData || snapshot.hasError ||\n'
        '            snapshot.data!.metadata.isFromCache ||\n'
        '            snapshot.data!.metadata.hasPendingWrites) {',
        'control-not-cached')


def verify(files):
    main, direct, gate, prize, maintenance, page, clock, outbox, safe = (
        files[key] for key in ('main','direct','gate','prize','maintenance','page','clock','outbox','safe'))
    for body, markers in (
        (main, ('readAccountEpoch: () => DedaPreferences.stabilityAccountEpoch',
                'readAuthEpoch: () => DedaAuthRuntime.capture()?.epoch',
                'accountChanges: DedaSectionAccountChanges.epoch',
                'DedaWeeklyOwnerPilotBridge.claimAfterOriginalReward(',
                'DedaWeeklyAccountViewGate(', 'DedaDailyTasksPage()')),
        (direct, (MARK, "db.collection('deda_sessions').doc(uid).get(_server)",
                  "db.collection('users').doc(uid).get(_server)",
                  'ownerDocs.any((doc)', 'DedaAuthRuntime.checkSnapshot(principal)',
                  'limit(maxRankedParticipants + 1).get(_server)',
                  'completeRankingSnapshot(snap.docs.length)',
                  'if (!currentWeekOwner()) return false;',
                  'claimed.length * 20', 'claimed.contains(key)', 'scores(w.id).doc(person.id)',
                  "week(DateTime.now().toUtc()).id != w.id",
                  "'rewardsCredited': false", 'DedaVerifiedActiveIdStore.read(authUid, pid)',
                  "'publicAppearance': publicAppearance", 'DedaLinkedOwnerSessionPolicy.verified(user, accountKey)')),
        (gate, ('_openingAccountEpoch', '_boundAuthEpoch', 'widget.accountChanges?.removeListener(_refreshSession)', '_sameViewer()')),
        (prize, ('!snapshot.data!.metadata.isFromCache', 'DedaWeeklyPrizePlan.minimum', 'DedaWeeklyPrizePlan.amounts(snapshot.data!.data())')),
        (maintenance, ('!snapshot.hasData || snapshot.hasError', 'metadata.isFromCache', 'currentWeekId()')),
        (page, ('Widget podium(', 'Widget rankingTable(', 'deda-weekly-inline-countdown',
                'clock.daysAndHours', 'DedaWeeklyPrizeAmount(', 'DedaWeeklyMaintenanceStatus(',
                'DedaUnifiedActiveIdLabel100410(', 'DedaWeeklyLeaderboardTapSurface(')),
        (clock, ('frozenLength = Duration(hours: 6)', 'DateTime.utc(2026, 10, 31, 3)', 'daysAndHours')),
        (outbox, ('deda_weekly_community_pending_100404', 'dayAllowedInCurrentWeek', '$_prefix|$uid|$accountKey')),
        (safe, ('currentAccountStillAuthorized', '_requestEpoch', 'drawOriginalEquippedAvatar: widget.drawOriginalEquippedAvatar')),
    ):
        for marker in markers:
            if marker not in body:
                raise ValueError('WEEKLY_VERIFY:' + marker)
    if main.count('DedaWeeklyAccountViewGate(') != 2 or 'limit(100).get()' in direct:
        raise ValueError('WEEKLY_VERIFY:routes-or-truncated-rank')
    if 'previousWeek' in page:
        raise ValueError('WEEKLY_VERIFY:old-week-tab-returned')


PATHS = {
    'main':'lib/main.dart',
    'direct':'lib/deda_weekly_firestore_direct_bridge.dart',
    'gate':'lib/deda_weekly_account_view_gate.dart',
    'prize':'lib/deda_weekly_prize_plan.dart',
    'maintenance':'lib/deda_weekly_maintenance_status.dart',
    'page':'lib/deda_weekly_leaderboard_page.dart',
    'clock':'lib/deda_weekly_league_clock.dart',
    'outbox':'lib/deda_weekly_community_outbox.dart',
    'safe':'lib/deda_weekly_leaderboard_safe_screen.dart',
}
TRANSFORMS = {'main':patch_main, 'direct':patch_direct, 'gate':patch_gate,
              'prize':patch_prize, 'maintenance':patch_maintenance}


def bind(project, verify_only=False):
    project = Path(project).resolve()
    if project == ROOT or ROOT in project.parents or project in ROOT.parents:
        raise ValueError('WEEKLY_DO_NOT_MODIFY_REPOSITORY')
    files = {key:(project/path).read_text() for key,path in PATHS.items()}
    if not verify_only:
        for key, patch in TRANSFORMS.items():
            files[key] = patch(files[key])
    verify(files)
    if not verify_only:
        for key in TRANSFORMS:
            (project/PATHS[key]).write_text(files[key])
    print('PASS_STAGE2_WEEKLY_ORIGINAL_ROUTES_RANK_OWNER_FREEZE_PRIZE_READ_NO_PAYOUT')



LAB_MARK = 'DEDA_STAGE04_WEEKLY_UNIFIED_UID'
LAB_IMPORT = "import 'deda_stage03_lab_uid_storage_2026_11_25.dart';\n"

def patch_lab_main(s):
    anchor = 'readCanonicalAccount: () => DedaBackend.accountKeyForPhone(\n            DedaPreferences.phone).trim(),'
    if s.count(anchor)!=2 or LAB_MARK in s or LAB_IMPORT not in s:
        raise ValueError('WEEKLY_LAB_BOTH_ROUTES_OR_PROFILE_IMPORT')
    return s.replace(anchor,
        'readCanonicalAccount: () => DedaStage03LabStorage.leagueLabMode\n'
        '            ? DedaStage03LabStorage.leagueAccountKey()\n'
        '            : DedaBackend.accountKeyForPhone(\n'
        '            DedaPreferences.phone).trim(),')

def patch_lab_gate(s):
    s=LAB_IMPORT+s
    return one(s,'_authReady && _account.hasMatch(account) && _uid.hasMatch(uid)',
        '_authReady && _uid.hasMatch(uid) && (DedaStage03LabStorage.leagueLabMode\n'
        '          ? account==uid && account==DedaStage03LabStorage.leagueAccountKey()\n'
        '          : _account.hasMatch(account))','lab-gate-one-uid')

LAB_LOAD = r'''
  // DEDA_STAGE04_WEEKLY_UNIFIED_UID
  static Future<Object?> _loadLabStandings(String accountKey,bool Function() sameViewer) async {
    if(!sameViewer() || accountKey!=DedaStage03LabStorage.leagueAccountKey())
      throw StateError('league-lab-owner-required');
    final opening=await DedaStage03LabStorage.readLeague(),p=opening.requireCurrent();
    final now=DateTime.now().toUtc(), w=week(now);
    void check(){
      opening.requireCurrent();
      if(!sameViewer() || accountKey!=DedaStage03LabStorage.leagueAccountKey() ||
          week(DateTime.now().toUtc()).id!=w.id)
        throw StateError('league-lab-owner-or-week-changed');
    }
    check();
    final current=await _read(w.id,p.originalId,'live',
        w.close.difference(now).inMilliseconds,lab:opening);
    check();
    final previous=w.start.isAtSameMomentAs(origin)?<String,dynamic>{
      'verified':true,'status':'closed','rewardsCredited':false,
      'weekId':'before-first-week','remainingMs':0,'rows':[],
      'viewerParticipantId':null,'viewerPlace':null,
    }:await _read(week(w.start.subtract(const Duration(milliseconds:1))).id,
        p.originalId,'closed',0,lab:opening);
    check();
    final fresh=await DedaStage03LabStorage.readLeague();
    opening.verifyUnchanged(fresh);
    check();
    return {'source':'deda_direct_firestore_v1','readOnly':true,
      'current':current,'previous':previous};
  }

'''

def patch_lab_load_entry(s):
    # Multiple identical checks exist in the original method. Match only
    # the complete public signature and insert before its first statement.
    anchor=('  static Future<Object?> loadStandings({\n'
            '    required String accountKey, required bool Function() sameViewer,\n'
            '  }) async {\n')
    return one(s,anchor,LAB_LOAD+anchor+
        '    if(DedaStage03LabStorage.leagueLabMode)return _loadLabStandings(accountKey,sameViewer);\n',
        'lab-load-signature')


def patch_lab_direct(s):
    if MARK not in s or LAB_MARK in s:
        raise ValueError('WEEKLY_LAB_EXISTING_DIRECT_REQUIRED')
    s=LAB_IMPORT+s
    s=patch_lab_load_entry(s)
    anchor='    required String accountKey, required String taskId,\n  }) async {'
    s=one(s,anchor,anchor+'\n    if(DedaStage03LabStorage.leagueLabMode){\n'
        '      final confirmed=await DedaStage03LabStorage.confirmLeagueClaim(accountKey,taskId);\n'
        '      if(confirmed)standingRefresh.value+=1;\n      return confirmed;\n    }','lab-claim-existing-only')
    s=one(s,'String id, String viewer, String status, int left) async {',
        'String id, String viewer, String status, int left,{DedaStage04LeagueRead? lab}) async {','lab-read-parameter')
    s=one(s,'    final all = <Map<String, dynamic>>[];',
        '    final owner=lab?.requireCurrent();\n'
        '    Map<String,Map<String,dynamic>>? fixture;\n'
        '    if(lab!=null){\n'
        "      final proof=await db.collection('deda_weekly_direct_weeks').doc(id).get(_server)\n"
        '          .timeout(const Duration(seconds:12));\n'
        '      lab.requireCurrent();\n'
        '      if(proof.metadata.isFromCache || proof.metadata.hasPendingWrites)\n'
        '        throw StateError("league-fixture-server-proof");\n'
        '      fixture=DedaStage04LeagueRead.verifyRankingProof(lab.requireCurrent(),id,proof.data(),\n'
        '        {for(final row in snap.docs)row.id:row.data()});\n'
        '    }\n'
        '    final all = <Map<String, dynamic>>[];','lab-score-proof')
    s=one(s,"          row['updatedAt'] is! Timestamp) continue;",
        "          row['updatedAt'] is! Timestamp) {\n"
        "        if(lab!=null && !(pid==viewer && xp==0 && tasks==0))\n"
        "          throw StateError('league-lab-invalid-rank-row');\n"
        "        continue;\n      }",'lab-no-skipped-invalid-rank')
    s=one(s,"all.add({'id': pid, 'name': name, 'xp': xp, 'tasks': tasks,",
        "all.add({'id': pid, 'name': owner!=null && pid==viewer?owner.displayName:name, 'xp': xp, 'tasks': tasks,",'lab-owner-name')
    s=one(s,'final known = pid == viewer && authUid != null',
        'final known = lab==null && pid == viewer && authUid != null','lab-no-old-id-cache')
    s=one(s,'var displayedId = known?.displayId ?? pid;',
        'var displayedId = fixture!=null?fixture[pid]!["activeId"] as String:(known?.displayId ?? pid);','lab-owner-display-id')
    s=one(s,"if (proof?['displayId'] is String) {",
        "if (lab==null && proof?['displayId'] is String) {",'lab-no-overwrite-own-id')
    s=one(s,"if (p?['publicId'] == pid &&",
        "if (p?['publicId'] == pid && (fixture==null || p?['ownerUid']==fixture[pid]?['ownerUid']) &&",'lab-own-appearance-owner')
    # In lab mode the complete proof supplies the display ID. Never consult
    # the old alias store; read the existing server directory for appearance.
    s=one(s,"final fetched = await Future.wait<Map<String, dynamic>?>([",
        "final fetched = await Future.wait<Map<String, dynamic>?>([",'lab-fetch-anchor')
    s=one(s,"          db.collection('deda_public_active_aliases').doc(pid)",
        "          if(lab!=null) Future<Map<String,dynamic>?>.value(null) else\n"
        "          db.collection('deda_public_active_aliases').doc(pid)",'lab-no-old-alias-read')
    return s

def patch_lab_page(s):
    if LAB_IMPORT in s: raise ValueError('WEEKLY_LAB_DUPLICATE_PAGE')
    s=LAB_IMPORT+s
    for expression,scale in (('details?.activePublicId','11'),('profile(row)?.activePublicId','11*scale')):
        if expression=='details?.activePublicId':
            old=': DedaUnifiedActiveIdLabel100410(\n                        originalId:_originalFromWeekly(row)!,\n                        style:TextStyle(fontSize:11,color:silver))'
        else:
            old=': DedaUnifiedActiveIdLabel100410(\n                          originalId:_originalFromWeekly(row)!,\n                          style:TextStyle(fontSize:11*scale,color:silver))'
        new=': DedaStage03LabStorage.leagueLabMode ? Text('+expression+" ?? '—',\n"
        new+='                          textDirection:TextDirection.ltr,maxLines:1,overflow:TextOverflow.ellipsis,\n'
        new+='                          style:TextStyle(fontSize:'+scale+',color:silver)) '+old
        s=one(s,old,new,'lab-verified-label-'+scale)
    return s

def patch_lab_prize(s):
    # Only the original public widget, never the manager's increase writer.
    a=s.index('class DedaWeeklyPrizeAmount extends StatelessWidget')
    z=s.index('class DedaAdminLeaguePrizeSummary',a)
    public=s[a:z]
    public=one(public,'        final values = DedaWeeklyPrizePlan.amounts(snapshot.data!.data());',
        '        final data=snapshot.data!.data();\n'
        '        if(DedaStage03LabStorage.leagueLabMode){\n'
        '          final amounts=data?["amounts"];\n'
        '          if(DedaStage03LabStorage.leagueAccountKey().isEmpty || data?["weekId"]!=DedaWeeklyPrizePlan.thisWeekId ||\n'
        '              amounts is! List || amounts.length!=10 || List.generate(10,(i)=>i).any((i)=>\n'
        '                amounts[i] is! int || amounts[i]<DedaWeeklyPrizePlan.minimum[i] || amounts[i]>1000000))\n'
        "            return Text('💎 …',style:TextStyle(color:color,fontSize:fontSize));\n"
        '        }\n'
        '        final values = DedaWeeklyPrizePlan.amounts(data);','lab-prize-no-guesses')
    return LAB_IMPORT+s[:a]+public+s[z:]

def patch_lab_maintenance(s):
    return LAB_IMPORT+one(s,'        final data = snapshot.data!.data();',
        '        final data = snapshot.data!.data();\n'
        '        if(DedaStage03LabStorage.leagueLabMode &&\n'
        '            (DedaStage03LabStorage.leagueAccountKey().isEmpty || data?["weekId"]!=currentWeekId() || data?["paused"] is! bool)){\n'
        "          return const FittedBox(fit:BoxFit.scaleDown,child:Text('جارِ التحقق من حالة الدوري...'));\n"
        '        }','lab-control-proven')


# The original competitor card already has the callbacks. Bind them only in
# the disposable combined laboratory; no parallel social service or writer.
LAB_ACTION_MARK = 'DEDA_STAGE04_WEEKLY_EXISTING_SOCIAL_ACTIONS'

def patch_lab_main_actions(s):
    anchor = '          currentAccountStillAuthorized: stillSameViewer,\n'
    if s.count(anchor)!=2 or LAB_ACTION_MARK in s:
        raise ValueError('WEEKLY_LAB_SOCIAL_BOTH_ORIGINAL_ROUTES')
    return s.replace(anchor,anchor+
        '          // '+LAB_ACTION_MARK+'\n'
        '          labPublicProfileBuilder: (profile) => DedaFriendPublicProfilePage(profile: profile),\n'
        '          labAccountChanges: DedaSectionAccountChanges.epoch,\n')

LAB_SOCIAL = r'''
  // DEDA_STAGE04_WEEKLY_EXISTING_SOCIAL_ACTIONS
  // Only the peer already proven by verifyRankingProof is supported.
  // No public ID is interpreted as an authentication UID.
  bool get _labSocialEnabled => mounted && _stillCurrent &&
      DedaStage03LabStorage.leagueLabMode && DedaSocialService.stage04LabMode &&
      widget.labPublicProfileBuilder!=null && widget.labAccountChanges!=null;

  bool _labPeer(DedaWeeklyPublicCompetitor target) =>
      target.safePublicIdentity &&
      target.participantId=='weekly-user-DEDA-QA5678' &&
      target.originalPublicId=='@DEDA-QA5678' &&
      target.activePublicId=='@DEDA-QA5678';

  DedaWeeklyFriendRelation _labRelation(DedaWeeklyPublicCompetitor target) {
    try {
      if(!_labSocialEnabled || _snapshot==null || _labFriends==null)
        return DedaWeeklyFriendRelation.unknown;
      final view=_labFriends!.requireCurrent();
      if(view.uid!=DedaStage03LabStorage.leagueAccountKey())
        return DedaWeeklyFriendRelation.unknown;
      if(target.originalPublicId==view.originalId)return DedaWeeklyFriendRelation.self;
      if(!_labPeer(target))return DedaWeeklyFriendRelation.unknown;
      final rows=view.rows.where((r)=>r.peerUid=='synthetic-peer-001' ||
          r.peerPublicId==target.originalPublicId).toList();
      if(rows.isEmpty)return DedaWeeklyFriendRelation.notFriends;
      if(rows.length!=1 || rows.single.peerUid!='synthetic-peer-001' ||
          rows.single.peerPublicId!=target.originalPublicId)
        return DedaWeeklyFriendRelation.unknown;
      switch(rows.single.status) {
        case 'accepted': return DedaWeeklyFriendRelation.friends;
        case 'pending': return DedaWeeklyFriendRelation.pending;
        case 'rejected': return DedaWeeklyFriendRelation.notFriends;
        default: return DedaWeeklyFriendRelation.unknown;
      }
    } catch(_) { return DedaWeeklyFriendRelation.unknown; }
  }

  Future<void> _labAction(DedaWeeklyPublicCompetitor target,
      {required bool send}) async {
    if(!_labSocialEnabled || !_labPeer(target) || _labActionInFlight ||
        _snapshot==null || (send && (!DedaSocialService.stage04Actions ||
          _labRelation(target)!=DedaWeeklyFriendRelation.notFriends)))return;
    _labActionInFlight=true;
    try {
      final week=DedaStage04LeagueRead.weekId(DateTime.now().toUtc());
      final owner=DedaStage03LabStorage.leagueAccountKey();
      void check() {
        if(!_labSocialEnabled || owner.isEmpty ||
            DedaStage03LabStorage.leagueAccountKey()!=owner ||
            DedaStage04LeagueRead.weekId(DateTime.now().toUtc())!=week)
          throw StateError('league-social-session-or-week-changed');
      }
      check();
      // The rendered competitor is not authority; re-read current complete
      // standings with the original guarded loader before either action.
      final fresh=DedaWeeklyServerSnapshotPair.parse(
          await widget.loadVerifiedStandings!());
      check();
      final live=fresh.current;
      final current=live.profilesByUid[target.participantId]?.verifiedCompetitor;
      if(!live.verified || current==null || !_labPeer(current) ||
          !current.isOtherVerifiedParticipant(live.viewerUid) ||
          current.displayName!=target.displayName)
        throw StateError('league-social-stale-competitor');
      final session=await DedaSocialService.readLabSession();
      check();
      if(!session.stage04Current || session.profile.ownerUid!=owner)
        throw StateError('league-social-owner-conflict');

      Future<DedaSocialProfile> verifiedProfile() async {
        if(!_labSocialEnabled || !session.stage04Current ||
            DedaStage03LabStorage.leagueAccountKey()!=owner)
          throw StateError('league-social-session-changed');
        final profile=await DedaSocialService.readLabPublicProfile(
            target.originalPublicId);
        if(!_labSocialEnabled || !session.stage04Current ||
            DedaStage03LabStorage.leagueAccountKey()!=owner ||
            profile==null || profile.ownerUid!='synthetic-peer-001' ||
            profile.publicId!=target.originalPublicId ||
            profile.displayName!=target.displayName)
          throw StateError('league-social-directory-conflict');
        return profile;
      }

      final profile=await verifiedProfile();
      check();
      if(send) {
        if(!DedaSocialService.stage04Actions)
          throw StateError('league-social-write-held');
        // Reuse the original service and its fresh central transaction;
        // do not create a relation, task receipt or reward in this screen.
        await DedaSocialService.sendFriendRequest(sender:session,target:profile);
        if(_labSocialEnabled && session.stage04Current) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content:Text('تم إرسال طلب الصداقة')));
          unawaited(_read());
        }
      } else {
        // Retain the original public-profile page. Refresh through the
        // existing relationship feed and verified directory, not phone data.
        final updates=DedaSocialService.watchRelations(session.uid)
            .asyncMap((_)=>verifiedProfile());
        final auth=FirebaseAuth.instance.authStateChanges();
        await Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>
          AnimatedBuilder(animation:widget.labAccountChanges!,builder:(ctx,child)=>
            StreamBuilder<User?>(stream:auth,builder:(ctx,authState)=>
              StreamBuilder<DedaSocialProfile>(stream:updates,builder:(ctx,profileState) {
                if(!_labSocialEnabled || !session.stage04Current ||
                    authState.hasError || authState.data?.uid!=owner ||
                    profileState.hasError) {
                  return const Scaffold(body:Center(child:Text('جارِ التحقق من ملف المتصدر')));
                }
                final verified=profileState.data;
                if(verified==null)return const Scaffold(
                    body:Center(child:CircularProgressIndicator()));
                return widget.labPublicProfileBuilder!(verified);
              })))));
      }
    } catch(_) {
      if(_labSocialEnabled)ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content:Text('تعذر التحقق من الإجراء، أعد المحاولة')));
    } finally {
      _labActionInFlight=false;
    }
  }

'''

def patch_lab_safe(s):
    if LAB_ACTION_MARK in s or LAB_IMPORT in s:
        raise ValueError('WEEKLY_LAB_SOCIAL_DUPLICATE_SAFE')
    s=LAB_IMPORT+"import 'package:firebase_auth/firebase_auth.dart';\n"\
        "import 'deda_social_service.dart';\n"\
        "import 'deda_weekly_competitor_public_card.dart';\n"+s
    s=one(s,'    this.onOpenDailyTasks,\n',
        '    this.onOpenDailyTasks,\n    this.labPublicProfileBuilder,\n    this.labAccountChanges,\n',
        'lab-social-optional-original-profile')
    s=one(s,'  final Duration? refreshInterval;',
        '  final Duration? refreshInterval;\n'
        '  final Widget Function(DedaSocialProfile)? labPublicProfileBuilder;\n'
        '  final Listenable? labAccountChanges;', 'lab-social-fields')
    s=one(s,'  bool _requestInFlight = false;',
        '  bool _requestInFlight = false;\n'
        '  bool _labActionInFlight=false;\n'
        '  DedaStage04FriendsRead? _labFriends;\n'+LAB_SOCIAL,
        'lab-social-existing-screen')
    s=one(s,'      setState(() => _snapshot = converted);',
        '      DedaStage04FriendsRead? friends;\n'
        '      if(_labSocialEnabled) {\n'
        '        try { friends=await DedaStage03LabStorage.readFriends(); friends.requireCurrent(); }\n'
        '        catch(_) { friends=null; }\n'
        '      }\n'
        '      if(!mounted || epoch!=_requestEpoch || !_stillCurrent)return;\n'
        '      setState(() { _snapshot=converted; _labFriends=friends; });',
        'lab-social-central-relations')
    s=one(s,'      onOpenDailyTasks: widget.onOpenDailyTasks,',
        '      onOpenDailyTasks: widget.onOpenDailyTasks,\n'
        '      friendRelationFor: _labSocialEnabled && safeSnapshot!=null ? _labRelation : null,\n'
        '      onOpenExistingPublicProfile: _labSocialEnabled && safeSnapshot!=null\n'
        '          ? (target)=>_labAction(target,send:false) : null,\n'
        '      onSendExistingFriendRequest: _labSocialEnabled && safeSnapshot!=null && DedaSocialService.stage04Actions\n'
        '          ? (target)=>_labAction(target,send:true) : null,',
        'lab-social-original-card-callbacks')
    return s


def bind_lab(project):
    project=Path(project).resolve()
    if project==ROOT or ROOT in project.parents or project in ROOT.parents:
        raise ValueError('WEEKLY_LAB_DISPOSABLE_REQUIRED')
    files={key:(project/path).read_text() for key,path in PATHS.items()}
    verify(files)
    transforms={'main':lambda s:patch_lab_main_actions(patch_lab_main(s)),'gate':patch_lab_gate,
                'direct':patch_lab_direct,'page':patch_lab_page,'safe':patch_lab_safe,
                'prize':patch_lab_prize,'maintenance':patch_lab_maintenance}
    updated={key:patch(files[key]) for key,patch in transforms.items()}
    for key,value in updated.items():
        (project/PATHS[key]).write_text(value)
    print('PASS_STAGE04_WEEKLY_ORIGINAL_ROUTES_CENTRAL_UID_RECEIPTS_READ_ONLY')


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
