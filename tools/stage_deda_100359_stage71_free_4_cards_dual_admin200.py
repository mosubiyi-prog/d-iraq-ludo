#!/usr/bin/env python3
"""Stage71 ONLY on reconstructed 100359: free four original card styles, dual
GM 100+100 management, NO purchase flow or price in customer card actions.
Keep 100 original IDs private, original account maps/signature unchanged.
"""
from pathlib import Path

MAIN=Path('lib/main.dart')
ADMIN=Path('lib/admin_pages.dart')
M_IMPORT="import 'deda_stage71_free_id_cards.dart';\n"
OWNED_IMPORT="import 'deda_stage71_free_owned_use_profile.dart';\n"
A_IMPORT="import 'deda_stage71_dual_admin_page.dart';\n"
MARK="// DEDA_STAGE71_OWNER_APPROVED_FOUR_FREE_CARDS_TWO_ADMIN100_NO_PURCHASE"
S_BEGIN="class _DedaIdentifierStorePageState extends State<DedaIdentifierStorePage> {"
S_END="class _DedaProfilePhase2PageState extends State<DedaProfilePhase2Page> {"
SHOP_ACTION="""child: DedaPoint17ShopCardAction(
                  identifier: widget.identifier,
                  color: color,
                ),"""
FREE_ACTION="""child: DedaStage71FreeCardAction(
                  originalId: DedaBackend.personalShareIdForPhone(
                    DedaPreferences.phone,
                  ).trim(),
                  color: color,
                ),"""
PROFILE_FALLBACK="""fallback: DedaPoint14VerifiedProfileSlot(
                        identifier: id,
                        onCopy: _copyDedaId,
                        width: (width - (compact ? 34.0 : 44.0)).clamp(0.0, 320.0).toDouble(),
                        compact: compact,
                      ),"""
FREE_FALLBACK="""fallback: DedaStage71ActiveProfileFoil(
                        originalId: id,
                        fallback: DedaStage71FreeProfileFoil(
                        originalId: id,
                        onCopy: _copyDedaId,
                        fallback: DedaPoint14VerifiedProfileSlot(
                          identifier: id,
                          onCopy: _copyDedaId,
                          width: (width - (compact ? 34.0 : 44.0)).clamp(0.0, 320.0).toDouble(),
                          compact: compact,
                        ),
                        ),
                      ),"""

ORIGINAL_OWNED_PANEL="""            DedaPoint15OwnedIdentifierPanel(
              originalId: DedaBackend.personalShareIdForPhone(
                DedaPreferences.phone,
              ).trim(),
            ),"""
NEW_OWNED_PANEL="""            DedaStage71OwnedIdsPanel(
              originalId: DedaBackend.personalShareIdForPhone(
                DedaPreferences.phone,
              ).trim(),
            ),"""

def once(s, a, b, label):
    n=s.count(a)
    if n!=1: raise ValueError('SAFE_STOP_STAGE71_'+label+'_'+str(n))
    return s.replace(a,b,1)

