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
    'deda_stage2_isolated_admin_dashboard_2026_11_21.dart',
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
    admin_path = project/'lib/admin_pages.dart'
    if not main_path.exists() or not pubspec_path.exists() or not admin_path.exists():
        raise ValueError('STAGE2_REQUIRES_FULL_ASSEMBLED_DEDA_APP')
    main = main_path.read_text()
    pubspec = pubspec_path.read_text()
    admin_source = admin_path.read_text()
    import_statement = "import 'deda_stage2_google_access_card_2026_11_21.dart';"
    isolated_admin_import = "import 'deda_stage2_isolated_admin_dashboard_2026_11_21.dart';"
    pilot_insert = """            if (dedaStableGoogleLoginEnabled) ...[
              DedaStage2GoogleAccessCard(
                onFreshGoogleIdentity: _onStage2FreshGoogleIdentity,
              ),
              const SizedBox(height: 12),
            ],
"""
    expected_import = "import 'deda_backend.dart';\n"
    isolated_main_import = "import 'deda_stage2_isolated_admin_identity_2026_11_21.dart';"
    settings_admin_anchor = ("                                final isAdmin =\n"
                             "                                    await DedaBackend.currentUserIsAdmin();")
    ISOLATED_SETTINGS_GATE = """                                // The public user session must never enter the
                                // legacy admin Dashboard with isolated admin ON.
                                if (dedaIsolatedAdminIdentityEnabled) {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => DedaAdminLoginPage(
                                        isArabic: DedaLanguageState.isArabic,
                                        dedaPhone: phone,
                                      ),
                                    ),
                                  );
                                  return;
                                }

"""
    guarded_boot = """String? _dedaStage2PendingGoogleUid;

Future<void> _dedaStage2LoadPreferencesWithGoogleFence() async {
  // Both the normal boot and measured-startup callback use this one gate.
  // Legacy preferences still load unmodified, even with the pilot disabled.
  await DedaPreferences.load();
  if (dedaStableGoogleLoginEnabled) {
    _dedaStage2PendingGoogleUid =
        await DedaStableGoogleLogin.pendingGoogleUid();
    if (_dedaStage2PendingGoogleUid != null) {
      DedaPreferences.suspendLegacyLiveSessionForGoogle();
    }
  }
}

Future<void> main() async {"""
    in_memory_fence = """  /// Clear ONLY the active in-memory old account after verified Google
  /// switching. Old stored details and Firestore records are never deleted.
  static void suspendLegacyLiveSessionForGoogle() {
    isLoggedIn = false;
    userName = '';
    phone = '';
    accountPhone = '';
    accountType = null;
    profileAvatarStyle = 0;
    profileFrameStyle = 0;
    profileBackgroundStyle = 0;
  }

"""
    handoff_method = """  Future<void> _onStage2FreshGoogleIdentity(String uid) async {
    if (await DedaStableGoogleLogin.pendingGoogleUid() != uid) {
      throw StateError('deda-stage2-google-handoff-principal-invalid');
    }
    // Prevent any old DEDA page/route from seeing this fresh Google UID.
    DedaPreferences.suspendLegacyLiveSessionForGoogle();
    _dedaStage2PendingGoogleUid = uid;
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (_) => DedaStage2GooglePendingPage(
          expectedUid: uid,
          loginPageBuilder: (_) => const LoginPage(),
          onSignedOut: () => _dedaStage2PendingGoogleUid = null,
        ),
      ),
      (_) => false,
    );
  }

"""
    expected_logout = "            OutlinedButton.icon(\n              onPressed: _logout,"
    ISOLATED_ADMIN_LOGIN = "      // Isolated Stage2 gateway. Never pass a secondary principal to the\n      // legacy Dashboard while its privileged calls still use default Auth.\n      if (dedaIsolatedAdminIdentityEnabled) {\n        final isolated = await DedaIsolatedAdminIdentity.open();\n        try {\n          await isolated.verifyAdminLogin(\n            email: _email.text,\n            password: _password.text,\n            dedaPhone: widget.dedaPhone,\n          );\n          final verifiedProfile = await isolated.readVerifiedAdminProfile(\n            dedaPhone: widget.dedaPhone,\n          );\n          if (verifiedProfile['mustChangePassword'] == true) {\n            throw StateError('deda-isolated-admin-password-change-pending');\n          }\n          await _saveIdentity();\n          if (!mounted) {\n            await isolated.signOutSecondaryAdmin();\n            return;\n          }\n          Navigator.pushReplacement(\n            context,\n            MaterialPageRoute(\n              builder: (_) => DedaStage2IsolatedDashboardPage(\n                isArabic: widget.isArabic,\n                dedaPhone: widget.dedaPhone,\n                admin: isolated,\n                profile: verifiedProfile,\n              ),\n            ),\n          );\n          return;\n        } catch (_) {\n          await isolated.signOutSecondaryAdmin();\n          rethrow;\n        }\n      }\n"
    if not verify_only:
        if import_statement in main or 'DedaStage2GoogleAccessCard(' in main:
            raise ValueError('STAGE2_ALREADY_APPLIED_VERIFY_ONLY')
        main = one(main, expected_import,
                   expected_import + import_statement + '\n' +
                   isolated_main_import + '\n', 'main-import')
        main = one(main, 'Future<void> main() async {',
                   guarded_boot, 'pending-google-global-state')
        # Measured-startup source intentionally loads preferences a second
        # time via its callback. Guard BOTH boot paths, never a different
        # legacy-account routine outside main(), and preserve DEDA load.
        start_marker = 'Future<void> main() async {'
        end_marker = 'class _DedaCleanPageTransitionsBuilder'
        if main.count(start_marker) != 1 or main.count(end_marker) != 1:
            raise ValueError('STAGE2_MAIN_STARTUP_BOUNDARY_CHANGED')
        prefix, after_start = main.split(start_marker, 1)
        startup, suffix = after_start.split(end_marker, 1)
        load_call = 'await DedaPreferences.load();'
        load_count = startup.count(load_call)
        if load_count not in (1, 2):
            raise ValueError(f'STAGE2_BOOT_LOAD_PATHS_CHANGED:found={load_count}')
        startup = startup.replace(
            load_call, 'await _dedaStage2LoadPreferencesWithGoogleFence();')
        main = prefix + start_marker + startup + end_marker + suffix
        main = one(main, '  static bool _liveVerifiedOriginalOwner(',
                   in_memory_fence + '  static bool _liveVerifiedOriginalOwner(',
                   'legacy-live-profile-fence')
        main = one(main, '  Future<void> _logout() async {',
                   handoff_method + '  Future<void> _logout() async {',
                   'google-auth-handoff-route')
        main = one(main, '          home: DedaPreferences.isLoggedIn\n',
                   """          home: _dedaStage2PendingGoogleUid != null
              ? DedaStage2GooglePendingPage(
                  expectedUid: _dedaStage2PendingGoogleUid!,
                  loginPageBuilder: (_) => const LoginPage(),
                  onSignedOut: () => _dedaStage2PendingGoogleUid = null,
                )
              : DedaPreferences.isLoggedIn
""", 'pending-boot-home-gate')
        main = one(main, expected_logout, pilot_insert + expected_logout,
                   'existing-signout-location')
        main = one(main, settings_admin_anchor,
                   ISOLATED_SETTINGS_GATE + settings_admin_anchor,
                   'settings-isolated-route-before-legacy-auth')
        if 'google_sign_in:' in pubspec:
            raise ValueError('STAGE2_EXISTING_GOOGLE_DEPENDENCY_REVIEW_REQUIRED')
        pubspec = one(pubspec, '  firebase_auth: ^5.3.3\n',
                      '  firebase_auth: ^5.3.3\n' + GOOGLE_DEPENDENCY + '\n',
                      'pubspec-google-signin')
        if "import 'deda_stage2_isolated_admin_dashboard_2026_11_21.dart';" in admin_source:
            raise ValueError('STAGE2_ALREADY_APPLIED_VERIFY_ONLY')
        admin_source = one(
            admin_source,
            "import 'deda_backend.dart';\n",
            "import 'deda_backend.dart';\n"
            "import 'deda_stage2_isolated_admin_identity_2026_11_21.dart';\n"
            "import 'deda_stage2_isolated_admin_dashboard_2026_11_21.dart';\n",
            'isolated-admin-ui-imports',
        )
        # Stage1 added DedaAuthRuntime.run around the ORIGINAL admin login
        # in the assembled app; the unassembled review copy has a direct call.
        # Insert the isolated gate at the common outer try block, NEVER
        # inside that public session transition coordinator.
        login_start = '  Future<void> _login() async {'
        login_end = '  Future<bool> _forcePasswordChange() async {'
        if admin_source.count(login_start) != 1 or admin_source.count(login_end) != 1:
            raise ValueError('STAGE2_STOP_SOURCE_DRIFT:admin-login-boundaries')
        before_login, remainder = admin_source.split(login_start, 1)
        login_body, after_login = remainder.split(login_end, 1)
        login_prelude = ("    setState(() {\n"
                         "      _loading = true;\n"
                         "      _error = null;\n"
                         "    });\n"
                         "    try {\n")
        if (login_body.count(login_prelude) != 1 or
                login_body.count('DedaBackend.signInAdmin(') != 1 or
                login_body.count('DedaAdminDashboardPage(') != 1):
            raise ValueError('STAGE2_STOP_SOURCE_DRIFT:admin-login-core')
        login_body = one(
            login_body, login_prelude,
            login_prelude + ISOLATED_ADMIN_LOGIN,
            'isolated-admin-safe-login-route',
        )
        admin_source = before_login + login_start + login_body + login_end + after_login
        # Fail closed when the isolated mode is explicitly enabled: the old
        # invitation flow uses public Auth and the old Dashboard uses DedaBackend.
        # Neither may run against the secondary administrative principal.
        invite_start = '  Future<void> _activate() async {\n'
        invite_block = """  Future<void> _activate() async {
    if (dedaIsolatedAdminIdentityEnabled) {
      setState(() => _error = t(
        'تفعيل الدعوات متوقف لحين إكمال عزل الإدارة.',
        'Invitation activation is unavailable during isolated admin migration.',
      ));
      return;
    }
"""
        admin_source = one(admin_source, invite_start, invite_block,
                           'legacy-invitation-auth-must-be-blocked')
        dashboard_start = ('class _DedaAdminDashboardPageState '
                           'extends State<DedaAdminDashboardPage> {')
        dashboard_end = 'class _AdminRequestsPage extends StatelessWidget {'
        if (admin_source.count(dashboard_start) != 1 or
                admin_source.count(dashboard_end) != 1):
            raise ValueError('STAGE2_STOP_SOURCE_DRIFT:legacy-dashboard-boundaries')
        before_dashboard, remainder = admin_source.split(dashboard_start, 1)
        dashboard_body, after_dashboard = remainder.split(dashboard_end, 1)
        dashboard_body = one(
            dashboard_body,
            '    super.initState();\n    _load();\n',
            '    super.initState();\n'
            '    if (!dedaIsolatedAdminIdentityEnabled) _load();\n',
            'legacy-dashboard-init-no-public-auth',
        )
        dashboard_body = one(
            dashboard_body,
            '  Widget build(BuildContext context) {\n    final profile = _profile;',
            """  Widget build(BuildContext context) {
    if (dedaIsolatedAdminIdentityEnabled) {
      return const Scaffold(
        body: Center(child: Text('Use isolated administrator sign-in.')),
      );
    }
    final profile = _profile;""",
            'legacy-dashboard-build-fail-closed',
        )
        admin_source = (before_dashboard + dashboard_start + dashboard_body +
                        dashboard_end + after_dashboard)
        # Validate all proposed anchor edits BEFORE writing anything.
        for name in MODULES:
            if (project/'lib'/name).exists():
                raise ValueError('STAGE2_SOURCE_OVERWRITE_FORBIDDEN:'+name)
            if not (REPO/'lib'/name).exists():
                raise ValueError('STAGE2_REQUIRED_MODULE_MISSING:'+name)
        existing_test = project/'test'/GOOGLE_TEST
        if existing_test.exists() and existing_test.read_bytes() != (
                REPO/'test'/GOOGLE_TEST).read_bytes():
            raise ValueError('STAGE2_EXISTING_TEST_MISMATCH_REFUSE_OVERWRITE')
        main_path.write_text(main)
        pubspec_path.write_text(pubspec)
        admin_path.write_text(admin_source)
        for name in MODULES:
            (project/'lib'/name).write_bytes((REPO/'lib'/name).read_bytes())
        (project/'test').mkdir(exist_ok=True)
        if not existing_test.exists():
            existing_test.write_bytes((REPO/'test'/GOOGLE_TEST).read_bytes())
    if (main.count(import_statement) != 1 or
        main.count(isolated_main_import) != 1 or
        main.count(ISOLATED_SETTINGS_GATE) != 1 or
        not main.index(ISOLATED_SETTINGS_GATE) <
            main.index(settings_admin_anchor) or
        (
        main.count('DedaStage2GoogleAccessCard(') != 1 or
        not main.index('DedaStage2GoogleAccessCard(') <
            main.index(expected_logout) or
        main.count('DedaPreferences.suspendLegacyLiveSessionForGoogle();') != 2 or
        main.count('DedaStage2GooglePendingPage(') != 2 or
        main.count('String? _dedaStage2PendingGoogleUid;') != 1 or
        main.count('Future<void> _dedaStage2LoadPreferencesWithGoogleFence() async {') != 1 or
        main.count('await DedaPreferences.load();') < 1 or
        main.count('await _dedaStage2LoadPreferencesWithGoogleFence();') not in (1, 2) or
        not main.index('await DedaStableGoogleLogin.pendingGoogleUid();') <
            main.index('await DedaTaskEngine.initializeForCurrentAccount();') or
        main.count(expected_logout) != 1 or
        pubspec.count(GOOGLE_DEPENDENCY) != 1
        )):
        raise ValueError('STAGE2_VERIFY_UI_DEPENDENCY_GATE_FAILED')
    # Both paths are compiled. The legacy route stays intact while Stage2
    # stays OFF; privileged secondary sessions never enter that old route.
    if (admin_source.count(isolated_admin_import) != 1 or
        admin_source.count("import 'deda_stage2_isolated_admin_identity_2026_11_21.dart';") != 1 or
        admin_source.count('if (dedaIsolatedAdminIdentityEnabled) {') != 3 or
        admin_source.count('DedaStage2IsolatedDashboardPage(') != 1 or
        admin_source.count('DedaBackend.signInAdmin(') != 1 or
        not admin_source.index('if (dedaIsolatedAdminIdentityEnabled) {') <
            admin_source.index('DedaBackend.signInAdmin(') or
        'deda-isolated-admin-password-change-pending' not in admin_source or
        'await isolated.signOutSecondaryAdmin();' not in admin_source or
        admin_source.count('if (!dedaIsolatedAdminIdentityEnabled) _load();') != 1 or
        admin_source.count('Use isolated administrator sign-in.') != 1 or
        admin_source.count('Invitation activation is unavailable during isolated admin migration.') != 1):
        raise ValueError('STAGE2_ADMIN_DASHBOARD_BRIDGE_GATE_FAILED')
    for name in MODULES:
        if (project/'lib'/name).read_bytes() != (REPO/'lib'/name).read_bytes():
            raise ValueError('STAGE2_VERIFY_SOURCE_HASH_MISMATCH:'+name)
    if (project/'test'/GOOGLE_TEST).read_bytes() != (
            REPO/'test'/GOOGLE_TEST).read_bytes():
        raise ValueError('STAGE2_VERIFY_TEST_SOURCE_MISMATCH')
    # The new feature can never be silently enabled in user builds.
    for name in MODULES:
        text = (project/'lib'/name).read_text()
        if name == 'deda_stage2_isolated_admin_dashboard_2026_11_21.dart':
            # This view reuses the *single* disabled-by-default constant
            # from isolated identity; never define another feature flag here.
            if (text.count('if (!dedaIsolatedAdminIdentityEnabled)') != 2 or
                    'bool.fromEnvironment(' in text or
                    'FirebaseAuth.instance' in text or
                    'FirebaseFirestore.instance' in text or
                    'DedaBackend.' in text):
                raise ValueError('STAGE2_ISOLATED_ADMIN_UI_MUST_REMAIN_CLOSED')
        elif name != 'deda_stage2_google_access_card_2026_11_21.dart':
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
        'isolatedRequestBridgePrepared': True,
        'onDeviceQaComplete': False,
        'verifyOnly': verify_only,
    }

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('project', type=Path)
    parser.add_argument('--verify-only', action='store_true')
    args = parser.parse_args()
    print(prepare(args.project, verify_only=args.verify_only))
