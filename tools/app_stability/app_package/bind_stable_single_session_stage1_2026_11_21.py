#!/usr/bin/env python3
"""DEDA stage 1: bind hard session safeguards into an ISOLATED assembled app.

A source patch, not an Auth/Firestore write or a working admin replacement.
Fail closed unless the exact previously reviewed Flutter source is present.
Never edit the repository checkout, protected reference, Firebase, or Google Play.
"""
import argparse
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
BACKEND = "lib/deda_backend.dart"
PIN = "lib/deda_pin_auth.dart"

def change_once(text: str, before: str, after: str, path: str) -> str:
    count = text.count(before)
    if count != 1:
        raise ValueError(f"STAGE1_SOURCE_ANCHOR_CHANGED:{path}:found={count}")
    return text.replace(before, after, 1)

def change_variant(text: str, variants: list[tuple[str, str]], path: str) -> str:
    """Accept ONLY one of the two reviewed exact source shapes."""
    matches = [(before, after) for before, after in variants if text.count(before) == 1]
    if len(matches) != 1 or any(text.count(before) > 1 for before, _ in variants):
        raise ValueError(f"STAGE1_SOURCE_ANCHOR_CHANGED:{path}:variant_matches={len(matches)}")
    before, after = matches[0]
    return text.replace(before, after, 1)

def admin_authority_bounds(text, start, stop):
    if text.count(start) != 1 or text.count(stop) != 1:
        raise ValueError("STAGE1_ADMIN_AUTHORITY_BOUNDARY_CHANGED")
    a = text.index(start)
    z = text.index(stop, a + len(start))
    return a, z

