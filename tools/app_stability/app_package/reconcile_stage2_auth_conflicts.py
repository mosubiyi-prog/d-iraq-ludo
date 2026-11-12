#!/usr/bin/env python3
"""Conservative, auditable resolution of Stage2 auth-related merge overlaps.

Only reconciles the exact source patterns reviewed against 100436:
- preserve DedaAuthRuntime.wait wrappers from signed baseline;
- add the independently verified linked UID checks from Stage2;
- never discard either owner/admin session protection path.
Unknown conflicts remain unresolved; nothing is written to signed source.
"""
import re

MARKER = re.compile(
    r"(?ms)^<<<<<<< [^\n]*\n(.*?)^\|\|\|\|\|\|\| [^\n]*\n"
    r"(.*?)^=======\n(.*?)^>>>>>>> [^\n]*\n"
)


def once(text, old, new, description):
    if text.count(old) != 1:
        raise ValueError("UNSAFE_STAGE2_AUTH_RECONCILE " + description
                         + " count=" + str(text.count(old)))
    return text.replace(old, new, 1)


def _backend_share_prewrite_guard_100443(ours, base, theirs):
    """Review ONLY the two original-ID projection overlaps from 100443.

    Keep both the signed AuthRuntime.wait wrappers and the new owner-UID
    server-preflight. Unknown overlaps always stay blocked by the merger.
    """
    if ("await DedaAuthRuntime.wait(() => userRef.set({" in ours
            and "await userRef.set({" in base
            and "original-share-session-changed-before-user-write" in theirs
            and "await userRef.set({" in theirs):
        return once(
            theirs, "await userRef.set({",
            "await DedaAuthRuntime.wait(() => userRef.set({",
            "100443 original user write retains runtime guard")

    if ("final existing = await DedaAuthRuntime.wait(() => ref.get());" in ours
            and "await DedaAuthRuntime.wait(() => ref.set({" in ours
            and "original-share-session-changed-before-route-write" in theirs
            and "original-share-route-owner-conflict" in theirs):
        result = once(
            theirs, "final existing = await ref.get();",
            "final existing = await DedaAuthRuntime.wait(() => ref.get());",
            "100443 original route read retains runtime guard")
        return once(
            result, "await ref.set({",
            "await DedaAuthRuntime.wait(() => ref.set({",
            "100443 original route write retains runtime guard")
    return None


def _backend(ours, base, theirs):
    reviewed_id = _backend_share_prewrite_guard_100443(ours, base, theirs)
    if reviewed_id is not None:
        return reviewed_id
    # Preserve the exact signed AuthRuntime lane around owner-scoped reads
    # while keeping the new fail-closed no-implicit-UID preflight intact.
    if ("var user = await DedaAuthRuntime.wait(() => _ensurePublicUser());" in ours
            and "var user = await _ensurePublicUser();" in base
            and "deda-original-owner-login-required" in theirs
            and "mayImplicitlyPrepareOwnerSession(" in theirs
            and "var user = await _ensurePublicUser();" in theirs):
        return once(
            theirs, "var user = await _ensurePublicUser();",
            "var user = await DedaAuthRuntime.wait(() => _ensurePublicUser());",
            "100441 preserve AuthRuntime and no implicit owner UID")
    # Both imports are necessary: unified public premium-ID routing and
    # server-verifiable owner UIDs are unrelated authorities.
    if ("import 'deda_qa32_public_recipient_resolver.dart';" in ours
            and "import 'deda_100431_linked_owner_session_policy.dart';" in theirs):
        return ours + theirs
    # Never silently sign out a valid linked original owner. If the feature
    # switch is off, preserve the known-good session transition wrapper.
    if "await signOutAdmin();" in theirs and "DedaAuthRuntime.wait" in ours:
        return once(theirs, "await signOutAdmin();",
                    "await DedaAuthRuntime.wait(() => signOutAdmin());",
                    "backend linked-owner signout wait")
    # For owner-scoped legacy session restores, combine BOTH conditions:
    # (a) server-confirmed original UID and (b) the existing session gate.
    if ("DedaPinAuth.restoreTrustedSessionForAccountKey(accountKey)" in theirs
            and "DedaAuthRuntime.wait" in ours):
        result = once(
            theirs,
            "await DedaPinAuth.restoreTrustedSessionForAccountKey(accountKey);",
            "await DedaAuthRuntime.wait(() => "
            "DedaPinAuth.restoreTrustedSessionForAccountKey(accountKey));",
            "backend restore owner session",
        )
        if "await DedaLinkedOwnerSessionPolicy.verified(authUser, accountKey)" in result:
            result = once(
                result,
                "await DedaLinkedOwnerSessionPolicy.verified(authUser, accountKey)",
                "await DedaAuthRuntime.wait(() => "
                "DedaLinkedOwnerSessionPolicy.verified(authUser, accountKey))",
                "backend owner proof within active session",
            )
        if "!await currentUserIsAdmin()" in result:
            result = once(
                result,
                "!await currentUserIsAdmin()",
                "!await DedaAuthRuntime.wait(() => currentUserIsAdmin())",
                "backend admin permission gate",
            )
        return result
    return None


