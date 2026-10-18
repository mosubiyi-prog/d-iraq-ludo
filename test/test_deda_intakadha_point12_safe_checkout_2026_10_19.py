#!/usr/bin/env python3
"""Point12 5000 diamond card checkout: fail-closed account scope regression."""
import ast
import importlib.util
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parent.parent
P7=ROOT/"tools/stage_deda_intakadha_point7_four_cards_id_management_2026_10_18.py"
P12=ROOT/"tools/stage_deda_intakadha_point12_safe_card_checkout_2026_10_19.py"

def load(path,name):
    spec=importlib.util.spec_from_file_location(name,path)
    m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
    return m

def old_var(path,name):
    tree=ast.parse(path.read_text(encoding="utf-8"))
    hits=[s.value.value for s in tree.body if isinstance(s,ast.Assign)
          and any(isinstance(t,ast.Name) and t.id==name for t in s.targets)
          and isinstance(s.value,ast.Constant)]
    assert len(hits)==1
    return hits[0]

class Point12CheckoutTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.mod=load(P12,"point12_checkout")
        cls.widget=old_var(P7,"WIDGET")
        cls.source=(
            "// DEDA_INTAKADHA_POINT11_FOUR_CARDS_LIVE_ID_PREVIEW_2026_10_19\n"
            "// protected source before panel\n"
            +cls.widget+
            "class _DedaAccountInfoPageState extends State<DedaAccountInfoPage> {\n"
            +old_var(P7,"NEW_BUTTON")+"\n}\n"
            +"class DedaDiamondsState {}\n"
            "// protected source after account\n"
        )
        cls.done=cls.mod.apply(cls.source)

    def test_price_confirmation_and_separate_identifier_price(self):
        s=self.mod.HEADER+self.mod.upgraded_widget()
        self.assertIn("static const int priceDiamonds = 5000;",s)
        self.assertIn("تأكيد شراء بطاقة الآيدي",s)
        self.assertIn("مقابل 5,000 ماسة",s)
        self.assertIn("سعر البطاقة منفصل عن سعر المعرّف",s)
        self.assertIn("deda_point12_cancel_purchase",s)
        self.assertIn("deda_point12_confirm_purchase",s)

    def test_checkout_disabled_without_audited_backend_callbacks(self):
        self.assertIn("onPurchaseVerified: null,",self.done)
        self.assertIn("refreshVerifiedOwnership: null,",self.done)
        self.assertIn("serverVerifiedOwnedColors: const <DedaPremiumIdCardColor>{},",self.done)
        self.assertIn("onActivateVerified: null,",self.done)
        self.assertIn("onPressed: canPurchase",self.done)
        self.assertIn("widget.onPurchaseVerified != null",self.done)
        self.assertIn("widget.refreshVerifiedOwnership != null",self.done)

    def test_all_four_styles_have_one_purchase_control_and_price(self):
        s=self.mod.upgraded_widget()
        self.assertIn("for (final style in DedaPremiumIdCardColor.values)",s)
        self.assertIn("'deda_point12_buy_' + style.name",s)
        self.assertIn("شراء بـ5,000 ماسة",s)
        self.assertIn("DedaPremiumIdCard(",s)

    def test_only_backend_receipt_and_refetched_owned_grant_entitlement(self):
        s=self.mod.upgraded_widget()
        for needle in (
            "receipt.serverConfirmed","receipt.transactionId.trim().isEmpty",
            "receipt.color != style","receipt.diamondsCharged != priceDiamonds",
            "receipt.diamondsCharged != 0","!verified.contains(style)",
            "_freshOwned.addAll(verified)",
            "widget.refreshVerifiedOwnership!()", "widget.onPurchaseVerified!(style, requestId)",
        ):
            self.assertIn(needle,s,needle)

    def test_double_tap_busy_guard_and_retries_same_request_key(self):
        s=self.mod.upgraded_widget()
        self.assertIn("if (_purchaseBusy || _freshOwned.contains(style)",s)
        self.assertIn("if (confirmed != true || !mounted || _accountEpoch != openingEpoch || _purchaseBusy",s)
        self.assertIn("_requestIds.putIfAbsent(",s)
        self.assertIn("setState(() => _purchaseBusy = true);",s)
        self.assertIn("setState(() => _purchaseBusy = false);",s)

    def test_stage12_never_mutates_legacy_wallet_inventory_or_purchases(self):
        s=self.mod.upgraded_widget()
        for bad in ("DedaDiamondsWallet.spend(", "DedaStyleInventory.addOwned(",
                    "spendPersonalGiftedDiamonds(", "FirebaseFirestore.instance",
                    "setProfileAppearance(", "SharedPreferences.getInstance("):
            self.assertNotIn(bad,s)
        self.assertEqual(self.done.replace(self.mod.upgraded_widget(),self.widget,1)
                         .replace(self.mod.CALL_NEW,self.mod.CALL_OLD,1),self.source)

    def test_missing_stage11_exact_panel_or_account_guard_fails_closed(self):
        for token in (self.mod.POINT11,self.widget,self.mod.CALL_OLD,
                      "serverVerifiedOwnedColors: const <DedaPremiumIdCardColor>{},"):
            damaged=self.source.replace(token,"BAD_SOURCE",1)
            with self.assertRaisesRegex(ValueError,"SAFE_STOP"):
                self.mod.apply(damaged)

    def test_no_duplicate_purchase_when_rerun_and_modified_state_rejected(self):
        self.assertEqual(self.mod.apply(self.done),self.done)
        bad=self.done.replace("onPurchaseVerified: null,",
                              "onPurchaseVerified: (s, k) async => throw Exception(),",1)
        with self.assertRaisesRegex(ValueError,"SAFE_STOP"):
            self.mod.apply(bad)
        self.assertEqual(self.done.count(self.mod.MARKER),1)

    def test_cross_account_switch_clears_owned_and_ignores_late_receipt(self):
        ui = self.mod.upgraded_widget()
        for token in (
            "void didUpdateWidget(",
            "oldWidget.identifier != widget.identifier",
            "_accountEpoch++;",
            "_freshOwned.clear();",
            "_requestIds.clear();",
            "_accountEpoch != openingEpoch",
            "_accountEpoch == openingEpoch",
        ):
            self.assertIn(token, ui, token)

    def test_previous_use_button_retained_unmodified(self):
        self.assertIn("'deda_intakadha_point7_use_' + style.name",self.done)
        self.assertIn("onTap: () => setState(() => _preview = style)",self.done)
        self.assertIn("onPressed: canUse",self.done)
        self.assertIn("serverVerifiedOwnedColors",self.done)

    def test_cli_uses_disposable_source_file_only(self):
        with tempfile.TemporaryDirectory() as td:
            target=Path(td)/"lib/main.dart";target.parent.mkdir()
            target.write_text(self.source,encoding="utf-8")
            for expected in ("5000-diamond checkout","already present"):
                result=subprocess.run([sys.executable,str(P12)],cwd=td,text=True,
                                      capture_output=True,check=False)
                self.assertEqual(result.returncode,0,result.stderr)
                self.assertIn(expected,result.stdout)
                self.assertEqual(target.read_text(encoding="utf-8"),self.done)

if __name__=="__main__":
    unittest.main()
