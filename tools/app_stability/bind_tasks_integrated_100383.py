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
    main=root/'lib/main.dart'
    s=main.read_text()
    s=one(s, "import 'traffic_quiz_page.dart';",
          "import 'traffic_quiz_page.dart';\nimport 'deda_task_signal_bridge.dart';",
          'bridge import')
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
    DedaTaskSignalBridge.onFriendAccepted = () async {
      await recordSuccessfulEvent(DedaTaskEvent.friendAccepted);
    };
    _generalManagerBonusActive = false;""",
          'confirmed friend signal when account initialized')
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
    main.write_text(s)

    social=root/'lib/deda_social_service.dart'
    a=social.read_text()
    a=one(a,"import 'deda_backend.dart';",
          "import 'dart:async';\nimport 'deda_backend.dart';\nimport 'deda_task_signal_bridge.dart';",
          'social bridge and nonblocking event import')
    start=a.index("static Future<void> respondToRequest(")
    end=a.index("static Future<void> removeRelation(",start)
    segment=a[start:end]
    # Existing 100382 guard reformats Firestore update across several lines.
    # Extend ONLY the actual accepted-relationship write, after SDK success.
    pos=segment.find("await DedaSectionOperationContext.wait(() => ref.update(")
    finish=segment.find("}));",pos)
    if pos<0 or finish<0 or segment.count("ref.update(")!=1:
        raise ValueError('guarded accepted-friend write changed')
    finish+=4
    segment=segment[:finish]+"""
    if (accept) {
      await DedaTaskSignalBridge.friendAccepted();
    }"""+segment[finish:]
    a=a[:start]+segment+a[end:]
    # When another user ACCEPTS our outgoing request, the confirmed
    # friendship appears in the server stream on the next friend-page view.
    # This covers both sender and recipient, without credit for a pending request.
    liveMark="      final items = snapshot.docs"
    if a.count(liveMark)!=1:
        p=a.find("static Stream<List<DedaFriendshipRecord>> watchRelations(")
        print('FRIEND_WATCH_SHAPE',repr(a[p:p+2500]))
        raise ValueError('friendship verified observer source changed')
    a=a.replace(liveMark,"""      if (!snapshot.metadata.isFromCache &&
          !snapshot.metadata.hasPendingWrites) {
        final today = DateTime.now().toLocal();
        final acceptedToday = snapshot.docs.any((doc) {
          final data = doc.data();
          final when = data['respondedAt'];
          if (data['status'] != 'accepted' || when is! Timestamp) return false;
          final local = when.toDate().toLocal();
          return local.year == today.year &&
              local.month == today.month && local.day == today.day;
        });
        if (acceptedToday) {
          unawaited(DedaTaskSignalBridge.friendAccepted());
        }
      }
      final items = snapshot.docs""",1)
    social.write_text(a)
    return {'preservedLegacyTaskAwardIds':True,'taskActions':4,
            'financialCodeTouched':False,'receivedPlaceUnchanged':True}
