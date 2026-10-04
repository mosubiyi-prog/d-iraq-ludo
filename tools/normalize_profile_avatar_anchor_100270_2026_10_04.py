from pathlib import Path

path = Path('lib/main.dart')
text = path.read_text(encoding='utf-8')
marker = '// DEDA_PROFILE_AVATAR_ANCHOR_NORMALIZED_100270'
if marker in text:
    print('100270 profile avatar anchor already normalized')
    raise SystemExit(0)

start = text.index('class _DedaProfilePhase2PageState')
end = text.index('class DedaPublicProfilePreviewPage', start)
scope = text[start:end]
old = '_avatar(frame, compact ? 82 : 90),'
if scope.count(old) != 1:
    raise SystemExit(f'expected one compact profile avatar call, found {scope.count(old)}')
scope = scope.replace(old, '_avatar(frame, compact ? 92 : 104),', 1)
text = text[:start] + scope + text[end:]
text = marker + '\n' + text
path.write_text(text, encoding='utf-8')
print('normalized 100270 profile avatar anchor without changing final intended size')