def patch_admin_authority(text):
    # One strict role predicate for the legacy authority reads. Keep the
    # historical display normalizer intact and the isolated Admin Auth separate.
    anchor = "  static bool adminHasPermission("
    text = change_once(text, anchor, """  static String? _explicitAdminAuthorityRole(dynamic value) {
    final raw = (value ?? '').toString().trim();
    if (raw.isEmpty) return null;
    final role = normalizeAdminRole(raw);
    return const <String>{'general_manager', 'deputy_manager',
      'employee', 'province_agent'}.contains(role) ? role : null;
  }

""" + anchor, BACKEND)
    def scoped(start, stop, transform):
        nonlocal text
        a,z = admin_authority_bounds(text,start,stop)
        text = text[:a]+transform(text[a:z])+text[z:]
    def permission(body):
        return change_once(body,
            "    final role = normalizeAdminRole(profile['role'] ?? profile['jobTitle']);",
            "    final role = _explicitAdminAuthorityRole(profile['role'] ?? profile['jobTitle']);\n    if (role == null) return false;", BACKEND)
    scoped(anchor, "  static Future<Map<String, dynamic>> currentAdminProfile(", permission)
    def profile(body):
        body = change_once(body, "    if (!snapshot.exists ||",
            "    if (!snapshot.exists || snapshot.metadata.isFromCache ||\n        snapshot.metadata.hasPendingWrites ||", BACKEND)
        return change_once(body,
            "    final role = normalizeAdminRole(data?['role'] ?? data?['jobTitle']);",
            """    final role = _explicitAdminAuthorityRole(data?['role'] ?? data?['jobTitle']);
    if (role == null) {
      _clearAdminProfileCache();
      throw StateError('deda-stability-explicit-admin-role-required');
    }""", BACKEND)
    scoped("  static Future<Map<String, dynamic>> currentAdminProfile(",
           "  static Future<Map<String, String>> _adminIdentity(", profile)
    def is_admin(body):
        raw = "await FirebaseFirestore.instance.collection('admins').doc(uid).get();"
        guarded = "await DedaAuthRuntime.wait(() => FirebaseFirestore.instance.collection('admins').doc(uid).get());"
        body = change_variant(body, [(raw,raw.replace(".get();",".get(const GetOptions(source: Source.server));")),
            (guarded,guarded.replace(".get());",".get(const GetOptions(source: Source.server)));"))], BACKEND)
        return change_once(body, "    return admin.exists &&",
            """    return FirebaseAuth.instance.currentUser?.uid == uid &&
        !admin.metadata.isFromCache && !admin.metadata.hasPendingWrites &&
        _explicitAdminAuthorityRole(data?['role'] ?? data?['jobTitle']) != null &&
        admin.exists &&""", BACKEND)
    scoped("  static Future<bool> currentUserIsAdmin()", "  // Administration entry visibility is separate", is_admin)
    def gateway(body, kind):
        if kind == 'visible':
            return change_once(body, "          access.exists &&",
                "          !access.metadata.isFromCache && !access.metadata.hasPendingWrites &&\n          access.exists &&", BACKEND)
        body = change_once(body,"      if (!access.exists ||",
            "      if (!access.exists || access.metadata.isFromCache ||\n          access.metadata.hasPendingWrites ||",BACKEND)
        if kind == 'manager':
            return change_once(body,"      final allowedRole = normalizeAdminRole(\n        data['allowedRole'] ?? data['role'],\n      );\n      return accessType == 'general_manager_gateway' ||\n          allowedRole == 'general_manager';",
                """      final allowedRole = _explicitAdminAuthorityRole(
        data['allowedRole'] ?? data['role'],
      );
      return allowedRole == 'general_manager' &&
          (accessType == 'general_manager_gateway' || accessType == 'member');""",BACKEND)
        # Preserve the historical repair code, but never let a bound UID be
        # automatically reassigned by an email match in the protected assembly.
        body = change_once(body,"      final allowedRole =\n          normalizeAdminRole(data['allowedRole'] ?? data['role']);",
            "      final allowedRole =\n          _explicitAdminAuthorityRole(data['allowedRole'] ?? data['role']);",BACKEND)
        body = change_once(body,"      if (!uidMatches && !emailMatches) return false;",
            """      if (allowedUid.isNotEmpty && !uidMatches) return false;
      if (!uidMatches && !emailMatches) return false;""",BACKEND)
        return change_once(body,"        return role == 'general_manager' &&\n            (data['allowedRole'] ?? 'general_manager').toString() ==\n                'general_manager';",
            """        final boundUid = (data['adminUid'] ?? '').toString().trim();
        return role == 'general_manager' &&
            _explicitAdminAuthorityRole(data['allowedRole']) == 'general_manager' &&
            (boundUid.isEmpty || boundUid == profile['uid']);""",BACKEND)
    scoped("  static Future<bool> currentDedaAccountCanSeeAdminEntry(",
        "  static Future<bool> currentDedaAccountIsGeneralManager(",lambda b:gateway(b,'visible'))
    scoped("  static Future<bool> currentDedaAccountIsGeneralManager(",
        "  static Future<bool> currentAdminSessionMatchesDedaEntry(",lambda b:gateway(b,'manager'))
    scoped("  static Future<bool> currentAdminSessionMatchesDedaEntry(",
        "  static Stream<QuerySnapshot<Map<String, dynamic>>>\n      generalManagerAdminEntryPhones()",lambda b:gateway(b,'match'))
    return text

