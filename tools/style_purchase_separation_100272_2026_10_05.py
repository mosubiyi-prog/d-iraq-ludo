from pathlib import Path

path = Path('lib/main.dart')
text = path.read_text(encoding='utf-8')
marker = '// DEDA_STYLE_PURCHASE_SEPARATION_100272'
if marker in text:
    print('100272 style purchase separation already applied')
    raise SystemExit(0)

if '// DEDA_GIFTS_MAIN_UI_100271' not in text:
    raise SystemExit('100271 gifts/main UI must be applied before 100272')
if '// DEDA_SOCIAL_UI_WALLET_FIXES_100270' not in text:
    raise SystemExit('100270 social UI wallet fixes must be applied before 100272')

# ---------------------------------------------------------------------------
# 1) My Profile: the diamond stat must show the spendable wallet. For the
#    authorized general-manager personal account that is the separate testing
#    million; for every other user it remains the normal earned + received
#    diamonds balance. Both notifiers are observed so the card refreshes after
#    a purchase without changing the underlying normal 15-diamond balance.
# ---------------------------------------------------------------------------
profile_state = 'class _DedaProfilePhase2PageState extends State<DedaProfilePhase2Page> {'
profile_pos = text.find(profile_state)
if profile_pos < 0:
    raise SystemExit('profile state missing')

diamond_notifier = 'valueListenable: DedaDiamondsWallet.balanceNotifier,'
diamond_pos = text.find(diamond_notifier, profile_pos)
if diamond_pos < 0:
    raise SystemExit('profile diamond stat notifier missing')

stat_start = text.rfind('        Expanded(', profile_pos, diamond_pos)
next_gap = text.find('        const SizedBox(width: 8),', diamond_pos)
if stat_start < 0 or next_gap < 0:
    raise SystemExit('profile diamond stat bounds missing')

profile_diamond_block = r'''        Expanded(
          child: ValueListenableBuilder<int>(
            valueListenable: DedaDiamondsWallet.balanceNotifier,
            builder: (context, normalDiamonds, _) =>
                ValueListenableBuilder<int>(
              valueListenable:
                  DedaDiamondsWallet.generalManagerPersonalNotifier,
              builder: (context, managerDiamonds, __) => _statCard(
                icon: Icons.diamond_rounded,
                value:
                    '${DedaDiamondsWallet.hasGeneralManagerPersonalWallet ? managerDiamonds : normalDiamonds}',
                label: dedaText('الماسات', 'Diamonds'),
                color: const Color(0xFF7639D4),
                surface: const Color(0xFFF1E8FF),
              ),
            ),
          ),
        ),
'''
text = text[:stat_start] + profile_diamond_block + text[next_gap:]

# ---------------------------------------------------------------------------
# 2) Paid frames: remove ALL level prerequisites from the purchase action.
#    This does not touch XP, levels, task rewards, or any level-gift system.
# ---------------------------------------------------------------------------
style_state = 'class _DedaStylePageState extends State<DedaStylePage> {'
style_pos = text.find(style_state)
if style_pos < 0:
    raise SystemExit('style page state missing')

buy_frame = '  Future<void> _buyFrame(int index) async {'
frame_start = text.find(buy_frame, style_pos)
frame_busy = text.find('    setState(() => _busy = true);', frame_start)
if frame_start < 0 or frame_busy < 0:
    raise SystemExit('buy frame bounds missing')
frame_prefix = '''  Future<void> _buyFrame(int index) async {\n    if (_busy) return;\n'''
text = text[:frame_start] + frame_prefix + text[frame_busy:]

buy_badge = '  Future<void> _buyBadge(String id, int level, int amount, bool diamonds) async {'
badge_start = text.find(buy_badge, style_pos)
badge_busy = text.find('    setState(() => _busy = true);', badge_start)
if badge_start < 0 or badge_busy < 0:
    raise SystemExit('buy badge bounds missing')
badge_prefix = '''  Future<void> _buyBadge(\n    String id,\n    int _level,\n    int amount,\n    bool diamonds,\n  ) async {\n    if (_busy) return;\n'''
text = text[:badge_start] + badge_prefix + text[badge_busy:]