def _pin_guard_100441(ours, base, theirs):
    """Preserve signed 100441 AuthRuntime waits AND the new same-UID guard.

    Match only four reviewed merge overlaps. Never override unknown blocks,
    and never remove the existing runtime serialization or original owner
    checks. The assembled source is still analyzed and privately tested.
    """
    if ("await DedaAuthRuntime.wait(() => _provePin(accountKey: accountKey, pin: pin));" in ours
            and "await _provePin(accountKey: accountKey, pin: pin);" in base
            and "final expectedUid = dedaLinkedOwnerCompatEnabled" in theirs
            and "await _openSession(accountKey, expectedOriginalUid: expectedUid);" in theirs):
        # The linked-owner source now explicitly pins the verified UID during
        # PIN proof. Keep that argument in assembled 100441; never silently
        # regress to a proof that can create/switch an anonymous principal.
        scoped_proof = (
            "await _provePin(\n"
            "      accountKey: accountKey, pin: pin, expectedOriginalUid: expectedUid);"
        )
        legacy_proof = "await _provePin(accountKey: accountKey, pin: pin);"
        if scoped_proof in theirs:
            result = once(
                theirs, scoped_proof,
                "await DedaAuthRuntime.wait(() => _provePin(\n"
                "      accountKey: accountKey, pin: pin, expectedOriginalUid: expectedUid));",
                "100441 preserve UID-bound PIN proof wait")
        elif legacy_proof in theirs:
            result = once(
                theirs, legacy_proof,
                "await DedaAuthRuntime.wait(() => _provePin(accountKey: accountKey, pin: pin));",
                "100441 preserve legacy PIN proof wait")
        else:
            return None
        return once(result,
            "await _openSession(accountKey, expectedOriginalUid: expectedUid);",
            "await DedaAuthRuntime.wait(() => _openSession(accountKey, expectedOriginalUid: expectedUid));",
            "100441 preserve session write wait")

    if ("final install = await DedaAuthRuntime.wait(() => installId());" in ours
            and "await DedaAuthRuntime.wait(() => _profileRef(accountKey).set(" in ours
            and "ensureOriginalUidUnchanged();" in theirs
            and "await _profileRef(accountKey).set(" in theirs):
        result = once(theirs,
            "final install = await installId();",
            "final install = await DedaAuthRuntime.wait(() => installId());",
            "100441 preserve install wait")
        return once(result,
            "await _profileRef(accountKey).set(",
            "await DedaAuthRuntime.wait(() => _profileRef(accountKey).set(",
            "100441 preserve profile write wait")

    if ("await DedaAuthRuntime.wait(() => FirebaseFirestore.instance.collection('users').doc(user.uid).set(" in ours
            and "ensureOriginalUidUnchanged();" in theirs
            and "await FirebaseFirestore.instance.collection('users').doc(user.uid).set(" in theirs):
        return once(theirs,
            "await FirebaseFirestore.instance.collection('users').doc(user.uid).set(",
            "await DedaAuthRuntime.wait(() => FirebaseFirestore.instance.collection('users').doc(user.uid).set(",
            "100441 preserve user write wait")

    if ("await DedaAuthRuntime.wait(() => rememberKnownAccount(phone));" in ours
            and "ensureOriginalUidUnchanged();" in theirs
            and "await rememberKnownAccount(phone);" in theirs):
        return once(theirs,
            "await rememberKnownAccount(phone);",
            "await DedaAuthRuntime.wait(() => rememberKnownAccount(phone));",
            "100441 preserve remembered-account wait")
    return None


