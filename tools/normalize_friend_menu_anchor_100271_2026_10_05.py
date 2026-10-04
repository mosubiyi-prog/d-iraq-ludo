from pathlib import Path
import re

path = Path('lib/main.dart')
text = path.read_text(encoding='utf-8')

# DEDA 100270 formats the compact friend-card icon across several lines.
# Normalize only this one structurally unique direct-removal button so the
# 100271 menu patch can replace it deterministically. No runtime behavior is
# changed by this normalizer itself.
expected = '''              IconButton(
                tooltip: dedaText('إزالة الصديق', 'Remove friend'),
                onPressed: onRemove,
                icon: const Icon(Icons.more_vert_rounded, color: Color(0xFF607487)),
              ),'''

if expected in text:
    print('friend menu anchor already normalized for 100271')
    raise SystemExit(0)

pattern = re.compile(
    r"              IconButton\(\n"
    r"\s+tooltip: dedaText\('إزالة الصديق', 'Remove friend'\),\n"
    r"\s+onPressed: onRemove,\n"
    r"\s+icon: const Icon\(\n"
    r"\s+Icons\.more_vert_rounded,\n"
    r"\s+color: Color\(0xFF607487\),\n"
    r"\s+\),\n"
    r"\s+\),"
)

text, count = pattern.subn(expected, text, count=1)
if count != 1:
    raise SystemExit(f'formatted friend direct-remove anchor count={count}')

path.write_text(text, encoding='utf-8')
print('normalized formatted 100270 friend overflow anchor for 100271')
