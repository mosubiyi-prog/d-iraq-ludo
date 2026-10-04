from pathlib import Path

path = Path('lib/main.dart')
text = path.read_text(encoding='utf-8')
marker = '// DEDA_BADGE_BUTTON_ANCHOR_NORMALIZED_100270'
if marker in text:
    print('100270 badge button anchor already normalized')
    raise SystemExit(0)

style_start = text.index('class _DedaStylePageState')
needle = '_buyBadge(id, level, price, diamonds)'
needle_pos = text.index(needle, style_start)

# Find only the badge purchase branch around the known call. dart format can
# reflow SizedBox/FilledButton endings, so do not depend on exact indentation or
# closing-parenthesis layout.
block_start = text.rfind('\n        else', style_start, needle_pos)
if block_start < 0:
    block_start = text.rfind('\n      else', style_start, needle_pos)
if block_start < 0:
    raise SystemExit('formatted badge else branch start not found')
block_start += 1

# The badge purchase branch is the final child of the Row in _badgeTile. Keep
# the Row closing token itself and replace only the else branch before it.
row_end = text.find('\n      ]),', needle_pos)
if row_end < 0:
    row_end = text.find('\n    ]),', needle_pos)
if row_end < 0:
    raise SystemExit('formatted badge Row closing token not found')

normalized = '''        else
          SizedBox(height: 38,
            child: FilledButton(
              onPressed: _busy ? null : () => _buyBadge(id, level, price, diamonds),
              child: Text(diamonds ? '💎 $price' : '🪙 $price'),
            )),'''

text = text[:block_start] + normalized + text[row_end:]
text = marker + '\n' + text
path.write_text(text, encoding='utf-8')
print('normalized 100270 badge lock button anchor structurally')
