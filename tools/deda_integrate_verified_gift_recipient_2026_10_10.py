"""Safe integration of the existing, already tested manager diamond gift page.

Run only AFTER the 100318 golden navigation/manager gift reconstruction,
and AFTER the accepted compact launch admin page is restored.
This migrates the original gift management page into the new dashboard,
enhances only the read-only public identity preview, and does NOT enable
friend transfers or changes to production Firestore rules.
"""
from pathlib import Path

admin_path = Path("lib/admin_pages.dart")
backend_path = Path("lib/deda_backend.dart")
rebuilt_path = Path("/tmp/deda_rebuilt_admin_with_gifts.dart")
assert rebuilt_path.is_file(), "Source gift page was not reconstructed"
admin = admin_path.read_text(encoding="utf-8")
backend = backend_path.read_text(encoding="utf-8")
rebuilt = rebuilt_path.read_text(encoding="utf-8")
marker = "// DEDA_GIFT_RECIPIENT_PUBLIC_PREVIEW_2026_10_10"

if marker in admin:
    raise SystemExit("Gift profile card patch must run only once in each build")
if "class DedaAdminDiamondGiftPage" in admin:
    raise SystemExit("Refuse duplicate gift page")
if rebuilt.count("// DEDA_ADMIN_DIAMOND_GIFT_UI_100270") != 1:
    raise SystemExit("Original 100270 gift page marker missing or duplicated")
if "DEDA_ADMIN_GIFTS_UI_100271" not in rebuilt:
    raise SystemExit("Secure pending-gift flow and immutable ledger missing")

# The generated page consists of two top-level classes. Extract the exact
# complete widget tree without modifying its tested confirmation/sending logic.
start = rebuilt.index("// DEDA_ADMIN_DIAMOND_GIFT_UI_100270")
state = rebuilt.index("class _DedaAdminDiamondGiftPageState", start)
open_brace = rebuilt.index("{", state)
depth = 0
end = None
for i in range(open_brace, len(rebuilt)):
    char = rebuilt[i]
    if char == "{":
        depth += 1
    elif char == "}":
        depth -= 1
        if depth == 0:
            end = i + 1
            break
if end is None or end <= state:
    raise SystemExit("Unable to identify complete gift-state class")
gift_page = rebuilt[start:end]
if gift_page.count("class DedaAdminDiamondGiftPage") != 1 or "grantDiamondGift(" not in gift_page:
    raise SystemExit("Gift page extraction would omit tested transaction")

# In the verified manager's lookup, first require one active PERSONAL DEDA ID,
# then enrich with public non-phone social information if available.
method = "  static Future<Map<String, dynamic>?> adminDiamondGiftTarget("
if backend.count(method) != 1:
    raise SystemExit("Expected exactly one administrative recipient lookup")
start_lookup = backend.index(method)
end_lookup = backend.find("\n  }\n", start_lookup)
if end_lookup < 0:
    raise SystemExit("Cannot find recipient lookup boundary")
old_lookup = backend[start_lookup:end_lookup]
old_result = """    return <String, dynamic>{
      'publicId': publicId,
      'displayName': (data['displayName'] ?? 'DEDA').toString(),
    };"""
new_result = """    // Read only public display fields. No phone, email, ownerUid, or PIN
    // leaves this function. An optional public profile must NOT block
    // legitimate gifting if the social profile does not exist yet.
    Map<String, dynamic>? social;
    try {
      final socialDoc = await FirebaseFirestore.instance
          .collection('deda_social_profiles')
          .doc(publicId)
          .get();
      social = socialDoc.data();
    } catch (_) {
      social = null;
    }
    final publicName = (social?['displayName'] ?? data['displayName'] ?? 'DEDA')
        .toString().trim();
    return <String, dynamic>{
      'publicId': publicId,
      'displayName': publicName.isEmpty ? 'DEDA' : publicName,
      'avatarStyle': social?['avatarStyle'],
      'frameStyle': social?['frameStyle'],
      'backgroundStyle': social?['backgroundStyle'],
      'level': social?['level'],
    };"""
