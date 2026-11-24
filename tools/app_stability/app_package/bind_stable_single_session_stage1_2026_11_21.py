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
    return text

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
                if any(mark not in original for mark in checks) or (
                    "linkedOwnerPilotEnabled: true," not in logout or
                    "FirebaseAuth.instance.currentUser?.uid != confirmedAdminUid" not in logout or
                    "if (dedaLinkedOwnerCompatEnabled)" in logout or
                    "await signOutAdmin();" in original.split(
                        "  static Future<User> _ensureOwnerSessionForAccountKey(", 1
                    )[1].split("  static Future<bool> _isCurrentGeneralManagerSession", 1)[0]
                ):
                    raise ValueError("STAGE1_VERIFY_BACKEND_FAILED")
            else:
                start = original.index("  static Future<User> _ensureAnonymousSession(")
                stop = original.index("  static Future<User> _ensurePinSessionForAccount(", start)
                part = original[start:stop]
                if ("deda-stability-original-login-no-anonymous-uid" not in part
                    or "deda-stability-explicit-session-switch-required" not in part
                    or "await auth.signOut();" in part
                    or "DedaAuthRuntime.signOut(auth)" in part):
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
