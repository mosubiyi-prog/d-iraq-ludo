#!/usr/bin/env python3
"""Source-only, fail-closed reconciliation of legacy 100436 UI with Stage2 entry.

Use only on an ephemeral EXACT 100436 assembled application. Keeps the full
old owner-login transaction, task backup, league, admin and friend paths.
A *separate* verified-only account commit is added for the new linked-UID
entry, never enabled by the guard. No APK or backend mutation here.
"""
from reconcile_stage2_auth_conflicts import MARKER, once

LOGIN_METHOD = "  static Future<void> saveLogin({"
AFTER_LOGIN = "  static Future<void> setAccountType("

VERIFIED_METHOD = """
  // Verified replacement-phone account is a DIFFERENT trust path from
  // the existing 100436 PIN/login flow. Only caller-supplied original UID
  // that still matches live FirebaseAuth can reach this method.
  // Financial assets are never copied or minted here.
  static Future<void> _saveVerifiedLinkedOwnerLogin({
    required String name,
    required String normalizedPhone,
    required DedaAccountType type,
    required String? verifiedOriginalUid,
  }) async {
    if (!dedaLinkedOwnerCompatEnabled ||
        verifiedOriginalUid == null || verifiedOriginalUid.isEmpty ||
        !_liveVerifiedOriginalOwner(normalizedPhone, verifiedOriginalUid)) {
      throw StateError('verified-owner-original-uid-not-current');
    }
    await DedaAuthRuntime.run<void>(
      kind: DedaSessionTransitionKind.ownerLogin,
      origin: DedaSessionTransitionOrigin.userAction,
      action: () async {
        final prefs = await DedaAuthRuntime.wait(
          () => SharedPreferences.getInstance());
        final account = normalizedPhone.replaceAll(RegExp(r'[^0-9]'), '');
        final accountGuard =
            DedaLinkedOwnerSessionPolicy.protectedAccountKey(account);
        final oldGuard = prefs.getString(accountGuard);
        final oldUid = prefs.getString(_linkedVerifiedUidKey);
        final oldAccount = prefs.getString(_linkedVerifiedAccountKey);
        if ((oldGuard != null && oldGuard != verifiedOriginalUid) ||
            (oldUid != null && oldUid != verifiedOriginalUid) ||
            (oldAccount != null && oldAccount != account) ||
            !_liveVerifiedOriginalOwner(normalizedPhone, verifiedOriginalUid)) {
          throw StateError('linked-owner-preexisting-account-conflict');
        }

        // Mark login incomplete BEFORE any profile or provenance writes.
        if (!await DedaAuthRuntime.wait(
              () => prefs.setBool(_loggedInKey, false))) {
          throw StateError('verified-login-prepare-not-saved');
        }
        if (!await DedaAuthRuntime.wait(
                () => prefs.setString(accountGuard, verifiedOriginalUid)) ||
            !await DedaAuthRuntime.wait(
                () => prefs.setString(_linkedVerifiedUidKey,
                    verifiedOriginalUid)) ||
            !await DedaAuthRuntime.wait(
                () => prefs.setString(_linkedVerifiedAccountKey, account))) {
          throw StateError('linked-owner-provenance-not-saved');
        }
        final ownerName = name.trim();
        if (ownerName.isEmpty) throw StateError('verified-profile-name-empty');
        final saved = await DedaAuthRuntime.wait(() => Future.wait<bool>([
          prefs.setString(_userNameKey, ownerName),
          prefs.setString(_phoneKey, normalizedPhone),
          prefs.setString(_accountPhoneKey, normalizedPhone),
          prefs.setString(_accountTypeKey, type.name),
        ]));
        if (saved.any((ok) => !ok) ||
            prefs.getString(_linkedVerifiedUidKey) != verifiedOriginalUid ||
            prefs.getString(_linkedVerifiedAccountKey) != account ||
            !_liveVerifiedOriginalOwner(normalizedPhone, verifiedOriginalUid)) {
          throw StateError('verified-owner-profile-not-saved');
        }
        if (!await DedaAuthRuntime.wait(
            () => prefs.setBool(_loggedInKey, true))) {
          throw StateError('verified-login-commit-not-saved');
        }
        if (!_liveVerifiedOriginalOwner(normalizedPhone, verifiedOriginalUid)) {
          await DedaAuthRuntime.wait(
              () => prefs.setBool(_loggedInKey, false));
          throw StateError('verified-owner-session-changed-during-save');
        }

        // Public presentation is updated only after the verified disk commit.
        userName = ownerName;
        phone = normalizedPhone;
        accountPhone = normalizedPhone;
        accountType = type;
        isLoggedIn = true;
        profileAvatarStyle = await DedaAuthRuntime.wait(
            () => _loadRoyalSafeAvatarStyle(prefs, normalizedPhone));
        profileFrameStyle =
            (prefs.getInt(_profileFrameKey(normalizedPhone)) ?? 0)
                .clamp(0, 18).toInt();
        profileBackgroundStyle =
            (prefs.getInt(_profileBackgroundKey(normalizedPhone)) ?? 0)
                .clamp(0, 8).toInt();
        // Do not sync an old/local name over the verified server account.
        // A separately audited service owns wallet, ID and restored XP.
      },
    );
  }

"""

