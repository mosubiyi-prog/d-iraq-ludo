from pathlib import Path

main = Path('lib/main.dart').read_text(encoding='utf-8')
errors = []


def need(text, token, label):
    if token not in text:
        errors.append(f'missing {label}: {token}')


def forbid(text, token, label):
    if token in text:
        errors.append(f'forbidden {label}: {token}')


need(main, '// DEDA_STYLE_PURCHASE_SEPARATION_100272', '100272 marker')
need(main, '// DEDA_GIFTS_MAIN_UI_100271', '100271 gifts retained')
need(main, "valueListenable: DedaDiamondsWallet.balanceNotifier", 'normal diamond notifier retained')
need(main, 'DedaDiamondsWallet.generalManagerPersonalNotifier', 'manager personal notifier in profile')
need(main, 'DedaDiamondsWallet.hasGeneralManagerPersonalWallet', 'manager personal balance selection')
need(main, "label: dedaText('الماسات', 'Diamonds')", 'profile diamond label retained')
need(main, 'static int _localBalance = 0;', 'normal diamond wallet retained')
need(main, 'static int _generalManagerPersonalBalance = 0;', 'separate manager personal wallet retained')

style_start = main.find('// DEDA_STYLE_PURCHASE_SEPARATION_100272')
if style_start < 0:
    errors.append('style section start missing')
    style = ''
else:
    style = main[style_start:]

# No purchase action or visual purchase card may be level-gated.
for token, label in [
    ('يحتاج هذا الإطار إلى المستوى', 'frame purchase level rejection'),
    ('This frame requires level', 'frame purchase level rejection EN'),
    ('تحتاج إلى المستوى $level أولًا', 'badge purchase level rejection'),
    ('You need level $level first', 'badge purchase level rejection EN'),
    ('مقفول • مستوى', 'frame visual level lock'),
    ('Locked • Lv', 'frame visual level lock EN'),
    ("dedaText('مقفول • $level'", 'badge visual level lock'),
    ("dedaText('Locked • $level'", 'badge visual level lock EN'),
    ('progress.level < minLevel', 'frame level gate expression'),
    ('(_progress?.level ?? 1) < level', 'badge level gate expression'),
    ("dedaText('يتطلب مستوى $minLevel'", 'frame level subtitle'),
    ("dedaText('المستوى $level'", 'badge paid level subtitle'),
]:
    forbid(style, token, label)

need(
    style,
    '3 مجانية، والبقية تُشترى مباشرة بالماسات أو عملة DEDA.',
    'clear paid-frame explanation',
)
need(
    style,
    'Three are free; the rest can be purchased directly with diamonds or DEDA currency.',
    'clear paid-frame explanation EN',
)

# Prices and payment paths remain exactly the purchasing mechanism. Price
# literals are checked independently from ternary formatting so dart format is
# free to wrap the expression across lines without weakening the invariant.
for token, label in [
    ("'💎 30'", 'premium frame 1 diamond price'),
    ("'🪙 120'", 'premium frame 2 DEDA currency price'),
    ("'💎 60'", 'premium frame 3 diamond price'),
    ('await DedaDiamondsWallet.spend(index == 3 ? 30 : 60)', 'frame diamond payment'),
    ('await DedaSocialProgressWallet.spendCoins(120)', 'frame DEDA currency payment'),
    ("_badgeTile('badge_member'", 'free member badge'),
    ("_badgeTile('badge_spark'", 'paid spark badge'),
    ("_badgeTile('badge_elite'", 'paid elite badge'),
    ("price == 0", 'free-vs-paid badge subtitle'),
    ("diamonds ? '💎 $price' : '🪙 $price'", 'paid badge price display'),
]:
    need(style, token, label)

# Level and XP systems are preserved; only the purchase prerequisite is gone.
for token, label in [
    ('DedaSocialProgressWallet.load()', 'level progress load retained'),
    ('DedaSocialProgressWallet.xpPerLevel', 'XP level progress retained'),
    ("dedaText('المستوى ${progress.level}'", 'level display retained'),
    ('DedaTaskEngine', 'task/reward system retained'),
]:
    need(main, token, label)

# Friendship and gift work from 100271 must stay untouched.
for token, label in [
    ("value: 'gift_future'", 'future friend gift option'),
    ('class DedaMyGiftsPage', 'My Gifts page'),
    ('DedaBackend.claimDiamondGift(', 'manual gift claim'),
    ('class DedaGiftInbox', 'pending gift counter'),
]:
    need(main, token, label)

if errors:
    print('DEDA 100272 VALIDATION FAILED')
    for error in errors:
        print(f' - {error}')
    raise SystemExit(1)

print('DEDA 100272 purchase/level separation validation passed.')
print('Validated: manager personal diamonds in profile, paid styles never level-gated,')
print('prices/payment paths retained, level/XP systems retained, and 100271 gifts retained.')