# ---------------------------------------------------------------------------
# 3) Style copy and cards: paid items advertise only their currency price.
#    They must never say "requires level" or render a disabled level lock.
# ---------------------------------------------------------------------------
old_copy_ar = '3 مجانية، والبقية تُفتح بالمستوى ثم بالماسات أو عملة DEDA.'
new_copy_ar = '3 مجانية، والبقية تُشترى مباشرة بالماسات أو عملة DEDA.'
old_copy_en = 'Three are free; the rest unlock by level and diamonds or DEDA currency.'
new_copy_en = 'Three are free; the rest can be purchased directly with diamonds or DEDA currency.'
if text.count(old_copy_ar) != 1 or text.count(old_copy_en) != 1:
    raise SystemExit('style explanatory copy anchor mismatch')
text = text.replace(old_copy_ar, new_copy_ar, 1)
text = text.replace(old_copy_en, new_copy_en, 1)

# Remove the frame min-level declaration inside the six-card generator.
frame_gen = "children: List<Widget>.generate(6, (index) {"
frame_gen_pos = text.find(frame_gen, style_pos)
price_pos = text.find('final price =', frame_gen_pos)
min_pos = text.find('final minLevel =', frame_gen_pos, price_pos)
if frame_gen_pos < 0 or price_pos < 0 or min_pos < 0:
    raise SystemExit('frame minLevel declaration missing')
min_line_start = text.rfind('\n', frame_gen_pos, min_pos) + 1
min_stmt_end = text.find(';', min_pos)
if min_stmt_end < 0:
    raise SystemExit('frame minLevel declaration terminator missing')
text = text[:min_line_start] + text[min_stmt_end + 1:]

# Replace the subtitle under each frame with the actual price only.
subtitle_start = text.find('Text(minLevel > 1', frame_gen_pos)
subtitle_style = text.find('style: const TextStyle', subtitle_start)
if subtitle_start < 0 or subtitle_style < 0:
    raise SystemExit('frame level subtitle missing')
indent = '                    '
text = text[:subtitle_start] + "Text(price,\n" + indent + text[subtitle_style:]

# Replace the 100270 disabled level-lock button with a normal purchase button.
lock_onpress = text.find('onPressed: _busy || progress.level < minLevel', frame_gen_pos)
lock_child = text.find('child: Text(progress.level < minLevel', lock_onpress)
lock_price_end = text.find(': price),', lock_child)
if lock_onpress < 0 or lock_child < 0 or lock_price_end < 0:
    raise SystemExit('100270 frame level-lock button missing')
lock_price_end += len(': price),')
frame_button = '''onPressed: _busy ? null : () => _buyFrame(index),\n                              child: Text(price),'''
text = text[:lock_onpress] + frame_button + text[lock_price_end:]

# Paid badge subtitle: free only when price == 0; otherwise show its currency.
badge_tile = '  Widget _badgeTile('
badge_tile_pos = text.find(badge_tile, style_pos)
badge_subtitle = text.find('Text(level > 1', badge_tile_pos)
badge_subtitle_style = text.find('style: const TextStyle', badge_subtitle)
if badge_tile_pos < 0 or badge_subtitle < 0 or badge_subtitle_style < 0:
    raise SystemExit('badge level subtitle missing')
badge_subtitle_new = '''Text(\n              price == 0\n                  ? dedaText('مجانية', 'Free')\n                  : (diamonds ? '💎 $price' : '🪙 $price'),\n              '''
text = (
    text[:badge_subtitle]
    + badge_subtitle_new
    + text[badge_subtitle_style:]
)

# Replace the 100270 disabled badge lock button.
badge_lock_press = text.find(
    'onPressed: _busy || (_progress?.level ?? 1) < level', badge_tile_pos
)
badge_lock_child = text.find(
    'child: Text((_progress?.level ?? 1) < level', badge_lock_press
)
badge_lock_end_token = ": (diamonds ? '💎 $price' : '🪙 $price'))"
badge_lock_end = text.find(badge_lock_end_token, badge_lock_child)
if badge_lock_press < 0 or badge_lock_child < 0 or badge_lock_end < 0:
    raise SystemExit('100270 badge level-lock button missing')
badge_lock_end += len(badge_lock_end_token)
badge_button = '''onPressed: _busy\n                  ? null\n                  : () => _buyBadge(id, level, price, diamonds),\n              child: Text(diamonds ? '💎 $price' : '🪙 $price')'''
text = text[:badge_lock_press] + badge_button + text[badge_lock_end:]

# Add a marker close to the style state for deterministic validation.
text = text.replace(
    style_state,
    '// DEDA_STYLE_PURCHASE_SEPARATION_100272\n' + style_state,
    1,
)

path.write_text(text, encoding='utf-8')
print('applied DEDA 100272 paid-style/level separation + profile manager balance')
