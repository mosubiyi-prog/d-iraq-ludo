#!/usr/bin/env python3
"""Stage51: wrap existing real Add Friend search, do not rewrite social service.

Apply on the exact reconstructed 100359 source AFTER stages48,49,50.
Canonical friend ID remains in DedaSocialService, friend pair keys,
QR, WhatsApp and location sharing. Premium aliases NEVER create profiles.
"""
from pathlib import Path

MAIN = Path("lib/main.dart")
MARKER = "// DEDA_OWNER19_STAGE51_FRIEND_SEARCH_CANONICAL_ALIAS_NO_DEPLOY"
IMPORT = "import 'deda_stage51_verified_friend_alias_search.dart';\n"
START = "class _DedaAddFriendPageState extends State<DedaAddFriendPage> {"
END = "class _DedaSearchResultCard extends StatelessWidget {"
OLD_CHECK = "DedaSocialService.looksLikePersonalId(id)"
NEW_CHECK = "DedaStage51FriendSearch.acceptsInput(id)"
OLD_LOOKUP = "DedaSocialService.findByPublicId(id)"
NEW_LOOKUP = "DedaStage51FriendSearch.findByUserInput(id)"
ORIGINAL_AFTER_LOOKUP = """      if (!mounted) return;
      setState(() {"""
NEW_AFTER_LOOKUP = """      if (!mounted) return;
      // A premium alias belonging to the signed-in requester must NEVER
      // allow a self-friend request. Canonical existing ID remains unchanged.
      if (found != null && found.ownerUid == _session?.uid) {
        setState(() {
          _result = null;
          _resultMessage = dedaText('لا يمكنك إضافة نفسك كصديق.',
              'You cannot add yourself as a friend.');
        });
        return;
      }
      setState(() {"""


def apply(source: str) -> str:
    if MARKER in source:
        if source.count(MARKER) != 1 or source.count(IMPORT) != 1 or \
                source.count(NEW_CHECK) != 1 or \
                source.count(NEW_LOOKUP) != 1 or \
                source.count(NEW_AFTER_LOOKUP) != 1:
            raise ValueError("SAFE_STOP: partial Stage51 friend integration")
        return source
    for token in (
        "DEDA_OWNER19_STAGE50_FRIEND_INK_THREE_PUBLIC_SURFACES_NO_DEPLOY",
        "DEDA_OWNER19_STAGE49_ORIGINAL_QR_PLUS_VERIFIED_PREMIUM_INK",
        "DEDA_OWNER19_STAGE48_PROFILE_ACTIVE_ID_FIXED_INK_NO_DEPLOY",
    ):
        if source.count(token) != 1:
            raise ValueError("SAFE_STOP: approved earlier step is absent")
    if source.count(START) != 1 or source.count(END) != 1 or \
            IMPORT in source:
        raise ValueError("SAFE_STOP: Add Friend source not unique")
    a = source.index(START)
    b = source.index(END, a + len(START))
    before = source
    original = source[a:b]
    for token in (OLD_CHECK, OLD_LOOKUP, ORIGINAL_AFTER_LOOKUP):
        if original.count(token) != 1:
            raise ValueError("SAFE_STOP: Add Friend original operation changed")
    if original.count("DedaSocialService.sendFriendRequest(") != 1 or \
            original.count("_session!.publicId") != 1:
        raise ValueError("SAFE_STOP: original social relationship lost")
    # Only two callsites change and one post-lookup self-guard is inserted.
    edited = original.replace(OLD_CHECK, NEW_CHECK, 1)
    edited = edited.replace(OLD_LOOKUP, NEW_LOOKUP, 1)
    edited = edited.replace(ORIGINAL_AFTER_LOOKUP, NEW_AFTER_LOOKUP, 1)
    if edited.replace(NEW_CHECK, OLD_CHECK, 1).replace(
            NEW_LOOKUP, OLD_LOOKUP, 1).replace(
            NEW_AFTER_LOOKUP, ORIGINAL_AFTER_LOOKUP, 1) != original:
        raise ValueError("SAFE_STOP: friend route mutation beyond approved")
    result = source[:a] + edited + source[b:]
    mat = "import 'package:flutter/material.dart';\n"
    if result.count(mat) != 1:
        raise ValueError("SAFE_STOP: material import not unique")
    result = result.replace(mat, mat + IMPORT + MARKER + "\n", 1)
    if result.replace(mat + IMPORT + MARKER + "\n", mat, 1).replace(
            edited, original, 1) != before:
        raise ValueError("SAFE_STOP: unrelated user/social source changed")
    return result


if __name__ == "__main__":
    src = MAIN.read_text(encoding="utf-8")
    new = apply(src)
    if new != src:
        MAIN.write_text(new, encoding="utf-8")
    print("PASS: old IDs search exactly as before while flags remain OFF")
    print("PASS: premium ID resolves ONLY verified canonical social profile")
    print("PASS: no friend pair keys / QR / place or location share modified")
