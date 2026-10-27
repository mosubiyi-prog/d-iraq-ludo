"""Read-only wallet display consistency on reconstructed real DEDA 100390."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[3]


def module(name):
    path=ROOT/name
    spec=importlib.util.spec_from_file_location(path.stem,path)
    x=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(x)
    return x


class WalletConsistency(unittest.TestCase):
    def test_original100390_shared_diamonds_gold_and_no_wallet_changes(self):
        restore=module("tools/app_stability/tests/test_weekly_stage13_original_signed_candidate.py")
        stage13=module("tools/app_stability/app_package/bind_weekly_stage13.py")
        stage14=module("tools/app_stability/app_package/bind_active_id_boot_prewarm_stage14.py")
        stage15=module("tools/app_stability/app_package/bind_wallet_live_single_source_stage15.py")
        with tempfile.TemporaryDirectory() as work:
            app=Path(work)/"signed-original-100390"
            original=restore.restored(app)
            stage13.bind(app)
            stage14.bind(app)
            protected={
                name:stage15.sha(app/name)
                for name in ("lib/deda_backend.dart",
                             "lib/deda_social_service.dart",
                             "lib/traffic_quiz_page.dart",
                             "lib/deda_unified_currency_totals.dart",
                             "lib/deda_profile_visible_diamonds.dart",
                             "pubspec.yaml","pubspec.lock")
            }
            before=(app/"lib/main.dart").read_text()
            method_start=before.index("class _DedaStylePageState")
            method_end=before.index("\nclass ",method_start+20)
            old_style=before[method_start:method_end]
            self.assertEqual(old_style.count("value: _diamonds,"),1)
            self.assertEqual(old_style.count("progress.coins"),2)
            self.assertNotIn("DedaDiamondsWallet.balanceNotifier.addListener(",old_style)
            cfg=stage15.bind(app)
            full=(app/"lib/main.dart").read_text()
            style=full[full.index("class _DedaStylePageState"):]
            style=style[:style.index("\nclass ",20)]
            self.assertTrue(cfg["styleDiamondNowLive"])
            self.assertTrue(cfg["styleGoldNowLive"])
            self.assertFalse(cfg["walletSpendingChanged"])
            self.assertIn("int get _personalDiamonds => DedaUnifiedCurrencyTotals(",style)
            self.assertIn("DedaDiamondsWallet.balanceNotifier.addListener(",style)
            self.assertIn("generalManagerPersonalNotifier",style)
            self.assertIn("DedaSocialProgressWallet.coinsNotifier",style)
            self.assertIn("WidgetsBinding.instance.addObserver(this);",style)
            self.assertIn("AppLifecycleState.resumed",style)
            self.assertIn("_miniBalanceChip('💎', _personalDiamonds)",style)
            self.assertIn("value: _personalDiamonds,",style)
            self.assertIn("value: _personalGold,",style)
            self.assertIn("_miniBalanceChip('🪙', _personalGold)",style)
            self.assertNotIn("progress.coins",style)
            self.assertNotIn("int _diamonds = 0",style)
            self.assertIn("DedaDiamondsWallet.spend(price);",style)
            self.assertIn("DedaSocialProgressWallet.spendCoins(price);",style)
            self.assertEqual(before[:method_start],full[:method_start])
            self.assertEqual(before[method_end:],full[full.index("\nclass ",full.index("class _DedaStylePageState")+20):])
            for name,digest in protected.items():
                self.assertEqual(stage15.sha(app/name),digest,name)
            for name,digest in original.items():
                if name not in ("lib/main.dart","lib/deda_verified_active_id_store.dart"):
                    self.assertEqual(stage15.sha(app/name),digest,name)
            meta=json.loads((app/"internal-build-inputs.json").read_text())
            self.assertEqual(meta["versionCode"],100390)
            self.assertEqual(meta["package"],"com.diraq.ludo.d_iraq_ludo")
            self.assertIs(meta["financialRestoreEnabled"],False)
            self.assertIs(meta["completeOwnerDelivery"],False)
            self.assertEqual(meta["sourceHashes"]["lib/main.dart"],
                stage15.sha(app/"lib/main.dart"))
            with self.assertRaises(ValueError):
                stage15.bind(app)

    def test_fails_closed_without_stage14_or_inside_repository(self):
        stage15=module("tools/app_stability/app_package/bind_wallet_live_single_source_stage15.py")
        with self.assertRaises(ValueError):
            stage15.bind(ROOT)
        restore=module("tools/app_stability/tests/test_weekly_stage13_original_signed_candidate.py")
        with tempfile.TemporaryDirectory() as work:
            app=Path(work)
            restore.restored(app)
            with self.assertRaises(ValueError):
                stage15.bind(app)


if __name__=="__main__":
    unittest.main()
