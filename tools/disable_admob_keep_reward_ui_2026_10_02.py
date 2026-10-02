from pathlib import Path
import re

main_path = Path('lib/main.dart')
text = main_path.read_text(encoding='utf-8')

text = text.replace("import 'package:google_mobile_ads/google_mobile_ads.dart';\n", '')
text = text.replace('  await MobileAds.instance.initialize();\n', '')
text = re.sub(
    r"\n  static const String _rewardedTestAdUnitId =\n      'ca-app-pub-3940256099942544/5224354917';\n",
    '\n',
    text,
    count=1,
)

start_marker = '  Future<void> _watchTaskRewardedAd(String taskId) async {'
end_marker = '  Future<void> _openTask(int index) async {'
start = text.find(start_marker)
end = text.find(end_marker, start)
if start < 0 or end < 0:
    raise SystemExit('Rewarded ad method markers not found')

safe_method = r'''  Future<void> _watchTaskRewardedAd(String taskId) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          dedaText(
            'الإعلانات متوقفة مؤقتًا في نسخة الإصلاح. مهامك ونقاطك الأساسية تعمل بشكل طبيعي.',
            'Ads are temporarily disabled in this repair build. Your tasks and base points continue to work normally.',
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

'''
text = text[:start] + safe_method + text[end:]
main_path.write_text(text, encoding='utf-8')

pubspec = Path('pubspec.yaml')
pub = pubspec.read_text(encoding='utf-8')
pub = re.sub(r'^\s*google_mobile_ads:\s*[^\n]+\n', '', pub, flags=re.MULTILINE)
pubspec.write_text(pub, encoding='utf-8')

manifest = Path('android/app/src/main/AndroidManifest.xml')
if manifest.exists():
    m = manifest.read_text(encoding='utf-8')
    m = re.sub(
        r'\s*<meta-data\s+android:name="com\.google\.android\.gms\.ads\.APPLICATION_ID"\s+android:value="[^"]+"\s*/>\s*',
        '\n',
        m,
        flags=re.MULTILINE,
    )
    manifest.write_text(m, encoding='utf-8')

forbidden = ('google_mobile_ads', 'MobileAds.', 'RewardedAd.', 'AdRequest(', 'com.google.android.gms.ads.APPLICATION_ID')
combined = main_path.read_text(encoding='utf-8') + pubspec.read_text(encoding='utf-8')
if manifest.exists():
    combined += manifest.read_text(encoding='utf-8')
left = [token for token in forbidden if token in combined]
if left:
    raise SystemExit('AdMob runtime references remain: ' + ', '.join(left))

print('AdMob runtime disabled; rewarded task UI and base task logic preserved.')
