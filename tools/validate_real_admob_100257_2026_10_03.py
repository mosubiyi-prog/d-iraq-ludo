from pathlib import Path

main = Path('lib/main.dart').read_text(encoding='utf-8')
manifest = Path('android/app/src/main/AndroidManifest.xml').read_text(encoding='utf-8')
pubspec = Path('pubspec.yaml').read_text(encoding='utf-8')

REAL_APP_ID = 'ca-app-pub-2512641627784244~4635932278'
REAL_REWARDED_ID = 'ca-app-pub-2512641627784244/6037567292'
TEST_APP_ID = 'ca-app-pub-3940256099942544~3347511713'
TEST_REWARDED_ID = 'ca-app-pub-3940256099942544/5224354917'

required_main = [
    "import 'package:google_mobile_ads/google_mobile_ads.dart';",
    'await MobileAds.instance.initialize();',
    'RewardedAd.load(',
    'onUserEarnedReward:',
    REAL_REWARDED_ID,
    '_rewardedAdUnitId',
    'claimTaskRewardedAdBonus(',
    'pointsDelta = pointsPerTask;',
    'شاهد الإعلان حتى النهاية وخذ +5 نقاط إضافية',
]
for marker in required_main:
    if marker not in main:
        raise SystemExit(f'Missing real-AdMob marker: {marker}')

if REAL_APP_ID not in manifest:
    raise SystemExit('Real DEDA AdMob App ID missing from AndroidManifest.xml')
if 'com.google.android.gms.ads.APPLICATION_ID' not in manifest:
    raise SystemExit('AdMob APPLICATION_ID metadata missing from AndroidManifest.xml')
if 'google_mobile_ads: 9.1.0' not in pubspec:
    raise SystemExit('Expected google_mobile_ads dependency version missing')

for forbidden in (TEST_APP_ID, TEST_REWARDED_ID, '_rewardedTestAdUnitId'):
    if forbidden in main or forbidden in manifest:
        raise SystemExit(f'Test AdMob marker leaked into closed-testing build: {forbidden}')

for forbidden_text in (
    'تعذر عرض إعلان الاختبار الآن',
    'تعذر تجهيز إعلان الاختبار الآن',
    'The test ad could not be shown',
    'The test ad could not be loaded',
):
    if forbidden_text in main:
        raise SystemExit(f'Test-ad wording leaked into closed-testing build: {forbidden_text}')

# Reward stays exactly +5 and remains granted only by the rewarded callback.
if main.count('onUserEarnedReward:') != 1:
    raise SystemExit('Unexpected rewarded callback count')
if "'rewarded_ad|$cycle|$taskId'" not in main:
    raise SystemExit('Rewarded-ad daily/task award key missing')
if 'pointsDelta = pointsPerTask;' not in main:
    raise SystemExit('Rewarded bonus no longer follows +5 task points')

print('Build 100257 real AdMob IDs and rewarded-ad invariants validated.')
