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

OWNER_CONFIRM_WIDGET = """
            // Optional original-phone confirmation, strictly behind private
            // linked-owner feature switch; never visible on the old 100436 UI.
            if (dedaLinkedOwnerCompatEnabled &&
                Firebase.apps.isNotEmpty &&
                (DedaPreferences.accountPhone.isNotEmpty ||
                    DedaPreferences.phone.isNotEmpty) &&
                (() {
                  final phone = DedaPreferences.accountPhone.isNotEmpty
                      ? DedaPreferences.accountPhone : DedaPreferences.phone;
                  final user = FirebaseAuth.instance.currentUser;
                  final account = phone.replaceAll(RegExp(r'[^0-9]'), '');
                  return user != null &&
                      (user.isAnonymous ||
                       user.email ==
                           DedaLinkedOwnerSessionPolicy.ownerEmail(account));
                })()) ...[
              DedaOwnerConfirmButton(
                phone: DedaPreferences.accountPhone.isNotEmpty
                    ? DedaPreferences.accountPhone : DedaPreferences.phone,
                originalId: DedaBackend.personalShareIdForPhone(
                  DedaPreferences.accountPhone.isNotEmpty
                      ? DedaPreferences.accountPhone : DedaPreferences.phone),
              ),
              const SizedBox(height: 12),
            ],
"""

VERIFIED_EARLY_BRANCH = """
    if (verifiedCanonicalProfile) {
      await _saveVerifiedLinkedOwnerLogin(
        name: name, normalizedPhone: normalizedPhone,
        type: type, verifiedOriginalUid: verifiedOriginalUid,
      );
      return;
    }
"""


def resolve_block(ours, base, theirs):
    if ("import 'deda_verified_active_id_store.dart';" in ours and
            "import 'deda_100431_linked_owner_session_policy.dart';" in theirs):
        # Keep both old unified ID and new linked-owner imports.
        return ours + theirs
    if "On a private, confirmed replacement phone" in theirs:
        # 100436's DedaPreferences.load() scopes its original 'prefs'
        # inside an AuthRuntime callback. Stage2's added boot guard must
        # read its own prefs rather than capture a nonexistent local.
        guarded = once(
            theirs, "    if (dedaLinkedOwnerCompatEnabled &&",
            "    final prefs = await SharedPreferences.getInstance();\n"
            "    if (dedaLinkedOwnerCompatEnabled &&",
            "linked owner boot preferences scope",
        )
        return ours + guarded
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
        # The original account-page layout diverged from raw stage2 too far
        # for local diff3 placement. Preserve ALL of 100436 UI here; append
        # a guarded confirmation tile later at the unique logout anchor.
        return ours
    return None


def reconcile_main(candidate, assembled_100436):
    """Keep exact 100436 account transaction and account-hub layout.

    Conflict resolution here does not replace old login/account UI with a
    possibly incomplete raw Stage2 source. The signed assembled versions
    of those two methods remain the sole baseline; Stage2 adds separate,
    feature-flagged entry and verified-UID persistence.
    """
    source = candidate.decode("utf-8")
    trusted = assembled_100436.decode("utf-8")
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

    # Always restore the ENTIRE known-good 100436 login method, not an
    # incompletely merged region with different try/finally and backup flow.
    original_a = trusted.index(LOGIN_METHOD)
    original_b = trusted.index(AFTER_LOGIN, original_a)
    original_method = trusted[original_a:original_b]
    if ("DedaAuthRuntime.run<void>(" not in original_method or
            "verifiedCanonicalProfile" in original_method):
        raise ValueError("UNSAFE_MAIN_100436_STAGE2 expected original 100436 transaction")
    header = "  }) async {"
    if original_method.count(header) < 1:
        raise ValueError("UNSAFE_MAIN_100436_STAGE2 100436 method signature drift")
    new_header = (
        "    bool verifiedCanonicalProfile = false,\n"
        "    String? verifiedOriginalUid,\n"
        + header
    )
    original_method = once(original_method, header, new_header,
                           "100436 saveLogin signature")
    original_method = once(
        original_method, new_header,
        new_header + VERIFIED_EARLY_BRANCH + LEGACY_GUARD,
        "verified-only account path before the unchanged legacy body",
    )
    modified_a = source.index(LOGIN_METHOD)
    modified_b = source.index(AFTER_LOGIN, modified_a)
    source = (
        source[:modified_a] + original_method + VERIFIED_METHOD +
        source[modified_b:]
    )

    # The existing 100436 account hub contains more management/place UI
    # than the raw Stage2 source. Restore the whole class, then add one
    # separately gated confirmation widget at its existing logout button.
    tag = "class _DedaAccountHubPageState"
    trusted_start = trusted.index(tag)
    trusted_end = trusted.find("\nclass ", trusted_start + 12)
    if trusted_end < 0:
        trusted_end = len(trusted)
    safe_hub = trusted[trusted_start:trusted_end]
    if safe_hub.count("onPressed: _logout") != 1:
        raise ValueError("UNSAFE_MAIN_100436_STAGE2 original hub logout not unique")
    logout = safe_hub.index("onPressed: _logout")
    widget_anchor = "            const SizedBox(height: 20),"
    insert_at = safe_hub.rfind(widget_anchor, 0, logout)
    if insert_at < 0 or logout - insert_at > 600:
        raise ValueError("UNSAFE_MAIN_100436_STAGE2 owner widget insertion drift")
    safe_hub = safe_hub[:insert_at] + OWNER_CONFIRM_WIDGET + safe_hub[insert_at:]
    new_start = source.index(tag)
    new_end = source.find("\nclass ", new_start + 12)
    if new_end < 0:
        new_end = len(source)
    source = source[:new_start] + safe_hub + source[new_end:]
    # Restore ONLY the reviewed Stage2 existing-account entry handler
    # into the original PIN/login screen, which has different control flow.
    from pathlib import Path
    raw = (Path(__file__).resolve().parents[3] / "lib/main.dart").read_text()
    begin = raw.index("  void _openExistingAccount() {")
    finish = raw.index("  Future<void> login() async {", begin)
    handler = raw[begin:finish]
    if (handler.count("DedaLinkedOwnerGuardianAssembly.prepare()") != 1 or
            handler.count("DedaPreferences.saveLogin(") != 1 or
            "if (!login.fullAccountRestored" not in handler):
        raise ValueError("UNSAFE_MAIN_100436_STAGE2 unexpected owner login handler")
    login_page = source.index("class _LoginPageState")
    login_action = source.index("  Future<void> login() async {", login_page)
    if "_openExistingAccount()" in source[login_page:login_action]:
        raise ValueError("UNSAFE_MAIN_100436_STAGE2 duplicate owner login handler")
    source = source[:login_action] + handler + source[login_action:]
    return source.encode("utf-8"), resolved
