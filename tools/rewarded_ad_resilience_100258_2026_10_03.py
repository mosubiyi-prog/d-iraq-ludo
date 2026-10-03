from pathlib import Path

path = Path('lib/main.dart')
text = path.read_text(encoding='utf-8')

state_marker = "  final Set<String> _watchingRewardedTaskIds = <String>{};\n  static const String _rewardedAdUnitId =\n"
state_replacement = "  final Set<String> _watchingRewardedTaskIds = <String>{};\n  RewardedAd? _preparedRewardedAd;\n  Future<bool>? _rewardedAdLoadFuture;\n  bool _rewardedAdRetryLoopRunning = false;\n  DateTime? _rewardedAdNextAutomaticAttemptAt;\n  static const String _rewardedAdUnitId =\n"
if text.count(state_marker) != 1:
    raise SystemExit('Expected exactly one rewarded-ad state marker')
text = text.replace(state_marker, state_replacement, 1)

init_marker = "  @override\n  void initState() {\n    super.initState();\n    _loadRewardState();\n  }\n"
init_replacement = init_marker + "\n  @override\n  void dispose() {\n    _preparedRewardedAd?.dispose();\n    _preparedRewardedAd = null;\n    super.dispose();\n  }\n"
if text.count(init_marker) != 1:
    raise SystemExit('Expected exactly one daily-tasks initState marker')
text = text.replace(init_marker, init_replacement, 1)

start_marker = "  Future<void> _watchTaskRewardedAd(String taskId) async {\n"
end_marker = "  Future<void> _openTask(int index) async {\n"
start = text.find(start_marker)
if start < 0:
    raise SystemExit('Rewarded-ad watch method start not found')
end = text.find(end_marker, start)
if end < 0:
    raise SystemExit('Rewarded-ad watch method end marker not found')

methods = r'''  Future<bool> _loadRewardedAdOnce() {
    if (_preparedRewardedAd != null) {
      return Future<bool>.value(true);
    }

    final inFlight = _rewardedAdLoadFuture;
    if (inFlight != null) return inFlight;

    final completer = Completer<bool>();
    _rewardedAdLoadFuture = completer.future;

    RewardedAd.load(
      adUnitId: _rewardedAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedAdLoadFuture = null;
          if (!mounted) {
            ad.dispose();
            if (!completer.isCompleted) completer.complete(false);
            return;
          }

          _preparedRewardedAd?.dispose();
          _preparedRewardedAd = ad;
          _rewardedAdNextAutomaticAttemptAt = null;
          if (!completer.isCompleted) completer.complete(true);
        },
        onAdFailedToLoad: (error) {
          _rewardedAdLoadFuture = null;
          debugPrint(
            'DEDA rewarded ad load failed: '
            'code=${error.code}, domain=${error.domain}, message=${error.message}',
          );
          if (!completer.isCompleted) completer.complete(false);
        },
      ),
    );

    return completer.future;
  }

  Future<void> _preloadRewardedAdWithRetry({bool force = false}) async {
    if (_preparedRewardedAd != null || _rewardedAdRetryLoopRunning) return;

    final nextAttempt = _rewardedAdNextAutomaticAttemptAt;
    if (!force &&
        nextAttempt != null &&
        DateTime.now().isBefore(nextAttempt)) {
      return;
    }

    _rewardedAdRetryLoopRunning = true;
    var loaded = false;
    const retryDelays = <Duration>[
      Duration.zero,
      Duration(seconds: 2),
      Duration(seconds: 5),
      Duration(seconds: 10),
    ];

    try {
      for (final delay in retryDelays) {
        if (!mounted || _preparedRewardedAd != null) {
          loaded = _preparedRewardedAd != null;
          break;
        }

        if (delay > Duration.zero) {
          await Future<void>.delayed(delay);
          if (!mounted || _preparedRewardedAd != null) {
            loaded = _preparedRewardedAd != null;
            break;
          }
        }

        loaded = await _loadRewardedAdOnce();
        if (loaded) break;
      }
    } finally {
      _rewardedAdRetryLoopRunning = false;
      if (!loaded && mounted && _preparedRewardedAd == null) {
        _rewardedAdNextAutomaticAttemptAt =
            DateTime.now().add(const Duration(minutes: 1));
      }
    }
  }

  void _queueRewardedAdPreload() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _preloadRewardedAdWithRetry();
    });
  }

  void _showRewardedAdUnavailableMessage() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          dedaText(
            'تعذر تجهيز الإعلان الآن. حاول مرة أخرى بعد قليل.',
            'The ad could not be prepared right now. Please try again shortly.',
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Future<void> _watchTaskRewardedAd(String taskId) async {
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

    var ad = _preparedRewardedAd;
    if (ad == null) {
      final loaded = await _loadRewardedAdOnce();
      if (!mounted) return;
      if (!loaded) {
        setState(() => _watchingRewardedTaskIds.remove(taskId));
        _showRewardedAdUnavailableMessage();
        _rewardedAdNextAutomaticAttemptAt = null;
        _preloadRewardedAdWithRetry(force: true);
        return;
      }
      ad = _preparedRewardedAd;
    }

    if (ad == null) {
      if (mounted) {
        setState(() => _watchingRewardedTaskIds.remove(taskId));
      }
      _showRewardedAdUnavailableMessage();
      return;
    }

    _preparedRewardedAd = null;
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
        _rewardedAdNextAutomaticAttemptAt = null;
        _queueRewardedAdPreload();
      },
      onAdFailedToShowFullScreenContent: (failedAd, error) {
        failedAd.dispose();
        debugPrint(
          'DEDA rewarded ad show failed: '
          'code=${error.code}, domain=${error.domain}, message=${error.message}',
        );
        if (!mounted) return;
        setState(() => _watchingRewardedTaskIds.remove(taskId));
        _showRewardedAdUnavailableMessage();
        _rewardedAdNextAutomaticAttemptAt = null;
        _queueRewardedAdPreload();
      },
    );

    ad.show(
      onUserEarnedReward: (shownAd, reward) async {
        rewardEarned = true;
        final result = await DedaTaskEngine.claimTaskRewardedAdBonus(taskId);
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
  }

'''

text = text[:start] + methods + text[end:]

card_start = text.find("  Widget _taskCard({\n")
if card_start < 0:
    raise SystemExit('Task card method not found')
card_body = text.find("  }) {\n", card_start)
if card_body < 0:
    raise SystemExit('Task card body start not found')
signature = text[card_start:card_body]
if 'required bool rewardedBonusClaimed' not in signature:
    raise SystemExit('Rewarded bonus flag missing from task-card signature')

preload_hook = "    if (rewardClaimed && !rewardedBonusClaimed) {\n      _queueRewardedAdPreload();\n    }\n\n"
insert_at = card_body + len("  }) {\n")
text = text[:insert_at] + preload_hook + text[insert_at:]

for forbidden in (
    "dedaText('تفاصيل خطأ الإعلان', 'Ad error details')",
    "'فشل تحميل إعلان الاختبار.",
):
    if forbidden in text:
        raise SystemExit(f'Legacy technical rewarded-ad dialog remains: {forbidden}')

path.write_text(text, encoding='utf-8')
print('DEDA rewarded-ad preload, retry and user-safe error handling applied for 100258.')
