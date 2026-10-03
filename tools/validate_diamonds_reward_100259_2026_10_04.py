from pathlib import Path

text = Path('lib/main.dart').read_text(encoding='utf-8')

checks = {
    'wallet': 'class DedaDiamondsWallet',
    'reward=3': 'static const int rewardPerAd = 3;',
    'daily ads=5': 'static const int maxAdsPerDay = 5;',
    'profile card': 'Widget _diamondsBalanceCard(int diamonds)',
    'tasks card': 'Widget _diamondsRewardCard()',
    'success message': 'تم منحك 3 ماسات بنجاح 💎',
    'no reward message': 'لم تكتمل مشاهدة الإعلان، لذلك لم تتم إضافة الماسات.',
    'profile navigation': 'MaterialPageRoute(builder: (_) => const DedaAccountHubPage())',
    'existing task reward survives': 'تمت مشاهدة الإعلان وإضافة +5 نقاط إلى رصيدك.',
    'real rewarded unit survives': 'ca-app-pub-2512641627784244/6037567292',
}
missing = [name for name, needle in checks.items() if needle not in text]
if missing:
    raise SystemExit('Missing 100259 markers: ' + ', '.join(missing))

info = text.index(
    'توضيح: يمكن إنجاز بعض مهام الخريطة ضمن مسار واحد، وسيحتسبها DEDA تلقائيًا عند تحقق شروطها.'
)
tasks_card_call = text.index('_diamondsRewardCard()', info)
if tasks_card_call <= info:
    raise SystemExit('Diamonds reward card is not below the explanation box')

points = text.index("title: dedaText('النقاط', 'Points')")
diamonds_profile = text.index('_diamondsBalanceCard(diamonds)', points)
favorites = text.index("title: dedaText('المفضلة', 'Favorites')", diamonds_profile)
if not (points < diamonds_profile < favorites):
    raise SystemExit('Diamonds profile card must be between Points and Favorites')

earned = text.index(
    'onUserEarnedReward: (shownAd, reward)',
    text.index('_watchDiamondsRewardedAd'),
)
claim = text.index('DedaDiamondsWallet.claimReward()', earned)
if claim <= earned:
    raise SystemExit('Diamonds must only be claimed from onUserEarnedReward')

if text.count('static const int rewardPerAd = 3;') != 1:
    raise SystemExit('Unexpected duplicate diamonds reward constant')
if text.count('static const int maxAdsPerDay = 5;') != 1:
    raise SystemExit('Unexpected duplicate diamonds daily limit')

# Build 100259 intentionally has exactly two rewarded callbacks:
# one established +5-points task path and one new +3-diamonds path.
if text.count('onUserEarnedReward:') != 2:
    raise SystemExit('Expected exactly two rewarded callbacks in 100259')

# Both reward surfaces must keep using the single centralized loader/preload
# introduced by 100258, not create a second competing ad loader.
if text.count('RewardedAd.load(') != 1:
    raise SystemExit('Diamonds must reuse the single centralized RewardedAd loader')

print('DEDA 100259 diamonds reward validation passed.')
