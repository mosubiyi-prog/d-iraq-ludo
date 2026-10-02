from pathlib import Path
import re

main = Path('lib/main.dart').read_text(encoding='utf-8')
quiz = Path('lib/traffic_quiz_page.dart').read_text(encoding='utf-8')
pub = Path('pubspec.yaml').read_text(encoding='utf-8')

assert 'google_mobile_ads: 9.1.0' in pub
assert "import 'package:google_mobile_ads/google_mobile_ads.dart';" in main
assert main.count('MobileAds.instance.initialize()') == 1

watch_start = main.find('  Future<void> _watchTaskRewardedAd(String taskId) async {')
watch_end = main.find('  Future<void> _openTask(int index) async {', watch_start)
assert watch_start >= 0 and watch_end > watch_start
watch_block = main[watch_start:watch_end]
assert 'await MobileAds.instance.initialize();' in watch_block
assert 'RewardedAd.load(' in watch_block
assert 'onUserEarnedReward:' in watch_block
assert main.find('MobileAds.instance.initialize()') >= watch_start

# Exactly one rewarded-ad button definition and one placement call.
# The placement call is inside the generic daily-task card, so daily login stays excluded.
assert main.count('_taskRewardedAdButton(') == 2
card_start = main.find('  Widget _taskCard({')
assert card_start >= 0
card_end = main.find('\n  @override\n  Widget build(', card_start)
if card_end < 0:
    card_end = len(main)
card_block = main[card_start:card_end]
assert '_taskRewardedAdButton(' in card_block
assert 'if (rewardClaimed) ...[' in card_block

# DEDA daily task list must remain exactly eight task fields.
tasks_marker = 'final tasks = <(IconData, String, String, String)>['
tasks_start = main.find(tasks_marker)
assert tasks_start >= 0
search_from = tasks_start + len(tasks_marker)
tasks_end = main.find('\n    ];', search_from)
assert tasks_end > search_from
tasks_block = main[search_from:tasks_end]
count = len(re.findall(r'(?m)^\s{6}\($', tasks_block))
assert count == 8, f'Expected 8 daily task cards, found {count}'

# Ads are forbidden inside the traffic quiz / traffic guidance page itself.
for token in ('google_mobile_ads', 'RewardedAd', 'MobileAds', '_taskRewardedAdButton'):
    assert token not in quiz, f'Forbidden ad token in traffic quiz page: {token}'

print('Rewarded ads scope validated: 8 daily task cards only; daily login and traffic quiz page excluded.')
