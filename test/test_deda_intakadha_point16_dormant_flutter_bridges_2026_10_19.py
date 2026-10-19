#!/usr/bin/env python3
import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
def load(file, alias):
    spec=importlib.util.spec_from_file_location(alias,ROOT/"tools"/file)
    module=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

phone=load("stage_deda_intakadha_point16_authenticated_flutter_calls_2026_10_19.py","p16_client")
social=load("stage_deda_intakadha_point16_friend_alias_lookup_2026_10_19.py","p16_alias")

def phone_fixture():
    return (
      phone.IMPORT +
      "// DEDA_INTAKADHA_POINT14_SERVER_VERIFIED_CARD_USE_2026_10_19\n"+
      "// DEDA_INTAKADHA_POINT15_SERVER_VERIFIED_OWNED_IDENTIFIERS_2026_10_19\n"+
      "class DedaPoint14VerifiedBridge {}\n"+
      "class DedaPoint15OwnedIdsBridge {}\n"+
      "class DedaPremiumIdCardsManagementPanel {}\n"+
      "class DedaPoint14VerifiedProfileSlot {\n"+phone.PROFILE_INIT+"\n}\n"+
      "class DedaPoint14VerifiedAccountPanel {\n"+phone.PROFILE_INIT+"\n"+
      phone.OLD_PAYMENTS+"\n}\n"+
      "class DedaPoint15OwnedIdentifierPanel {\n"+phone.OWNED_INIT+"\n}\n"+
      phone.ACCOUNT+"\n"
    )
class Point16Bridges(unittest.TestCase):
    def test_private_phone_100356_transport_additions_are_exact_reversible(self):
        old=phone_fixture()
        after=phone.apply(old)
        self.assertEqual(after.count(phone.MARKER),1)
        self.assertEqual(after.count(phone.PROFILE_INIT_NEW),2)
        self.assertEqual(after.count(phone.OWNED_INIT_NEW),1)
        self.assertEqual(after.count(phone.NEW_PAYMENTS),1)
        self.assertEqual(phone.apply(after),after)
    def test_phone_transport_default_off_and_requires_appcheck_setup(self):
        self.assertIn("'DEDA_PREMIUM_IDS_SERVER_LIVE'",phone.GATEWAY)
        self.assertIn("defaultValue: false",phone.GATEWAY)
        self.assertIn("FirebaseAuth.instance.currentUser?.uid",phone.GATEWAY)
        self.assertIn("dedaPremiumBuyCard",phone.GATEWAY)
        self.assertIn("dedaPremiumReadCards",phone.GATEWAY)
        self.assertIn("dedaPremiumReadIdentifiers",phone.GATEWAY)
        self.assertIn("dedaPremiumActivateIdentifier",phone.GATEWAY)
        self.assertIn("DedaPoint15OwnedIdsBridge.grantReservedRemote = null",phone.GATEWAY)
        self.assertIn("charged != 5000",phone.GATEWAY)
        self.assertNotIn("DedaDiamondsWallet.spend",phone.GATEWAY)
        self.assertNotIn("deda_diamond_gift_balances",phone.GATEWAY)
    def test_phone_partial_source_stops(self):
        with self.assertRaisesRegex(ValueError,"SAFE_STOP"):
            phone.apply(phone_fixture().replace(phone.OLD_PAYMENTS,"",1))
        with self.assertRaisesRegex(ValueError,"SAFE_STOP"):
            phone.apply(phone_fixture().replace("POINT14","POINT99",1))
    def test_phone_imports_added_just_once(self):
        full=phone.apply(phone_fixture())
        self.assertEqual(full.count(phone.MORE_IMPORTS),1)
        self.assertEqual(full.count("FirebaseFunctions.instance"),1)
    def test_readonly_social_alias_apply_real_checkedin_file(self):
        original=(ROOT/"lib/deda_social_service.dart").read_text(encoding="utf8")
        changed=social.apply(original)
        self.assertEqual(changed.count(social.MARKER),1)
        self.assertEqual(social.apply(changed),changed)
        restored=changed.replace(social.ALIAS,"",1).replace(
            social.NEW_LOOKUP,social.OLD_LOOKUP,1).replace(
            social.LOOKS_NEW,social.LOOKS_OLD,1).replace(
            social.IMPORT+social.NEW_IMPORT,social.IMPORT,1)
        self.assertEqual(restored,original)
    def test_friends_original_uids_safe_no_permission_to_location(self):
        self.assertIn("defaultValue: false",social.ALIAS)
        self.assertIn("final requester = FirebaseAuth.instance.currentUser?.uid",social.ALIAS)
        self.assertIn("dedaPremiumResolveAlias",social.ALIAS)
        self.assertIn("var publicId = requestedId;",social.NEW_LOOKUP)
        self.assertIn("directoryData['kind'] != 'personal'",social.NEW_LOOKUP)
        self.assertNotIn("createLocationShare",social.ALIAS)
        self.assertNotIn("deda_owned_identifier_registry",social.ALIAS)
    def test_no_activation_of_unverified_readonly_lookup(self):
        with self.assertRaisesRegex(ValueError,"SAFE_STOP"):
            social.apply((ROOT/"lib/deda_social_service.dart").read_text().replace(
                social.OLD_LOOKUP, "", 1))
    def test_four_to_twelve_char_support_without_original_account_id_mutation(self):
        self.assertIn("{4,12}",social.LOOKS_NEW)
        self.assertIn("{6}",social.ALIAS)
        self.assertIn("publicId = canonical",social.NEW_LOOKUP)
        self.assertIn("doc(publicId).get()",social.NEW_LOOKUP)
    def test_original_gm_grant_and_purchase_not_exported(self):
        index=(ROOT/"functions/index.js").read_text()
        self.assertNotIn("dedaPremiumAdminGrantReserved",index)
        self.assertNotIn("dedaPremiumBuyCard",index)

if __name__=="__main__": unittest.main()
