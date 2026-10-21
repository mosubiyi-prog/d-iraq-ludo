#!/usr/bin/env python3
"""QA32 share-screen visible identifier follows the authenticated active alias.

Canonical _personalId, _sendShare, recipient routing, GPS data and QR backend
are NOT changed. This is the sender's own visually verified alias only.
Run after the QA32 account header integration and exact app reconstruction.
"""
from pathlib import Path
import re

MAIN = Path("lib/main.dart")
MARK = "// DEDA_QA32_SHARE_SENDER_VERIFIED_ACTIVE_ID_VISUAL_ONLY"
START = "class _DedaShareLocationPageState extends State<DedaShareLocationPage> {"
END = "class DedaReceivedLocationsPage"  # used only if present; fallback next class
PAT = re.compile(
    r"_idCard\(\s*title:\s*dedaText\(\s*'معرفي الشخصي'\s*,"
    r"\s*'My personal ID'\s*,\s*\)\s*,\s*"
    r"id:\s*_personalId\s*,\s*icon:\s*Icons\.person\s*,\s*\)"
)

def apply(source):
    if MARK in source:
        if source.count(MARK)!=1 or \
           source.count("DedaQa32ActiveAccountScope(")!=2:
            raise ValueError("SAFE_STOP_QA32_SHARE_PARTIAL")
        return source
    if source.count(START)!=1 or source.count("DedaQa32ActiveAccountScope(")!=1:
        raise ValueError("SAFE_STOP_QA32_SHARE_REQUIRED_ACCOUNT_STAGE")
    a=source.index(START)
    # Only this class, never other receiver/user cards.
    nxt=re.search(r"\nclass [A-Za-z_][A-Za-z_0-9]*",source[a+len(START):])
    if nxt is None: raise ValueError("SAFE_STOP_QA32_SHARE_CLASS_END")
    b=a+len(START)+nxt.start()
    section=source[a:b]
    matches=list(PAT.finditer(section))
    if len(matches)!=1:raise ValueError("SAFE_STOP_QA32_SHARE_PERSONAL_CARD_AMBIGUOUS")
    old=matches[0].group()
    inserted="""// DEDA_QA32_SHARE_SENDER_VERIFIED_ACTIVE_ID_VISUAL_ONLY
                          DedaQa32ActiveAccountScope(
                            originalId: _personalId,
                            builder: (context, proof) => _idCard(
                              title: dedaText('معرفي الشخصي', 'My personal ID'),
                              id: proof?.isPremium == true
                                  ? proof!.displayId : _personalId,
                              icon: Icons.person,
                            ),
                          )"""
    s=section[:matches[0].start()]+inserted+section[matches[0].end():]
    if s.count("_idCard(")!=section.count("_idCard(") or \
       s.count("DedaQa32ActiveAccountScope(")!=1 or \
       s.count("_personalId")!=section.count("_personalId")+1:
        # _personalId appears inside both originalId and fallback ID;
        # compare exact reverse and inspect change, not guessed counts.
        if s.replace(inserted,old,1)!=section:
            raise ValueError("SAFE_STOP_QA32_SHARE_UNRELATED_MUTATION")
    if s.replace(inserted,old,1)!=section:
        raise ValueError("SAFE_STOP_QA32_SHARE_UNRELATED_MUTATION")
    result=source[:a]+s+source[b:]
    if result.count(MARK)!=1 or result.count("DedaQa32ActiveAccountScope(")!=2:
        raise ValueError("SAFE_STOP_QA32_SHARE_NEW_WRAPPER_NOT_UNIQUE")
    return result

if __name__=="__main__":
    before=MAIN.read_text()
    after=apply(before)
    if before!=after:MAIN.write_text(after)
    print("PASS_QA32_SHARE_PERSONAL_ID_SHOWS_VERIFIED_ACTIVE_ALIAS")
    print("PASS_QA32_CANONICAL_LOCATION_BACKEND_AND_ROUTING_UNCHANGED")
