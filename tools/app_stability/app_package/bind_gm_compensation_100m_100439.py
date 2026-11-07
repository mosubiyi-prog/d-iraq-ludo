#!/usr/bin/env python3
"""Stage owner-approved GM administrative compensation capacity in the SAME isolated
100439 Google/recovery assembly. Never touch the signed 100439 original or Firebase.

This is capacity support, not a credit: the visible balance is always the REAL
Firestore wallet balance. A trusted, audited server-only 99m allocation and a
separately reviewed compatible rules release are required before 100m is spendable.
"""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
BACKEND = "lib/deda_backend.dart"
OLD_CAP = "  static const int generalManagerDiamondGiftBudget = 1000000;"
NEW_CAP = """  // 100m maximum ADMINISTRATIVE compensation pool; never personal diamonds.
  // Do not create or top up this balance from the phone.
  static const int generalManagerDiamondGiftBudget = 100000000;
  // Preserve the existing maximum size of ONE audited gift.
  static const int generalManagerSingleDiamondGiftLimit = 1000000;"""
OLD_CREATE = """          'initialBalance': generalManagerDiamondGiftBudget,
          'balance': generalManagerDiamondGiftBudget,"""
NEW_CREATE = """          // A new client wallet remains at the LEGACY 1m under existing rules.
          // Only a separately approved Admin SDK operation can add 99m.
          'initialBalance': 1000000,
          'balance': 1000000,"""
OLD_READ = """      final balance =
          ((snapshot.data()?['balance'] as num?)?.toInt() ?? 0)
              .clamp(0, generalManagerDiamondGiftBudget)
              .toInt();
      return balance;"""
NEW_READ = """      // Never display a fabricated 100m or conceal a corrupted wallet.
      final balance = snapshot.data()?['balance'];
      final initial = snapshot.data()?['initialBalance'];
      if (balance is! int || initial is! int ||
          (initial != 1000000 && initial != generalManagerDiamondGiftBudget) ||
          balance < 0 || balance > initial) {
        throw StateError('admin-compensation-wallet-server-proof-failed');
      }
      return balance;"""
OLD_GRANT = "if (amount <= 0 || amount > generalManagerDiamondGiftBudget) {"
NEW_GRANT = "if (amount <= 0 || amount > generalManagerSingleDiamondGiftLimit) {"
OLD_DEBIT = """        final currentAdmin =
            ((walletSnapshot.data()?['balance'] as num?)?.toInt() ?? 0)
                .clamp(0, generalManagerDiamondGiftBudget)
                .toInt();"""
NEW_DEBIT = """        final walletData = walletSnapshot.data();
        final available = walletData?['balance'];
        final initial = walletData?['initialBalance'];
        if (available is! int || initial is! int ||
            (initial != 1000000 &&
                initial != generalManagerDiamondGiftBudget) ||
            available < 0 || available > initial) {
          throw StateError('admin-compensation-wallet-server-proof-failed');
        }
        final currentAdmin = available;"""


def fail(why):
    raise ValueError("BLOCK_GM_100M_COMPENSATION:" + why)


def once(source, before, after, where):
    count = source.count(before)
    if count != 1:
        fail(where + " expected one original anchor, found " + str(count))
    return source.replace(before, after, 1)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def bind(project):
    project = Path(project).resolve()
    if project == ROOT or ROOT in project.parents or project in ROOT.parents:
        fail("never modify repository or protected source")
    manifest = project / "internal-build-inputs.json"
    if not manifest.is_file() or not (
            project / "deda-stage2-core-merge-proof.json").is_file():
        fail("full protected recovery assembly proof missing")
    meta = json.loads(manifest.read_text(encoding="utf-8"))
    if meta.get("financialRestoreEnabled") is not False:
        fail("financial restore must stay disabled")
    if not meta.get("weekly100439AdminWinnersPrizeReport", {}).get(
            "singlePanelNoDuplicate"):
        fail("approved manager-winners base missing")
    if not meta.get("googleOriginalUidSettings", {}).get(
            "googleProgressDrivenByVerifiedOperations"):
        fail("Google guardian integration missing")
    if not meta.get("smartSecondStageAccount", {}).get("defaultOff"):
        fail("smart second stage proof missing")
    backend = project / BACKEND
    if not backend.is_file():
        fail("assembled manager gift backend missing")
    original = backend.read_text(encoding="utf-8")
    if ("// DEDA_ADMIN_DIAMONDS_100270" not in original or
            "deda_admin_diamond_wallets" not in original or
            "grantDiamondGift({" not in original):
        fail("approved gift wallet implementation missing")
    current = original
    for label, before, after in [
        ("manager-only admin cap", OLD_CAP, NEW_CAP),
        ("legacy client create unchanged", OLD_CREATE, NEW_CREATE),
        ("server balance strict read", OLD_READ, NEW_READ),
        ("single gift cap retained", OLD_GRANT, NEW_GRANT),
        ("server balance strict debit", OLD_DEBIT, NEW_DEBIT),
    ]:
        current = once(current, before, after, label)
    if current == original or current.count("generalManagerDiamondGiftBudget = 100000000;") != 1:
        fail("admin 100m capacity not staged exactly once")
    backend.write_text(current, encoding="utf-8")
    meta.setdefault("sourceHashes", {})[BACKEND] = digest(backend)
    meta["generalManagerCompensation100m"] = {
        "targetAdminPoolDiamonds": 100000000,
        "serverOnlyAdditionalAllocation": 99000000,
        "existingOneMillionWalletPreserved": True,
        "clientCreatesOnlyLegacyOneMillion": True,
        "singleGiftLimitUnchanged": 1000000,
        "displayOnlyVerifiedServerBalance": True,
        "requiresServerApprovalAndRuleReview": True,
        "personalManagerWalletUnchanged": True,
        "noOtherUserWalletChanged": True,
        "noAutomaticPayouts": True,
        "defaultNotFunded": True,
        "financialRestoreEnabled": False,
        "noFirebaseOrPlayDeploy": True,
        "noApkBuilt": True,
    }
    manifest.write_text(json.dumps(meta, indent=2, ensure_ascii=False) + "\n",
                        encoding="utf-8")
    print("PASS_GM_ADMIN_COMPENSATION_100M_CAPACITY_SAME_ISOLATED_ASSEMBLY")
    print("PASS_NO_CLIENT_MINT_NO_FINANCIAL_RESTORE_NO_BUILD_OR_DEPLOY")


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("project", type=Path)
    bind(p.parse_args().project)
