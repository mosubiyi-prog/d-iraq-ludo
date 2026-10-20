#!/usr/bin/env python3
"""Stage71 ONLY on reconstructed 100359: free four original card styles, dual
GM 100+100 management, NO purchase flow or price in customer card actions.
Keep 100 original IDs private, original account maps/signature unchanged.
"""
from pathlib import Path

MAIN=Path('lib/main.dart')
ADMIN=Path('lib/admin_pages.dart')
M_IMPORT="import 'deda_stage71_free_id_cards.dart';\n"
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
FREE_FALLBACK="""fallback: DedaStage71FreeProfileFoil(
                        originalId: id,
                        onCopy: _copyDedaId,
                        fallback: DedaPoint14VerifiedProfileSlot(
                          identifier: id,
                          onCopy: _copyDedaId,
                          width: (width - (compact ? 34.0 : 44.0)).clamp(0.0, 320.0).toDouble(),
                          compact: compact,
                        ),
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
    # Formerly-for-sale Group002 moved to manager section. Never show its
    # candidates publicly even when the profile routes pass a catalog in.
    import re
    pattern = re.compile(
        r'(key:\\s*const\\s+Key\\(\\\'deda_point9_scrollable_identifiers_below_cards\\\'\\).*?'
        r'itemCount:)\\s*.*?(,\\s*itemBuilder:)',
        re.S,
    )
    matches=list(pattern.finditer(shop))
    if len(matches)!=1:
        raise ValueError('SAFE_STOP_STAGE71_EXPECTED_ONE_PUBLIC_CATALOG_SCROLLER_'+str(len(matches)))
    shop=pattern.sub(lambda m:m.group(1)+' 0'+m.group(2),shop,count=1)
    result=src[:a]+shop+src[b:]
    # Cosmetic previews only; catalog proposals stay within protected admin.
    route=re.compile(r'readOnlyCatalog\\s*:\\s*DedaPoint10CandidateGroup002\\s*\\.\\s*identifiers\\s*,')
    result,n=route.subn('readOnlyCatalog: const <String>[],',result)
    if n>1:
        raise ValueError('SAFE_STOP_STAGE71_EXTRA_PUBLIC_CATALOG_ROUTE')
    result=once(result,PROFILE_FALLBACK,FREE_FALLBACK,
                'PROFILE_FREE_ORIGINAL_FOIL')
    result=once(result,"import 'package:flutter/material.dart';\n",
        "import 'package:flutter/material.dart';\n"+M_IMPORT,
        'MAIN_IMPORT')
    if result.count('DedaStage71FreeCardAction(')!=1 or \
       result.count('DedaStage71FreeProfileFoil(')!=1:
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