def verify_admin_authority(text):
    for start, stop, markers in (
        ("  static String? _explicitAdminAuthorityRole(", "  static bool adminHasPermission(",
            ("if (raw.isEmpty) return null;", "normalizeAdminRole(raw)")),
        ("  static bool adminHasPermission(", "  static Future<Map<String, dynamic>> currentAdminProfile(",
            ("_explicitAdminAuthorityRole(", "if (role == null) return false;")),
        ("  static Future<Map<String, dynamic>> currentAdminProfile(", "  static Future<Map<String, String>> _adminIdentity(",
            ("snapshot.metadata.isFromCache","snapshot.metadata.hasPendingWrites","deda-stability-explicit-admin-role-required")),
        ("  static Future<bool> currentUserIsAdmin()", "  // Administration entry visibility is separate",
            ("Source.server","admin.metadata.isFromCache","admin.metadata.hasPendingWrites","_explicitAdminAuthorityRole(","currentUser?.uid == uid")),
        ("  static Future<bool> currentDedaAccountCanSeeAdminEntry(", "  static Future<bool> currentDedaAccountIsGeneralManager(",
            ("access.metadata.isFromCache","access.metadata.hasPendingWrites")),
        ("  static Future<bool> currentDedaAccountIsGeneralManager(", "  static Future<bool> currentAdminSessionMatchesDedaEntry(",
            ("access.metadata.isFromCache","access.metadata.hasPendingWrites","_explicitAdminAuthorityRole(","return allowedRole == 'general_manager' &&")),
        ("  static Future<bool> currentAdminSessionMatchesDedaEntry(", "  static Stream<QuerySnapshot<Map<String, dynamic>>>\n      generalManagerAdminEntryPhones()",
            ("access.metadata.isFromCache","access.metadata.hasPendingWrites","if (allowedUid.isNotEmpty && !uidMatches) return false;","boundUid == profile['uid']")),
    ):
        a,z = admin_authority_bounds(text,start,stop)
        if any(text[a:z].count(marker) != 1 for marker in markers):
            raise ValueError("STAGE1_VERIFY_ADMIN_AUTHORITY:" + start)