if old_lookup.count(old_result) != 1:
    raise SystemExit("Known safe recipient fields/lookup changed")
backend = backend.replace(old_result, new_result, 1)

# Replace the old generic icon-only mini-panel with the same exact public
# user identity, a framed representation and stable DEDA ID. Its sending
# action remains the 100271 pending/claim + protected admin-pool transaction.
open_target = "                if (_target != null) ...["
target_index = gift_page.find(open_target)
if target_index < 0:
    raise SystemExit("Manager gift target card not found")
card_start = gift_page.find("                  Container(", target_index)
amount = gift_page.find("controller: _amountController,", card_start)
if card_start < 0 or amount < 0:
    raise SystemExit("Gift amount UI card not found")
card_end = gift_page.rfind(
    "                  const SizedBox(height: 10),", card_start, amount)
if card_end <= card_start:
    raise SystemExit("Unable to preserve gift amount field safely")
gift_page = (
    gift_page[:card_start]
    + """                  // DEDA_GIFT_RECIPIENT_PUBLIC_PREVIEW_2026_10_10
                  DedaGiftRecipientPreview(
                    profile: _target!,
                    isArabic: widget.isArabic,
                  ),
"""
    + gift_page[card_end:]
)
if gift_page.count("DedaGiftRecipientPreview(") != 1:
    raise SystemExit("Recipient card insertion not unique")

# Restore the menu entry without changing ANY dashboard permission branches,
# navigation handlers, grid column counts or design styles.
phone_card = """                          onTap: () => _open(
                            DedaAdminEntryPhonesPage(isArabic: ar),
                          ),
                        ),"""
if admin.count(phone_card) != 1:
    raise SystemExit("Approved manager dashboard phones-card anchor changed")
gift_card = """
                      if (DedaBackend.normalizeAdminRole(profile['role']) ==
                          'general_manager')
                        _dashboardCard(
                          icon: Icons.card_giftcard_rounded,
                          accentColor: const Color(0xFF8335C2),
                          backgroundColor: const Color(0xFFF2E7FF),
                          title: t('إرسال الهدايا', 'Send gifts'),
                          subtitle: t(
                            'ماسات للمستخدمين بعد التحقق من المعرف',
                            'Diamonds after recipient ID verification',
                          ),
                          onTap: () => _open(
                            DedaAdminDiamondGiftPage(isArabic: ar),
                          ),
                        ),"""
admin = admin.replace(phone_card, phone_card + gift_card, 1)
if admin.count("import 'deda_gift_recipient_preview.dart';") != 0:
    raise SystemExit("Recipient preview imported unexpectedly already")
import_anchor = "import 'deda_admin_compact_card.dart';"
if admin.count(import_anchor) != 1:
    raise SystemExit("Manager UI import anchor changed")
admin = admin.replace(
    import_anchor,
    import_anchor + "\nimport 'deda_gift_recipient_preview.dart';",
    1,
)
admin += "\n\n" + gift_page + "\n"

# Do not overwrite either file if ANY assertion failed. App's actual wallet
# and proof-of-ownership rules are unchanged.
if admin.count("DedaAdminDiamondGiftPage(isArabic: ar)") != 1:
    raise SystemExit("Missing manager-only gift navigation")
if admin.count("DedaGiftRecipientPreview(") != 1:
    raise SystemExit("Public recipient preview not visible exactly once")
if "crossAxisCount:" not in admin or "mainAxisExtent:" not in admin:
    raise SystemExit("Accepted compact cards unexpectedly lost")
if "DedaSocialProgressWallet.spendCoins" in admin:
    raise SystemExit("Client-local coins cannot fund peer gifts")
admin_path.write_text(admin, encoding="utf-8")
backend_path.write_text(backend, encoding="utf-8")
print("PASS: restored original secure admin diamond gifts with verified public recipient profile")
print("Friends/coins transfers remain DISABLED until server-authoritative ledger and security tests")
