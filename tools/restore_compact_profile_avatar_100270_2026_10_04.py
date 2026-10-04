from pathlib import Path

path = Path('lib/main.dart')
text = path.read_text(encoding='utf-8')
old = '_avatar(frameStyle, compact ? 92 : 104)'
new = '_avatar(frameStyle, compact ? 82 : 90)'
if text.count(old) != 1:
    raise SystemExit(f'expected one unified profile avatar size call, found {text.count(old)}')
text = text.replace(old, new, 1)
path.write_text(text, encoding='utf-8')
print('restored approved compact 82/90 profile avatar size after 100270 unification')
