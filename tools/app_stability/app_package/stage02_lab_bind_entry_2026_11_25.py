"""Reuse the verified phase-01 hold; bind phase-02 Auth-only entry.
Full-source packaging remains offline. Live runtime uses the identical entry
and guardian in an Auth/Core-only disposable Android scaffold, no other SDKs.
"""
import hashlib
import json
import os
from pathlib import Path
import shutil
import sys
import xml.etree.ElementTree as ET

import stage01_lab_gate_2026_11_25 as gate
from stage01_lab_bind_full_2026_11_25 import EXPECTED_CONFIG, HELD, IMPORT, WRAPPER
from stage01_lab_prepare_probe_2026_11_25 import ANDROID, TOOLS

ENTRY = 'deda_stage02_lab_entry_2026_11_25.dart'
OPTIONS = 'deda_stage02_lab_options_2026_11_25.dart'
FILES = (ENTRY, 'deda_stage02_lab_single_uid_2026_11_25.dart',
         'deda_auth_session_runtime.dart', 'deda_session_transition_gate.dart',
         'deda_section_operation_context.dart')


def prepare(root, mode, config):
    root = Path(root).resolve()
    repo = gate.ROOT.resolve()
    gate.require(root.is_dir() and root != repo and repo not in root.parents
                 and root not in repo.parents, 'DISPOSABLE_ROOT_REQUIRED')
    gate.validate(config, gate.PACKAGE)
    canonical = json.dumps(config, sort_keys=True, separators=(',', ':')).encode()
    gate.require(hashlib.sha256(canonical).hexdigest() == EXPECTED_CONFIG,
                 'LAB_CONFIG_FINGERPRINT_REQUIRED')
    gate.require(not list(root.rglob('google-services.json')), 'NATIVE_CONFIG_FORBIDDEN')
    lib = root/'lib'
    main = lib/'main.dart'
    gate.require(not (lib/ENTRY).exists() and not (lib/OPTIONS).exists(), 'DUPLICATE_ENTRY')
    if mode == 'full-offline':
        original = main.read_text()
        gate.require(original.count(IMPORT) == 1 and original.count(WRAPPER+HELD) == 1
                     and original.count('_dedaStage01HeldOriginalMain(') == 1,
                     'PHASE01_HOLD_REQUIRED')
        new_import = "import '"+ENTRY+"' as stage02Lab;\n"
        new_wrapper = WRAPPER.replace('stage01Lab.main()', 'stage02Lab.main()')
        modified = original.replace(IMPORT, new_import, 1).replace(WRAPPER, new_wrapper, 1)
        gate.require(modified.replace(new_import, IMPORT, 1).replace(new_wrapper, WRAPPER, 1)
                     == original, 'ORIGINAL_BODY_CHANGED')
        gate.require((lib/FILES[1]).is_file(), 'MISSING_EXISTING_UID_GUARD')
        shutil.copyfile(repo/'lib'/ENTRY, lib/ENTRY)
        main.write_text(modified)
        key = 'AIza'+'x'*35
        test = root/'test/deda_stage02_full_entry_test.dart'
        test.write_text("""import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/main.dart' as full;
void main() {
  testWidgets('full entry fails closed without native Firebase', (tester) async {
    await tester.runAsync(() async {
      await full.main().timeout(const Duration(seconds: 20));
    });
    await tester.pump();
    await tester.pumpAndSettle(const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
    expect(find.text('BLOCKED_STAGE02_CONFIG_OR_AUTH_INIT'), findsOneWidget);
  });
}
""")
    elif mode == 'auth-runtime':
        gate.require(len(list(lib.glob('*.dart'))) == 1, 'FRESH_AUTH_SCAFFOLD_REQUIRED')
        for name in FILES:
            shutil.copyfile(repo/'lib'/name, lib/name)
        main.write_text("import '"+ENTRY+"' as entry;\nFuture<void> main() => entry.main();\n")
        key = config['client'][0]['api_key'][0]['current_key']
        (root/'pubspec.yaml').write_text("""name: uiddevice
publish_to: none
version: 0.2.0+2
environment:
  sdk: ">=3.6.0 <4.0.0"
dependencies:
  flutter:
    sdk: flutter
  firebase_core: 3.15.2
  firebase_auth: 5.7.0
flutter:
  uses-material-design: true
""")
        manifest = root/'android/app/src/main/AndroidManifest.xml'
        tree = ET.parse(manifest)
        doc = tree.getroot()
        app = doc.find('application')
        app.set('{'+ANDROID+'}allowBackup','false')
        app.set('{'+ANDROID+'}label','DEDA LAB AUTH ONLY')
        ET.SubElement(doc,'uses-permission',{'{'+ANDROID+'}name':'android.permission.INTERNET'})
        ET.SubElement(app,'provider',{'{'+ANDROID+'}name':'com.google.firebase.provider.FirebaseInitProvider',
                                     '{'+TOOLS+'}node':'remove'})
        tree.write(manifest,encoding='utf-8',xml_declaration=True)
    else:
        raise ValueError('invalid mode')
    (lib/OPTIONS).write_text("import 'package:firebase_core/firebase_core.dart';\n"
        "const stage02LabOptions = FirebaseOptions(apiKey: "+json.dumps(key)+
        ", appId: '"+gate.APP_ID+"', messagingSenderId: '"+gate.NUMBER+
        "', projectId: '"+gate.PROJECT+"', storageBucket: '"+gate.BUCKET+"');\n")
    print('PASS_STAGE02_ENTRY_BOUND_'+mode.upper().replace('-','_'))


if __name__ == '__main__':
    try:
        prepare(sys.argv[1],sys.argv[2],json.loads(os.environ['LAB_CONFIG']))
    except Exception as exc:
        print('BLOCK_STAGE02_ENTRY_BIND',type(exc).__name__)
        raise SystemExit(1) from None
