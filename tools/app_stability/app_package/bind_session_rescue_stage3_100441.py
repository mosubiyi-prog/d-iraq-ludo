#!/usr/bin/env python3
"""Stage3 SOURCE-ONLY opt-in binder on assembled protected 100440 source.

Run AFTER the smart second-stage binder in a disposable project.
Never mutate source 100440, production Firebase, a released APK or Play.
"""
from __future__ import annotations

import argparse
import json
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]

def replace_once(text: str, old: str, new: str, label: str) -> str:
    if text.count(old) != 1:
        raise ValueError("BLOCK_STAGE3_ANCHOR:" + label + ":" + str(text.count(old)))
    return text.replace(old, new, 1)

def bind(project: Path) -> None:
    project = Path(project)
    main_path = project / "lib/main.dart"
    if not main_path.is_file():
        raise ValueError("BLOCK_STAGE3_MISSING_ASSEMBLED_MAIN")
    main = main_path.read_text()
    if "DedaSessionRescueStage3Bridge" in main:
        raise ValueError("BLOCK_STAGE3_DUPLICATE_BIND")

    main = replace_once(
        main,
        "import 'deda_100433_owner_confirmation_ui.dart';",
        "import 'deda_100433_owner_confirmation_ui.dart';\n"
        "import 'deda_session_recovery_coordinator.dart';\n"
        "import 'deda_session_rescue_stage3_bridge.dart';",
        "isolated stage3 imports",
    )
    main = replace_once(
        main,
        "  bool _adminEntryVisible = false;",
        "  bool _adminEntryVisible = false;\n"
        "  DedaRescueStatus? _sessionRescueStatus;\n",
        "settings rescue state",
    )
    # PRESERVE the entire existing administration guard verbatim. It may
    # differ between protected 100436 and 100440 assembly variants.
    main = replace_once(
        main,
        "  Future<void> _refreshAdminEntryVisibility() async {",
        "  Future<void> _refreshAdminEntryVisibilityOriginal() async {",
        "retain original admin check and permissions",
    )
    main = replace_once(
        main,
        "  Widget _sectionTitle(String text) {",
        """  Future<void> _refreshAdminEntryVisibility() async {
    // Rescue feature ON: an absent principal must not be turned into a
    // different anonymous UID by a legacy admin-entry readiness helper.
    if (dedaSessionRescueStage3Enabled && Firebase.apps.isNotEmpty &&
        FirebaseAuth.instance.currentUser == null) {
      if (mounted) {
        setState(() {
          _adminEntryVisible = false;
          _sessionRescueStatus = DedaRescueStatus.signedOut;
        });
      }
      return;
    }
    await _refreshAdminEntryVisibilityOriginal();
    if (!mounted || _adminEntryVisible ||
        !dedaSessionRescueStage3Enabled) return;
    final phone = DedaPreferences.accountPhone.trim().isNotEmpty
        ? DedaPreferences.accountPhone
        : DedaPreferences.phone;
    final rescue = await DedaSessionRescueStage3Bridge.runForPhone(phone);
    if (!mounted) return;
    setState(() => _sessionRescueStatus = rescue?.status);
    // This is not authorization: repeat the EXACT original server-controlled
    // gateway check ONLY when the same owner UID was re-proven.
    if (rescue?.mayRecheckAdminGateway == true) {
      await _refreshAdminEntryVisibilityOriginal();
    }
  }

  Widget _sectionTitle(String text) {""",
        "wrapper around original admin entry gate",
    )
    main = replace_once(
        main,
        """                  // Fail closed: ordinary users see no administration
                  // heading, card, button, or reserved blank space.
                  if (_adminEntryVisible) ...[""",
        """                  // Network trouble is not proof of admin denial.
                  // This generic retry does not reveal any protected card.
                  if (!_adminEntryVisible &&
                      _sessionRescueStatus ==
                          DedaRescueStatus.temporarilyOffline) ...[
                    ListTile(
                      title: Text(dedaText(
                        'تعذر الاتصال للتحقق من حسابك.',
                        'Could not reconnect to verify your account.',
                      )),
                      trailing: TextButton(
                        onPressed: _refreshAdminEntryVisibility,
                        child: Text(dedaText('إعادة المحاولة', 'Retry')),
                      ),
                    ),
                  ],
                  // Fail closed: ordinary users see no administration
                  // heading, card, button, or reserved blank space.
                  if (_adminEntryVisible) ...[""",
        "network retry UI without showing admin access",
    )
    # 100414 adds more work into Home's post-frame callback. Replace only
    # the unique initializer call; preserve its other owner-read watchers.
    main = replace_once(
        main,
        "      _initializeShareIdentity();",
        """      // Preserve the initial location-share initialization, then
      // inspect the same owner's Firebase session (never in parallel).
      if (dedaSessionRescueStage3Enabled && Firebase.apps.isNotEmpty &&
          FirebaseAuth.instance.currentUser == null) {
        // Do not let the legacy share-session helper create an anonymous
        // substitute for the missing original UID. Inspection only.
        unawaited(DedaSessionRescueStage3Bridge
            .runForPhone(DedaPreferences.phone).then((_) {}));
      } else {
        unawaited(_initializeShareIdentity().then((_) async {
          if (!mounted || !dedaSessionRescueStage3Enabled) return;
          await DedaSessionRescueStage3Bridge
              .runForPhone(DedaPreferences.phone);
        }));
      }""",
        "home single initializer safe sequential rescue",
    )
    for file_name in (
        "deda_session_recovery_coordinator.dart",
        "deda_session_rescue_stage3_core.dart",
        "deda_session_rescue_stage3_bridge.dart",
    ):
        source = ROOT / "lib" / file_name
        target = project / "lib" / file_name
        if not source.is_file() or target.exists():
            raise ValueError("BLOCK_STAGE3_SOURCE_OVERWRITE:" + file_name)
    # Validate all source anchors before the first write. Clones only.
    main_path.write_text(main)
    for file_name in (
        "deda_session_recovery_coordinator.dart",
        "deda_session_rescue_stage3_core.dart",
        "deda_session_rescue_stage3_bridge.dart",
    ):
        shutil.copy2(ROOT / "lib" / file_name, project / "lib" / file_name)

    # Metadata is a staging record only, not a release authorization.
    metadata = project / "internal-build-inputs.json"
    if metadata.exists():
        record = json.loads(metadata.read_text())
        record["sessionRescueStage3"] = {
            "defaultOff": True,
            "requiresExplicitBuildFlag": "DEDA_SESSION_RESCUE_STAGE3",
            "sameGuardianOnly": True,
            "activePremiumIdMinLength": 4,
            "immutableOriginalIdLength": 6,
            "adminEntryMustRemainServerAuthorized": True,
            "noImplicitProviderLink": True,
            "ownerPhoneVerificationPending": True,
        }
        metadata.write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n")
    print("PASS_STAGE3_DISPOSABLE_BRIDGE_GUARD_ADMIN_4CHAR_NO_APK")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("project", type=Path)
    args = parser.parse_args()
    bind(args.project)
