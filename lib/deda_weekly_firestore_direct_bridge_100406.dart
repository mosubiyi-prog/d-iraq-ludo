import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'deda_verified_active_id_store.dart';
import 'deda_weekly_community_outbox.dart';
import 'deda_weekly_league_clock.dart';
import 'deda_qa32_spark_public_identifier_directory.dart';

/// Same original +20 XP -> direct Firestore score; no Functions, money or XP grants.
class DedaWeeklyFirestoreDirectBridge {
  DedaWeeklyFirestoreDirectBridge._();
  static final db = FirebaseFirestore.instance;
  static final ValueNotifier<int> standingRefresh = ValueNotifier<int>(0);
  static final Set<String> _retrying = <String>{};
  static final origin = DateTime.utc(2026, 10, 31, 3); // Sat 06:00 Baghdad
  static final accountPattern = RegExp(r'^[0-9]{10,16}$');
  static final idPattern = RegExp(r'^@DEDA-[A-Z0-9]{4,12}$');

  static ({String id, DateTime start, DateTime close}) week(DateTime now) {
    final delta = now.toUtc().difference(origin).inMilliseconds;
    if (delta < 0) throw StateError('league-not-started');
    final start = origin.add(Duration(
      milliseconds: (delta ~/ const Duration(days: 7).inMilliseconds) *
          const Duration(days: 7).inMilliseconds,
    ));
    final local = start.add(const Duration(hours: 3));
    final id = '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
    return (id: id, start: start,
      close: start.add(const Duration(days: 6, hours: 18)));
  }

  static Future<({String uid, String id, String name})?> identity(
      String accountKey) async {
    final user = FirebaseAuth.instance.currentUser;
    if (!accountPattern.hasMatch(accountKey) || user == null ||
        !user.isAnonymous) return null;
    final uid = user.uid;
    final sess = await db.collection('deda_sessions').doc(uid).get();
    if (sess.data()?['accountKey'] != accountKey) return null;
    final doc = await db.collection('users').doc(uid).get();
    final data = doc.data();
    if (data == null || data['accountKey'] != accountKey) return null;
    final id = data['sharePersonalId'];
    if (id is! String || !idPattern.hasMatch(id)) return null;
    var name = (data['name'] is String ? data['name'] as String : '').trim();
    if (name.length < 2 || name.length > 60 || name.contains('@')) {
      final p = await db.collection('deda_account_profiles').doc(accountKey).get();
      name = (p.data()?['name'] is String ? p.data()!['name'] as String : '').trim();
    }
    if (name.length < 2 || name.length > 60 || name.contains('@')) {
      name = 'مستخدم ديدا';
    }
    if (FirebaseAuth.instance.currentUser?.uid != uid) return null;
    return (uid: uid, id: id, name: name);
  }

  static CollectionReference<Map<String, dynamic>> scores(String weekId) =>
      db.collection('deda_weekly_direct_weeks').doc(weekId)
          .collection('scores');

