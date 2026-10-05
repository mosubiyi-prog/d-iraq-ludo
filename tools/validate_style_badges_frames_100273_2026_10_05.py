from pathlib import Path

main = Path('lib/main.dart').read_text(encoding='utf-8')
pubspec = Path('pubspec.yaml').read_text(encoding='utf-8')

required = [
    '// DEDA_STYLE_BADGES_FRAMES_100273',
    "'badge_member'",
    "'badge_spark'",
    "'badge_elite'",
    "'badge_royal'",
    "'badge_season1'",
    "'badge_legendary'",
    'const List<int> dedaStylePrices = <int>[0, 100, 200, 150, 300, 200];',
    'const List<bool> dedaStyleUsesDiamonds =',
    "'assets/deda_style/badge_$index.png'",
    "'assets/deda_style/frame_$safeStyle.png'",
    'DedaDiamondsWallet.purchasableBalance',
    'DedaSocialProgressWallet.spendCoins(price)',
    'DedaDiamondsWallet.spend(price)',
    "final active = <String>{badgeId};",
    "'رصيد المشتريات'",
    "'ماساتي الشخصية'",
    "'عملة DEDA'",
    'DedaStyleInventory.activeBadgeNotifier',
    'DedaProfileAppearanceState.frameNotifier.value = index;',
]
for token in required:
    if token not in main:
        raise SystemExit(f'100273 validation missing: {token}')

# The new default must contain only the first free frame. Legacy ownership is
# preserved only through persisted data/current equipped migration logic.
default_owned = "final owned = <String>{'frame_0', 'badge_member'};"
if default_owned not in main:
    raise SystemExit('100273 free-default inventory is not exact')

for bad in (
    "<String>{'frame_0', 'frame_1', 'frame_2', 'badge_member'}",
    "active.length > 3",
):
    if bad in main:
        raise SystemExit(f'100273 stale multi-style behavior remains: {bad}')

if '    - assets/deda_style/\n' not in pubspec:
    raise SystemExit('100273 asset directory missing from pubspec')

asset_dir = Path('assets/deda_style')
for kind in ('badge', 'frame'):
    for index in range(6):
        p = asset_dir / f'{kind}_{index}.png'
        if not p.exists() or p.stat().st_size < 2000:
            raise SystemExit(f'100273 missing generated artwork: {p}')

# Privacy invariant: public friend profile must not expose phone/private fields.
privacy_copy = 'لا تظهر هنا أرقام الهاتف أو إعدادات الحساب الخاصة.'
if privacy_copy not in main:
    raise SystemExit('friend public-profile privacy copy was lost')

# Critical previous-layer markers must survive unchanged in the resulting app.
for marker in (
    '// DEDA_GIFTS_MAIN_UI_100271',
    '// DEDA_STYLE_PURCHASE_SEPARATION_100272',
    '// DEDA_SOCIAL_UI_WALLET_FIXES_100270',
):
    if marker not in main:
        raise SystemExit(f'previous stable marker missing: {marker}')

print('DEDA 100273 validation passed: 6 matched badge/frame sets, exact prices, visible wallets, single active badge')