def patch_backend(text: str) -> str:
    path = BACKEND
    # Public section retries can never create a Firebase identity.
    public_error = """    // Phase 1: signed-out public sections remain signed-out. A new account
    // has its own EXPLICIT enrollment path; never mint another UID on a read.
    throw StateError('deda-stability-explicit-auth-entry-no-new-uid');"""
    text = change_variant(text, [
        ("""    final credential = await auth.signInAnonymously();
    if (credential.user == null) throw StateError('anonymous-auth-failed');
    return credential.user!;""", public_error),
        ("""    final credential = await DedaAuthRuntime.wait(() => DedaAuthRuntime.anonymous(auth));
    if (credential.user == null) throw StateError('anonymous-auth-failed');
    return credential.user!;""", public_error),
    ], path)
    # The legacy owner resolver must not sign out a different authenticated
    # user merely because it could not find that owner's old PIN session.
    owner_error = """      // No section/owner read may log out a live administrator or user.
      // A verified account switch is a separate explicit user action.
      throw StateError('deda-stability-owner-read-cannot-switch-auth');"""
    text = change_variant(text, [
        ("""      // Preserve the existing, non-pilot compatibility path unchanged.
      await signOutAdmin();""", owner_error),
        ("""      // Preserve the existing, non-pilot compatibility path unchanged.
      await DedaAuthRuntime.wait(() => signOutAdmin());""", owner_error),
    ], path)
    # A shared FirebaseAuth admin password call changes the DEFAULT user
    # before the role is checked. Until phase 2 supplies separate Admin Auth,
    # fail closed instead of destroying an existing public session.
    text = change_variant(text, [
        ("""    _clearAdminProfileCache();
    final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email.trim(),""",
         """    if (FirebaseAuth.instance.currentUser != null) {
      throw StateError('deda-stability-admin-isolated-auth-required');
    }
    _clearAdminProfileCache();
    final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email.trim(),"""),
        ("""    _clearAdminProfileCache();
    final credential = await DedaAuthRuntime.wait(() => DedaAuthRuntime.email(FirebaseAuth.instance,
      email: email.trim(),""",
         """    if (FirebaseAuth.instance.currentUser != null) {
      throw StateError('deda-stability-admin-isolated-auth-required');
    }
    _clearAdminProfileCache();
    final credential = await DedaAuthRuntime.wait(() => DedaAuthRuntime.email(FirebaseAuth.instance,
      email: email.trim(),"""),
    ], path)
    text = change_once(text,
        """    final uid = credential.user?.uid;
    if (uid == null) return false;
    final admin =""",
        """    final uid = credential.user?.uid;
    if (uid == null) return false;
    if (FirebaseAuth.instance.currentUser?.uid != uid) {
      throw StateError('deda-stability-admin-principal-changed');
    }
    final admin =""", path)
    # Legacy invitation activation can create a credential on default Auth
    # BEFORE invitation proof. Never let it displace an existing owner/admin.
    # This is the same preservation rule as signInAdmin, not a new auth lane.
    invite_start = "  static Future<Map<String, dynamic>> activateAdminInvitation({"
    invite_end = "  static Future<void> changeCurrentAdminPassword("
    if text.count(invite_start) != 1 or text.count(invite_end) != 1:
        raise ValueError("STAGE1_INVITE_BOUNDARY_CHANGED")
    prefix, rest = text.split(invite_start, 1)
    invite, suffix = rest.split(invite_end, 1)
    invite = change_once(invite,
        """    final auth = FirebaseAuth.instance;
    UserCredential credential;""",
        """    final auth = FirebaseAuth.instance;
    if (auth.currentUser != null) {
      throw StateError('deda-stability-admin-invite-preserve-existing-session');
    }
    UserCredential credential;""", path)
    text = prefix + invite_start + invite + invite_end + suffix
    # Password mutation must verify the actual admin and absence of owner
    # data on the shared default Auth. No cached role or blank role accepted.
    password_start = "  static Future<void> changeCurrentAdminPassword("
    password_end = "  // Administration member password recovery."
    if text.count(password_start) != 1 or text.count(password_end) != 1:
        raise ValueError("STAGE1_PASSWORD_BOUNDARY_CHANGED")
    prefix, rest = text.split(password_start, 1)
    password, suffix = rest.split(password_end, 1)
    password_proof = """    final proof = await FirebaseFirestore.instance.collection('admins')
        .doc(user.uid).get(const GetOptions(source: Source.server));
    final owner = await FirebaseFirestore.instance.collection('deda_sessions')
        .doc(user.uid).get(const GetOptions(source: Source.server));
    final role = (proof.data()?['role'] ?? proof.data()?['jobTitle'] ?? '').toString().trim();
    if (FirebaseAuth.instance.currentUser?.uid != user.uid ||
        !proof.exists || proof.metadata.isFromCache || proof.metadata.hasPendingWrites ||
        owner.exists || owner.metadata.isFromCache || owner.metadata.hasPendingWrites ||
        proof.data()?['active'] != true || normalizeAdminStatus(proof.data()) != 'active' ||
        role.isEmpty || !const {'general_manager', 'deputy_manager', 'employee', 'province_agent'}.contains(normalizeAdminRole(role))) {
      throw StateError('deda-stability-admin-password-owner-preserved');
    }
"""
    post_password = """
    if (FirebaseAuth.instance.currentUser?.uid != user.uid) {
      throw StateError('deda-stability-admin-password-principal-changed');
    }"""
    raw_password = "    await user.updatePassword(newPassword);"
    guarded_password = "    await DedaAuthRuntime.wait(() => user.updatePassword(newPassword));"
    guarded_proof = password_proof.replace(
        "await FirebaseFirestore.instance.collection('admins')",
        "await DedaAuthRuntime.wait(() => FirebaseFirestore.instance.collection('admins')"
    ).replace(
        "await FirebaseFirestore.instance.collection('deda_sessions')",
        "await DedaAuthRuntime.wait(() => FirebaseFirestore.instance.collection('deda_sessions')"
    ).replace("get(const GetOptions(source: Source.server));",
              "get(const GetOptions(source: Source.server)));")
    password = change_variant(password, [
        (raw_password, password_proof + raw_password + post_password),
        (guarded_password, guarded_proof + guarded_password + post_password),
    ], path)
    text = prefix + password_start + password + password_end + suffix
    # Scope all admin-logout changes to its existing function.
    begin = "  static Future<void> signOutAdmin() async {"
    end = "  // DEDA in-app location sharing v1."
    if text.count(begin) != 1 or text.count(end) != 1:
        raise ValueError("STAGE1_ADMIN_EXIT_BOUNDARY_CHANGED")
    prefix, rest = text.split(begin, 1)
    body, suffix = rest.split(end, 1)
    body = change_once(body,
        """    // Only the optional linked-owner recovery build uses this guard.
    // The published compatibility behavior is unchanged with the flag OFF.
    if (dedaLinkedOwnerCompatEnabled) {""",
        """    // Phase 1 guards ALL new QA sessions, even when the old
    // linked-owner recovery flag is OFF. Existing Play remains untouched.
    {""", path)
    body = change_once(body,
        "linkedOwnerPilotEnabled: dedaLinkedOwnerCompatEnabled,",
        "linkedOwnerPilotEnabled: true,", path)
    body = change_once(body,
        """    if (dedaLinkedOwnerCompatEnabled &&
        FirebaseAuth.instance.currentUser?.uid != confirmedAdminUid) {""",
        """    if (FirebaseAuth.instance.currentUser?.uid != confirmedAdminUid) {""", path)
    text = prefix + begin + body + end + suffix
    text = patch_admin_authority(text)
    verify_admin_authority(text)
    return text

