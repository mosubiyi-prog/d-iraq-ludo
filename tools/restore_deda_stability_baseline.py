"""Restore an immutable 100380 source-only workspace; never touches Android/signing.

Output MUST be absent or empty. --pilot overlays the two identity files.
--startup-metrics adds an opt-in module and exact-hash main instrumentation.
--session-gate copies an UNWIRED session coordinator for isolated tests only.
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


def restore(output, pilot=False, startup_metrics=False, session_gate=False):
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
    if session_gate:
        shutil.copy2(REPO / SESSION_MODULE, output / SESSION_MODULE)
    return {'verifiedFiles':len(verified), 'pilot':pilot,
            'startupMetrics':startup_metrics, 'sessionGateFoundation':session_gate,
            'flutterVersion':manifest['flutterVersion']}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output',type=Path)
    parser.add_argument('--pilot',action='store_true')
    parser.add_argument('--startup-metrics',action='store_true')
    parser.add_argument('--session-gate',action='store_true')
    args = parser.parse_args()
    print(json.dumps(restore(args.output,args.pilot,args.startup_metrics,args.session_gate)))
