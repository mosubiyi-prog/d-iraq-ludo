from pathlib import Path

path = Path('tools/task_rewarded_ads_test_2026_10_02.py')
text = path.read_text(encoding='utf-8')

old = '''replace_once(
    "    required bool rewardClaimed,\\n    required bool claiming,\\n  }) {\\n",
    "    required bool rewardClaimed,\\n    required bool rewardedBonusClaimed,\\n    required bool claiming,\\n    required bool watchingRewardedAd,\\n  }) {\\n",
    'task card rewarded parameters',
)
'''

new = '''replace_once(
    "  Widget _taskCard({\\n    required int index,\\n    required String taskId,\\n    required IconData icon,\\n    required String title,\\n    required String subtitle,\\n    required String action,\\n    required bool completed,\\n    required bool rewardClaimed,\\n    required bool claiming,\\n  }) {\\n",
    "  Widget _taskCard({\\n    required int index,\\n    required String taskId,\\n    required IconData icon,\\n    required String title,\\n    required String subtitle,\\n    required String action,\\n    required bool completed,\\n    required bool rewardClaimed,\\n    required bool rewardedBonusClaimed,\\n    required bool claiming,\\n    required bool watchingRewardedAd,\\n  }) {\\n",
    'task card rewarded parameters',
)
'''

count = text.count(old)
if count != 1:
    raise SystemExit(f'expected one loose task-card parameter patch block, found {count}')

path.write_text(text.replace(old, new, 1), encoding='utf-8')
print('Rewarded-ad patch targeting tightened to the unique _taskCard signature.')