def _pin(ours, base, theirs):
    reviewed_guard = _pin_guard_100441(ours, base, theirs)
    if reviewed_guard is not None:
        return reviewed_guard
    # One reviewed _provePin overlap: retain the signed runtime wait when
    # legacy mode needs an existing anonymous session, but NEVER create or
    # switch Auth when the UID-bound original proof is already required.
    if ("final user = await DedaAuthRuntime.wait(() => _ensureAnonymousSession());" in ours
            and "final user = await _ensureAnonymousSession();" in base
            and "original-pin-owner-changed-before-proof" in theirs
            and "final user = expectedOriginalUid == null" in theirs
            and "? await _ensurePinSessionForAccount(accountKey)" in theirs):
        return once(
            theirs,
            "? await _ensurePinSessionForAccount(accountKey)",
            "? await DedaAuthRuntime.wait(() => _ensurePinSessionForAccount(accountKey))",
            "100441 preserve runtime Auth guard before UID-bound PIN proof")
    # This preserves safe auth transition on normal signout while blocking
    # loss of the linked original UID when the feature gate is enabled.
    if ("await auth.signOut();" in theirs and
            "DedaAuthRuntime.signOut(auth)" in ours):
        return once(theirs, "await auth.signOut();",
                    "await DedaAuthRuntime.wait("
                    "() => DedaAuthRuntime.signOut(auth));",
                    "pin linked-owner signout protection")
    if "final snapshot = await _directoryRef(phone)" in theirs:
        if "DedaAuthRuntime.wait" not in ours:
            return None
        result = once(theirs, "await _ensureAnonymousSession();",
                      "await DedaAuthRuntime.wait(() => _ensureAnonymousSession());",
                      "pin lookup session")
        return once(
            result, "final snapshot = await _directoryRef(phone)",
            "final snapshot = await DedaAuthRuntime.wait("
            "() => _directoryRef(phone)",
            "pin protected directory read",
        )
    if ("final user = await _ensurePinSessionForAccount(accountKey);" in theirs
            and "DedaAuthRuntime.wait" in ours):
        result = once(
            theirs, "final user = await _ensurePinSessionForAccount(accountKey);",
            "final user = await DedaAuthRuntime.wait("
            "() => _ensurePinSessionForAccount(accountKey));",
            "pin verified owner session",
        )
        if "final install = await installId();" in result:
            result = once(result, "final install = await installId();",
                          "final install = await DedaAuthRuntime.wait(() => installId());",
                          "pin install ownership")
        if "await FirebaseFirestore.instance" in result:
            result = once(
                result, "await FirebaseFirestore.instance",
                "await DedaAuthRuntime.wait(() => FirebaseFirestore.instance",
                "pin protected firestore write",
            )
        return result
    if ("final user = await _ensureAnonymousSession();" in theirs
            and "dedaLinkedOwnerCompatEnabled" in theirs
            and "DedaAuthRuntime.wait" in ours):
        result = once(
            theirs, "final user = await _ensureAnonymousSession();",
            "final user = await DedaAuthRuntime.wait(() => _ensureAnonymousSession());",
            "pin trusted anonymous fallback",
        )
        if "final install = await installId();" in result:
            result = once(
                result, "final install = await installId();",
                "final install = await DedaAuthRuntime.wait(() => installId());",
                "pin trusted session install",
            )
        if "final existing = await FirebaseFirestore.instance" in result:
            result = once(
                result, "final existing = await FirebaseFirestore.instance",
                "final existing = await DedaAuthRuntime.wait("
                "() => FirebaseFirestore.instance",
                "pin trusted pre-link server session read",
            )
            result = once(
                result, ".get(const GetOptions(source: Source.server));",
                ".get(const GetOptions(source: Source.server)));",
                "pin trusted read balanced wait",
            )
        if "    await FirebaseFirestore.instance" in result:
            result = once(
                result, "    await FirebaseFirestore.instance",
                "    await DedaAuthRuntime.wait(() => FirebaseFirestore.instance",
                "pin trusted session firestore write",
            )
        return result
    return None


def reconcile(relative, candidate):
    """Return bytes, with only specifically reviewed blocks resolved.

    All unknown or unmatched conflicts remain present and must be blocked by
    the caller, not guessed away. The final Dart analyzer is still mandatory.
    """
    if relative not in {"lib/deda_backend.dart", "lib/deda_pin_auth.dart"}:
        return candidate, 0
    text = candidate.decode("utf-8")
    count = 0

    def replace(match):
        nonlocal count
        ours, base, theirs = match.groups()
        resolved = (_backend if relative.endswith("backend.dart") else _pin)(
            ours, base, theirs
        )
        if resolved is None:
            return match.group(0)
        count += 1
        return resolved

    output = MARKER.sub(replace, text)
    return output.encode("utf-8"), count
