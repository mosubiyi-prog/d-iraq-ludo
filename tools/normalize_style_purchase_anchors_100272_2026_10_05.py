from pathlib import Path
import re

path = Path('lib/main.dart')
text = path.read_text(encoding='utf-8')

single = '  Future<void> _buyBadge(String id, int level, int amount, bool diamonds) async {'
if single in text:
    print('100272 badge purchase signature already normalized')
    raise SystemExit(0)

pattern = re.compile(
    r"  Future<void> _buyBadge\(\s*"
    r"String id,\s*"
    r"int level,\s*"
    r"int amount,\s*"
    r"bool diamonds,\s*"
    r"\) async \{"
)
text, count = pattern.subn(single, text, count=1)
if count != 1:
    raise SystemExit(f'formatted _buyBadge signature count={count}')

path.write_text(text, encoding='utf-8')
print('normalized formatted 100271 badge purchase signature for 100272')
