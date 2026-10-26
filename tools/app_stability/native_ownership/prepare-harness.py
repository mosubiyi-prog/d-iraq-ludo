"""Original PIN and inventory readers; purchases forbidden in an isolated app."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import sys

ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/'tools/app_stability'))
from bind_owned_frame_reader import bind_source
spec=importlib.util.spec_from_file_location('owned_transport_tools',ROOT/'tools/app_stability/native_transport/prepare-harness.py')
transport=importlib.util.module_from_spec(spec);spec.loader.exec_module(transport)
PACKAGE='dev.deda.qa.deda_owned_qa'
ORIGINAL=('deda_pin_auth.dart','deda_lab_frame_secure_checkout.dart','deda_owner18_frame_checkout.dart',
          'deda_owner18_cosmetics.dart','deda_owner18_original_account_proof.dart','deda_qa32_manager_original_owner_proof.dart')
CURRENT=('deda_owned_frame_reader.dart','deda_auth_session_runtime.dart','deda_section_operation_context.dart','deda_session_transition_gate.dart')

def gift_read_methods(source):
    """Keep original signatures and bodies; no rewritten wallet/query logic."""
    anchors=(
      ('  static String _normalizePersonalDedaId(', '  /// Creates the protected one-million administrative gift wallet'),
      ('  static List<Map<String, dynamic>> _sortedGiftMaps(', '  static Stream<List<Map<String, dynamic>>> watchCurrentAdminDiamondGifts()'),
      ('  static Future<int> personalGiftedDiamondBalance(', '  /// The personal account may only DECREASE'),
    )
    parts=[]
    for first,last in anchors:
        if source.count(first)!=1 or source.count(last)!=1:raise ValueError('original gift read source drift')
        start=source.index(first);end=source.index(last,start)
        parts.append(source[start:end])
    return '\n'.join(parts)

def prepare(harness,baseline):
    harness,baseline=Path(harness).resolve(),Path(baseline).resolve()
    if harness==ROOT or ROOT in harness.parents:raise ValueError('harness must be outside repository')
    app=harness/'android/app';manifest=app/'src/main/AndroidManifest.xml'
    if not (harness/'.metadata').is_file() or PACKAGE not in (app/'build.gradle.kts').read_text() or (app/'google-services.json').exists():
        raise ValueError('isolated original ownership harness required')
    if (harness/'native-owned-source-manifest.json').exists():raise ValueError('refuse overwrite')
    expected=json.loads((ROOT/'tools/app_stability/100380-baseline-manifest.json').read_text())
    sources={}
    for name in ORIGINAL:
        b=(baseline/'lib'/name).read_bytes()
        if hashlib.sha256(b).hexdigest()!=expected['files']['lib/'+name]:raise ValueError('original source hash drift')
        sources[name]=bind_source(b.decode()).encode() if name=='deda_lab_frame_secure_checkout.dart' else b
    for name in CURRENT:sources[name]=(ROOT/'lib'/name).read_bytes()
    sources['main.dart']=Path(__file__).with_name('main.dart').read_bytes()
    backend=(baseline/'lib/deda_backend.dart').read_bytes()
    if hashlib.sha256(backend).hexdigest()!=expected['files']['lib/deda_backend.dart']:raise ValueError('original backend source hash drift')
    extracted=gift_read_methods(backend.decode())
    template=Path(__file__).with_name('backend-stub.dart').read_text()
    if template.count('  // ORIGINAL_GIFT_READ_METHODS')!=1:raise ValueError('gift read template drift')
    sources['deda_backend.dart']=template.replace('  // ORIGINAL_GIFT_READ_METHODS',extracted).encode()
    locked=transport.versions(baseline/'pubspec.lock');wanted={k:v for k,v in locked.items() if k.startswith(transport.FAMILIES)}
    lines=['name: deda_owned_qa','publish_to: none','version: 0.0.1+1','environment:',"  sdk: '>=3.4.0 <4.0.0'",'dependencies:','  flutter:','    sdk: flutter']
    lines += [f'  {name}: {wanted[name]}' for name in transport.FAMILIES]
    lines += ['dependency_overrides:']+[f'  {k}: {v}' for k,v in sorted(wanted.items())]+['flutter:','  uses-material-design: true']
    (harness/'pubspec.yaml').write_text('\n'.join(lines)+'\n');(harness/'analysis_options.yaml').unlink(missing_ok=True)
    shutil.rmtree(harness/'test',ignore_errors=True)
    for name,b in sources.items():(harness/'lib'/name).write_bytes(b)
    text=manifest.read_text().replace('<application','<application android:usesCleartextTraffic="true"',1)
    if 'android.permission.INTERNET' not in text:text=text.replace('<application','<uses-permission android:name="android.permission.INTERNET"/>\n<application',1)
    manifest.write_text(text)
    (harness/'native-owned-source-manifest.json').write_text(json.dumps({'scope':'original PIN, inventory and gift wallet/history readers; synthetic historical fixtures only',
      'package':PACKAGE,'projectId':'demo-deda-live-progress-compat','files':{'lib/'+k:hashlib.sha256(v).hexdigest() for k,v in sources.items()},
      'originalSourceHashes':{name:expected['files']['lib/'+name] for name in ORIGINAL},'pinnedTransportVersions':wanted,
      'originalBackendSHA256':hashlib.sha256(backend).hexdigest(),'originalGiftReadMethodsSHA256':hashlib.sha256(extracted.encode()).hexdigest(),
      'originalGiftReadMethodsByteExact':True,'earnedBalanceMigrationTested':False,'generalManagerWalletTested':False,
      'purchaseDependenciesAreFailingStubs':True,'actualPurchaseTested':False},indent=2)+'\n')

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('harness',type=Path);parser.add_argument('baseline',type=Path);parser.add_argument('--verify',action='store_true');a=parser.parse_args()
    if a.verify:transport.verify(a.harness,a.baseline)
    else:prepare(a.harness,a.baseline)
