from pathlib import Path

MAIN = Path('lib/main.dart')
MANIFEST = Path('android/app/src/main/AndroidManifest.xml')

REAL_APP_ID = 'ca-app-pub-2512641627784244~4635932278'
REAL_REWARDED_ID = 'ca-app-pub-2512641627784244/6037567292'
TEST_APP_ID = 'ca-app-pub-3940256099942544~3347511713'
TEST_REWARDED_ID = 'ca-app-pub-3940256099942544/5224354917'

main = MAIN.read_text(encoding='utf-8')
manifest = MANIFEST.read_text(encoding='utf-8')

if TEST_REWARDED_ID not in main:
    raise SystemExit('Expected Google rewarded test unit ID was not found before real-ID switch')
if TEST_APP_ID not in manifest:
    raise SystemExit('Expected Google sample App ID was not found before real-ID switch')

main = main.replace(TEST_REWARDED_ID, REAL_REWARDED_ID)
main = main.replace('_rewardedTestAdUnitId', '_rewardedAdUnitId')
main = main.replace('تعذر عرض إعلان الاختبار الآن. حاول مرة أخرى.', 'تعذر عرض الإعلان الآن. حاول مرة أخرى.')
main = main.replace('The test ad could not be shown. Please try again.', 'The ad could not be shown. Please try again.')
main = main.replace('تعذر تجهيز إعلان الاختبار الآن. حاول مرة أخرى.', 'تعذر تجهيز الإعلان الآن. حاول مرة أخرى.')
main = main.replace('The test ad could not be loaded. Please try again.', 'The ad could not be loaded. Please try again.')

manifest = manifest.replace(TEST_APP_ID, REAL_APP_ID)

MAIN.write_text(main, encoding='utf-8')
MANIFEST.write_text(manifest, encoding='utf-8')
print('Build 100257 switched from Google test IDs to DEDA real AdMob IDs.')
