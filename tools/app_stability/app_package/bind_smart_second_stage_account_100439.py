#!/usr/bin/env python3
"""Bind the owner-approved smart SECOND account screen to an isolated assembly.

Run AFTER bind_google_account_settings_100439.py, in a disposable full app
assembly only. The original 100439 source, APK, app resources, Firebase and
wallet are never written by this script. Fail closed on unexpected anchors.
"""
import argparse
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MODULE = "lib/deda_step2_smart_second_stage_account_page_100439.dart"
MAIN = "lib/main.dart"
IMPORT = "import 'deda_step2_existing_account_signin_page.dart';"
ENTRY = "  void _openExistingAccount() {\n"
NEXT = "\n  Future<void> login() async {"
PROTECTED_EXISTING = """      final exists = await DedaPinAuth.accountExists(normalizedPhone);
      if (!mounted) return;
      if (exists) {"""
# Exact statement and method scope are required; indentation varies between
# the raw staging file and the protected fully assembled login guardian.
GUARD_LOGIN = re.compile(
    r"(?m)^(?P<indent>[ ]+)await _completeVerifiedLogin\(normalizedPhone\);$"
)

ORIGINAL_EXISTING = re.compile(
    r"  void _openExistingAccount\(\) \{\n"
    r"    if \(!dedaStep2ExistingAccountEntryEnabled \|\| !mounted\) return;\n"
    r"    Navigator\.of\(context\)\.push\(MaterialPageRoute<void>\(\n"
    r"      builder: \(pageContext\) => DedaExistingAccountSignInPage\(\n"
    r"(?P<arguments>.*?)\n"
    r"      \),\n"
    r"    \)\);\n"
    r"  \}\n",
    flags=re.DOTALL,
)


def abort(reason):
    raise SystemExit("BLOCK_SMART_SECOND_ACCOUNT:" + reason)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def exactly_once(text, before, after, label):
    if text.count(before) != 1:
        abort(label + ": expected one exact original anchor, got " +
              str(text.count(before)))
    return text.replace(before, after, 1)


def _build_methods(arguments):
    # Original verified Google and PIN guardian callbacks are preserved as
    # EXACT text, not rewritten or simplified. The existing route and smart
    # switch share one widget builder and one guardian handler.
    common = """  Widget _buildExistingAccountForm(BuildContext pageContext, {
    bool embedded = false,
    String? initialPhone,
  }) {
    return DedaExistingAccountSignInPage(
      embedded: embedded,
      initialPhone: initialPhone,
""" + arguments + """
    );
  }

  void _openExistingAccount() {
    if (!dedaStep2ExistingAccountEntryEnabled || !mounted) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (pageContext) => _buildExistingAccountForm(pageContext),
    ));
  }

"""
    smart = """  void _openSmartSecondAccountStage(
      String initialName, String normalizedPhone, {required bool accountExists}) {
    if (!dedaSmartSecondStageAccountEnabled ||
        !dedaStep2ExistingAccountEntryEnabled || !mounted) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (pageContext) => DedaSmartSecondStageAccountPage(
        initialName: initialName,
        initialPhone: normalizedPhone,
        initialChoice: accountExists
            ? DedaSmartAccountChoice.existingAccount
            : DedaSmartAccountChoice.newAccount,
        existingAccountBuilder: (_) => _buildExistingAccountForm(
          pageContext, embedded: true, initialPhone: normalizedPhone),
        onCreateNew: (fullName, phone, pin) async {
          if (!mounted || !pageContext.mounted) {
            throw StateError('expired-new-owner-intent');
          }
          // Never silently overwrite or reuse a previous owner's number.
          // The subsequent CREATE transaction repeats this check atomically.
          if (await DedaPinAuth.accountExists(phone)) {
            throw StateError('existing-owner-number');
          }
          if (!mounted || !pageContext.mounted) {
            throw StateError('expired-new-owner-intent');
          }
          final created = await DedaPinAuth.createAccount(
            phone: phone, fullName: fullName, pin: pin);
          final createdUid = created['uid'];
          if (createdUid is! String || createdUid.isEmpty ||
              FirebaseAuth.instance.currentUser?.uid != createdUid) {
            throw StateError('new-owner-uid-not-proven');
          }
          final accountKey = DedaPinAuth.accountKeyForPhone(phone);
          final records = await Future.wait([
            FirebaseFirestore.instance.doc('users/$createdUid').get(
                const GetOptions(source: Source.server)),
            FirebaseFirestore.instance.doc(
                'deda_account_directory/$accountKey').get(
                const GetOptions(source: Source.server)),
          ]);
          if (!mounted || !pageContext.mounted ||
              FirebaseAuth.instance.currentUser?.uid != createdUid ||
              records.any((r) => !r.exists || r.metadata.isFromCache ||
                  r.metadata.hasPendingWrites) ||
              records[0].data()?['accountKey'] != accountKey ||
              records[1].data()?['accountKey'] != accountKey ||
              records[1].data()?['createdUid'] != createdUid) {
            throw StateError('new-owner-server-readback-not-proven');
          }
          // Commit local login only AFTER server creation and UID readback.
          await DedaPreferences.saveLogin(
            name: fullName, normalizedPhone: phone,
            type: DedaAccountType.user,
          );
          if (!mounted || !pageContext.mounted) return;
          Navigator.of(pageContext).pushAndRemoveUntil(
            MaterialPageRoute<void>(
              builder: (_) => HomePage(userName: fullName)),
            (_) => false,
          );
        },
      ),
    ));
  }

"""
    return common + smart


