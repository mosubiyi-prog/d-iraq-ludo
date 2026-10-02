from pathlib import Path

path = Path('lib/main.dart')
text = path.read_text(encoding='utf-8')

startup = '  await MobileAds.instance.initialize();\n'
if startup not in text:
    raise SystemExit('Expected startup MobileAds initialization was not found')
text = text.replace(startup, '', 1)

old = '''    setState(() => _watchingRewardedTaskIds.add(taskId));

    RewardedAd.load(
'''
new = '''    setState(() => _watchingRewardedTaskIds.add(taskId));

    try {
      await MobileAds.instance.initialize();
    } catch (_) {
      if (!mounted) return;
      setState(() => _watchingRewardedTaskIds.remove(taskId));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            dedaText(
              'تعذر تهيئة إعلان الاختبار الآن. التطبيق سيبقى يعمل بشكل طبيعي.',
              'The test ad could not be initialized. The app will keep working normally.',
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
      return;
    }

    RewardedAd.load(
'''
if text.count(old) != 1:
    raise SystemExit(f'Expected one rewarded-ad load marker, found {text.count(old)}')
text = text.replace(old, new, 1)

path.write_text(text, encoding='utf-8')
print('Moved Mobile Ads initialization out of app startup and into rewarded-ad action with failure isolation.')