def patch_main(src:str)->str:
    if MARK in src:
        if src.count(MARK)!=1 or src.count(M_IMPORT)!=1 or FREE_ACTION not in src:
            raise ValueError('SAFE_STOP_STAGE71_PARTIAL_MAIN')
        return src
    if src.count(S_BEGIN)!=1 or src.count(S_END)!=1:
        raise ValueError('SAFE_STOP_STAGE71_STORE_BOUNDS')
    a,b=src.index(S_BEGIN),src.index(S_END)
    shop=src[a:b]
    if shop.count('DedaPremiumIdCard(')!=1 or shop.count(SHOP_ACTION)!=1:
        raise ValueError('SAFE_STOP_STAGE71_REAL_FOUR_FOILS_NOT_FOUND')
    shop=once(shop,SHOP_ACTION,FREE_ACTION,'FOUR_FREE_CARD_ACTION')
    shop=once(shop,"'تصميم البطاقة: 5,000 ماسة'",
              "'تصميم البطاقة: مجاني'",'AR_CARD_PRICE')
    # No paid Group002 branch can ever reopen from an old dart-define.
    # The store is now FREE cards only; selection never spends diamonds.
    shop=once(shop,'child: const bool.fromEnvironment(',
              'child: false && const bool.fromEnvironment(',
              'DISABLE_OLD_GROUP002_SALE_EVEN_IF_FLAG_ON')
    for old, new in (
      ('Card design: 5,000 diamonds','Card design: Free'),
      ('المعاينة مجانية، وثمن التصميم منفصل عن ثمن المعرّف.',
       'التصاميم الأربعة مجانية ومتاحة للاستخدام.'),
      ('Preview is free; the card and identifier have separate prices.',
       'All four card designs are free to use.'),
      ('متجر المعرّفات','البطاقات المجانية'),
      ('Identifier store','Free ID cards'),
    ):
        shop=shop.replace(old,new)
    # Formerly-for-sale Group002 moved to manager section. Never show its
    # candidates publicly even when the profile routes pass a catalog in.
    import re
    # Exactly one candidate list widget exists in the approved store. The
    # former-sale catalog belongs in Admin now; zero visible public rows.
    if shop.count('ListView.builder(')!=1 or shop.count('itemCount:')!=1:
        raise ValueError('SAFE_STOP_STAGE71_GROUP002_LIST_COUNT')
    first=shop.index('ListView.builder(')
    count=shop.index('itemCount:',first)
    builder=shop.index('itemBuilder:',count)
    comma=shop.rfind(',',count,builder)
    if comma < count or 'DedaPoint10CandidateGroup002.identifiers' in shop[count:comma]:
        # The source may reference an old immutable candidate list, but the
        # hidden list must still be fully isolated from all other widgets.
        pass
    if comma < count or not shop[comma+1:builder].strip()=='':
        raise ValueError('SAFE_STOP_STAGE71_UNKNOWN_PUBLIC_LIST_STRUCTURE')
    shop=shop[:count]+'itemCount: 0,'+shop[comma+1:]
    result=src[:a]+shop+src[b:]
    # Cosmetic previews only; catalog proposals stay within protected admin.
    route=re.compile(r'readOnlyCatalog\s*:\s*DedaPoint10CandidateGroup002\s*\.\s*identifiers\s*,')
    result,n=route.subn('readOnlyCatalog: const <String>[],',result)
    if n>1:
        raise ValueError('SAFE_STOP_STAGE71_EXTRA_PUBLIC_CATALOG_ROUTE')
    result=once(result,PROFILE_FALLBACK,FREE_FALLBACK,
                'PROFILE_FREE_ORIGINAL_FOIL')
    result=once(result,ORIGINAL_OWNED_PANEL,NEW_OWNED_PANEL,
                'OWNED_IDS_GIFT_AND_USE')

    result=once(result,"import 'package:flutter/material.dart';\n",
        "import 'package:flutter/material.dart';\n"+M_IMPORT+OWNED_IMPORT,
        'MAIN_IMPORT')
    if result.count('DedaStage71FreeCardAction(')!=1 or \
       result.count('DedaStage71FreeProfileFoil(')!=1 or \
       result.count('DedaStage71ActiveProfileFoil(')!=1 or \
       result.count('DedaStage71OwnedIdsPanel(')!=1:
        raise ValueError('SAFE_STOP_STAGE71_MISSING_FREE_ACTION')
    return result.replace('class DedaPoint17ShopCardAction',
        'class DedaPoint17ShopCardAction',1).replace(
        S_BEGIN, "  "+MARK+"\n"+S_BEGIN,1)

def patch_admin(src:str)->str:
    if A_IMPORT in src:
        if src.count(A_IMPORT)!=1 or 'DedaStage71DualAdminPage(isArabic: ar)' not in src:
            raise ValueError('SAFE_STOP_STAGE71_PARTIAL_ADMIN_ROUTE')
        return src
    src=once(src,"import 'deda_exclusive_ids_admin_page.dart';\n",
        "import 'deda_exclusive_ids_admin_page.dart';\n"+A_IMPORT,
        'ADMIN_IMPORT')
    return once(src,'DedaExclusiveIdsAdminPage(isArabic: ar)',
                'DedaStage71DualAdminPage(isArabic: ar)',
                'ADMIN200_DUAL_COLUMN_ROUTE')

if __name__=='__main__':
    old=MAIN.read_text()
    new=patch_main(old)
    if new!=old: MAIN.write_text(new)
    adm=ADMIN.read_text()
    update=patch_admin(adm)
    if update!=adm: ADMIN.write_text(update)
    print('PASS stage71: four original REAL ID artworks FREE and selectable; no diamond spend')
    print('PASS stage71: original profile ID uses saved FREE foil; original copy preserved')
    print('PASS stage71: original 100 + former-sale 100 routed GM-only as two-column manager UI')
    print('PASS stage71: no production wallet, original 100 secret, Play or Firebase mutation')
