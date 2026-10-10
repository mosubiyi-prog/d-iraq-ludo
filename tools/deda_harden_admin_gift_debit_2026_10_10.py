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

# The gift itself is an immutable Firestore audit record in the very same
# successful transaction. A secondary best-effort administrative audit write
# must NEVER turn an already committed gift into a misleading 'send failed'
# message that could cause the general manager to resend the same diamonds.
secondary_audit = """    await _writeAdminAudit(
      'diamond_gift_created',
      details: <String, dynamic>{
        'giftId': result['giftId'],
        'targetPublicId': publicId,
        'targetName': targetName,
        'amount': amount,
        'reason': cleanReason,
        'status': 'pending',
        'adminBalanceAfter': result['adminBalance'],
      },
    );
    return result;"""
safe_audit = """    // The gift entry is already durably committed and visible in manager
    // history. Do not report 'send failed' when optional secondary audit is
    // interrupted after the gift was actually created.
    try {
      await _writeAdminAudit(
        'diamond_gift_created',
        details: <String, dynamic>{
          'giftId': result['giftId'],
          'targetPublicId': publicId,
          'targetName': targetName,
          'amount': amount,
          'reason': cleanReason,
          'status': 'pending',
          'adminBalanceAfter': result['adminBalance'],
        },
      );
    } catch (_) {
      // Core atomic gift creation remains valid in deda_diamond_gifts.
    }
    return result;"""
assert section.count(secondary_audit)==1, "secondary audit scope changed"
section = section.replace(secondary_audit,safe_audit,1)

src = src[:start]+section+src[end:]
assert src.count("'lastGiftId': giftRef.id")==1
assert src.count("Core atomic gift creation remains valid")==1
file.write_text(src,encoding="utf-8")
print("PASS: administrative gift budget debits atomically linked to pending gift IDs")
