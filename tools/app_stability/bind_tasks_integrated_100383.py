"""100383 task replacements: preserve wallet/award IDs; change only actions.

Apply to staged restored workspace after original signed base is reconstructed.
Does not reset old data or touch balances, server rules or purchases.
"""
from pathlib import Path
import shutil

def one(text, old, new, label):
    if text.count(old) != 1:
        k=text.find("Add a friend")
        print('TASK500_ACTION_CONTEXT',repr(text[k-180:k+650]))
        raise ValueError('task500 unexpected source '+label+': '+str(text.count(old)))
    return text.replace(old,new,1)

def bind(root):
    root=Path(root)
    repo=Path(__file__).resolve().parents[2]
    shutil.copy2(repo/'lib/deda_task_signal_bridge.dart',root/'lib/deda_task_signal_bridge.dart')
    shutil.copy2(repo/'lib/deda_task_write_fence.dart',root/'lib/deda_task_write_fence.dart')
    main=root/'lib/main.dart'
    s=main.read_text()
    s=one(s, "import 'traffic_quiz_page.dart';",
          "import 'traffic_quiz_page.dart';\n"
          "import 'deda_task_signal_bridge.dart';\n"
          "import 'deda_task_write_fence.dart';",
          'bridge and safe task writer import')
    s=one(s,
          "  trafficQuizCorrectAnswer,\n}",
          """  trafficQuizCorrectAnswer,
  prizeCardsExplored,
  placeDiscovered,
  mapSearchTyped,
  friendAccepted,
}""",
          'event enum')
    s=one(s,
          "        DedaTaskEvent.trafficQuizCorrectAnswer => 'traffic_quiz_correct_answer',",
          """        DedaTaskEvent.trafficQuizCorrectAnswer => 'traffic_quiz_correct_answer',
        DedaTaskEvent.prizeCardsExplored => 'prize_cards_explored',
        DedaTaskEvent.placeDiscovered => 'place_discovered',
        DedaTaskEvent.mapSearchTyped => 'map_search_typed',
        DedaTaskEvent.friendAccepted => 'friend_accepted',""",
          'event keys')
    s=one(s,
          """        DedaTaskEvent.registeredPlaceShared => DedaTaskIds.shareRegisteredPlace,
        DedaTaskEvent.receivedPlaceOpened => DedaTaskIds.openReceivedPlace,
        DedaTaskEvent.savedPlaceOpened => DedaTaskIds.openSavedPlace,
        DedaTaskEvent.addedPlaceReviewed => DedaTaskIds.reviewAddedPlace,
        DedaTaskEvent.trafficQuizCompleted => DedaTaskIds.trafficSkills,
        DedaTaskEvent.longTripCompleted => DedaTaskIds.longTrip,""",
          """        DedaTaskEvent.registeredPlaceShared => null,
        DedaTaskEvent.receivedPlaceOpened => DedaTaskIds.openReceivedPlace,
        DedaTaskEvent.savedPlaceOpened => null,
        DedaTaskEvent.addedPlaceReviewed => null,
        DedaTaskEvent.trafficQuizCompleted => DedaTaskIds.trafficSkills,
        DedaTaskEvent.longTripCompleted => null,
        DedaTaskEvent.prizeCardsExplored => DedaTaskIds.shareRegisteredPlace,
        DedaTaskEvent.placeDiscovered => DedaTaskIds.openSavedPlace,
        DedaTaskEvent.mapSearchTyped => DedaTaskIds.reviewAddedPlace,
        DedaTaskEvent.friendAccepted => DedaTaskIds.longTrip,""",
          'old task IDs retain old awards; do not reward old actions')
    s=one(s,
          "    _loadedAccountKey = accountKey;\n    _generalManagerBonusActive = false;",
          """    _loadedAccountKey = accountKey;
    DedaTaskSignalBridge.bind(
      accountKey: accountKey,
      readCurrentAccount: _accountKey,
      onFriendAccepted: () async {
        if (_loadedAccountKey != accountKey || _accountKey() != accountKey) {
          return;
        }
        await recordSuccessfulEvent(DedaTaskEvent.friendAccepted);
      },
    );
    _generalManagerBonusActive = false;""",
          'session-scoped confirmed friendship after original account opened')
    # The same-account task writer must reject old in-flight writes when
    # a new PIN account or Firebase session starts.
    s=one(s,
          """    _loadedAccountKey = accountKey;
    DedaTaskSignalBridge.bind(""",
          """    _loadedAccountKey = accountKey;
    DedaTaskWriteFence.invalidate();
    DedaTaskSignalBridge.bind(""",
          'new authenticated account epoch')

    # A late server snapshot after logout must not award the new signed-in user.
    s=one(s,
          """  static void clearSessionView() {
    _loadedAccountKey = '';""",
          """  static void clearSessionView() {
    DedaTaskSignalBridge.revoke();
    DedaTaskWriteFence.invalidate();
    _loadedAccountKey = '';""",
          'revoke pending friendship signals on account logout')

    # Null-mapped deprecated actions must never masquerade as traffic answer
    # events, which would otherwise have an empty traffic_answer dedupe ID.
    s=one(s,
          """    final taskId = taskIdForEvent(event);
    final cleanDedupe = dedupeId?.trim() ?? '';""",
          """    final taskId = taskIdForEvent(event);
    if (taskId == null && event != DedaTaskEvent.trafficQuizCorrectAnswer) {
      return DedaTaskEventResult(
        accepted: false, completedNow: false, pointsAwarded: false,
        pointsDelta: 0, totalPoints: await totalPoints(),
        taskId: null, cycleId: cycle,
      );
    }
    final cleanDedupe = dedupeId?.trim() ?? '';""",
          'reject deprecated actions without phantom traffic points')

    # Only display/access names change; the immutable claim identifiers and
    # old earned balance ledger remain unchanged.
    s=one(s,
          """          'شارك إدارة مكانك إن وجد',
          'Share place management if available',""",
          """          'تفقّد بطاقات الفوز',
          'Explore prize cards',""",
          'replace owner task title')
    s=one(s,
          """          'إن وجد، شارك إدارة مكانك بصفتك صاحب المكان',
          'If available, share management of your place',""",
          """          'افتح ملفك الشخصي وتصفّح بطاقات الفوز',
          'Open your profile and explore prize cards',""",
          'replace owner task description')
    s=one(s,"        dedaText('زيارة مكان محفوظ', 'Visit a saved place'),",
          "        dedaText('اكتشف مكاناً جديداً', 'Discover a new place'),",
          'replace saved-place title')
    s=one(s,
          """          'قم بزيارة أحد الأماكن المحفوظة لديك',
          'Visit one of your saved places',""",
          """          'افتح الخريطة واختر مكاناً للاطلاع على تفاصيله',
          'Open the map and select a place to explore',""",
          'replace saved-place description')
    s=one(s,"        dedaText('مراجعة مكان مضاف', 'Review an added place'),",
          "        dedaText('ابحث عن مكان على الخريطة', 'Search for a map place'),",
          'replace review title')
    s=one(s,
          """          'راجع تفاصيل مكان قمت بإضافته سابقًا',
          'Review a place you previously added',""",
          """          'اكتب حرفاً واحداً في خانة البحث داخل الخريطة',
          'Type one character in the map search field',""",
          'replace review description')
    s=one(s,
          """          'استفد من رحلتك الطويلة إن وجدت',
          'Use a road service on a long trip',""",
          """          'إضافة صديق',
          'Add a friend',""",
          'replace long trip title')
    # Verified restored build uses a dynamic 1000-m distance widget. The
    # new friend task must never show old trip counters or distance.
    s=one(s,"        _longTripProgressText(),",
          """        dedaText(
          'أضف صديقاً جديداً بعد قبول طلب الصداقة',
          'Add a friend after acceptance of the request',
        ),""",
          'replace old trip distance progress with friend instruction')
    s=one(s,"        dedaText('استفد', 'Use'),",
          "        dedaText('أضف', 'Add'),",
          'friend task button')
    # Redirect to existing sections without marking completed merely on open.
    s=one(s,
          """      case 2:
        if (DedaPreferences.accountType == DedaAccountType.placeOwner) {""",
          """      case 2:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const DedaAccountHubPage()),
        );
        break;
      /* Original owner-page gate kept in source for reference, never used:
        if (DedaPreferences.accountType == DedaAccountType.placeOwner) {""",
          'prize profile navigation')
    s=one(s,
          """        }
        break;
      case 3:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const SavedPlacesPage(showFavorites: true),
          ),
        );""",
          """        }
      */
      case 3:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const MapReadyPage()),
        );""",
          'place discovery navigation')
    s=one(s,
          """      case 5:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PersonalPlacesPage()),
        );""",
          """      case 5:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const MapReadyPage()),
        );""",
          'search map navigation')
    s=one(s,
          """      case 7:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const MapReadyPage()),
        );""",
          """      case 7:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const DedaSocialHubPage()),
        );""",
          'friend task navigation')
    # Viewing the cards means actually expanding the panel in profile.
    s=one(s,
          """onTap: () {
                        setState(() => _pointsExpanded = !_pointsExpanded);
                      },""",
          """onTap: () {
                        final nowVisible = !_pointsExpanded;
                        setState(() => _pointsExpanded = nowVisible);
                        if (nowVisible) {
                          unawaited(DedaTaskEngine.recordSuccessfulEvent(
                            DedaTaskEvent.prizeCardsExplored,
                          ));
                        }
                      },""",
          'count prize card panel actually expanded, never spending points')
    # Map place is selected from actual results / existing map pins.
    s=one(s,
          """  void selectMapPlace(PlaceInfo place) {
    setState(() {""",
          """  void selectMapPlace(PlaceInfo place) {
    unawaited(DedaTaskEngine.recordSuccessfulEvent(
      DedaTaskEvent.placeDiscovered,
    ));
    setState(() {""",
          'count selecting real place')
    s=one(s,
          "  final TextEditingController _mapSearchController = TextEditingController();",
          "  final TextEditingController _mapSearchController = TextEditingController();\n"
          "  bool _dedaSearchCharacterAlreadyCounted = false;",
          'count first character only once per map-open session')
    s=one(s,
          """                  controller: _mapSearchController,
                  textDirection: DedaLanguageState.direction,""",
          """                  controller: _mapSearchController,
                  onChanged: (value) {
                    if (value.trim().isNotEmpty &&
                        !_dedaSearchCharacterAlreadyCounted) {
                      _dedaSearchCharacterAlreadyCounted = true;
                      unawaited(DedaTaskEngine.recordSuccessfulEvent(
                        DedaTaskEvent.mapSearchTyped,
                      ));
                    }
                  },
                  textDirection: DedaLanguageState.direction,""",
          'count first actual map-search character')

    # Three original local reward mutators share one FIFO lane. This prevents
    # overlapping claims from erasing each other's read/modify/write result.
    # Every await that precedes persisted state + the notifier has a session
    # guard. All legacy task IDs, earned XP/coin values and award keys stay
    # byte-for-byte identical (no restored account state is rewritten here).
    def session_safe_method(code, signature, next_signature, task_expr):
        start=code.index(signature)
        # The pinned original includes extra rewarded-ad methods between
        # task claim and successful-event. Scope to EXACT method closing,
        # not to the next independently named public API.
        end=code.index("\n  }\n\n",start)+len("\n  }\n\n")
        segment=code[start:end]
        if (segment.count("    final accountKey = _accountKey();") != 1
                or segment.count("await _writeState(prefs, accountKey, state);") != 1
                or segment.count("totalPointsNotifier.value = total;") != 1
                or not segment.endswith("  }\n\n")
                or "DedaTaskWriteFence" in segment):
            raise ValueError("Unexpected original task writer "+signature+
              " ACTUAL="+repr({
                "account": segment.count("    final accountKey = _accountKey();"),
                "write":segment.count("await _writeState(prefs, accountKey, state);"),
                "notifier":segment.count("totalPointsNotifier.value = total;"),
                "tail":repr(segment[-55:]),
                "fence": "DedaTaskWriteFence" in segment,
              }))
        guard="""    final taskSessionEpoch = DedaTaskWriteFence.generation;
    bool stillOnAccount() => DedaTaskWriteFence.isCurrent(
      generation: taskSessionEpoch,
      accountKey: accountKey,
      currentAccount: _accountKey(),
      loadedAccount: _loadedAccountKey,
    );
    DedaTaskEventResult rejectStale() => DedaTaskEventResult(
      accepted: false, completedNow: false, pointsAwarded: false,
      pointsDelta: 0, totalPoints: 0,
      taskId: """+task_expr+""",
      cycleId: cycleId ?? currentLocalCycleId(occurredAt),
    );
    return DedaTaskWriteFence.serialized<DedaTaskEventResult>(
      stillCurrent: stillOnAccount,
      stale: rejectStale,
      operation: () async {
"""
        segment=segment.replace("    final accountKey = _accountKey();",
                                "    final accountKey = _accountKey();\n"+guard,1)
        segment=segment.replace("await _writeState(prefs, accountKey, state);",
                                """if (!stillOnAccount()) return rejectStale();
    await _writeState(prefs, accountKey, state);""",1)
        segment=segment.replace("    totalPointsNotifier.value = total;",
                                """    if (!stillOnAccount()) return rejectStale();
    totalPointsNotifier.value = total;""",1)
        segment=segment[:-len("  }\n\n")]+"""      },
    );
  }

"""
        return code[:start]+segment+code[end:]

    s=session_safe_method(s,
        "  static Future<DedaTaskEventResult> claimTaskReward(",
        "  static Future<DedaTaskEventResult> recordSuccessfulEvent(",
        "taskId")
    s=session_safe_method(s,
        "  static Future<DedaTaskEventResult> claimTaskRewardedAdBonus(",
        "  static Future<DedaTaskEventResult> recordSuccessfulEvent(",
        "taskId")
    s=session_safe_method(s,
        "  static Future<DedaTaskEventResult> recordSuccessfulEvent(",
        "  static String currentLocalDayId(",
        "taskIdForEvent(event)")
    s=session_safe_method(s,
        "  static Future<DedaTaskEventResult> claimDailyLoginReward(",
        "  static Future<List<Map<String, dynamic>>> recentLedger(",
        "null")

    main.write_text(s)

    social=root/'lib/deda_social_service.dart'
    a=social.read_text()
    a=one(a,"import 'deda_backend.dart';",
          "import 'dart:async';\nimport 'deda_backend.dart';\nimport 'deda_task_signal_bridge.dart';",
          'social bridge and nonblocking event import')
    start=a.index("static Future<void> respondToRequest(")
    end=a.index("static Future<void> removeRelation(",start)
    segment=a[start:end]
    # Keep the AUTH UID from the beginning of the asynchronous response.
    # The restored original social service uses a different local variable
    # name from the stand-alone source; never rely on that variable.
    if segment.count("  }) async {") != 1:
        raise ValueError('original friend response signature changed')
    segment=segment.replace("  }) async {",
      "  }) async {\n    final dedaTaskOriginUid = "
      "FirebaseAuth.instance.currentUser?.uid ?? '';",
      1)
    # Existing 100382 guard reformats Firestore update across several lines.
    # Extend ONLY the actual accepted-relationship write, after SDK success.
    pos=segment.find("await DedaSectionOperationContext.wait(() => ref.update(")
    finish=segment.find("}));",pos)
    if pos<0 or finish<0 or segment.count("ref.update(")!=1:
        raise ValueError('guarded accepted-friend write changed')
    finish+=4
    segment=segment[:finish]+"""
    if (accept) {
      await DedaTaskSignalBridge.friendAccepted(
        originatingUid: dedaTaskOriginUid,
        readCurrentUid: () => FirebaseAuth.instance.currentUser?.uid,
      );
    }"""+segment[finish:]
    a=a[:start]+segment+a[end:]
    # When another user ACCEPTS our outgoing request, the confirmed
    # friendship appears in the server stream on the next friend-page view.
    # This covers both sender and recipient, without credit for a pending request.
    start=a.index("static Stream<List<DedaFriendshipRecord>> watchRelations(")
    end=a.index("static Future<String> sendFriendRequest(",start)
    segment=a[start:end]
    marker=".listen((snapshot) {"
    if segment.count(marker)!=2:
        raise ValueError('split friend observer listeners changed')
    helper="""    void reportAcceptedToday(QuerySnapshot<Map<String, dynamic>> snapshot) {
      if (snapshot.metadata.isFromCache || snapshot.metadata.hasPendingWrites) {
        return;
      }
      final today = DateTime.now().toUtc().add(const Duration(hours: 3));
      final recent = snapshot.docs.any((doc) {
        final d = doc.data();
        final when = d['respondedAt'];
        if (d['status'] != 'accepted' || when is! Timestamp) return false;
        final day = when.toDate().toUtc().add(const Duration(hours: 3));
        return day.year == today.year &&
            day.month == today.month && day.day == today.day;
      });
      if (recent) {
        unawaited(DedaTaskSignalBridge.friendAccepted(
          originatingUid: uid,
          readCurrentUid: () => FirebaseAuth.instance.currentUser?.uid,
        ));
      }
    }

"""
    if segment.count('    void emit() {')!=1:
        raise ValueError('friend stream emit anchor changed')
    segment=segment.replace('    void emit() {',helper+'    void emit() {',1)
    segment=segment.replace(marker,marker+"\n          reportAcceptedToday(snapshot);")
    a=a[:start]+segment+a[end:]
    social.write_text(a)
    return {'preservedLegacyTaskAwardIds':True,'taskActions':4,
            'financialCodeTouched':False,'receivedPlaceUnchanged':True}
