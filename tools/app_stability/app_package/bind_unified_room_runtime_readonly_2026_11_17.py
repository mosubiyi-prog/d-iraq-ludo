#!/usr/bin/env python3
"""Wire one READ-ONLY Firebase room SDK adapter into the COMPLETE assembled DEDA.

Only runs on a disposable assembled app, AFTER 100447's protected ordered
parity/Google-session-card-removal stages. Nothing is deployed or built here.
Rejects nonunique anchors and existing changes; no production toggles.
"""
import argparse
import hashlib
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
ADAPTER = 'deda_unified_room_runtime_readonly.dart'
ENTRY = "import 'deda_unified_room_runtime_readonly.dart';\n"
CALL = '    unawaited(DedaUnifiedRoomRuntimeReadOnly.preflightOnHome());\n'
HOME = 'class _HomePageState extends State<HomePage> {'
INIT = '  @override\n  void initState() {\n    super.initState();\n'

def bind(project):
    project = Path(project).resolve()
    if project == REPO or REPO in project.parents or project in REPO.parents:
        raise RuntimeError('BLOCK_SOURCE_REPOSITORY_MODIFICATION')
    main_file = project / 'lib/main.dart'
    module_file = project / 'lib' / ADAPTER
    evidence = project / 'internal-build-inputs.json'
    if not main_file.is_file() or not evidence.is_file():
        raise RuntimeError('BLOCK_UNVERIFIED_ASSEMBLED_PROJECT')
    import json
    record = json.loads(evidence.read_text())
    if record.get('package') != 'com.diraq.ludo.d_iraq_ludo' or \
        record.get('financialRestoreEnabled') is not False or \
        record.get('completeOwnerDelivery') is not False:
        raise RuntimeError('BLOCK_ORIGINAL_APP_AND_FINANCIAL_GUARDS')
    text = main_file.read_text()
    if text.count(HOME) != 1 or text.count('import \'dart:async\';') != 1:
        raise RuntimeError('BLOCK_AMBIGUOUS_MAIN_OR_ASYNC_IMPORT')
    if ENTRY.strip() in text or 'DedaUnifiedRoomRuntimeReadOnly' in text or \
        module_file.exists():
        raise RuntimeError('BLOCK_DUPLICATE_ROOM_RUNTIME_INTEGRATION')
    if 'DedaGoogleSettingsLinkCard(' in text or \
        'DedaSessionDiagnosticReadOnlyTile(' in text or \
        'deda_step1_google_settings_link_100439.dart' in text:
        raise RuntimeError('BLOCK_REMOVED_CARD_REINTRODUCED')
    after_home = text.index(HOME) + len(HOME)
    pos = text.find(INIT, after_home)
    if pos == -1 or pos - after_home > 70000:
        raise RuntimeError('BLOCK_HOME_LIFECYCLE_ANCHOR_MISSING')
    original = (REPO / 'lib' / ADAPTER).read_bytes()
    if b'defaultValue: false' not in original or \
        b'FirebaseFunctions.instance' not in original or \
        b'preflightOnHome' not in original:
        raise RuntimeError('BLOCK_UNVERIFIED_REAL_ROOM_SDK_MODULE')
    patched = ENTRY + text
    # Only the intended HomePage lifecycle is touched, never login, cards
    # admin, premium ID, league, wallet, PIN, or existing stored user state.
    lifecycle = patched.index(INIT, patched.index(HOME))
    patched = patched[:lifecycle+len(INIT)] + CALL + patched[lifecycle+len(INIT):]
    if patched.count(CALL) != 1 or patched.count(ENTRY) != 1:
        raise RuntimeError('BLOCK_DUPLICATE_OR_MISSING_BIND')
    main_file.write_text(patched)
    module_file.write_bytes(original)
    result = {'source': '100447-assembled',
              'moduleSha256': hashlib.sha256(original).hexdigest(),
              'homeRuntimeHook': True,
              'featureDefaultOff': True,
              'firebaseProductionDeployed': False,
              'readOnly': True, 'apkBuilt': False}
    (project / 'deda-room-runtime-wiring-proof.json').write_text(
        json.dumps(result, indent=2) + '\n')
    print('PASS_ONE_REAL_SDK_READONLY_RUNTIME_HOOK_IN_FULL_APP_RELEASE_HOLD')

if __name__ == '__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('project')
    args=parser.parse_args()
    bind(args.project)
