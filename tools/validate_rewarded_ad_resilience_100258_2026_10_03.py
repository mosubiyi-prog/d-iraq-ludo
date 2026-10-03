from pathlib import Path

text = Path('lib/main.dart').read_text(encoding='utf-8')

required = [
    "RewardedAd? _preparedRewardedAd;",
    "Future<bool>? _rewardedAdLoadFuture;",
    "_preloadRewardedAdWithRetry",
    "Duration(seconds: 2)",
    "Duration(seconds: 5)",
    "Duration(seconds: 10)",
    "Duration(minutes: 1)",
    "_queueRewardedAdPreload();",
    "تعذر تجهيز الإعلان الآن. حاول مرة أخرى بعد قليل.",
    "DEDA rewarded ad load failed:",
    "DEDA rewarded ad show failed:",
    "ca-app-pub-2512641627784244/6037567292",
    "if (rewardClaimed && !rewardedBonusClaimed)",
]

for marker in required:
    if marker not in text:
        raise SystemExit(f'Missing 100258 rewarded-ad resilience marker: {marker}')

forbidden = [
    "تفاصيل خطأ الإعلان",
    "فشل تحميل إعلان الاختبار.",
    "ca-app-pub-3940256099942544/5224354917",
]

for marker in forbidden:
    if marker in text:
        raise SystemExit(f'Forbidden legacy/test rewarded-ad marker remains: {marker}')

if text.count("Future<void> _watchTaskRewardedAd(String taskId) async") != 1:
    raise SystemExit('Expected exactly one rewarded-ad watch method')

if text.count("RewardedAd.load(") != 1:
    raise SystemExit('Expected exactly one centralized RewardedAd.load call')

if text.count("_preparedRewardedAd?.dispose();") < 1:
    raise SystemExit('Prepared rewarded ad is not disposed with the page state')

print('Build 100258 rewarded-ad resilience validation passed.')