def patch_pin(text: str) -> str:
    path = PIN
    # ownerHelper is used by existing PIN login, lookup and passive restore.
    # Only explicitly chosen new enrollment or recovery may allocate a
    # requester UID (never accepted as a historical owner's proof).
    text = change_once(text,
        """    final current = auth.currentUser;
    // A login/section/helper for an EXISTING DEDA account may not mint a""",
        """    final current = auth.currentUser;
    if (current == null && action == _DedaAnonymousEntry.ownerHelper) {
      throw StateError('deda-stability-original-login-no-anonymous-uid');
    }
    // A login/section/helper for an EXISTING DEDA account may not mint a""", path)
    replacement = """    if (current != null) {
      // No PIN helper, recovery request or enrollment can silently replace
      // a signed-in non-anonymous identity on the shared FirebaseAuth.
      throw StateError('deda-stability-explicit-session-switch-required');
    }"""
    text = change_variant(text, [
        ("""    if (current != null) {
      // In the optional linked-owner pilot a helper may not discard the
      // current non-anonymous UID merely to obtain an anonymous session.
      // The user must explicitly exit/switch accounts first. Do not
      // repurpose this method to perform a silent switch.
      if (dedaLinkedOwnerCompatEnabled) {
        throw StateError('deda-explicit-anonymous-session-switch-required');
      }
      await auth.signOut();
    }""", replacement),
        ("""    if (current != null) {
      // In the optional linked-owner pilot a helper may not discard the
      // current non-anonymous UID merely to obtain an anonymous session.
      // The user must explicitly exit/switch accounts first. Do not
      // repurpose this method to perform a silent switch.
      if (dedaLinkedOwnerCompatEnabled) {
        throw StateError('deda-explicit-anonymous-session-switch-required');
      }
      await DedaAuthRuntime.wait(() => DedaAuthRuntime.signOut(auth));
    }""", replacement),
    ], path)
    # Passive gateway reads may refresh only an already verified SAME
    # account/UID, regardless of the old linked-owner compatibility flag.
    start = "  static Future<User> restoreTrustedSessionForAccountKey("
    stop = "  static Future<Map<String, dynamic>> createAccount("
    if text.count(start) != 1 or text.count(stop) != 1:
        raise ValueError("STAGE1_TRUSTED_REFRESH_BOUNDARY_CHANGED")
    prefix, rest = text.split(start, 1)
    refresh, suffix = rest.split(stop, 1)
    refresh = change_once(refresh,
        """    if (dedaLinkedOwnerCompatEnabled) {
      // An implicit trusted-session refresh""",
        """    {
      // deda-stability-trusted-refresh-same-account-only
      // An implicit trusted-session refresh""", path)
    refresh = change_once(refresh,
        "linkedOwnerPilotEnabled: dedaLinkedOwnerCompatEnabled,",
        "linkedOwnerPilotEnabled: true,", path)
    # Never dispatch the old refresh write after the principal has rotated
    # during the asynchronous install lookup. Keep existing runtime checks.
    recheck = """
    if (FirebaseAuth.instance.currentUser?.uid != user.uid) {
      throw StateError('deda-stability-trusted-refresh-principal-changed');
    }"""
    refresh = change_variant(refresh, [
        ("    final install = await installId();",
         "    final install = await installId();" + recheck),
        ("    final install = await DedaAuthRuntime.wait(() => installId());",
         "    final install = await DedaAuthRuntime.wait(() => installId());" + recheck),
    ], path)
    text = prefix + start + refresh + stop + suffix
    # Local logout must not delete a UID-wide server session.
    logout_start = "  static Future<void> signOutFirebase() async {"
    if text.count(logout_start) != 1:
        raise ValueError("STAGE1_PIN_LOGOUT_BOUNDARY_CHANGED")
    prefix, logout = text.split(logout_start, 1)
    old = """    final current = auth.currentUser;
    final anonymousUid =
        current != null && current.isAnonymous ? current.uid : null;

    // End the local Firebase session immediately. Remote housekeeping is
    // best-effort and must never hold the logout screen open.
"""
    logout = change_once(logout, old,
        """    // deda-stability-device-logout-preserve-shared-session:
    // Explicit local sign-out does not delete UID-wide server documents.
""", path)
    cleanup = """
    if (anonymousUid != null) {
      final firestore = FirebaseFirestore.instance;
      unawaited(
        Future.wait([
          firestore.collection('deda_sessions').doc(anonymousUid).delete(),
          firestore.collection('deda_auth_attempts').doc(anonymousUid).delete(),
        ]).catchError((_) => <void>[]),
      );
    }"""
    logout = change_once(logout, cleanup, "", path)
    return prefix + logout_start + logout