def bind(project):
    project = Path(project).resolve()
    if project == ROOT or ROOT in project.parents:
        abort("may not modify repository or protected reference")
    manifest = project / "internal-build-inputs.json"
    if not manifest.is_file() or not (
            project / "deda-stage2-core-merge-proof.json").is_file():
        abort("full original 100439 guardian assembly missing")
    meta = json.loads(manifest.read_text())
    google = meta.get("googleOriginalUidSettings", {})
    if not google.get("googleProgressDrivenByVerifiedOperations") or not (
            meta.get("weekly100439AdminWinnersPrizeReport", {})
            .get("singlePanelNoDuplicate")):
        abort("expected full manager-prizes plus Google UI assembly missing")
    if meta.get("financialRestoreEnabled") is not False:
        abort("financial restore must remain disabled")

    module = ROOT / MODULE
    target = project / MODULE
    if not module.is_file():
        abort("smart second-stage reviewed source not found")
    if target.is_file() and digest(target) != digest(module):
        abort("smart second-stage source drift")
    main = project / MAIN
    current = main.read_text()
    if "DedaSmartSecondStageAccountPage(" in current:
        abort("duplicate smart second account screen")
    if current.count(ENTRY) != 1 or current.count(NEXT) != 1:
        abort("original existing-account route not found")
    start = current.index(ENTRY)
    end = current.index(NEXT, start)
    original_route = current[start:end]
    match = ORIGINAL_EXISTING.fullmatch(original_route)
    if match is None:
        abort("guardian-backed existing route changed: review required")
    args = match.group("arguments")
    if "verifiedGoogleLogin: (reportProgress) async {" not in args or (
            "verifiedLogin: (phone, pin) async {" not in args) or (
            "if (!login.fullAccountRestored" not in args):
        abort("existing Google/PIN guardian flow or hold gate missing")
    current = current[:start] + _build_methods(args) + current[end:]
    current = exactly_once(current, IMPORT, IMPORT +
        "\nimport 'deda_pin_auth.dart';" +
        "\nimport 'deda_google_recovery_progress_100439.dart';" +
        "\nimport 'deda_step2_smart_second_stage_account_page_100439.dart';",
        "additive second page and new PIN creator imports")
    # Original signed 100436/100439 login has an existing-account lookup,
    # NOT the raw Stage2 _completeVerifiedLogin shortcut. Insert only AFTER
    # its verified exists read, BEFORE the unchanged existing/new branches.
    if current.count(PROTECTED_EXISTING) == 1:
        routed = """      final exists = await DedaPinAuth.accountExists(normalizedPhone);
      if (!mounted) return;
      if (dedaSmartSecondStageAccountEnabled &&
          dedaStep2ExistingAccountEntryEnabled) {
        _openSmartSecondAccountStage(
            '', normalizedPhone, accountExists: exists);
        return;
      }
      if (exists) {"""
        current = exactly_once(current, PROTECTED_EXISTING, routed,
            "protected original phone-first account lookup")
        assembled_protected = True
    else:
        # Separate, previously tested raw Stage2 development entry. The
        # account existence check is server-backed, never guessed by UI.
        commits = list(GUARD_LOGIN.finditer(current))
        if len(commits) != 1 or commits[0].start() < current.index(NEXT):
            abort("unrecognized login source; fail without touching first page")
        commit = commits[0]
        indent = commit.group("indent")
        guarded = (
            indent + "if (dedaSmartSecondStageAccountEnabled &&\n" +
            indent + "    dedaStep2ExistingAccountEntryEnabled) {\n" +
            indent + "  final accountExists =\n" +
            indent + "      await DedaPinAuth.accountExists(normalizedPhone);\n" +
            indent + "  if (!mounted) return;\n" +
            indent + "  _openSmartSecondAccountStage(\n" +
            indent + "      name, normalizedPhone, accountExists: accountExists);\n" +
            indent + "  return;\n" +
            indent + "}\n" + commit.group(0)
        )
        current = current[:commit.start()] + guarded + current[commit.end():]
        assembled_protected = False
    if current.count("DedaSmartSecondStageAccountPage(") != 1 or (
            current.count("_buildExistingAccountForm(") != 3):
        abort("smart second account and shared existing guard not exactly once")
    if assembled_protected:
        if current.count("      if (exists) {") != 1:
            abort("protected original login branch missing after safe insertion")
    elif current.count("await _completeVerifiedLogin(normalizedPhone);") != 1:
        abort("default-off raw first-page behavior unexpectedly removed")
    main.write_text(current)
    if not target.is_file():
        target.write_bytes(module.read_bytes())
    hashes = meta.setdefault("sourceHashes", {})
    for path in (MAIN, MODULE):
        hashes[path] = digest(project / path)
    meta["smartSecondStageAccount"] = {
        "originalFirstScreenSourceProtected": True,
        "originalFirstScreenVisibleFieldsUnchanged": True,
        "newAccountNameAndSixDigitPinPreserved": True,
        "existingAccountSameScreen": True,
        "existingGoogleProgressAndGuardianCallbacksReused": True,
        "newAccountDuplicateCheckBeforeServerAtomicCreate": True,
        "newAccountServerUIDReadbackBeforeLocalLogin": True,
        "noNewAccountOnGoogleOrExistingMode": True,
        "defaultOff": True,
        "financialRestoreEnabled": False,
        "noFirebaseOrPlayDeploy": True,
    }
    manifest.write_text(json.dumps(meta, ensure_ascii=False, indent=2) + "\n")
    print("PASS_SMART_SECOND_STAGE_ONLY_IN_FULL_ISOLATED_ASSEMBLY")
    print("PASS_100439_PROTECTED_FIRST_SCREEN_AND_EXISTING_GUARDIAN_PRESERVED")


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("project", type=Path)
    args = p.parse_args()
    bind(args.project)
