from pathlib import Path

path = Path('lib/main.dart')
text = path.read_text(encoding='utf-8')


def replace_once(old: str, new: str, label: str) -> None:
    global text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected exactly one match, found {count}')
    text = text.replace(old, new, 1)


replace_once(
    "import 'package:image_picker/image_picker.dart';\n",
    "import 'package:image_picker/image_picker.dart';\nimport 'package:google_mobile_ads/google_mobile_ads.dart';\n",
    'google_mobile_ads import',
)

replace_once(
    "Future<void> main() async {\n  WidgetsFlutterBinding.ensureInitialized();\n",
    "Future<void> main() async {\n  WidgetsFlutterBinding.ensureInitialized();\n  await MobileAds.instance.initialize();\n",
    'Mobile Ads initialization',
)

engine_marker = "  static Future<DedaTaskEventResult> recordSuccessfulEvent(\n"
engine_methods = r'''  static Future<bool> isTaskRewardedAdBonusClaimed(
    String taskId, {
    String? cycleId,
  }) async {
    final accountKey = _accountKey();
    if (accountKey.isEmpty) return false;
    final prefs = await SharedPreferences.getInstance();
    final state = await _readState(prefs, accountKey);
    final awards = Map<String, dynamic>.from(state['awards'] as Map);
    final cycle = cycleId ?? currentLocalCycleId();
    return awards.containsKey('rewarded_ad|$cycle|$taskId');
  }

  static Future<DedaTaskEventResult> claimTaskRewardedAdBonus(
    String taskId, {
    DateTime? occurredAt,
    String? cycleId,
  }) async {
    final accountKey = _accountKey();
    final cycle = cycleId ?? currentLocalCycleId(occurredAt);
    if (accountKey.isEmpty) {
      return DedaTaskEventResult(
        accepted: false,
        completedNow: false,
        pointsAwarded: false,
        pointsDelta: 0,
        totalPoints: 0,
        taskId: taskId,
        cycleId: cycle,
      );
    }

    final prefs = await SharedPreferences.getInstance();
    final state = await _readState(prefs, accountKey);
    final awards = Map<String, dynamic>.from(state['awards'] as Map);
    final ledger = List<dynamic>.from(state['ledger'] as List);
    final baseAwardId = 'task|$cycle|$taskId';
    final bonusAwardId = 'rewarded_ad|$cycle|$taskId';
    final baseRewardClaimed = awards.containsKey(baseAwardId);
    final alreadyAwarded = awards.containsKey(bonusAwardId);

    // The ad bonus is available only after the original +5 task reward was
    // claimed. This keeps the reward order explicit and prevents ad-only points.
    if (!baseRewardClaimed) {
      return DedaTaskEventResult(
        accepted: false,
        completedNow: false,
        pointsAwarded: false,
        pointsDelta: 0,
        totalPoints: _effectiveTotalFromState(state),
        taskId: taskId,
        cycleId: cycle,
      );
    }

    var pointsDelta = 0;
    if (!alreadyAwarded) {
      pointsDelta = pointsPerTask;
      final now = (occurredAt ?? DateTime.now()).toUtc().toIso8601String();
      final award = <String, dynamic>{
        'id': bonusAwardId,
        'points': pointsDelta,
        'type': 'rewarded_ad_bonus',
        'event': 'rewarded_ad_completed',
        'cycleId': cycle,
        'taskId': taskId,
        'createdAt': now,
      };
      awards[bonusAwardId] = award;
      ledger.add(award);
      if (ledger.length > _maxLedgerEntries) {
        ledger.removeRange(0, ledger.length - _maxLedgerEntries);
      }
      state['awards'] = awards;
      state['ledger'] = ledger;
      await _writeState(prefs, accountKey, state);
    }

    final total = _effectiveTotalFromState(state);
    _loadedAccountKey = accountKey;
    totalPointsNotifier.value = total;
    revisionNotifier.value++;

    return DedaTaskEventResult(
      accepted: true,
      completedNow: false,
      pointsAwarded: !alreadyAwarded,
      pointsDelta: pointsDelta,
      totalPoints: total,
      taskId: taskId,
      cycleId: cycle,
    );
  }

'''
replace_once(engine_marker, engine_methods + engine_marker, 'rewarded ad engine methods')