LEGACY_GUARD = """
    // The 100436 login remains intact when pilot is OFF. A previously
    // verified UID must never be reopened through the legacy typed name path.
    if (dedaLinkedOwnerCompatEnabled) {
      final prefsGuard = await SharedPreferences.getInstance();
      final account = normalizedPhone.replaceAll(RegExp(r'[^0-9]'), '');
      final currentOwner = Firebase.apps.isEmpty
          ? null : FirebaseAuth.instance.currentUser;
      if (!DedaLinkedOwnerSessionPolicy.mayUseUnverifiedLocalLogin(
        linkedOwnerPilotEnabled: true,
        hasStoredOriginalUid:
            prefsGuard.containsKey(_linkedVerifiedUidKey),
        hasStoredAccountKey:
            prefsGuard.containsKey(_linkedVerifiedAccountKey),
        hasProtectedTargetAccount: prefsGuard.containsKey(
            DedaLinkedOwnerSessionPolicy.protectedAccountKey(account)),
        hasLiveLinkedOwnerSession:
            currentOwner != null && !currentOwner.isAnonymous,
      )) {
        throw StateError('linked-owner-requires-verified-login-or-logout');
      }
    }
"""

VERIFIED_EARLY_BRANCH = """
    if (verifiedCanonicalProfile) {
      return _saveVerifiedLinkedOwnerLogin(
        name: name, normalizedPhone: normalizedPhone,
        type: type, verifiedOriginalUid: verifiedOriginalUid,
      );
    }
"""


def resolve_block(ours, base, theirs):
    if ("import 'deda_verified_active_id_store.dart';" in ours and
            "import 'deda_100431_linked_owner_session_policy.dart';" in theirs):
        # Keep both old unified ID and new linked-owner imports.
        return ours + theirs.replace(
            "import 'deda_daily_published_tasks.dart';\n"
            "import 'deda_daily_user_task_display.dart';\n", "")
    if "On a private, confirmed replacement phone" in theirs:
        return ours + theirs
    if ("if (verifiedCanonicalProfile &&" in theirs and
            "DedaAuthRuntime.run<void>(" in ours):
        return ours
    if ("await DedaAuthRuntime.wait(() => Future.wait([" in ours and
            "prefs.getInt(_profileBackgroundKey(normalizedPhone))" in theirs):
        return ours
    if ("final followupEpoch = _authAccountEpoch;" in ours and
            "if (!verifiedCanonicalProfile)" in theirs):
        return ours
    if ("DedaPinAuth.signOutFirebase()" in ours and
            "_linkedVerifiedUidKey" in theirs):
        return (
            "    await DedaAuthRuntime.wait("
            "() => prefs.remove(_linkedVerifiedUidKey));\n"
            "    await DedaAuthRuntime.wait("
            "() => prefs.remove(_linkedVerifiedAccountKey));\n" + ours
        )
    if "final exists = await DedaPinAuth.accountExists(" in ours:
        # Original 100436 PIN create/sign-in routing is immutable.
        return ours
    if "linked-owner-requires-verified-login-or-logout" in theirs:
        # The explicit guard is installed inside saveLogin above.
        return ours
    if "Original-phone-only confirmation" in theirs:
        anchor = ("            const SizedBox(height: 20),\n"
                  "            OutlinedButton.icon(")
        first = theirs.index("            // Original-phone-only confirmation")
        ending = theirs.index(anchor, first)
        addition = theirs[first:ending]
        return once(ours, anchor, addition + anchor,
                    "owner confirm button before existing logout")
    return None


def reconcile_main(candidate):
    source = candidate.decode("utf-8")
    resolved = 0

    def do_merge(match):
        nonlocal resolved
        ours, base, theirs = match.groups()
        done = resolve_block(ours, base, theirs)
        if done is None:
            return match.group(0)
        resolved += 1
        return done

    source = MARKER.sub(do_merge, source)
    if "<<<<<<< " in source or ">>>>>>> " in source:
        return source.encode("utf-8"), resolved
    if resolved != 9:
        raise ValueError("UNSAFE_MAIN_100436_STAGE2 expected 9 reviewed "
                         "overlaps, got " + str(resolved))
    first = source.index(LOGIN_METHOD)
    last = source.index(AFTER_LOGIN, first)
    method = source[first:last]
    if ("verifiedCanonicalProfile = false" not in method or
            "String? verifiedOriginalUid" not in method):
        raise ValueError("UNSAFE_MAIN_100436_STAGE2 verified login signature missing")
    header_end = method.index("}) async {") + len("}) async {")
    if "DedaAuthRuntime.run<void>(" not in method:
        raise ValueError("UNSAFE_MAIN_100436_STAGE2 baseline session lane missing")
    method = (
        method[:header_end] + VERIFIED_EARLY_BRANCH + LEGACY_GUARD +
        method[header_end:]
    )
    source = source[:first] + method + VERIFIED_METHOD + source[last:]
    return source.encode("utf-8"), resolved
