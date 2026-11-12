#!/usr/bin/env python3
"""Safely add exactly one Google-link field ABOVE voice/navigation settings.

Apply only to an independently assembled full 100439 source; never replace
the signed 100439 main.dart, Android assets, Firebase rules or wallet.
No build, Firebase deployment, login or financial writes are performed.
"""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MODULE = "lib/deda_step1_google_settings_link_100439.dart"
REPLACEMENT = "lib/deda_step2_google_replacement_login_100439.dart"
PROGRESS = "lib/deda_google_recovery_progress_100439.dart"
MAIN = "lib/main.dart"
BACKEND = "lib/deda_backend.dart"
PUBSPEC = "pubspec.yaml"
GOOGLE_CONFIG = "config/deda_google_auth_100439/google-services.json"
ANDROID_CONFIG = "android/app/google-services.json"
IMPORT = "import 'deda_100433_owner_confirmation_ui.dart';"
SETTINGS_ANCHOR = """                  _sectionTitle(
                      dedaText('الصوت والملاحة', 'Voice & navigation')),"""
INSERT = """                  if (dedaStep1GoogleOwnerLinkEnabled) ...[
                    DedaGoogleSettingsLinkCard(
                      phone: DedaPreferences.accountPhone.trim().isNotEmpty
                          ? DedaPreferences.accountPhone
                          : DedaPreferences.phone,
                      originalId: DedaBackend.personalShareIdForPhone(
                        DedaPreferences.accountPhone.trim().isNotEmpty
                            ? DedaPreferences.accountPhone
                            : DedaPreferences.phone),
                      isArabic: DedaLanguageState.isArabic,
                    ),
                    const SizedBox(height: 8),
                  ],
"""
GOOGLE_PIN = "  google_sign_in: 6.3.0"


def abort(why):
    raise SystemExit("BLOCK_GOOGLE_OWNER_SETTINGS:" + why)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def exactly_once(text, old, replacement, label):
    if text.count(old) != 1:
        abort(label + " expected 1 anchor, got " + str(text.count(old)))
    return text.replace(old, replacement, 1)