def bind(project: Path, *, verify_only: bool = False) -> dict:
    project = project.resolve()
    if project == REPO or project in REPO.parents or REPO in project.parents:
        raise ValueError("STAGE1_DO_NOT_MODIFY_REPOSITORY_OR_PROTECTED_BASELINE")
    files = {BACKEND: patch_backend, PIN: patch_pin}
    proposed = {}
    for relative, patch in files.items():
        target = project / relative
        original = target.read_text(encoding="utf-8")
        if verify_only:
            # Reversibility is not required here, but all safety markers and
            # removal of legacy destructive callsites are mandatory.
            if relative == BACKEND:
                start = original.index("  static Future<void> signOutAdmin() async {")
                stop = original.index("  // DEDA in-app location sharing v1.", start)
                logout = original[start:stop]
                checks = (
                    "deda-stability-explicit-auth-entry-no-new-uid",
                    "deda-stability-owner-read-cannot-switch-auth",
                    "deda-stability-admin-isolated-auth-required",
                    "deda-stability-admin-principal-changed",
                    "deda-stability-admin-invite-preserve-existing-session",
                )
                invite = original.split(
                    "  static Future<Map<String, dynamic>> activateAdminInvitation({", 1
                )[1].split("  static Future<void> changeCurrentAdminPassword(", 1)[0]
                invite_guard = """    final auth = FirebaseAuth.instance;
    if (auth.currentUser != null) {
      throw StateError('deda-stability-admin-invite-preserve-existing-session');
    }
    UserCredential credential;"""
                if invite.count(invite_guard) != 1:
                    raise ValueError("STAGE1_VERIFY_BACKEND_FAILED")
                password = original.split(
                    "  static Future<void> changeCurrentAdminPassword(", 1
                )[1].split("  // Administration member password recovery.", 1)[0]
                if ("deda-stability-admin-password-owner-preserved" not in password
                    or "owner.exists" not in password
                    or "role.isEmpty" not in password
                    or "deda-stability-admin-password-principal-changed" not in password
                    or password.index("deda-stability-admin-password-owner-preserved") >
                        password.index("user.updatePassword(")):
                    raise ValueError("STAGE1_VERIFY_BACKEND_FAILED")
                if any(mark not in original for mark in checks) or (
                    "linkedOwnerPilotEnabled: true," not in logout or
                    "FirebaseAuth.instance.currentUser?.uid != confirmedAdminUid" not in logout or
                    "if (dedaLinkedOwnerCompatEnabled)" in logout or
                    "await signOutAdmin();" in original.split(
                        "  static Future<User> _ensureOwnerSessionForAccountKey(", 1
                    )[1].split("  static Future<bool> _isCurrentGeneralManagerSession", 1)[0]
                ):
                    raise ValueError("STAGE1_VERIFY_BACKEND_FAILED")
                verify_admin_authority(original)
            else:
                start = original.index("  static Future<User> _ensureAnonymousSession(")
                stop = original.index("  static Future<User> _ensurePinSessionForAccount(", start)
                part = original[start:stop]
                if ("deda-stability-original-login-no-anonymous-uid" not in part
                    or "deda-stability-explicit-session-switch-required" not in part
                    or "await auth.signOut();" in part
                    or "DedaAuthRuntime.signOut(auth)" in part):
                    raise ValueError("STAGE1_VERIFY_PIN_FAILED")
                refresh = original.split(
                    "  static Future<User> restoreTrustedSessionForAccountKey(", 1
                )[1].split("  static Future<Map<String, dynamic>> createAccount(", 1)[0]
                for marker in (
                    "deda-stability-trusted-refresh-same-account-only",
                    "linkedOwnerPilotEnabled: true,",
                    "existing.metadata.isFromCache",
                    "existing.metadata.hasPendingWrites",
                    "existing.data()?['uid'] != user.uid",
                    "existing.data()?['accountKey'] != cleanKey",
                    "deda-stability-trusted-refresh-principal-changed",
                ):
                    if refresh.count(marker) != 1:
                        raise ValueError("STAGE1_VERIFY_TRUSTED_REFRESH:" + marker)
                if ("if (dedaLinkedOwnerCompatEnabled) {" in refresh or
                    refresh.index("deda-stability-trusted-refresh-principal-changed") >
                        refresh.index(".set(<String, dynamic>{")):
                    raise ValueError("STAGE1_VERIFY_TRUSTED_REFRESH_ORDER")
                pin_logout = original.split("  static Future<void> signOutFirebase() async {", 1)[1]
                if ("deda-stability-device-logout-preserve-shared-session" not in pin_logout
                    or ".delete()" in pin_logout
                    or "unawaited(" in pin_logout
                    or not any(call in pin_logout for call in ("auth.signOut()", "DedaAuthRuntime.signOut(auth)"))):
                    raise ValueError("STAGE1_VERIFY_PIN_FAILED")
            continue
        proposed[relative] = patch(original)
    # Validate both anchor sets before modifying either file.
    for relative, updated in proposed.items():
        (project / relative).write_text(updated, encoding="utf-8")
    if not verify_only:
        bind(project, verify_only=True)
    return {"status": "STAGE1_SOURCE_GUARDS_BOUND_NO_FIREBASE_WRITE",
            "files": sorted(files), "verify_only": verify_only}

if __name__ == "__main__":
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument("project", type=Path)
    cli.add_argument("--verify-only", action="store_true")
    args = cli.parse_args()
    print(bind(args.project, verify_only=args.verify_only))
