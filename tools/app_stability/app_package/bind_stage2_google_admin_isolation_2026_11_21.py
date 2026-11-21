#!/usr/bin/env python3
"""Stage2 Google + secondary admin Auth SOURCE integration in FULL isolated DEDA.

No Firebase Auth/Firestore mutation, APK, AAB, or Google Play action.
The Google feature and separate admin probe remain OFF until complete account
onboarding + privileged admin dashboard auth-scoping + on-device QA.
Do not modify original protected source, project configuration or UI locations.
"""
import argparse
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
MODULES = (
    'deda_stable_google_login_2026_11_21.dart',
    'deda_stage2_google_access_card_2026_11_21.dart',
    'deda_stage2_isolated_admin_identity_2026_11_21.dart',
)
GOOGLE_TEST = 'deda_stage2_google_and_admin_isolation_policy_test.dart'
GOOGLE_DEPENDENCY = '  google_sign_in: ^6.2.2'

def one(s, old, new, label):
    count = s.count(old)
    if count != 1:
        raise ValueError(f'STAGE2_STOP_SOURCE_DRIFT:{label}:found={count}')
    return s.replace(old, new, 1)

def prepare(project: Path, verify_only: bool = False):
    project = project.resolve()
    if project == REPO or project in REPO.parents or REPO in project.parents:
        raise ValueError('STAGE2_PROTECTED_OR_REPOSITORY_WRITE_REFUSED')
    main_path = project/'lib/main.dart'
    pubspec_path = project/'pubspec.yaml'
    if not main_path.exists() or not pubspec_path.exists():
        raise ValueError('STAGE2_REQUIRES_FULL_ASSEMBLED_DEDA_APP')
    main = main_path.read_text()
    pubspec = pubspec_path.read_text()
    import_statement = "import 'deda_stage2_google_access_card_2026_11_21.dart';"
    pilot_insert = """            if (dedaStableGoogleLoginEnabled) ...[
              const DedaStage2GoogleAccessCard(),
              const SizedBox(height: 12),
            ],
"""
    expected_import = "import 'deda_backend.dart';\n"
    expected_logout = "            OutlinedButton.icon(\n              onPressed: _logout,"
    if not verify_only:
        if import_statement in main or 'DedaStage2GoogleAccessCard()' in main:
            raise ValueError('STAGE2_ALREADY_APPLIED_VERIFY_ONLY')
        main = one(main, expected_import,
                   expected_import + import_statement + '\n', 'main-import')
        main = one(main, expected_logout, pilot_insert + expected_logout,
                   'existing-signout-location')
        if 'google_sign_in:' in pubspec:
            raise ValueError('STAGE2_EXISTING_GOOGLE_DEPENDENCY_REVIEW_REQUIRED')
        pubspec = one(pubspec, '  firebase_auth: ^5.3.3\n',
                      '  firebase_auth: ^5.3.3\n' + GOOGLE_DEPENDENCY + '\n',
                      'pubspec-google-signin')
        # Validate all proposed anchor edits BEFORE writing anything.
        for name in MODULES:
            if (project/'lib'/name).exists():
                raise ValueError('STAGE2_SOURCE_OVERWRITE_FORBIDDEN:'+name)
            if not (REPO/'lib'/name).exists():
                raise ValueError('STAGE2_REQUIRED_MODULE_MISSING:'+name)
        if (project/'test'/GOOGLE_TEST).exists():
            raise ValueError('STAGE2_EXISTING_TEST_OVERWRITE_FORBIDDEN')
        main_path.write_text(main)
        pubspec_path.write_text(pubspec)
        for name in MODULES:
            (project/'lib'/name).write_bytes((REPO/'lib'/name).read_bytes())
        (project/'test').mkdir(exist_ok=True)
        (project/'test'/GOOGLE_TEST).write_bytes(
            (REPO/'test'/GOOGLE_TEST).read_bytes())
    if main.count(import_statement) != 1 or (
        main.count('const DedaStage2GoogleAccessCard()') != 1 or
        not main.index('const DedaStage2GoogleAccessCard()') <
            main.index(expected_logout) or
        main.count(expected_logout) != 1 or
        pubspec.count(GOOGLE_DEPENDENCY) != 1
    ):
        raise ValueError('STAGE2_VERIFY_UI_DEPENDENCY_GATE_FAILED')
    for name in MODULES:
        if (project/'lib'/name).read_bytes() != (REPO/'lib'/name).read_bytes():
            raise ValueError('STAGE2_VERIFY_SOURCE_HASH_MISMATCH:'+name)
    if (project/'test'/GOOGLE_TEST).read_bytes() != (
            REPO/'test'/GOOGLE_TEST).read_bytes():
        raise ValueError('STAGE2_VERIFY_TEST_SOURCE_MISMATCH')
    # The new feature can never be silently enabled in user builds.
    for name in MODULES:
        text = (project/'lib'/name).read_text()
        if name != 'deda_stage2_google_access_card_2026_11_21.dart':
            if 'defaultValue: false' not in text:
                raise ValueError('STAGE2_FEATURE_MUST_DEFAULT_OFF:'+name)
    if 'DedaIsolatedAdminIdentity' not in (project/'lib'/MODULES[2]).read_text():
        raise ValueError('STAGE2_ADMIN_AUTH_ISOLATION_NOT_PRESENT')
    return {
        'status': 'PASS_STAGE2_GOOGLE_ADMIN_SOURCE_BOUND_QA_ONLY',
        'fullAppMainPath': str(main_path),
        'firebaseProductionChanged': False,
        'playChanged': False,
        'featureDefaultOff': True,
        'adminDashboardAuthorized': False,
        'onDeviceQaComplete': False,
        'verifyOnly': verify_only,
    }

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('project', type=Path)
    parser.add_argument('--verify-only', action='store_true')
    args = parser.parse_args()
    print(prepare(args.project, verify_only=args.verify_only))
