from pathlib import Path

path = Path('lib/main.dart')
text = path.read_text(encoding='utf-8')
state = 'class _DedaProfilePhase2PageState extends State<DedaProfilePhase2Page> {'
end_marker = 'class DedaPublicProfilePreviewPage'
start = text.index(state)
end = text.index(end_marker, start)
scope = text[start:end]

old = '''    unawaited(DedaDiamondsWallet.load());
    unawaited(() async {
      await DedaTaskEngine.initializeForCurrentAccount();
      if (mounted) await _loadOpenedPointTiers();
    }());'''
new = '''    unawaited(DedaDiamondsWallet.load());
    unawaited(DedaTaskEngine.initializeForCurrentAccount());'''
if scope.count(old) != 1:
    raise SystemExit(f'expected one final 100263 profile init anchor, found {scope.count(old)}')
scope = scope.replace(old, new, 1)
text = text[:start] + scope + text[end:]
path.write_text(text, encoding='utf-8')
print('normalized profile init anchor for 100269 patch application')
