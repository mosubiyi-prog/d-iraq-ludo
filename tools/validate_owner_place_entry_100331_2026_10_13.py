"""100331 UI-only regression guards after the full golden app rebuild."""
from pathlib import Path

code = Path("lib/main.dart").read_text(encoding="utf-8")
profile = code[
    code.index("class _DedaProfilePhase2PageState extends State<DedaProfilePhase2Page> {"):
    code.index("class DedaPublicProfilePreviewPage")
]
account = code[
    code.index("class _DedaAccountInfoPageState extends State<DedaAccountInfoPage> {"):
    code.index("class DedaAccountHubPage")
]
owner = code[
    code.index("class OwnerPlacePage extends StatefulWidget"):
    code.index("class PersonalPlacesPage", code.index("class OwnerPlacePage extends StatefulWidget"))
]

assert profile.count("// DEDA_OWNER_PLACE_ENTRY_100331") == 1
assert profile.count("if (_accountType == DedaAccountType.placeOwner)") == 1
assert profile.count("_ownerPlaceCard(),") == 1
assert profile.count("Widget _ownerPlaceCard()") == 1
assert profile.count("const OwnerPlacePage()") == 1
assert profile.index("_statsRow(),") < profile.index("_ownerPlaceCard(),")
assert profile.index("_ownerPlaceCard(),") < profile.index("_featureGrid(),")

assert account.count("if (type == DedaAccountType.placeOwner)") == 1
assert account.count("الانتقال إلى إدارة مكاني") == 1
assert account.count("const OwnerPlacePage()") == 1
assert "await DedaPreferences.setAccountType(type);" in account
assert "if (mounted) setState(() {});" in account

# All owner workflows continue to use the existing owner screen and backend.
for needle in (
    "DedaBackend.resubmitPlaceRequest(",
    "DedaBackend.ownerPlaceNotificationsStream(",
    "DedaBackend.ownerPlaceDeletionRequestForPlace(",
    "_draftKeyBase",
    "_placeIdKeyBase",
    "تعديل المكان",
    "إرسال الطلب للمراجعة",
):
    assert needle in owner, "Owner workflow missing: " + needle

print("PASS: profile card appears only for place owners, immediately after stats.")
print("PASS: account information shortcut follows the selected account type.")
print("PASS: original owner-place page, requests, drafts and notifications retained.")
print("NOTE: device interaction tests still required before production release.")