replace_once(
    "  final Set<String> _claimingTaskIds = <String>{};\n",
    "  final Set<String> _claimingTaskIds = <String>{};\n  final Set<String> _watchingRewardedTaskIds = <String>{};\n  static const String _rewardedTestAdUnitId =\n      'ca-app-pub-3940256099942544/5224354917';\n",
    'rewarded ad page state',
)

watch_method = r'''  Future<void> _watchTaskRewardedAd(String taskId) async {
    if (_watchingRewardedTaskIds.contains(taskId)) return;

    final alreadyClaimed =
        await DedaTaskEngine.isTaskRewardedAdBonusClaimed(taskId);
    if (!mounted) return;
    if (alreadyClaimed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            dedaText(
              'تم استلام مكافأة الإعلان لهذه المهمة اليوم مسبقًا.',
              'This task ad bonus was already claimed today.',
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          dedaText('مكافأة إضافية', 'Extra reward'),
          textAlign: TextAlign.center,
        ),
        content: Text(
          dedaText(
            'شاهد الإعلان حتى نقطة الاستحقاق لتحصل على +5 نقاط لهذه المهمة. إذا أغلقت الإعلان قبل اكتماله فلن تضاف النقاط.',
            'Watch the ad until the reward point to get +5 points for this task. Closing it early will not add the bonus.',
          ),
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(dedaText('إلغاء', 'Cancel')),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.play_circle_fill_rounded),
            label: Text(dedaText('شاهد الإعلان', 'Watch ad')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _watchingRewardedTaskIds.add(taskId));

    RewardedAd.load(
      adUnitId: _rewardedTestAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          if (!mounted) {
            ad.dispose();
            return;
          }

          var rewardEarned = false;
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (closedAd) {
              closedAd.dispose();
              if (!mounted) return;
              setState(() => _watchingRewardedTaskIds.remove(taskId));
              if (!rewardEarned) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      dedaText(
                        'لم تكتمل مشاهدة الإعلان، لذلك لم تتم إضافة النقاط الإضافية.',
                        'The ad was not completed, so the extra points were not added.',
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }
            },
            onAdFailedToShowFullScreenContent: (failedAd, error) {
              failedAd.dispose();
              if (!mounted) return;
              setState(() => _watchingRewardedTaskIds.remove(taskId));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    dedaText(
                      'تعذر عرض إعلان الاختبار الآن. حاول مرة أخرى.',
                      'The test ad could not be shown. Please try again.',
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            },
          );

          ad.show(
            onUserEarnedReward: (shownAd, reward) async {
              rewardEarned = true;
              final result =
                  await DedaTaskEngine.claimTaskRewardedAdBonus(taskId);
              if (!mounted) return;
              setState(() => _watchingRewardedTaskIds.remove(taskId));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    result.pointsAwarded
                        ? dedaText(
                            'تمت مشاهدة الإعلان وإضافة +5 نقاط إلى رصيدك.',
                            'Ad completed. +5 points were added to your balance.',
                          )
                        : dedaText(
                            'تم استلام مكافأة الإعلان لهذه المهمة مسبقًا.',
                            'This task ad bonus was already claimed.',
                          ),
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            },
          );
        },
        onAdFailedToLoad: (error) {
          if (!mounted) return;
          setState(() => _watchingRewardedTaskIds.remove(taskId));
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                dedaText(
                  'تعذر تجهيز إعلان الاختبار الآن. حاول مرة أخرى.',
                  'The test ad could not be loaded. Please try again.',
                ),
                textAlign: TextAlign.center,
              ),
            ),
          );
        },
      ),
    );
  }

'''
replace_once(
    "  Future<void> _openTask(int index) async {\n",
    watch_method + "  Future<void> _openTask(int index) async {\n",
    'rewarded ad watch method',
)

