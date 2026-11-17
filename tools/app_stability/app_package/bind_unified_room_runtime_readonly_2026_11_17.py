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
HOME = 'class HomePage extends '
CREATE = 'State<HomePage> createState() => _HomePageState();'

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
    # The complete 100447 generated HomePageState may use a modified class
    # declaration. Anchor to the unchanged unique HomePage state factory
    # instead, preserved since the signed 100436 source.
    if text.count(HOME) != 1 or text.count(CREATE) != 1 or \
        text.count("import 'dart:async';") < 1:
        raise RuntimeError('BLOCK_AMBIGUOUS_HOME_FACTORY:' +
                           str(text.count(HOME)) + ':' + str(text.count(CREATE)) +
                           ':' + str(text.count("import 'dart:async';")))
    if ENTRY.strip() in text or 'DedaUnifiedRoomRuntimeReadOnly' in text or \
        module_file.exists():
        raise RuntimeError('BLOCK_DUPLICATE_ROOM_RUNTIME_INTEGRATION')
    if 'DedaGoogleSettingsLinkCard(' in text or \
        'DedaSessionDiagnosticReadOnlyTile(' in text or \
        'deda_step1_google_settings_link_100439.dart' in text:
        raise RuntimeError('BLOCK_REMOVED_CARD_REINTRODUCED')
    if text.index(CREATE) < text.index(HOME) or \
        text.index(CREATE)-text.index(HOME)>3000:
        raise RuntimeError('BLOCK_HOME_FACTORY_OUTSIDE_HOME_WIDGET')
    original = (REPO / 'lib' / ADAPTER).read_bytes()
    if b'defaultValue: false' not in original or \
        b'FirebaseFunctions.instance' not in original or \
        b'preflightOnHome' not in original:
        raise RuntimeError('BLOCK_UNVERIFIED_REAL_ROOM_SDK_MODULE')
    # Hook exactly the existing HomePage factory (called upon entering
    # the logged-in home), without altering login/session, cards or widgets.
    # Feature default false => zero network calls and zero UI state changes.
    replacement = ("State<HomePage> createState() {\n" +
                   CALL + "    return _HomePageState();\n  }")
    patched = ENTRY + text.replace(CREATE, replacement, 1)
    if patched.count(CALL) != 1 or patched.count(ENTRY) != 1:
        raise RuntimeError('BLOCK_DUPLICATE_OR_MISSING_BIND')

    # Protect the *existing* Settings admin entry without relocating a card.
    # The visible gateway must never act on a response for a previous phone,
    # nor open admin after Firebase Auth switches while a lookup is awaiting.
    settings = 'class _DedaSettingsPageState extends State<DedaSettingsPage> {'
    if patched.count(settings) != 1:
        raise RuntimeError('BLOCK_AMBIGUOUS_SETTINGS_ADMIN_SECTION')
    refresh = '    if (!mounted) return;\\n    setState(() => _adminEntryVisible = allowed);'
    guarded_refresh = ("""    final activePhone = DedaPreferences.accountPhone.trim().isNotEmpty
        ? DedaPreferences.accountPhone
        : DedaPreferences.phone;
    if (!mounted ||
        DedaBackend.accountKeyForPhone(activePhone) !=
            DedaBackend.accountKeyForPhone(phone)) return;
    setState(() => _adminEntryVisible = allowed);""")
    if patched.count(refresh) != 1:
        raise RuntimeError('BLOCK_SETTINGS_ADMIN_REFRESH_ANCHOR_CHANGED')
    patched = patched.replace(refresh, guarded_refresh, 1)

    tap_start = 'final gateAllowed = await DedaBackend'
    tap_end = 'Navigator.push('
    if patched.count(tap_start) != 1:
        raise RuntimeError('BLOCK_ADMIN_TAP_GATE_AMBIGUOUS')
    a = patched.index(tap_start)
    b = patched.index(tap_end, a)
    tap = patched[a:b]
    expected_uid = """                                final gateUid =
                                    FirebaseAuth.instance.currentUser?.uid;
                                if (gateUid == null) return;

"""
    admin_probe = '                                final isAdmin ='
    if tap.count(admin_probe) != 1:
        raise RuntimeError('BLOCK_ADMIN_AUTH_PROBE_AMBIGUOUS')
    tap = tap.replace(admin_probe, expected_uid + admin_probe, 1)
    admin_probe_guard = '                                var adminSessionMatches = false;'
    if tap.count(admin_probe_guard) != 1:
        raise RuntimeError('BLOCK_ADMIN_MATCH_CHECK_AMBIGUOUS')
    tap = tap.replace(admin_probe_guard,
        """                                if (!context.mounted ||
                                    FirebaseAuth.instance.currentUser?.uid != gateUid) return;
""" + admin_probe_guard, 1)
    last_mounted = '                                if (!context.mounted) return;'
    if tap.count(last_mounted) != 2:
        raise RuntimeError('BLOCK_ADMIN_FINAL_ASYNC_BOUNDARY_CHANGED')
    # Only the final boundary after currentAdminSessionMatchesDedaEntry.
    pos = tap.rfind(last_mounted)
    tap = (tap[:pos] + tap[pos:].replace(last_mounted,
        """                                if (!context.mounted ||
                                    FirebaseAuth.instance.currentUser?.uid != gateUid) return;""", 1))
    patched = patched[:a] + tap + patched[b:]
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