def bind(project):
    project = Path(project).resolve()
    if project == ROOT or ROOT in project.parents:
        abort("must not modify repository or signed reference")
    manifest = project / "internal-build-inputs.json"
    if not manifest.is_file() or not (project / "deda-stage2-core-merge-proof.json").is_file():
        abort("missing verified full Stage2 assembly")
    meta = json.loads(manifest.read_text())
    if not meta.get("weekly100439AdminWinnersPrizeReport", {}).get("singlePanelNoDuplicate"):
        abort("100439 manager winners baseline missing")
    if meta.get("financialRestoreEnabled") is not False:
        abort("financial restoration must remain disabled")
    # Copy the owner-approved Google OAuth config into the disposable Android
    # build only; preserve the checked-in 100439 original and release signing.
    staged_config = ROOT / GOOGLE_CONFIG
    target_config = project / ANDROID_CONFIG
    original_config = ROOT / "google-services.json"
    if not staged_config.is_file() or not target_config.is_file():
        abort("reviewed OAuth config or generated Android app config missing")
    if digest(target_config) != digest(original_config):
        abort("Android config does not match protected 100439 build input")
    try:
        oauth = json.loads(staged_config.read_text())
        oauth_issues = __import__("runpy").run_path(
            str(ROOT / "tools/deda_google_auth_readiness_100439.py")
        )["review"](oauth)
    except (OSError, ValueError, KeyError):
        abort("invalid Google OAuth configuration")
    if oauth_issues:
        abort("Google OAuth release configuration not verified: " + ",".join(oauth_issues))

    main = project / MAIN
    module = project / MODULE
    replacement = project / REPLACEMENT
    progress = project / PROGRESS
    if not (ROOT / PROGRESS).is_file():
        abort("reviewed progress policy missing")
    if progress.exists() and digest(progress) != digest(ROOT / PROGRESS):
        abort("recovery progress policy does not match reviewed module")
    if not (ROOT / REPLACEMENT).is_file():
        abort("reviewed Google replacement-phone source missing")
    if replacement.exists() and digest(replacement) != digest(ROOT / REPLACEMENT):
        abort("replacement phone source does not match reviewed isolated module")
    if module.exists():
        abort("duplicate Google settings module")
    if not (ROOT / MODULE).is_file():
        abort("reviewed card source missing")
    old = main.read_text()
    if "DedaGoogleSettingsLinkCard(" in old:
        abort("Google settings card already exists")

    new = exactly_once(old, IMPORT,
        IMPORT + "\nimport 'deda_step1_google_settings_link_100439.dart';"
        + "\nimport 'deda_step2_google_replacement_login_100439.dart';"
        + "\nimport 'deda_google_recovery_progress_100439.dart';",
        "Google settings import")
    new = exactly_once(new, SETTINGS_ANCHOR,
        INSERT + SETTINGS_ANCHOR, "settings location above voice")
    new = exactly_once(new,
        "        currentEmail: user?.email,",
        """        currentEmail: user?.email,
        currentHasOriginalGoogleProvider: user != null &&
            user.providerData.any((p) => p.providerId == 'google.com') &&
            DedaLinkedOwnerSessionPolicy.userProviderIdentityMatches(
                user, prefs.getString(_linkedVerifiedAccountKey) ?? ''),""",
        "Google-linked owner cold-start preservation")
    new = exactly_once(new,
        """        enabled: dedaStep2ExistingAccountEntryEnabled,
        verifiedLogin: (phone, pin) async {""",
        """        enabled: dedaStep2ExistingAccountEntryEnabled,
        googleEnabled: dedaStep2GoogleReplacementLoginEnabled,
        verifiedGoogleLogin: (reportProgress) async {
          if (!mounted || !pageContext.mounted) {
            throw StateError('expired-google-existing-account-intent');
          }
          final verified =
              await DedaGoogleReplacementLogin.verifyOnNewPhone(
            explicitUserAction: true,
            isCurrentIntent: () => mounted && pageContext.mounted,
            onProgress: reportProgress,
          );
          // Identity proof only. Never claim 100% or show the green tick.
          // A separate live guardian completion receipt is required.
          return verified == null
              ? DedaGoogleRecoveryOutcome.cancelled
              : DedaGoogleRecoveryOutcome.identityVerifiedOnly;
        },
        verifiedLogin: (phone, pin) async {""",
        "replacement phone explicit Google button")
    if new.count("DedaGoogleSettingsLinkCard(") != 1:
        abort("not exactly one Google settings card")

    backend_path = project / BACKEND
    backend_old = backend_path.read_text()
    old_owner_gate = (
        "DedaLinkedOwnerSessionPolicy.emailMatches(user.email, cleanKey)")
    verified_owner_gate = (
        "DedaLinkedOwnerSessionPolicy.userProviderIdentityMatches(user, cleanKey)")
    # 100441's one-session source may already contain the stronger reviewed
    # provider gate. Do not replace or duplicate it during full assembly.
    if backend_old.count(verified_owner_gate) == 1 and old_owner_gate not in backend_old:
        backend_new = backend_old
    elif backend_old.count(old_owner_gate) == 1 and verified_owner_gate not in backend_old:
        backend_new = exactly_once(
            backend_old, old_owner_gate, verified_owner_gate,
            "protect original user vs admin in backend after Google linking")
    else:
        abort("ambiguous original-owner provider gate in full assembly")
    dependency = project / PUBSPEC
    old_pub = dependency.read_text()
    if "google_sign_in:" in old_pub:
        abort("Google package already configured; review required")
    new_pub = exactly_once(old_pub,
        "  google_mobile_ads: 9.1.0",
        "  google_mobile_ads: 9.1.0\n" + GOOGLE_PIN,
        "Google package dependency")
    main.write_text(new)
    backend_path.write_text(backend_new)
    module.write_bytes((ROOT / MODULE).read_bytes())
    if not replacement.exists():
        replacement.write_bytes((ROOT / REPLACEMENT).read_bytes())
    if not progress.exists():
        progress.write_bytes((ROOT / PROGRESS).read_bytes())
    dependency.write_text(new_pub)
    target_config.write_bytes(staged_config.read_bytes())
    meta["googleConfigSha256"] = digest(target_config)
    hashes = meta.setdefault("sourceHashes", {})
    for path in (MAIN, BACKEND, MODULE, REPLACEMENT, PROGRESS, PUBSPEC, ANDROID_CONFIG):
        hashes[path] = digest(project / path)
    meta["googleOriginalUidSettings"] = {
        "position": "top_of_settings_above_voice_navigation",
        "fields": 1,
        "defaultOff": True,
        "requiresOriginalUid": True,
        "requiresGoogleOAuthConfiguration": True,
        "googleOAuthReleaseConfigVerified": True,
        "googleConfigStagedOnlyInIsolatedAndroidApp": True,
        "googleReplacementLoginOptInOnly": True,
        "noCreateGoogleProviderPreflight": True,
        "googleLoginNeverCommitsProfileOrWallet": True,
        "googleProgressDrivenByVerifiedOperations": True,
        "googleFailureFreezesRedAndEnablesRetry": True,
        "noCheckmarkOr100WithoutFullAccountGuardian": True,
        "noNewUserOrDataMerge": True,
        "financialRestoreEnabled": False,
        "googlePackageLockUpdateRequiredInIsolatedWorkspace": True,
        "noFirebaseOrPlayDeploy": True,
    }
    manifest.write_text(json.dumps(meta, ensure_ascii=False, indent=2) + "\n")
    print("PASS_GOOGLE_LINK_FIELD_ABOVE_VOICE_ONLY_IN_FULL_ASSEMBLED_100439")
    print("PASS_ORIGINAL_100439_REPO_ASSETS_FIREBASE_AND_SIGNING_UNCHANGED")
    return meta["googleOriginalUidSettings"]


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("project", type=Path)
    args = parser.parse_args()
    bind(args.project)
