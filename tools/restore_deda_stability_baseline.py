"""Restore an immutable 100380 source-only workspace; never touches Android/signing.

Output MUST be absent or empty. --pilot overlays the two identity files.
--startup-metrics adds an opt-in module and exact-hash main instrumentation.
--session-gate copies an UNWIRED session coordinator for isolated tests only.
--session-flow adds its UNWIRED full-flow prototype and coordinator dependency.
--owner-firebase-port adds an UNWIRED owner adapter and principal observer.
--admin-firebase-adapter adds the UNWIRED admin flow and owner observer dependencies.
--legacy-progress-capture adds a read-only UNWIRED local evidence module.
--progress-evidence-store adds UNWIRED immutable archive IO with owner dependencies.
--progress-backup-coordinator composes capture/journal/archive, without app callsites.
--progress-backup-runtime binds an opt-in root host and account selection epochs.
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


LAZY_SECTIONS_MODULE = 'lib/deda_lazy_section_stack.dart'
STARTUP_MODULE = 'lib/deda_startup_measurements.dart'
SESSION_MODULE = 'lib/deda_session_transition_gate.dart'
SESSION_FLOW_MODULE = 'lib/deda_session_flow_prototype.dart'
PROGRESS_EVIDENCE_MODULE = 'lib/deda_progress_evidence_store.dart'
PROGRESS_BACKUP_MODULE = 'lib/deda_progress_backup_coordinator.dart'
PROGRESS_RUNTIME_MODULE = 'lib/deda_progress_backup_runtime.dart'
LEGACY_PROGRESS_MODULE = 'lib/deda_legacy_progress_capture.dart'
PURCHASE_EVIDENCE_MODULE = 'lib/deda_legacy_purchase_evidence.dart'
ADMIN_ADAPTER_MODULE = 'lib/deda_admin_session_firebase_adapter.dart'
OWNER_PORT_MODULES = ('lib/deda_owner_session_firebase_port.dart',
                      'lib/deda_session_principal_tracker.dart')


def bind_lazy_sections(source):
    """Only replace the original social hub's stack, preserving its children."""
    start = source.index('class _DedaSocialHubPageState ')
    end = source.index('class _DedaSocialTabSpec', start)
    section = source[start:end]
    before = 'body: IndexedStack(\n        index: _selectedIndex,'
    if section.count(before) != 1:
        raise ValueError('Social hub does not match original stack')
    after = 'body: DedaLazySectionStack(\n        enabled: dedaStabilityLazySections,\n        index: _selectedIndex,'
    section = section.replace(before, after, 1)
    source = source[:start] + section + source[end:]
    first_import = source.index('import ')
    return source[:first_import] + "import 'deda_lazy_section_stack.dart';\n" + source[first_import:]


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



def bind_progress_backup(source, original, *, measured=False):
    """Exact-source root/preferences binding; pilot stays false by default."""
    manifest = json.loads((REPO / 'tools/app_stability/100380-baseline-manifest.json').read_text())
    if hashlib.sha256(original.encode()).hexdigest() != manifest['files']['lib/main.dart']:
        raise ValueError('Backup binding requires exact baseline main')
    expected = instrument_startup(original) if measured else original
    if source != expected:
        raise ValueError('Backup binding requires exact generated source')
    source = source.replace('class DedaPreferences {', """class DedaPreferences {
  static String? get progressBackupAccountKey {
    if (!isLoggedIn) return null;
    final key = phone.replaceAll(RegExp(r'[^0-9]'), '');
    return key.isEmpty ? null : key;
  }
""", 1)
    for method in ['load()', 'saveLogin({', 'logout()']:
        header = '  static Future<void> ' + method
        start = source.index(header)
        body = source.index(' async {', start) + len(' async {')
        source = source[:body] + "\n    final backupSelection = dedaProgressBackupAccount.begin();" + source[body:]
        if method == 'load()':
            end = source.index('\n  static Future<void> setLanguage(', body)
            close = source.rindex('\n  }', body, end)
            source = source[:close] + "\n    dedaProgressBackupAccount.complete(backupSelection, progressBackupAccountKey);" + source[close:]
        elif method == 'saveLogin({':
            end = source.index('    unawaited(DedaTaskEngine.initializeForCurrentAccount());', body)
            source = source[:end] + "    dedaProgressBackupAccount.complete(backupSelection, progressBackupAccountKey);\n" + source[end:]
        else:
            # No completion on logout: intent remains absent even if SDK fails.
            source = source[:body] + source[body:].replace(
                'final backupSelection = dedaProgressBackupAccount.begin();',
                'dedaProgressBackupAccount.begin();', 1)
    launch = 'runApp(const DedaApp());'
    count = 2 if measured else 1
    if source.count(launch) != count:
        raise ValueError('Backup binding requires exact app launches')
    source = source.replace(launch, """runApp(DedaProgressBackupHost(
      currentAccount: () => DedaPreferences.progressBackupAccountKey,
      child: const DedaApp()));""")
    first_import = source.index('import ')
    return source[:first_import] + "import 'deda_progress_backup_runtime.dart';\n" + source[first_import:]