  static Future<bool> _send(String accountKey, String uid,
      String task, String day) async {
    if (FirebaseAuth.instance.currentUser?.uid != uid) return false;
    final now = DateTime.now().toUtc();
    // Never import points before the league start or from a prior week.
    // Original reward was already journaled under the same authenticated UID.
    if (!DedaWeeklyCommunityOutbox.dayAllowedInCurrentWeek(day, now)) {
      return false;
    }
    // No queue, receipt or weekly XP before 06:00 or in Saturday freeze.
    if (!DedaWeeklyLeagueClock.at(now).canAccumulate) return false;
    final w = week(now);
    if (!now.isBefore(w.close)) return false;
    final person = await identity(accountKey);
    if (person == null || person.uid != uid) return false;
    final owner = db.collection('deda_weekly_direct_accounts').doc(person.id);
    var alreadyBound = false;
    try {
      alreadyBound = (await owner.get()).exists;
    } catch (_) {
      // A missing private binding is intentionally not publicly readable.
      // Creation is checked against the logged-in DEDA session by rules.
    }
    if (!alreadyBound) {
      try {
        await owner.set({
          'accountKey': accountKey,
          'publicId': person.id,
          'createdByUid': uid,
          'createdAt': FieldValue.serverTimestamp(),
        });
      } catch (_) { /* Possible concurrent creation; score still checked. */ }
    }
    final ref = scores(w.id).doc(person.id);
    final key = '$day|$task';
    try {
      return await db.runTransaction<bool>((tx) async {
        final previous = await tx.get(ref);
        final old = previous.data();
        final claimed = List<String>.from(old?['claimedKeys'] as List? ??
            const <String>[]);
        if (claimed.contains(key)) return true;
        if (claimed.length >= 56) return false;
        claimed.add(key);
        tx.set(ref, <String, dynamic>{
          'weekId': w.id,
          'weekStart': Timestamp.fromDate(w.start),
          'publicId': person.id,
          'displayName': old?['displayName'] ?? person.name,
          'claimedKeys': claimed,
          'lastClaimKey': key,
          'completedTasks': claimed.length,
          'weeklyXp': claimed.length * 20,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        return true;
      }, timeout: const Duration(seconds: 12));
    } catch (_) {
      return false;
    }
  }

  static Future<bool> claimAfterOriginalReward({
    required String accountKey, required String taskId,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !user.isAnonymous ||
        !DedaWeeklyLeagueClock.at(DateTime.now().toUtc()).canAccumulate ||
        !DedaWeeklyCommunityOutbox.tasks.contains(taskId)) return false;
    try {
      return await DedaWeeklyCommunityOutbox.recordAndSend(
        accountKey: accountKey, uid: user.uid, taskId: taskId,
        send: (task, day) => _send(accountKey, user.uid, task, day),
      );
    } catch (_) { return false; }
  }

  static Future<Object?> loadStandings({
    required String accountKey, required bool Function() sameViewer,
  }) async {
    if (!sameViewer()) throw StateError('league-account-switched');
    final me = await identity(accountKey);
    if (me == null || !sameViewer()) throw StateError('league-account-missing');
    // Do not block first standings paint on up to eight server transactions.
    // A confirmed old-task retry updates the standings once completed, with
    // no fabricated XP or changed awards. The journal serializes duplicate
    // sends and only replays existing same-week authenticated task receipts.
    final retryKey = '${me.uid}|$accountKey';
    if (_retrying.add(retryKey)) {
      unawaited(DedaWeeklyCommunityOutbox.retry(
        accountKey: accountKey, uid: me.uid, limit: 8,
        send: (task, day) => _send(accountKey, me.uid, task, day),
      ).then((count) {
        if (count > 0 && FirebaseAuth.instance.currentUser?.uid == me.uid) {
          try {
            if (sameViewer()) standingRefresh.value += 1;
          } catch (_) { /* View disposed or account switched. */ }
        }
      }).catchError((Object _) {
        // Failed deliveries remain pending under the same authenticated UID.
      }).whenComplete(() => _retrying.remove(retryKey)));
    }
    if (!sameViewer()) throw StateError('league-account-switched');
    final w = week(DateTime.now().toUtc());
    final first = w.start.isAtSameMomentAs(origin);
    final prev = first ? null :
        week(w.start.subtract(const Duration(milliseconds: 1)));
    final current = await _read(w.id, me.id, 'live',
        w.close.difference(DateTime.now().toUtc()).inMilliseconds);
    // DEDA 100405: own-account private admin-review message.
    // This is NOT a public accusation and never modifies original level XP.
    try {
      final noticeDoc = await db.collection('deda_weekly_direct_notices')
          .doc(w.id).collection('users').doc(me.id).get();
      final review = noticeDoc.data();
      if (review != null && review['publicId'] == me.id &&
          review['notice'] is String &&
          (review['notice'] as String).length <= 240 &&
          (review['notice'] as String).length >= 12) {
        current['reviewNotice'] = review['notice'];
      }
    } catch (_) {
      // Unavailable review notice never hides genuine leaderboard results.
    }
    final previous = prev == null ? <String, dynamic>{
      'verified': true, 'status': 'closed', 'rewardsCredited': false,
      'weekId': 'before-first-week', 'remainingMs': 0,
      'rows': [], 'viewerParticipantId': null, 'viewerPlace': null,
    } : await _read(prev.id, me.id, 'closed', 0);
    if (!sameViewer() ||
        FirebaseAuth.instance.currentUser?.uid != me.uid) {
      throw StateError('league-account-switched');
    }
    return {'source': 'deda_direct_firestore_v1',
      'readOnly': true, 'current': current, 'previous': previous};
  }

  static Future<Map<String, dynamic>> _read(
      String id, String viewer, String status, int left) async {
    final snap = await scores(id).limit(100).get();
    final all = <Map<String, dynamic>>[];
    for (final item in snap.docs) {
      final row = item.data();
      final pid = row['publicId'];
      final name = row['displayName'];
      final xp = row['weeklyXp'];
      final tasks = row['completedTasks'];
      if (pid is! String || !idPattern.hasMatch(pid) || item.id != pid ||
          name is! String || name.length < 2 || name.length > 60 ||
          xp is! int || tasks is! int || xp < 20 || xp > 1120 ||
          xp != tasks * 20) continue;
      all.add({'id': pid, 'name': name, 'xp': xp, 'tasks': tasks,
        'stamp': row['updatedAt'] is Timestamp
          ? (row['updatedAt'] as Timestamp).millisecondsSinceEpoch : 0});
    }
    all.sort((a,b) {
      final byXp = (b['xp'] as int).compareTo(a['xp'] as int);
      if (byXp != 0) return byXp;
      final byDate = (a['stamp'] as int).compareTo(b['stamp'] as int);
      return byDate != 0 ? byDate :
          (a['id'] as String).compareTo(b['id'] as String);
    });
    final place = all.indexWhere((r) => r['id'] == viewer);
    final selected = all.take(10).toList();
    if (place >= 10) selected.add(all[place]);
    // The owner has ONE verified display-ID store shared with the profile.
    // Only reuse server-confirmed same-Firebase-UID UI data; never rekey XP,
    // prove authorization from the cache, or borrow another user's ID.
    final authUid = FirebaseAuth.instance.currentUser?.uid;
    final rows = await Future.wait<Map<String, dynamic>>(
      selected.map((r) async {
        final rank = all.indexOf(r) + 1;
        final pid = r['id'] as String;
        final known = pid == viewer && authUid != null
            ? DedaVerifiedActiveIdStore.read(authUid, pid)
            : null;
        var displayedId = known?.displayId ?? pid;

        // Firestore alias + equipment for every competitor are independent.
        // Never serialize these reads across the whole Top 10. All results
        // remain scoped to the verified original score ID.
        final fetched = await Future.wait<Map<String, dynamic>?>([
          db.collection('deda_public_active_aliases').doc(pid)
              .get(const GetOptions(source: Source.server))
              .then((doc) => doc.data()).catchError((_) => null),
          db.collection('deda_social_profiles').doc(pid)
              .get(const GetOptions(source: Source.server))
              .then((doc) => doc.data()).catchError((_) => null),
        ]);
        final proof =
            DedaQa32SparkPublicIdentifierDirectory.styleFromProjection(
                pid, fetched[0]);
        if (proof?['displayId'] is String) {
          displayedId = proof!['displayId'] as String;
        }
        // If the public alias query transiently failed, a same-account
        // previously Stage71-confirmed ID may still render as UI only.
        // The original ID remains the hidden stable score document key.
        final p = fetched[1];
        final avatar = p?['avatarStyle'];
        final frame = p?['frameStyle'];
        Map<String, dynamic>? publicAppearance;
        if (p?['publicId'] == pid &&
            p?['ownerUid'] is String &&
            (p!['ownerUid'] as String).isNotEmpty &&
            avatar is int && avatar >= 0 && avatar <= 8 &&
            frame is int && frame >= 0 && frame <= 18) {
          publicAppearance = {
            'originalPublicId': pid,
            'activePublicId': displayedId,
            'displayName': r['name'],
            'avatarStyle': avatar,
            'equippedFrameStyle': frame,
            'publicOwnerVerified': true,
            'equippedAppearanceVerified': true,
          };
        }
        return {
          'place': rank, 'participantId': 'weekly-user-${pid.substring(1)}',
          'displayName': r['name'], 'activePublicId': displayedId,
          if (publicAppearance != null) 'publicAppearance': publicAppearance,
          'weeklyPoints': r['xp'], 'verifiedTaskCompletions': r['tasks'],
          'diamondsIfFinalWinner': rank == 1 ? 150 : rank == 2 ? 100 :
            rank == 3 ? 50 : rank <= 10 ? 10 : 0,
        };
      }),
    );
    return {
      'verified': true, 'status': status, 'rewardsCredited': false,
      'weekId': id, 'remainingMs': left.clamp(0, const Duration(days: 7).inMilliseconds),
      'rows': rows,
      'viewerParticipantId': place >= 0
          ? 'weekly-user-${viewer.substring(1)}' : null,
      'viewerPlace': place >= 0 ? place + 1 : null,
    };
  }
}
