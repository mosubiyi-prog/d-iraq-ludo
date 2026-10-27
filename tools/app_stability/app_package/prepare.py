"""Prepare isolated signed-build INPUTS from the pinned app source, not history.

Does not invoke Flutter, sign, run an app, deploy or export signing material.
Caller first creates a clean Android project with pinned Flutter3.47.7.
"""
import argparse
import ast
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import runpy
import shutil

REPO = Path(__file__).resolve().parents[3]
PACKAGE = 'com.diraq.ludo.d_iraq_ludo'
# Exact flags from the accepted100379 signed workflow. New flags below are
# isolated client integration, while financial archive/restore stays OFF.
BASE_FLAGS = {
    'USE_NEXT_GEN_SDK': True, 'DEDA_DAILY_TASK_DISPLAY_PREVIEW': False,
    'DEDA_SOCIAL_TASKS_UI_PREVIEW': True, 'DEDA_SERVER_AUTOMATIONS_LIVE': False,
    'DEDA_PLACE_ENGAGEMENT_LIVE': True, 'DEDA_SPARK_FIRESTORE_LIVE': True,
    'DEDA_OWNER_PLACE_BRANDING_LIVE': True, 'DEDA_OWNER_PLACE_LOGO_UPLOADS_LIVE': False,
    'DEDA_PREMIUM_IDS_SERVER_LIVE': False, 'DEDA_PREMIUM_ALIAS_ROUTING_LIVE': False,
    'DEDA_OWNER_PRIVATE_SANDBOX': False,
    'DEDA_STAGE71_ADMIN200_RULES_AND_PRIVATE_CATALOG_DEPLOYED': True,
    'DEDA_QA32_SPARK_PUBLIC_IDS_LIVE': True, 'DEDA_LAB_FRAME_ATOMIC_CHECKOUT_APPROVED': True,
}


def flags(variant):
    if variant not in ('control', 'candidate'):
        raise ValueError('Unknown internal variant')
    enabled = variant == 'candidate'
    return {**BASE_FLAGS, 'DEDA_STABILITY_STARTUP_METRICS': True,
            'DEDA_STABILITY_IDENTITY_PILOT': enabled,
            'DEDA_STABILITY_AUTH_RUNTIME': enabled,
            'DEDA_STABILITY_SECTION_ENTRY': enabled,
            'DEDA_STABILITY_LAZY_SECTIONS': enabled,
            # The client is packaged for isolated integration. The new rules
            # still need an explicit reviewed production deployment.
            'DEDA_STABILITY_PRIVATE_DATA': enabled,
            'DEDA_STABILITY_PROGRESS_BACKUP_PILOT': False}


def known_admob_ids():
    tree = ast.parse((REPO/'tools/apply_real_admob_ids_100257_2026_10_03.py').read_text())
    values = {}
    for node in tree.body:
        if isinstance(node, ast.Assign) and len(node.targets) == 1 and isinstance(node.targets[0], ast.Name):
            if node.targets[0].id in ('TEST_APP_ID', 'REAL_APP_ID'):
                values[node.targets[0].id] = ast.literal_eval(node.value)
    if set(values) != {'TEST_APP_ID', 'REAL_APP_ID'}:
        raise ValueError('Original AdMob ID source changed')
    return values


