#!/usr/bin/env python3
"""QA32: friend PUBLIC profile displays the exact owner's full premium foil.

Stage after Stage50 ink wrappers on fully reconstructed 100359. Only the one
public preview of an ACTIVE server verified ID is promoted to DedaPremiumIdCard;
compact friend/search rows stay small; all account/auth/contacts/QR unchanged.
Feature remains OFF until independently authorized public-read backend.
"""
from pathlib import Path
import re

MAIN = Path("lib/main.dart")
MARKER = "// DEDA_QA32_FRIEND_PUBLIC_FULL_VERIFIED_ID_FOIL_NO_DEPLOY"
START = "class DedaFriendPublicProfilePage extends StatelessWidget {"
INJECTED = """premiumCardBuilder: (verified) => FittedBox(
                        fit: BoxFit.scaleDown,
                        child: SizedBox(
                          width: 248,
                          child: DedaPremiumIdCard(
                            identifier: verified.displayId,
                            color: DedaPremiumIdCardColor.values.firstWhere(
                              (choice) => choice.name == verified.permanentColor,
                            ),
                            height: 50,
                          ),
                        ),
                      ),
                      """

def apply(source: str) -> str:
    if MARKER in source:
        if source.count(MARKER) != 1 or source.count(INJECTED) != 1:
            raise ValueError("SAFE_STOP_QA32_PUBLIC_CARD_PARTIAL_APPLY")
        return source
    if source.count(START) != 1 or \
       source.count("DEDA_OWNER19_STAGE50_FRIEND_INK_THREE_PUBLIC_SURFACES_NO_DEPLOY") != 1:
        raise ValueError("SAFE_STOP_QA32_FRIEND_SOURCE_PREREQUISITES")
    at=source.index(START)
    scope=source[at:]
    expression=re.compile(
        r"DedaStage50VerifiedFriendInkBadge\(\s*"
        r"originalId:\s*profile\.publicId,\s*fallback:\s*"
    )
    matches=list(expression.finditer(scope))
    if len(matches)!=1:
        raise ValueError("SAFE_STOP_QA32_PUBLIC_ID_BADGE_WRAPPER_COUNT="+str(len(matches)))
    match=matches[0]
    old=match.group()
    new=old.replace("fallback:",INJECTED+"fallback:",1)
    if old.count("fallback:")!=1 or new.count("premiumCardBuilder:")!=1:
        raise ValueError("SAFE_STOP_QA32_PUBLIC_ID_BADGE_INVALID")
    out=source[:at]+scope[:match.start()]+new+scope[match.end():]
    flutter_import="import 'package:flutter/material.dart';\n"
    if out.count(flutter_import)!=1:
        raise ValueError("SAFE_STOP_QA32_PUBLIC_CARD_IMPORT_AMBIGUOUS")
    out=out.replace(flutter_import,flutter_import+MARKER+"\n",1)
    if out.replace(flutter_import+MARKER+"\n",flutter_import,1).replace(new,old,1)!=source:
        raise ValueError("SAFE_STOP_QA32_PUBLIC_CARD_UNRELATED_MUTATION")
    if out.count("premiumCardBuilder:")!=1:
        raise ValueError("SAFE_STOP_QA32_PUBLIC_CARD_MULTIPLE_BUILDERS")
    return out

if __name__=="__main__":
    before=MAIN.read_text()
    after=apply(before)
    if after!=before: MAIN.write_text(after)
    print("PASS_QA32_PUBLIC_FRIEND_FULL_OWNER_FOIL_SAME_ARTWORK")
    print("PASS_QA32_NO_PRIVATE_USER_DATA_OR_SOCIAL_ROUTES_MUTATION")
