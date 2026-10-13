"""DEDA 100331 — restore the existing place-owner entry, UI only.

Run AFTER the accepted 100330 golden app is reconstructed. This does not
change OwnerPlacePage, Firestore, place requests, account storage or permissions.
"""
from pathlib import Path

path = Path("lib/main.dart")
source = path.read_text(encoding="utf-8")
marker = "// DEDA_OWNER_PLACE_ENTRY_100331"

if marker in source:
    print("Owner place entry already restored.")
    raise SystemExit(0)

profile_start = source.index(
    "class _DedaProfilePhase2PageState extends State<DedaProfilePhase2Page> {"
)
profile_end = source.index("class DedaPublicProfilePreviewPage", profile_start)
profile = source[profile_start:profile_end]

old_position = """          _statsRow(),
          const SizedBox(height: 8),
          ValueListenableBuilder<int>("""
new_position = """          _statsRow(),
          const SizedBox(height: 8),
          if (_accountType == DedaAccountType.placeOwner) ...<Widget>[
            _ownerPlaceCard(),
            const SizedBox(height: 8),
          ],
          ValueListenableBuilder<int>("""
if profile.count(old_position) != 1:
    raise SystemExit("STOP: approved 100330 profile layout anchor changed.")
profile = profile.replace(old_position, new_position, 1)

method_anchor = "  Widget _featureGrid() {"
owner_card = """  // DEDA_OWNER_PLACE_ENTRY_100331: visibility only; reuse original owner screen.
  Widget _ownerPlaceCard() {
    return Semantics(
      button: true,
      label: dedaText('إدارة مكاني', 'Manage my place'),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        child: Ink(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: <Color>[
                Color(0xFF087650),
                Color(0xFF075539),
              ],
              begin: AlignmentDirectional.topStart,
              end: AlignmentDirectional.bottomEnd,
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFE7C46C), width: 1.5),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x300B5E47),
                blurRadius: 13,
                offset: Offset(0, 5),
              ),
            ],
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const OwnerPlacePage()),
              );
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
              child: Row(
                textDirection: DedaLanguageState.direction,
                children: <Widget>[
                  Container(
                    width: 52,
                    height: 52,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFDEBF71)),
                    ),
                    child: const Icon(
                      Icons.storefront_outlined,
                      color: Color(0xFFFFE29C),
                      size: 29,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          dedaText('إدارة مكاني', 'Manage my place'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          dedaText(
                            'أضف مكانك وتابع طلباتك وتعديلاته',
                            'Add your place and follow requests and edits',
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFE5F4ED),
                            fontSize: 13.5,
                            height: 1.3,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.chevron_left_rounded,
                    color: Color(0xFFFFE29C),
                    size: 26,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

"""
if profile.count(method_anchor) != 1:
    raise SystemExit("STOP: owner card insertion anchor missing.")
profile = profile.replace(method_anchor, owner_card + method_anchor, 1)

# Account information: show the optional one-tap route immediately on switch.
info_start = source.index("class _DedaAccountInfoPageState extends State<DedaAccountInfoPage> {")
info_end = source.index("class DedaAccountHubPage", info_start)
info = source[info_start:info_end]
segment_tail = """                    onSelectionChanged: (selection) {
                      if (selection.isNotEmpty) {
                        _setType(selection.first);
                      }
                    },
                  ),"""
owner_shortcut = """                    onSelectionChanged: (selection) {
                      if (selection.isNotEmpty) {
                        _setType(selection.first);
                      }
                    },
                  ),
                  if (type == DedaAccountType.placeOwner) ...<Widget>[
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const OwnerPlacePage(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.storefront_outlined),
                      label: Text(
                        dedaText(
                          'الانتقال إلى إدارة مكاني',
                          'Open Manage my place',
                        ),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF086847),
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(52),
                      ),
                    ),
                  ],"""
if info.count(segment_tail) != 1:
    raise SystemExit("STOP: account-type toggle anchor changed.")
info = info.replace(segment_tail, owner_shortcut, 1)

new_source = source[:info_start] + info + source[info_end:profile_start] + profile + source[profile_end:]
if new_source.count(marker) != 1:
    raise SystemExit("STOP: repeated owner entry marker.")
if new_source.count("class OwnerPlacePage extends StatefulWidget") != 1:
    raise SystemExit("STOP: original owner screen unexpectedly changed.")
for phrase in (
    "DedaBackend.resubmitPlaceRequest(",
    "DedaBackend.ownerPlaceNotificationsStream(",
    "DedaBackend.ownerPlaceDeletionRequestForPlace(",
):
    if source.count(phrase) != new_source.count(phrase):
        raise SystemExit("STOP: original owner place logic changed: " + phrase)

path.write_text(new_source, encoding="utf-8")
print("PASS: restored owner-only green/gold card and account info shortcut.")
