"""Restore an immutable 100380 source-only workspace; never touches Android/signing.

Output MUST be absent or empty. --pilot overlays the two identity files.
--startup-metrics adds an opt-in module and exact-hash main instrumentation.
--session-gate copies an UNWIRED session coordinator for isolated tests only.
--session-flow adds its UNWIRED full-flow prototype and coordinator dependency.
--owner-firebase-port adds an UNWIRED owner adapter and principal observer.
--admin-firebase-adapter adds the UNWIRED admin flow and owner observer dependencies.
--legacy-progress-capture adds a read-only UNWIRED local evidence module.
Existing APK/build workflows and the immutable archive remain unchanged.
"""
import argparse
import hashlib
import json
import re
import shutil
import tarfile
import textwrap
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
PILOT_FILES = ('lib/deda_stability_read_scope.dart',
               'lib/deda_qa32_active_account_scope.dart')


STARTUP_MODULE = 'lib/deda_startup_measurements.dart'
SESSION_MODULE = 'lib/deda_session_transition_gate.dart'
SESSION_FLOW_MODULE = 'lib/deda_session_flow_prototype.dart'
LEGACY_PROGRESS_MODULE = 'lib/deda_legacy_progress_capture.dart'
ADMIN_ADAPTER_MODULE = 'lib/deda_admin_session_firebase_adapter.dart'
OWNER_PORT_MODULES = ('lib/deda_owner_session_firebase_port.dart',
                      'lib/deda_session_principal_tracker.dart')


def instrument_startup(source):
    """Add opt-in probes to the exact immutable main; refuse source drift."""
    manifest = json.loads((REPO / 'tools/app_stability/100380-baseline-manifest.json').read_text())
    expected = manifest['files']['lib/main.dart']
    if hashlib.sha256(source.encode()).hexdigest() != expected:
        raise ValueError('Startup instrumentation requires exact baseline main')
    header = 'Future<void> main() async {\n'
    start = source.index(header)
    close = source.index('\n}\n\nclass _DedaCleanPageTransitionsBuilder', start)
    body = source[start + len(header):close]
    measured = """Future<void> main() async {
  if (!dedaStabilityStartupMetricsEnabled) {
BASELINE_BODY
    return;
  }
  await runDedaMeasuredStartup(
    measurements: dedaStartupMeasurements,
    initializeBindings: () { WidgetsFlutterBinding.ensureInitialized(); },
    initializeMapCache: () {
      BuiltInMapCachingProvider.getOrCreateInstance(
        maxCacheSize: 128 * 1024 * 1024,
      );
    },
    initializeFirebase: () async { await Firebase.initializeApp(); },
    loadPreferences: DedaPreferences.load,
    initializeTasks: DedaTaskEngine.initializeForCurrentAccount,
    launch: () { runApp(const DedaApp()); },
    observeFirstFrame: (callback) => WidgetsBinding.instance
        .addPostFrameCallback((_) => callback()),
  );
}""".replace('BASELINE_BODY', textwrap.indent(body, '  '))
    source = source[:start] + measured + source[close + 2:]
    first_import = source.index('import ')
    return source[:first_import] + "import 'deda_startup_measurements.dart';\n" + source[first_import:]


def restore(output, pilot=False, startup_metrics=False, session_gate=False, session_flow=False, owner_firebase_port=False, admin_firebase_adapter=False, legacy_progress_capture=False):
    output = output.resolve()
    if output == REPO or REPO in output.parents:
        raise ValueError('Output must be outside the repository')
    if output.exists() and any(output.iterdir()):
        raise ValueError('Output must be empty; refusing to overwrite work')
    data = REPO / 'tools/app_stability'
    manifest = json.loads((data/'100380-baseline-manifest.json').read_text())
    archive = data/'100380-baseline.tar.gz'
    if hashlib.sha256(archive.read_bytes()).hexdigest() != manifest['archiveSHA256']:
        raise ValueError('Baseline archive hash mismatch')
    verified = {}
    with tarfile.open(archive, 'r:gz') as tar:
        for member in tar.getmembers():
            name = member.name
            allowed = (re.fullmatch(r'lib/[A-Za-z0-9_]+\.dart', name) or
                       re.fullmatch(r'assets/deda_style/[A-Za-z0-9_]+\.png', name) or
                       name in ('pubspec.yaml','pubspec.lock'))
            if not allowed or not member.isfile() or name in verified:
                raise ValueError('Unexpected archive entry')
            if member.size > 5_000_000:
                raise ValueError('Oversized source file')
            blob = tar.extractfile(member).read()
            if hashlib.sha256(blob).hexdigest() != manifest['files'].get(name):
                raise ValueError('Baseline member hash mismatch: '+name)
            verified[name] = blob
    if set(verified) != set(manifest['files']):
        raise ValueError('Incomplete archive')
    output.mkdir(parents=True, exist_ok=True)
    # Preserve the repository artwork; legacy PNGs below come from the verified
    # previous signed APK. No APK, Android directory or signing material copied.
    shutil.copytree(REPO/'assets', output/'assets', dirs_exist_ok=True)
    for name, blob in verified.items():
        target = output/name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(blob)
    shutil.copytree(REPO/'test', output/'test', dirs_exist_ok=True)
    if pilot:
        for name in PILOT_FILES:
            shutil.copy2(REPO/name, output/name)
    if startup_metrics:
        shutil.copy2(REPO / STARTUP_MODULE, output / STARTUP_MODULE)
        main_path = output / 'lib/main.dart'
        main_path.write_text(instrument_startup(main_path.read_text()))
    if session_gate or session_flow or owner_firebase_port or admin_firebase_adapter:
        shutil.copy2(REPO / SESSION_MODULE, output / SESSION_MODULE)
    if session_flow or owner_firebase_port or admin_firebase_adapter:
        shutil.copy2(REPO / SESSION_FLOW_MODULE, output / SESSION_FLOW_MODULE)
    if owner_firebase_port or admin_firebase_adapter:
        for name in OWNER_PORT_MODULES:
            shutil.copy2(REPO / name, output / name)
    if admin_firebase_adapter:
        shutil.copy2(REPO / ADMIN_ADAPTER_MODULE, output / ADMIN_ADAPTER_MODULE)
    if legacy_progress_capture:
        shutil.copy2(REPO / LEGACY_PROGRESS_MODULE, output / LEGACY_PROGRESS_MODULE)
    return {'verifiedFiles':len(verified), 'pilot':pilot,
            'startupMetrics':startup_metrics, 'sessionGateFoundation':session_gate or session_flow or owner_firebase_port or admin_firebase_adapter,
            'sessionFlowPrototype':session_flow or owner_firebase_port or admin_firebase_adapter,
            'ownerFirebasePort':owner_firebase_port or admin_firebase_adapter,
            'adminFirebaseAdapter':admin_firebase_adapter,
            'legacyProgressCapture':legacy_progress_capture,
            'flutterVersion':manifest['flutterVersion']}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output',type=Path)
    parser.add_argument('--pilot',action='store_true')
    parser.add_argument('--startup-metrics',action='store_true')
    parser.add_argument('--session-gate',action='store_true')
    parser.add_argument('--session-flow',action='store_true')
    parser.add_argument('--owner-firebase-port',action='store_true')
    parser.add_argument('--admin-firebase-adapter',action='store_true')
    parser.add_argument('--legacy-progress-capture',action='store_true')
    args = parser.parse_args()
    print(json.dumps(restore(args.output,args.pilot,args.startup_metrics,args.session_gate,args.session_flow,args.owner_firebase_port,args.admin_firebase_adapter,args.legacy_progress_capture)))
