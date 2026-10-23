"""Inventory reconstructed Dart source; no Firebase/network access or writes.

Run on the verified 100379 Dart-only artifact after stage_deda_six_notes.py.
This is source evidence, not runtime coverage or a performance benchmark.
"""
import argparse
import hashlib
import json
import re
from pathlib import Path


def inventory(root):
    sources = {p.relative_to(root).as_posix(): p.read_text()
               for p in sorted((root / 'lib').rglob('*.dart'))}
    assert 'lib/main.dart' in sources, 'Missing generated main.dart'
    assert 'DedaSixActiveIdentity' in sources['lib/main.dart'], '100380 overlay missing'
    edges = {}
    for path, text in sources.items():
        local = []
        for uri in re.findall(r"(?:import|export|part)\s+['\"]([^'\"]+)['\"]", text):
            if uri.startswith('package:d_iraq_ludo/'):
                name = 'lib/' + uri.split('/', 1)[1]
            elif ':' not in uri:
                name = (Path(path).parent / uri).as_posix()
            else:
                continue
            if name in sources:
                local.append(name)
        edges[path] = sorted(set(local))
    reached, pending = set(), ['lib/main.dart']
    while pending:
        item = pending.pop()
        if item in reached:
            continue
        reached.add(item)
        pending.extend(edges[item])
    files = []
    for path, text in sources.items():
        classes = re.findall(r'^class\s+(\w+)', text, re.M)
        files.append({
            'path': path,
            'sha256': hashlib.sha256(text.encode()).hexdigest(),
            'lines': len(text.splitlines()),
            'reachableViaLocalImports': path in reached,
            'imports': edges[path],
            'pages': [c for c in classes if c.endswith('Page')],
            'classes': classes,
            'syntacticOccurrences': {
                'timeout': text.count('.timeout('),
                'listen': text.count('.listen('),
                'snapshots': text.count('.snapshots('),
                'authStateChanges': text.count('.authStateChanges('),
                'lifecycleHandler': text.count('void didChangeAppLifecycleState('),
                'transaction': text.count('.runTransaction('),
                'anonymousSignIn': text.count('.signInAnonymously('),
            },
        })
    return {
        'schemaVersion': 1,
        'referenceCommit': '08535d34a0028a916f978dc77a9a0f1a942a7c1b',
        'runtimeReference': '100379 Dart-only manifest + stage_deda_six_notes.py at reference commit',
        'limitation': 'Lexical inventory only. Import reachability does not prove a user can reach a page. Counts can include comments; no latency/device/network tests.',
        'files': files,
        'summary': {
            'dartFiles': len(files),
            'importReachableFiles': len(reached),
            'pageClasses': sum(len(f['pages']) for f in files),
            'sourceLines': sum(f['lines'] for f in files),
        },
    }


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    result = inventory(args.source.resolve())
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, ensure_ascii=False) + '\n')
    print(json.dumps(result['summary']))
