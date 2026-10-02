from pathlib import Path

main = Path('lib/main.dart').read_text(encoding='utf-8')
pubspec = Path('pubspec.yaml').read_text(encoding='utf-8')

required_main_markers = [
    "import 'package:google_mobile_ads/google_mobile_ads.dart';",
    'await MobileAds.instance.initialize();',
    'isTaskRewardedAdBonusClaimed(',
    'claimTaskRewardedAdBonus(',
    "'rewarded_ad|$cycle|$taskId'",
    "'rewarded_ad_completed'",
    "'ca-app-pub-3940256099942544/5224354917'",
    'RewardedAd.load(',
    'onUserEarnedReward:',
    'شاهد الإعلان حتى النهاية وخذ +5 نقاط إضافية',
    'تم استلام +5 نقاط إضافية',
    '_watchingRewardedTaskIds',
]

missing = [marker for marker in required_main_markers if marker not in main]
if missing:
    raise SystemExit('Missing rewarded-ad markers: ' + ' | '.join(missing))

if 'google_mobile_ads:' not in pubspec:
    raise SystemExit('google_mobile_ads dependency missing from pubspec.yaml')

# Safety: there must be exactly one reward id scheme and the bonus must remain +5.
if main.count("'rewarded_ad|$cycle|$taskId'") != 2:
    raise SystemExit('Unexpected rewarded-ad award-key marker count')
if 'pointsDelta = pointsPerTask;' not in main:
    raise SystemExit('Rewarded bonus no longer follows pointsPerTask')

print('DEDA task rewarded-ad test validation passed.')
