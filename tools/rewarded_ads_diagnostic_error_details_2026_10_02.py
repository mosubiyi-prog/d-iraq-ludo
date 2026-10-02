from pathlib import Path

path = Path('lib/main.dart')
text = path.read_text(encoding='utf-8')

old = r'''        onAdFailedToLoad: (error) {
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
'''

new = r'''        onAdFailedToLoad: (error) {
          if (!mounted) return;
          setState(() => _watchingRewardedTaskIds.remove(taskId));
          final details = dedaText(
            'فشل تحميل إعلان الاختبار.\nالكود: ${error.code}\nالنطاق: ${error.domain}\nالرسالة: ${error.message}',
            'Test ad failed to load.\nCode: ${error.code}\nDomain: ${error.domain}\nMessage: ${error.message}',
          );
          showDialog<void>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: Text(
                dedaText('تفاصيل خطأ الإعلان', 'Ad error details'),
                textAlign: TextAlign.center,
              ),
              content: SelectableText(
                details,
                textAlign: TextAlign.start,
              ),
              actionsAlignment: MainAxisAlignment.center,
              actions: [
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(dedaText('موافق', 'OK')),
                ),
              ],
            ),
          );
        },
'''

count = text.count(old)
if count != 1:
    raise SystemExit(f'Expected exactly one rewarded-ad load failure callback, found {count}')

text = text.replace(old, new, 1)
path.write_text(text, encoding='utf-8')
print('Rewarded ad load failure now shows code, domain and message for diagnosis.')
