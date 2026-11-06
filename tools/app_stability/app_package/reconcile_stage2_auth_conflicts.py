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


def _backend(ours, base, theirs):
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


def _pin(ours, base, theirs):
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