reward_button = r'''  Widget _taskRewardedAdButton({
    required String taskId,
    required bool bonusClaimed,
    required bool watching,
  }) {
    final foreground = bonusClaimed
        ? const Color(0xFF0A7A4B)
        : const Color(0xFF6A4A00);
    final background = bonusClaimed
        ? const Color(0xFFE2F1E8)
        : const Color(0xFFFFF3C9);
    final border = bonusClaimed
        ? const Color(0xFF8EC5A6)
        : const Color(0xFFE0B74C);

    return SizedBox(
      width: double.infinity,
      height: 30,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: border, width: 0.8),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: bonusClaimed || watching
                ? null
                : () => _watchTaskRewardedAd(taskId),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 7),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (watching)
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.7,
                        color: foreground,
                      ),
                    )
                  else
                    Icon(
                      bonusClaimed
                          ? Icons.check_circle_rounded
                          : Icons.ondemand_video_rounded,
                      size: 15,
                      color: foreground,
                    ),
                  const SizedBox(width: 5),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        watching
                            ? dedaText(
                                'جاري تجهيز الإعلان...',
                                'Preparing ad...',
                              )
                            : bonusClaimed
                                ? dedaText(
                                    'تم استلام +5 نقاط إضافية',
                                    '+5 bonus points claimed',
                                  )
                                : dedaText(
                                    'شاهد الإعلان حتى النهاية وخذ +5 نقاط إضافية',
                                    'Watch the ad and get +5 bonus points',
                                  ),
                        maxLines: 1,
                        style: TextStyle(
                          color: foreground,
                          fontSize: 10.2,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

'''
replace_once(
    "  Widget _taskCard({\n",
    reward_button + "  Widget _taskCard({\n",
    'rewarded ad button widget',
)

replace_once(
    "    required bool rewardClaimed,\n    required bool claiming,\n  }) {\n",
    "    required bool rewardClaimed,\n    required bool rewardedBonusClaimed,\n    required bool claiming,\n    required bool watchingRewardedAd,\n  }) {\n",
    'task card rewarded parameters',
)

replace_once(
    "                        _taskClaimButton(\n                          taskId: taskId,\n                          completed: completed,\n                          rewardClaimed: rewardClaimed,\n                          claiming: claiming,\n                        ),\n                      ],\n                    ),\n                  ],\n",
    "                        _taskClaimButton(\n                          taskId: taskId,\n                          completed: completed,\n                          rewardClaimed: rewardClaimed,\n                          claiming: claiming,\n                        ),\n                      ],\n                    ),\n                    if (rewardClaimed) ...[\n                      const SizedBox(height: 5),\n                      _taskRewardedAdButton(\n                        taskId: taskId,\n                        bonusClaimed: rewardedBonusClaimed,\n                        watching: watchingRewardedAd,\n                      ),\n                    ],\n                  ],\n",
    'task card rewarded row',
)

replace_once(
    "                                future: Future.wait<bool>([\n                                  DedaTaskEngine.isTaskCompleted(taskId),\n                                  DedaTaskEngine.isTaskRewardClaimed(taskId),\n                                ]),\n",
    "                                future: Future.wait<bool>([\n                                  DedaTaskEngine.isTaskCompleted(taskId),\n                                  DedaTaskEngine.isTaskRewardClaimed(taskId),\n                                  DedaTaskEngine.isTaskRewardedAdBonusClaimed(\n                                    taskId,\n                                  ),\n                                ]),\n",
    'rewarded state future',
)

replace_once(
    "                                  final rewardClaimed =\n                                      values != null && values.length > 1\n                                          ? values[1]\n                                          : false;\n",
    "                                  final rewardClaimed =\n                                      values != null && values.length > 1\n                                          ? values[1]\n                                          : false;\n                                  final rewardedBonusClaimed =\n                                      values != null && values.length > 2\n                                          ? values[2]\n                                          : false;\n",
    'rewarded state value',
)

replace_once(
    "                                      completed: completed,\n                                      rewardClaimed: rewardClaimed,\n                                      claiming:\n                                          _claimingTaskIds.contains(taskId),\n",
    "                                      completed: completed,\n                                      rewardClaimed: rewardClaimed,\n                                      rewardedBonusClaimed:\n                                          rewardedBonusClaimed,\n                                      claiming:\n                                          _claimingTaskIds.contains(taskId),\n                                      watchingRewardedAd:\n                                          _watchingRewardedTaskIds.contains(\n                                        taskId,\n                                      ),\n",
    'task card rewarded arguments',
)

path.write_text(text, encoding='utf-8')
print('DEDA task rewarded-ad test patch applied successfully.')
