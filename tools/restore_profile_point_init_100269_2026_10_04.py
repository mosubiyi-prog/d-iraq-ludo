from pathlib import Path

path = Path('lib/main.dart')
text = path.read_text(encoding='utf-8')
state = 'class _DedaProfilePhase2PageState extends State<DedaProfilePhase2Page> {'
end_marker = 'class DedaPublicProfilePreviewPage'
start = text.index(state)
end = text.index(end_marker, start)
scope = text[start:end]

old = '    unawaited(DedaTaskEngine.initializeForCurrentAccount());'
new = '''    unawaited(() async {
      await DedaTaskEngine.initializeForCurrentAccount();
      if (mounted) await _loadOpenedPointTiers();
    }());'''
if scope.count(old) != 1:
    raise SystemExit(f'expected one temporary task-engine init anchor, found {scope.count(old)}')
scope = scope.replace(old, new, 1)
text = text[:start] + scope + text[end:]
path.write_text(text, encoding='utf-8')
print('restored proven point-tier initialization after 100269')
