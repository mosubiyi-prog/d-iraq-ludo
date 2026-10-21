#!/usr/bin/env python3
"""QA32 receive-location cards display sender's verified ACTIVE alias.

The existing senderPublicId is immutable original routing identity and stays
unchanged inside Firestore & maps. Only the on-screen TEXT for PERSONAL shares
is wrapped with Stage50 owner-authorized public style. Shared places keep their
place ID unchanged. Feature gates remain OFF until user-approved server setup.
"""
from pathlib import Path
import re
MAIN=Path("lib/main.dart")
MARK="// DEDA_QA32_RECEIVED_PERSONAL_LOCATION_VERIFIED_SENDER_ALIAS_NO_DEPLOY"
START="class _DedaReceivedLocationsPageState extends State<DedaReceivedLocationsPage> {"
ANCHOR="Widget _shareCard(Map<String, dynamic> item)"
OLD=re.compile(
    r"Text\(\s*senderId\s*,\s*textDirection:\s*TextDirection\.ltr\s*,"
    r"\s*style:\s*const TextStyle\(\s*color:\s*Color\(0xFF5C635D\)\s*,"
    r"\s*fontWeight:\s*FontWeight\.w700\s*,\s*\)\s*,\s*\)"
)

def apply(source):
    if MARK in source:
        if source.count(MARK)!=1 or \
           source.count("originalId: senderId,")!=1:
            raise ValueError("SAFE_STOP_QA32_RECEIVER_PARTIAL")
        return source
    if source.count(START)!=1 or \
       source.count("DEDA_OWNER19_STAGE50_FRIEND_INK_THREE_PUBLIC_SURFACES_NO_DEPLOY")!=1:
        raise ValueError("SAFE_STOP_QA32_RECEIVER_REQUIRE_STAGE50")
    a=source.index(START)
    section=source[a:]
    if section.count(ANCHOR)!=1:
        raise ValueError("SAFE_STOP_QA32_RECEIVER_SHARE_CARD_COUNT")
    card_start=section.index(ANCHOR)
    segment=section[card_start:card_start+6500]
    matches=list(OLD.finditer(segment))
    if len(matches)!=1:
        raise ValueError("SAFE_STOP_QA32_RECEIVER_ID_TEXT_COUNT_"+str(len(matches)))
    old=matches[0].group()
    replacement="""// DEDA_QA32_RECEIVED_PERSONAL_LOCATION_VERIFIED_SENDER_ALIAS_NO_DEPLOY
                      if (placeShare)
                        """+old+"""
                      else
                        DedaStage50VerifiedFriendInkBadge(
                          originalId: senderId,
                          fallback: """+old+""",
                        )"""
    left=a+card_start+matches[0].start()
    right=a+card_start+matches[0].end()
    if source[left:right]!=old:raise ValueError("SAFE_STOP_QA32_RECEIVER_SOURCE_CHANGED")
    result=source[:left]+replacement+source[right:]
    if result.replace(replacement,old,1)!=source or \
       result.count(MARK)!=1 or \
       result.count("originalId: senderId,")!=1:
        raise ValueError("SAFE_STOP_QA32_RECEIVER_MODIFIED_UNRELATED_SOURCE")
    return result

if __name__=="__main__":
    before=MAIN.read_text()
    updated=apply(before)
    if updated!=before:MAIN.write_text(updated)
    print("PASS_QA32_RECEIVER_PERSONAL_SENDER_ACTIVE_VERIFIED_ALIAS")
    print("PASS_QA32_PLACE_SHARES_AND_ORIGINAL_ROUTE_UNCHANGED")
