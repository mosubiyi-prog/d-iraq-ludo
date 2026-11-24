"""Bind phase-01 hold to the assembled full app in disposable QA only.

Retain the original startup body verbatim, but remove it from the public entry
point. The only phase-01 entry is the same approved offline Core probe.
Never launch the original app, create Auth users, or distribute an APK.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET

import stage01_lab_gate_2026_11_25 as gate
from stage01_lab_prepare_probe_2026_11_25 import ANDROID, TOOLS, render_probe

EXPECTED_CONFIG = '705e70c89ef87374a56ed7cf1f31fc408050935b04a9b4120b8b11685872a323'
ENTRY = 'Future<void> main() async {'
HELD = 'Future<void> _dedaStage01HeldOriginalMain() async {'
IMPORT = "import 'deda_stage01_lab_entry_2026_11_25.dart' as stage01Lab;\n"
WRAPPER = "Future<void> main() async {\n  await stage01Lab.main();\n}\n\n"
PERMISSIONS = ('android.permission.INTERNET', 'android.permission.ACCESS_NETWORK_STATE')


def bind(root, config):
    root = Path(root).resolve()
    repo = gate.ROOT.resolve()
    gate.require(root.is_dir() and root != repo and repo not in root.parents and root not in repo.parents,
                 'DISPOSABLE_FULL_ASSEMBLY_REQUIRED')
    gate.validate(config, gate.PACKAGE)
    canonical = json.dumps(config, sort_keys=True, separators=(',', ':')).encode()
    gate.require(hashlib.sha256(canonical).hexdigest() == EXPECTED_CONFIG, 'LAB_CONFIG_FINGERPRINT_REQUIRED')
    main = root/'lib/main.dart'
    original = main.read_text()
    gate.require(original.count(ENTRY) == 1 and HELD not in original and IMPORT not in original,
                 'FULL_STARTUP_ANCHOR_CHANGED')
    gate.require('DedaApp' in original and 'DedaMapStyle' in original and 'Firebase.initializeApp' in original,
                 'FULL_DART_SOURCE_REQUIRED')
    gate.require(original.startswith('import ') or re.search(r"(?m)^import ", original), 'IMPORT_ANCHOR_REQUIRED')
    probe = root/'lib/deda_stage01_lab_entry_2026_11_25.dart'
    gate.require(not probe.exists() and not list(root.rglob('google-services.json')), 'PRODUCTION_CONFIG_OR_DUPLICATE')
    # Preserve namespace/Kotlin classes; only isolate Android application ID.
    app_gradle = root/'android/app/build.gradle.kts'
    settings = root/'android/settings.gradle.kts'
    gradle = app_gradle.read_text()
    setting_text = settings.read_text()
    gate.require(re.findall(r'applicationId\s*=\s*"([^"]+)"', gradle) == [gate.PRODUCTION_PACKAGE],
                 'ORIGINAL_APPLICATION_ID_ANCHOR')
    gradle = re.sub(r'(applicationId\s*=\s*")'+re.escape(gate.PRODUCTION_PACKAGE)+r'(")',
                    r'\g<1>'+gate.PACKAGE+r'\2', gradle)
    for path, body in ((app_gradle, gradle), (settings, setting_text)):
        gate.require(body.count('com.google.gms.google-services') == 1, 'GOOGLE_PLUGIN_ANCHOR')
    gradle = '\n'.join(l for l in gradle.split('\n') if 'com.google.gms.google-services' not in l)
    setting_text = '\n'.join(l for l in setting_text.split('\n') if 'com.google.gms.google-services' not in l)
    # Never load production signing material; debug build only. Native auto-init
    # and all network permissions are removed from the final packaged manifest.
    manifests = list((root/'android/app/src').rglob('AndroidManifest.xml'))
    primary = root/'android/app/src/main/AndroidManifest.xml'
    gate.require(primary in manifests, 'MANIFEST_REQUIRED')
    parsed = [(p, ET.parse(p)) for p in manifests]
    for p, tree in parsed:
        doc = tree.getroot()
        for node in list(doc):
            if node.tag.startswith('uses-permission') and node.get('{'+ANDROID+'}name') in PERMISSIONS:
                doc.remove(node)
        if p == primary:
            for name in PERMISSIONS:
                ET.SubElement(doc, 'uses-permission', {'{'+ANDROID+'}name':name,'{'+TOOLS+'}node':'remove'})
            app = doc.find('application')
            gate.require(app is not None, 'APPLICATION_REQUIRED')
            app.set('{'+ANDROID+'}allowBackup', 'false')
            app.set('{'+ANDROID+'}label', 'DEDA LAB - PHASE 01 HOLD')
            for name in ('com.google.firebase.provider.FirebaseInitProvider',):
                ET.SubElement(app, 'provider', {'{'+ANDROID+'}name':name,'{'+TOOLS+'}node':'remove'})
    # Use synthetic API key for the compiled offline package. The real config
    # is verified above and independently used by the readonly metadata check.
    dart = render_probe(gate, 'AIza'+'x'*35)
    modified = original.replace(ENTRY, WRAPPER+HELD, 1)
    first = re.search(r'(?m)^import ', modified).start()
    modified = modified[:first]+IMPORT+modified[first:]
    gate.require(modified.replace(IMPORT, '', 1).replace(WRAPPER+HELD, ENTRY, 1) == original,
                 'ORIGINAL_STARTUP_OR_SOURCE_CHANGED')
    gate.require(modified.count('stage01Lab.main()') == 1 and modified.count('_dedaStage01HeldOriginalMain(') == 1,
                 'ORIGINAL_STARTUP_REACHABLE_FROM_ENTRY')
    for p, tree in parsed:
        tree.write(p, encoding='utf-8', xml_declaration=True)
    app_gradle.write_text(gradle)
    settings.write_text(setting_text)
    main.write_text(modified)
    probe.write_text(dart)
    test = root/'test/deda_stage01_full_entry_hold_test.dart'
    gate.require(not test.exists(), 'TEST_EXISTS')
    test.write_text("""import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/main.dart' as full;

void main() {
  testWidgets('full entry stays in phase 01 without native Firebase',
      (tester) async {
    // Platform-channel replies and timeout timers must run outside FakeAsync.
    await tester.runAsync(() async {
      await full.main().timeout(const Duration(seconds: 10));
    });
    await tester.pump();
    await tester.pumpAndSettle(const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
    expect(find.text('BLOCKED: phase 01 lab configuration'), findsOneWidget);
  });
}
""")
    print('PASS_FULL_STARTUP_BODY_PRESERVED_PHASE01_ENTRY_BOUND')
    print('APPROVED_REAL_CONFIG_VALIDATED_SYNTHETIC_OFFLINE_BUILD_ONLY')


if __name__ == '__main__':
    try:
        bind(Path(sys.argv[1]), json.loads(os.environ['LAB_CONFIG']))
    except Exception as exc:
        # Never print config, key or file contents.
        print('BLOCK_FULL_LAB_BIND', type(exc).__name__)
        raise SystemExit(1) from None
