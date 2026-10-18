#!/usr/bin/env python3
"""Stage 9 of 16: open read-only ID store, four fixed 50dp cards above a scroller.

Apply on approved reconstructed 100356 Flutter main.dart AFTER point8.
Do not list fake IDs or enable purchase/activation. Stage10 populates validated
catalog. Stage11 adds ID selection preview. No change to wallet/Firebase data.
"""
from pathlib import Path

MAIN = Path("lib/main.dart")
PROFILE = "class _DedaProfilePhase2PageState extends State<DedaProfilePhase2Page> {"
PROFILE_END = "class DedaPublicProfilePreviewPage"
GRID = "  Widget _featureGrid() {"
CARD = "  Widget _featureCard({"
MARKER = "// DEDA_INTAKADHA_POINT9_STICKY_FOUR_ID_CARDS_STORE_2026_10_18"
POINT8 = "// DEDA_INTAKADHA_POINT8_PHOTOS_TILE_BECOMES_ID_SHOP_2026_10_18"
POINT5 = "// DEDA_INTAKADHA_POINT5_FOUR_PREMIUM_ID_ARTWORKS_2026_10_18"
OLD_TAP = "                onTap: () => _showPhase2Notice(\n                  'متجر المعرّفات قيد التجهيز. التصفح والشراء يتفعّلان بعد إكمال المتجر والتحقق من الملكية.',\n                  'The identifier store is being prepared. Browsing and purchases will open after the store and ownership checks are ready.',\n                ),"
NEW_TAP = "                onTap: () {\n                  final activeId = _dedaId;\n                  Navigator.push<void>(\n                    context,\n                    MaterialPageRoute<void>(\n                      builder: (_) => DedaIdentifierStorePage(\n                        identifier: activeId.isEmpty ? '@DEDA' : activeId,\n                      ),\n                    ),\n                  );\n                },"
PAGE = r'''// DEDA_INTAKADHA_POINT9_STICKY_FOUR_ID_CARDS_STORE_2026_10_18
// No fake stock, no ownership assertions, and no purchase/activation mutations.
// Stage10 may provide validated read-only catalog entries; stage11 handles
// actual selection logic. The profile and actual ID always remain unchanged.
class DedaIdentifierStorePage extends StatelessWidget {
  final String identifier;
  final List<String> readOnlyCatalog;

  const DedaIdentifierStorePage({
    super.key,
    required this.identifier,
    this.readOnlyCatalog = const <String>[],
  });

  String _cardName(DedaPremiumIdCardColor color) {
    switch (color) {
      case DedaPremiumIdCardColor.gold:
        return dedaText('ذهبي', 'Gold');
      case DedaPremiumIdCardColor.diamond:
        return dedaText('ماسي', 'Diamond');
      case DedaPremiumIdCardColor.royal:
        return dedaText('ملكي', 'Royal');
      case DedaPremiumIdCardColor.pink:
        return dedaText('وردي', 'Pink');
    }
  }

  Widget _fixedCard(DedaPremiumIdCardColor color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          DedaPremiumIdCard(
            key: ValueKey<String>('deda_point9_fixed_' + color.name),
            identifier: identifier,
            color: color,
            height: 50,
            // Free viewing only, no onTap ownership or purchase action.
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(
                _cardName(color),
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF563976),
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerEnd,
                  child: Text(
                    dedaText('تصميم البطاقة: 5,000 ماسة', 'Card design: 5,000 diamonds'),
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF654C7B),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // The cards are intentionally OUTSIDE the scrolling ListView.
    // On small devices show full-width 50dp rows, never two tiny
    // 140dp ID plates with unreadable identifiers.
    return Scaffold(
      key: const Key('deda_point9_identifier_store_page'),
      backgroundColor: const Color(0xFFF8FAF2),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A477E),
        foregroundColor: Colors.white,
        title: Text(dedaText('متجر المعرّفات', 'Identifier store')),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Container(
                key: const Key('deda_point9_fixed_four_cards'),
                padding: const EdgeInsets.fromLTRB(7, 8, 7, 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBF1),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: const Color(0xFFE0CC9B)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      dedaText(
                        'شاهد الآيدي بأربعة تصاميم',
                        'Preview the ID in four designs',
                      ),
                      style: const TextStyle(
                        color: Color(0xFF603E78),
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 5),
                    for (final style in DedaPremiumIdCardColor.values)
                      _fixedCard(style),
                    Text(
                      dedaText(
                        'المعاينة مجانية، وثمن التصميم منفصل عن ثمن المعرّف.',
                        'Preview is free; the card and identifier have separate prices.',
                      ),
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFF715779),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 7),
              Expanded(
                child: ListView.builder(
                  key: const Key('deda_point9_scrollable_identifiers_below_cards'),
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: readOnlyCatalog.isEmpty
                      ? 2
                      : readOnlyCatalog.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          dedaText(
                            'المعرّفات المعروضة للبيع',
                            'Identifiers offered for sale',
                          ),
                          style: const TextStyle(
                            color: Color(0xFF183D5E),
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                      );
                    }
                    if (readOnlyCatalog.isEmpty) {
                      return Padding(
                        key: const Key('deda_point9_catalog_not_yet_loaded'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 28,
                        ),
                        child: Column(
                          children: <Widget>[
                            const Icon(
                              Icons.inventory_2_outlined,
                              size: 36,
                              color: Color(0xFF827297),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              dedaText(
                                'قائمة المعرّفات قيد التجهيز، ولا توجد معرّفات متاحة للشراء الآن.',
                                'The identifier catalog is being prepared. No IDs are for sale yet.',
                              ),
                              style: const TextStyle(
                                color: Color(0xFF5C6576),
                                fontSize: 12,
                                height: 1.5,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      );
                    }
                    final candidate = readOnlyCatalog[index - 1];
                    return Card(
                      key: ValueKey<String>('deda_point9_readonly_' + candidate),
                      margin: const EdgeInsets.only(bottom: 7),
                      child: ListTile(
                        title: Text(
                          candidate,
                          textDirection: TextDirection.ltr,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(
                          dedaText(
                            'عرض فقط — الشراء والتفعيل غير متاحين',
                            'Preview only — purchases and activation are disabled',
                          ),
                        ),
                        leading: const Icon(Icons.badge_outlined),
                        // No onTap. Point 11 will add a guarded selection.
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

'''

