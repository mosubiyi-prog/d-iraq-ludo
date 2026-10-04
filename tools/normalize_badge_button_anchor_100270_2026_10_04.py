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
block_start = text.rfind('        else\n          SizedBox(', style_start, needle_pos)
if block_start < 0:
    raise SystemExit('formatted badge else/SizedBox start not found')
block_end_marker = '          ),\n      ]),'
block_end = text.find(block_end_marker, needle_pos)
if block_end < 0:
    raise SystemExit('formatted badge else/SizedBox end not found')
block_end += len('          ),')

normalized = '''        else
          SizedBox(height: 38,
            child: FilledButton(
              onPressed: _busy ? null : () => _buyBadge(id, level, price, diamonds),
              child: Text(diamonds ? '💎 $price' : '🪙 $price'),
            ))'''
text = text[:block_start] + normalized + text[block_end:]
text = marker + '\n' + text
path.write_text(text, encoding='utf-8')
print('normalized 100270 badge lock button anchor structurally')
