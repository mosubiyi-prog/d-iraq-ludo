#!/usr/bin/env python3
"""Stage3 SOURCE-ONLY opt-in binder on assembled protected 100440 source.

Run AFTER 100440 Google and smart second-stage binders in a disposable project.
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
    google_path = project / "lib/deda_step1_google_settings_link_100439.dart"
    if not main_path.is_file() or not google_path.is_file():
        raise ValueError("BLOCK_STAGE3_MISSING_ASSEMBLED_GOOGLE_OR_MAIN")
    main = main_path.read_text()
    google = google_path.read_text()
    if "DedaSessionRescueStage3Bridge" in main or "DedaSessionRescueStage3Bridge" in google:
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
    old_check = """    var allowed = false;
    try {
      allowed = await DedaBackend.currentDedaAccountCanSeeAdminEntry(
        phone: phone,
      );
    } catch (_) {
      allowed = false;
    }

    if (!mounted) return;
    setState(() => _adminEntryVisible = allowed);"""
    new_check = """    var allowed = false;
    DedaRescueStage3Result? rescue;
    // Keep the already-shipped gateway check and all its security rules.
    try {
      allowed = await DedaBackend.currentDedaAccountCanSeeAdminEntry(
        phone: phone,
      );
    } catch (_) {
      allowed = false;
    }
    if (!mounted) return;
    if (!allowed && dedaSessionRescueStage3Enabled) {
      // Only retry AFTER SAME UID original-account evidence. This does not
      // grant an admin role or bypass admin_entry_access.
      rescue = await DedaSessionRescueStage3Bridge.runForPhone(phone);
      if (!mounted) return;
      if (rescue?.mayRecheckAdminGateway == true) {
        try {
          allowed = await DedaBackend.currentDedaAccountCanSeeAdminEntry(
            phone: phone,
          );
        } catch (_) {
          allowed = false;
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _adminEntryVisible = allowed;
      _sessionRescueStatus = rescue?.status;
    });"""
    main = replace_once(main, old_check, new_check, "admin entry guarded retry")
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
    main = replace_once(
        main,
        """    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeShareIdentity();
    });""",
        """    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Never race the existing home identity initialization with a second
      // session-inspection lane. Start rescue after its original Future settles.
      unawaited(_initializeShareIdentity().then((_) async {
        if (!mounted || !dedaSessionRescueStage3Enabled) return;
        await DedaSessionRescueStage3Bridge
            .runForPhone(DedaPreferences.phone);
      }));
    });""",
        "home initial guarded rescue",
    )
    google = replace_once(
        google,
        "import 'deda_100430_owner_uid_continuity.dart';",
        "import 'deda_100430_owner_uid_continuity.dart';\n"
        "import 'deda_session_rescue_stage3_bridge.dart';",
        "google module import",
    )
    google = replace_once(
        google,
        """  void initState() {
    super.initState();
    unawaited(_refresh());
  }""",
        """  void initState() {
    super.initState();
    if (dedaSessionRescueStage3Enabled) {
      DedaSessionRescueStage3Bridge.updates.addListener(_onRescueReady);
    }
    unawaited(_refresh());
  }

  void _onRescueReady() {
    final checked = DedaSessionRescueStage3Bridge.updates.value;
    if (!mounted || _busy || !_active ||
        checked?.mayRecheckGoogleCard != true ||
        checked?.originalId != widget.originalId ||
        checked?.uid != FirebaseAuth.instance.currentUser?.uid) return;
    // Refresh the verified-state badge ONLY. Never auto-open/attach Google.
    unawaited(_refresh());
  }

  @override
  void dispose() {
    if (dedaSessionRescueStage3Enabled) {
      DedaSessionRescueStage3Bridge.updates.removeListener(_onRescueReady);
    }
    super.dispose();
  }""",
        "google ready badge refresh without linking",
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
    google_path.write_text(google)
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
            "googleNoAutoLink": True,
            "ownerPhoneVerificationPending": True,
        }
        metadata.write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n")
    print("PASS_STAGE3_DISPOSABLE_BRIDGE_GUARD_GOOGLE_ADMIN_4CHAR_NO_APK")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("project", type=Path)
    args = parser.parse_args()
    bind(args.project)