def apply(source: str) -> str:
    if source.count(PROFILE) != 1 or source.count(PROFILE_END) != 1:
        raise ValueError("SAFE_STOP: profile page not at exact rebuilt source boundary")
    for marker in (POINT5, POINT8):
        if source.count(marker) != 1:
            raise ValueError("SAFE_STOP: earlier stage missing or duplicated: " + marker)
    a = source.index(PROFILE)
    b = source.index(PROFILE_END, a)
    profile = source[a:b]
    if profile.count(GRID) != 1 or profile.count(CARD) != 1:
        raise ValueError("SAFE_STOP: original feature grid boundaries changed")
    grid_start = profile.index(GRID)
    grid_end = profile.index(CARD, grid_start)
    grid = profile[grid_start:grid_end]
    if MARKER in source:
        if source.count(MARKER) != 1 or PAGE not in source:
            raise ValueError("SAFE_STOP: partial page definition from stage9")
        if grid.count(NEW_TAP) != 1 or grid.count(OLD_TAP) != 0:
            raise ValueError("SAFE_STOP: stage9 store-navigation path changed")
        return source
    if "class DedaIdentifierStorePage extends" in source:
        raise ValueError("SAFE_STOP: conflicting store-page implementation present")
    if grid.count(OLD_TAP) != 1:
        raise ValueError("SAFE_STOP: exactly one coming-soon tap required in purple store tile")
    if grid.count("title: dedaText('متجر المعرّفات', 'Identifier store')") != 1:
        raise ValueError("SAFE_STOP: stage8 tile title lost")
    if grid.count("compactContent: true,") != 1:
        raise ValueError("SAFE_STOP: stage8 same-size tile design missing")
    updated_grid = grid.replace(OLD_TAP, NEW_TAP, 1)
    if updated_grid.replace(NEW_TAP, OLD_TAP, 1) != grid:
        raise ValueError("SAFE_STOP: changed fields besides tap callback")
    updated_profile = profile[:grid_start] + updated_grid + profile[grid_end:]
    updated_source = source[:a] + updated_profile + source[b:]
    updated_source = updated_source.replace(PROFILE, PAGE + PROFILE, 1)
    if updated_source.replace(PAGE, "", 1).replace(NEW_TAP, OLD_TAP, 1) != source:
        raise ValueError("SAFE_STOP: unauthorized change outside store page/one tap")
    return updated_source

if __name__ == "__main__":
    if not MAIN.is_file():
        raise SystemExit("SAFE_STOP: reconstructed lib/main.dart unavailable")
    previous = MAIN.read_text(encoding="utf-8")
    try:
        new = apply(previous)
    except ValueError as exc:
        raise SystemExit(str(exc))
    if new != previous:
        MAIN.write_text(new, encoding="utf-8")
        print("PASS: store tile navigates to a new read-only page with four fixed ID cards")
    else:
        print("PASS: stage9 already applied")
    print("PASS: list below scrolls independently; no fake sale stock or purchasing/activation")