def switch_manifest_id(text):
    ids = known_admob_ids()
    if text.count(ids['TEST_APP_ID']) != 1 or ids['REAL_APP_ID'] in text:
        raise ValueError('Original manifest ID anchor changed')
    return text.replace(ids['TEST_APP_ID'], ids['REAL_APP_ID'], 1)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def prepare(project, variant):
    flags(variant)
    project = Path(project).resolve()
    if project == REPO or REPO in project.parents or project in REPO.parents:
        raise ValueError('Build inputs must be outside the repository')
    if not (project/'android/app/build.gradle.kts').is_file() or not (project/'lib/main.dart').is_file():
        raise ValueError('Pinned Flutter Android scaffold required')
    record = project/'internal-build-inputs.json'
    source = project.parent/(project.name+'-verified-source')
    if source.exists() or record.exists():
        raise ValueError('Do not overwrite prepared build inputs')
    config = json.loads((REPO/'google-services.json').read_text())
    clients = [c for c in config.get('client', []) if
               c.get('client_info', {}).get('android_client_info', {}).get('package_name') == PACKAGE]
    if len(clients) != 1 or config.get('project_info', {}).get('project_id') != 'deda-25b88':
        raise ValueError('Original Firebase package/project mismatch')
    shutil.copy2(REPO/'google-services.json', project/'android/app/google-services.json')
    shutil.copy2(REPO/'deda_app_icon.png', project/'deda_app_icon.png')
    previous = Path.cwd()
    try:
        os.chdir(project)
        for script in ('configure_rewarded_ads_android_build_2026_10_02.py',
                       'apply_admob_android16_workmanager_fix_2026_10_02.py',
                       'android_media_save_patch.py'):
            runpy.run_path(str(REPO/'tools'/script), run_name='__main__')
        manifest = project/'android/app/src/main/AndroidManifest.xml'
        manifest.write_text(switch_manifest_id(manifest.read_text()))
    finally:
        os.chdir(previous)
    spec = importlib.util.spec_from_file_location('internal_restore', REPO/'tools/restore_deda_stability_baseline.py')
    restore = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(restore)
    options = {'startup_metrics': True}
    if variant == 'candidate':
        options.update(auth_runtime=True, pilot=True, admin_firebase_adapter=True,
                       progress_backup_runtime=True, section_entry=True, lazy_sections=True)
    restore.restore(source, **options)
    if variant == 'candidate':
        # Verified identity remains server-authoritative. Suppress the old-ID
        # flash while it is being resolved, without touching auth or wallets.
        patch_spec = importlib.util.spec_from_file_location(
            'deda_id_no_flash', REPO/'tools/app_stability/bind_active_id_no_flash.py')
        patch = importlib.util.module_from_spec(patch_spec)
        patch_spec.loader.exec_module(patch)
        patch.bind(source)
        unified_spec = importlib.util.spec_from_file_location(
            'deda_id_unified', REPO/'tools/app_stability/bind_unified_active_id_100382.py')
        unified = importlib.util.module_from_spec(unified_spec)
        unified_spec.loader.exec_module(unified)
        unified.bind(source)
        # Retain the approved replacement task signals, not traffic modifications.
        # The baseline quiz already has its original 20 sign topics x 5
        # presentational variants = 100 items, with 4 choices each.
        # No 500-bank asset, QA replay, one-time reset, or new quiz artwork.
        # Keep identity, session, places, profiles and wallet code untouched.
        tasks_spec = importlib.util.spec_from_file_location(
            'deda_tasks_100383', REPO/'tools/app_stability/bind_tasks_integrated_100383.py')
        tasks = importlib.util.module_from_spec(tasks_spec)
        tasks_spec.loader.exec_module(tasks)
        tasks.bind(source)
        old_quiz = (source/'lib/traffic_quiz_page.dart').read_text()
        if ('const int _trafficVariantsPerBase = 5;' not in old_quiz
                or "if (expanded.length != 100)" not in old_quiz
                or '_dedaTraffic500Asset' in old_quiz):
            raise ValueError('DEDA 100387: original 100-question quiz not restored')
        if (source/'assets/deda_traffic_500_bank_ar_v1.json').exists():
            raise ValueError('DEDA 100387: 500-question asset unexpectedly packaged')
    for name in ('lib', 'assets', 'test'):
        shutil.copytree(source/name, project/name, dirs_exist_ok=True)
    for name in ('pubspec.yaml', 'pubspec.lock'):
        shutil.copy2(source/name, project/name)
    sources = {str(p.relative_to(project)): sha(p) for p in (project/'lib').rglob('*.dart')}
    sources.update({name: sha(project/name) for name in ('pubspec.yaml', 'pubspec.lock')})
    platform = {str(p.relative_to(project)): sha(p) for p in (project/'android').rglob('*')
                if p.is_file() and (p.suffix in ('.kt', '.kts', '.xml', '.properties') or p.name == 'gradlew')
                and p.name != 'local.properties'}
    data = {'format': 1, 'variant': variant, 'package': PACKAGE, 'versionCode': 100387,
            'flutterVersion': '3.47.7', 'flags': flags(variant), 'sourceHashes': sources,
            'locationAcquisitionDeadlineSeconds': 12 if variant == 'candidate' else None,
            'accountScopedNotificationLifecycle': variant == 'candidate',
            'platformHashes': platform, 'googleConfigSha256': sha(REPO/'google-services.json'),
            'completeOwnerDelivery': False, 'financialRestoreEnabled': False,
            'productionExecutionPerformed': False, 'purpose': 'INTERNAL INTEGRATION ONLY - NOT FINAL OWNER DELIVERY'}
    record.write_text(json.dumps(data, indent=2)+'\n')
    return data


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('project', type=Path)
    parser.add_argument('--variant', required=True, choices=('control', 'candidate'))
    args = parser.parse_args()
    result = prepare(args.project, args.variant)
    print(json.dumps({'variant': result['variant'], 'verifiedSourceFiles': len(result['sourceHashes']),
                      'financialRestoreEnabled': False, 'completeOwnerDelivery': False}))
