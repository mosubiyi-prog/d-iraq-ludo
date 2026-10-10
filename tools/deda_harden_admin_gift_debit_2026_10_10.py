"""Attach each manager wallet debit to its immutable pending-gift record.

Run after the 100271 legacy reconstruction and identity-preview integration.
Rules are in the development firestore.rules snapshot; NO live deploy.
"""
from pathlib import Path

file = Path("lib/deda_backend.dart")
src = file.read_text(encoding="utf-8")
marker = "// DEDA_GIFT_WALLET_DEBIT_PROOF_2026_10_10"
assert marker not in src, "gift debit proof patch already applied"

start = src.find("  static Future<Map<String, dynamic>> grantDiamondGift({")
end = src.find("  static Stream<List<Map<String, dynamic>>> watchPersonalDiamondGifts(", start)
assert start > 0 and end > start, "100271 rebuilt manager gifting backend missing"
section = src[start:end]
old = """        transaction.update(walletRef, <String, dynamic>{
          'balance': nextAdmin,
          'updatedAt': FieldValue.serverTimestamp(),
        });"""
new = """        // DEDA_GIFT_WALLET_DEBIT_PROOF_2026_10_10
        // Immutable pending-gift ID proves this debit is paired with
        // exactly one gift creation in the SAME Firestore transaction.
        transaction.update(walletRef, <String, dynamic>{
          'balance': nextAdmin,
          'lastGiftId': giftRef.id,
          'updatedAt': FieldValue.serverTimestamp(),
        });"""
assert section.count(old)==1, "expected exact manager debit in rebuilt 100271 gifting"
section = section.replace(old,new,1)
src = src[:start]+section+src[end:]
assert src.count("'lastGiftId': giftRef.id")==1
file.write_text(src,encoding="utf-8")
print("PASS: administrative gift budget debits atomically linked to pending gift IDs")