def restore(output, pilot=False, startup_metrics=False, session_gate=False, session_flow=False, owner_firebase_port=False, admin_firebase_adapter=False, legacy_progress_capture=False, progress_evidence_store=False, progress_backup_coordinator=False, progress_backup_runtime=False, auth_runtime=False, lazy_sections=False, section_entry=False):
    auth_runtime = auth_runtime or section_entry
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
    if auth_runtime or session_gate or session_flow or owner_firebase_port or admin_firebase_adapter or progress_evidence_store or progress_backup_coordinator or progress_backup_runtime:
        shutil.copy2(REPO / SESSION_MODULE, output / SESSION_MODULE)
    if session_flow or owner_firebase_port or admin_firebase_adapter or progress_evidence_store or progress_backup_coordinator or progress_backup_runtime:
        shutil.copy2(REPO / SESSION_FLOW_MODULE, output / SESSION_FLOW_MODULE)
    if owner_firebase_port or admin_firebase_adapter or progress_evidence_store or progress_backup_coordinator or progress_backup_runtime:
        for name in OWNER_PORT_MODULES:
            shutil.copy2(REPO / name, output / name)
    if admin_firebase_adapter:
        shutil.copy2(REPO / ADMIN_ADAPTER_MODULE, output / ADMIN_ADAPTER_MODULE)
    if legacy_progress_capture or progress_evidence_store or progress_backup_coordinator or progress_backup_runtime:
        shutil.copy2(REPO / LEGACY_PROGRESS_MODULE, output / LEGACY_PROGRESS_MODULE)
    if progress_evidence_store or progress_backup_coordinator or progress_backup_runtime:
        shutil.copy2(REPO / PROGRESS_EVIDENCE_MODULE, output / PROGRESS_EVIDENCE_MODULE)
        shutil.copy2(REPO / PURCHASE_EVIDENCE_MODULE, output / PURCHASE_EVIDENCE_MODULE)
    if progress_backup_coordinator or progress_backup_runtime:
        shutil.copy2(REPO / PROGRESS_BACKUP_MODULE, output / PROGRESS_BACKUP_MODULE)
    if progress_backup_runtime:
        shutil.copy2(REPO / PROGRESS_RUNTIME_MODULE, output / PROGRESS_RUNTIME_MODULE)
        main_path = output / 'lib/main.dart'
        main_path.write_text(bind_progress_backup(main_path.read_text(),
            verified['lib/main.dart'].decode(), measured=startup_metrics))
    if auth_runtime:
        import sys
        sys.path.insert(0, str(REPO / 'tools/app_stability'))
        from bind_auth_runtime import bind
        bind(output, startup_metrics=startup_metrics, progress_backup_runtime=progress_backup_runtime)
        shutil.copy2(REPO / 'lib/deda_auth_session_runtime.dart', output / 'lib/deda_auth_session_runtime.dart')
        shutil.copy2(REPO / 'lib/deda_section_operation_context.dart', output / 'lib/deda_section_operation_context.dart')
        shutil.copy2(REPO / 'lib/deda_published_place_recovery.dart', output / 'lib/deda_published_place_recovery.dart')
    if lazy_sections:
        shutil.copy2(REPO / LAZY_SECTIONS_MODULE, output / LAZY_SECTIONS_MODULE)
        main_path = output / 'lib/main.dart'
        main_path.write_text(bind_lazy_sections(main_path.read_text()))
    if section_entry:
        shutil.copy2(REPO / 'lib/deda_section_state.dart', output / 'lib/deda_section_state.dart')
        from bind_section_entries import bind_directory
        shutil.copy2(REPO / 'lib/deda_protected_section_entry.dart',
                     output / 'lib/deda_protected_section_entry.dart')
        shutil.copy2(REPO / 'lib/deda_incoming_request_lifecycle.dart',
                     output / 'lib/deda_incoming_request_lifecycle.dart')
        from bind_owned_frame_reader import bind as bind_owned_frame_reader
        shutil.copy2(REPO/'lib/deda_owned_frame_reader.dart', output/'lib/deda_owned_frame_reader.dart')
        bind_owned_frame_reader(output)
        from bind_owned_frame_status import bind as bind_owned_frame_status
        bind_owned_frame_status(output)
        bind_directory(output)
        # Append after the common lifetime binding, preserving existing UI.
        from bind_account_choice import bind as bind_account_choice
        for name in ('deda_account_choice_sync.dart', 'deda_account_choice_firebase.dart',
                     'deda_free_card_sync_bridge.dart'):
            shutil.copy2(REPO/'lib'/name, output/'lib'/name)
        bind_account_choice(output)
    return {'sectionEntry':section_entry, 'lazySections':lazy_sections, 'authRuntime':auth_runtime, 'verifiedFiles':len(verified), 'pilot':pilot,
            'startupMetrics':startup_metrics, 'sessionGateFoundation':auth_runtime or session_gate or session_flow or owner_firebase_port or admin_firebase_adapter or progress_evidence_store or progress_backup_coordinator or progress_backup_runtime,
            'sessionFlowPrototype':session_flow or owner_firebase_port or admin_firebase_adapter or progress_evidence_store or progress_backup_coordinator or progress_backup_runtime,
            'ownerFirebasePort':owner_firebase_port or admin_firebase_adapter or progress_evidence_store or progress_backup_coordinator or progress_backup_runtime,
            'adminFirebaseAdapter':admin_firebase_adapter,
            'legacyProgressCapture':legacy_progress_capture or progress_evidence_store or progress_backup_coordinator or progress_backup_runtime,
            'progressEvidenceStore':progress_evidence_store or progress_backup_coordinator or progress_backup_runtime,
            'progressBackupCoordinator':progress_backup_coordinator or progress_backup_runtime,
            'progressBackupRuntime':progress_backup_runtime,
            'flutterVersion':manifest['flutterVersion']}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output',type=Path)
    parser.add_argument('--section-entry',action='store_true')
    parser.add_argument('--lazy-sections',action='store_true')
    parser.add_argument('--auth-runtime',action='store_true')
    parser.add_argument('--pilot',action='store_true')
    parser.add_argument('--startup-metrics',action='store_true')
    parser.add_argument('--session-gate',action='store_true')
    parser.add_argument('--session-flow',action='store_true')
    parser.add_argument('--owner-firebase-port',action='store_true')
    parser.add_argument('--admin-firebase-adapter',action='store_true')
    parser.add_argument('--legacy-progress-capture',action='store_true')
    parser.add_argument('--progress-evidence-store',action='store_true')
    parser.add_argument('--progress-backup-coordinator',action='store_true')
    parser.add_argument('--progress-backup-runtime',action='store_true')
    args = parser.parse_args()
    print(json.dumps(restore(args.output,args.pilot,args.startup_metrics,args.session_gate,args.session_flow,args.owner_firebase_port,args.admin_firebase_adapter,args.legacy_progress_capture,args.progress_evidence_store,args.progress_backup_coordinator,args.progress_backup_runtime,args.auth_runtime,args.lazy_sections,args.section_entry)))
