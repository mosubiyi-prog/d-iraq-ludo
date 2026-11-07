#!/usr/bin/env python3
"""DEDA stage4/point2 explicit missing-UID handoff in disposable full 100440.

Requires stage3 and stage4/point1 friends retry integrated first. Reuses the
existing 'I have an account' VERIFIED login route; does not create a second
PIN guardian, store PIN, clear preferences, auto-login or create an anonymous UID.
"""
from __future__ import annotations

import argparse
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
POLICY = "lib/deda_session_missing_owner_entry_100441.dart"

def once(data: str, old: str, new: str, name: str) -> str:
    count = data.count(old)
    if count != 1:
        raise ValueError(f"BLOCK_MISSING_OWNER_ENTRY_ANCHOR:{name}:{count}")
    return data.replace(old, new, 1)

def bind(project: Path) -> None:
    project = project.resolve()
    if project == ROOT or ROOT in project.parents or project in ROOT.parents:
        raise ValueError("BLOCK_MISSING_OWNER_NEVER_EDIT_REFERENCE")
    main_path = project / "lib" / "main.dart"
    candidate = project / POLICY
    if not main_path.is_file() or candidate.exists() or not (ROOT / POLICY).is_file():
        raise ValueError("BLOCK_MISSING_OWNER_SOURCE_NOT_ISOLATED")
    main = main_path.read_text()
    if ("DEDA_100441_FRIENDS_RETRY_FIX" not in main or
            "DedaSessionRescueStage3Bridge.runForPhone" not in main or
            "DedaMissingOwnerEntryPolicy" in main):
        raise ValueError("BLOCK_MISSING_OWNER_REQUIRES_FRIENDS_STAGE3_ASSEMBLY")

    main = once(main,
        "import 'deda_session_rescue_stage3_bridge.dart';",
        "import 'deda_session_rescue_stage3_bridge.dart';\n"
        "import 'deda_session_missing_owner_entry_100441.dart';",
        "policy import")

    login_start = main.index("class LoginPage extends StatefulWidget {")
    login_end = main.index("class _LoginPageState extends State<LoginPage>", login_start)
    login = main[login_start:login_end]
    login = once(login,
        "  const LoginPage({super.key});",
        """  const LoginPage({
    super.key,
    this.openExistingOriginalAfterExplicitConsent = false,
  });

  // True ONLY from a user-confirmed missing-UID rescue action. The normal
  // first login screen and account creation flow remain unchanged.
  final bool openExistingOriginalAfterExplicitConsent;""",
        "opt-in original login entry only")
    main = main[:login_start] + login + main[login_end:]

    state_start = main.index("class _LoginPageState extends State<LoginPage> {")
    state_end = main.index("class HomePage extends ", state_start)
    login_state = main[state_start:state_end]
    login_state = once(login_state,
        """  void initState() {
    super.initState();
    _loadLanguage();
  }""",
        """  void initState() {
    super.initState();
    _loadLanguage();
    if (widget.openExistingOriginalAfterExplicitConsent) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !dedaSessionRescueStage3Enabled ||
            !dedaStep2ExistingAccountEntryEnabled ||
            Firebase.apps.isEmpty ||
            FirebaseAuth.instance.currentUser != null) return;
        // The EXISTING verified PIN / canonical UID / server checkpoint
        // delegate is the sole login path. No fresh anonymous principal.
        _openExistingAccount();
      });
    }
  }""",
        "explicit original login preselection")
    main = main[:state_start] + login_state + main[state_end:]

    # A single, explicit button shared by friends + settings. The modal
    # rechecks live UID and account selection after the user confirms it.
    helper = """Future<void> dedaPromptOriginalAccountForMissingSession(
    BuildContext context) async {
  if (!DedaPreferences.isLoggedIn) return;
  final selectedPhone = DedaPreferences.accountPhone.trim().isNotEmpty
      ? DedaPreferences.accountPhone : DedaPreferences.phone;
  final selectedKey = DedaPinAuth.accountKeyForPhone(selectedPhone);
  final original = DedaBackend.personalShareIdForPhone(selectedPhone);
  bool offer() => DedaMissingOwnerEntryPolicy.canOffer(
    status: DedaRescueStatus.signedOut,
    rescueEnabled: dedaSessionRescueStage3Enabled,
    verifiedExistingEntryEnabled: dedaStep2ExistingAccountEntryEnabled,
    firebaseReady: Firebase.apps.isNotEmpty,
    liveUid: Firebase.apps.isEmpty
        ? null : FirebaseAuth.instance.currentUser?.uid,
    accountKey: selectedKey, originalId: original,
  );
  if (!offer()) return;
  final confirmed = await showDialog<bool>(
    context: context, barrierDismissible: false,
    builder: (dialog) => AlertDialog(
      title: Text(dedaText('استعادة جلسة حسابك الأصلي',
          'Restore your original account session')),
      content: Text(dedaText(
        'جلسة Firebase الأصلية غير موجودة. نفتح «لدي حساب سابق» حتى تؤكد '
        'رقمك والرمز من خلال الحارس الأصلي. لن نحذف بياناتك أو ننشئ UID جديداً.',
        'The original session is missing. Use the existing account screen '
        'to verify your phone and PIN with the original guardian. '
        'No data is cleared and no replacement UID is created.',
      )),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialog).pop(false),
          child: Text(dedaText('إلغاء', 'Cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialog).pop(true),
          child: Text(dedaText('لدي حساب سابق', 'I have an account')),
        ),
      ],
    ),
  );
  if (!context.mounted) return;
  if (!DedaMissingOwnerEntryPolicy.mayOpenAfterConsent(
    explicitUserConsent: confirmed == true,
    accountUnchanged: selectedPhone ==
        (DedaPreferences.accountPhone.trim().isNotEmpty
            ? DedaPreferences.accountPhone : DedaPreferences.phone),
    status: DedaRescueStatus.signedOut,
    rescueEnabled: dedaSessionRescueStage3Enabled,
    verifiedExistingEntryEnabled: dedaStep2ExistingAccountEntryEnabled,
    firebaseReady: Firebase.apps.isNotEmpty,
    liveUid: Firebase.apps.isEmpty
        ? null : FirebaseAuth.instance.currentUser?.uid,
    accountKey: selectedKey, originalId: original,
  )) return;
  // Push instead of logout / pushAndRemoveUntil: back preserves all
  // previous local account data when owner proof is cancelled or denied.
  await Navigator.of(context).push<void>(MaterialPageRoute<void>(
    builder: (_) => const LoginPage(
      openExistingOriginalAfterExplicitConsent: true),
  ));
}

"""
    main = once(main,
        "class LoginPage extends StatefulWidget {",
        helper + "class LoginPage extends StatefulWidget {",
        "one shared consent-only original login entry")

    friends_start = main.index("class _DedaFriendsPageState extends State<DedaFriendsPage> {")
    friends_end = main.index("class _DedaFriendCompactCard", friends_start)
    friends = main[friends_start:friends_end]
    # The next block appears ONLY in the error branch introduced by point 1.
    friend_action_anchor = """                        FilledButton.icon(
                          onPressed: _loadingFriends
                              ? null : () => unawaited(_prepare()),
                          icon: const Icon(Icons.refresh_rounded),
                          label: Text(dedaText('إعادة المحاولة', 'Retry')),
                        ),
                      ],
                    ),
            )"""
    friend_action = """                        FilledButton.icon(
                          onPressed: _loadingFriends
                              ? null : () => unawaited(_prepare()),
                          icon: const Icon(Icons.refresh_rounded),
                          label: Text(dedaText('إعادة المحاولة', 'Retry')),
                        ),
                        if (dedaSessionRescueStage3Enabled &&
                            dedaStep2ExistingAccountEntryEnabled &&
                            Firebase.apps.isNotEmpty &&
                            FirebaseAuth.instance.currentUser == null) ...[
                          const SizedBox(height: 8),
                          TextButton.icon(
                            onPressed: () => unawaited(
                              dedaPromptOriginalAccountForMissingSession(context)),
                            icon: const Icon(Icons.verified_user_outlined),
                            label: Text(dedaText(
                              'تأكيد حسابي السابق', 'Verify my existing account')),
                          ),
                        ],
                      ],
                    ),
            )"""
    friends = once(friends, friend_action_anchor, friend_action,
                   "friends missing session explicit login")
    main = main[:friends_start] + friends + main[friends_end:]

    # Settings is useful when friends cannot be opened. Do not disclose
    # admin access; only suggest restoring the missing regular owner session.
    settings_anchor = """                  // Fail closed: ordinary users see no administration
                  // heading, card, button, or reserved blank space.
                  if (_adminEntryVisible) ...["""
    settings_replacement = """                  // An absent original Firebase session is NOT admin denial.
                  // Explicit owner entry only; never show the admin panel.
                  if (!_adminEntryVisible &&
                      _sessionRescueStatus == DedaRescueStatus.signedOut &&
                      dedaSessionRescueStage3Enabled &&
                      dedaStep2ExistingAccountEntryEnabled &&
                      Firebase.apps.isNotEmpty &&
                      FirebaseAuth.instance.currentUser == null) ...[
                    ListTile(
                      title: Text(dedaText(
                        'تأكيد جلسة حساب ديدا الأصلي',
                        'Verify your original DEDA session')),
                      trailing: TextButton(
                        onPressed: () => unawaited(
                          dedaPromptOriginalAccountForMissingSession(context)),
                        child: Text(dedaText('لدي حساب سابق', 'I have an account')),
                      ),
                    ),
                  ],
                  // Fail closed: ordinary users see no administration
                  // heading, card, button, or reserved blank space.
                  if (_adminEntryVisible) ...["""
    main = once(main, settings_anchor, settings_replacement,
                "settings user re-entry without admin grant")
    if "signInAnonymously()" in helper or "createAccount(" in helper:
        raise ValueError("BLOCK_MISSING_OWNER_SIDE_EFFECT")
    # Validate all surgery in memory before writing the disposable files.
    main_path.write_text(main)
    shutil.copy2(ROOT / POLICY, candidate)
    print("PASS_EXPLICIT_MISSING_UID_REUSES_EXISTING_PIN_UID_GUARD_NO_NEW_ACCOUNT")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("project", type=Path)
    bind(parser.parse_args().project)
