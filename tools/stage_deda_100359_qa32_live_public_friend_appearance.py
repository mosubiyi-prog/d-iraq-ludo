#!/usr/bin/env python3
"""QA32 public friend appearance: server-updated avatar/frame/bg, no private data.

Apply after verified crown card + royal hero; keep all social friend operations,
routing IDs, canonical owner UID and privacy boundaries unmodified.
"""
from pathlib import Path
MAIN=Path("lib/main.dart")
START="class DedaFriendPublicProfilePage extends StatelessWidget {"
END="class DedaStylePage extends StatefulWidget {"
MARK="// DEDA_QA32_PUBLIC_FRIEND_LIVE_APPEARANCE_UID_BOUND_NO_DEPLOY"
IMPORT="import 'deda_qa32_live_friend_appearance.dart';\n"
MAT="import 'package:flutter/material.dart';\n"

def apply(source):
    if MARK in source:
        if source.count(MARK)!=1 or source.count(IMPORT)!=1:
            raise ValueError("SAFE_STOP_QA32_LIVE_PUBLIC_PARTIAL")
        return source
    if source.count(START)!=1 or source.count(END)!=1 or \
       source.count("DEDA_QA32_FRIEND_PUBLIC_ROYAL_HERO_CONTRAST_NO_DEPLOY")!=1:
        raise ValueError("SAFE_STOP_QA32_LIVE_PUBLIC_STAGE_ORDER")
    start=source.index(START)
    stop=source.index(END,start)
    frag=source[start:stop]
    old="""  @override
  Widget build(BuildContext context) {
    final bg = dedaProfileBackgroundColors(profile.backgroundStyle);"""
    new="""  // DEDA_QA32_PUBLIC_FRIEND_LIVE_APPEARANCE_UID_BOUND_NO_DEPLOY
  // Stream only the other person's approved public avatar/frame/background,
  // never local viewer preferences, diamonds, session IDs or private fields.
  @override
  Widget build(BuildContext context) {
    return DedaQa32LiveFriendAppearance(
      initial: profile,
      builder: (context, verified) => _buildVisible(context, verified),
    );
  }

  Widget _buildVisible(BuildContext context, DedaSocialProfile profile) {
    final bg = dedaProfileBackgroundColors(profile.backgroundStyle);"""
    if frag.count(old)!=1:raise ValueError("SAFE_STOP_QA32_LIVE_PUBLIC_RENDER_COUNT")
    frag=frag.replace(old,new,1)
    if frag.count("DedaStage50VerifiedFriendInkBadge(")!=1 or \
       frag.count("DedaFramedAvatar(")!=1 or \
       frag.count("DedaPremiumIdCard(")!=1:
        raise ValueError("SAFE_STOP_QA32_LIVE_PUBLIC_COMPONENTS_MISSING")
    result=source[:start]+frag+source[stop:]
    if result.count(MAT)!=1 or IMPORT in result:
        raise ValueError("SAFE_STOP_QA32_LIVE_PUBLIC_IMPORT_AMBIGUOUS")
    result=result.replace(MAT,MAT+IMPORT,1)
    if result.replace(MAT+IMPORT,MAT,1).replace(new,old,1)!=source:
        raise ValueError("SAFE_STOP_QA32_LIVE_PUBLIC_UNRELATED_SOURCE_CHANGED")
    return result

if __name__=="__main__":
    current=MAIN.read_text()
    updated=apply(current)
    if updated!=current:MAIN.write_text(updated)
    print("PASS_QA32_PUBLIC_FRIEND_LIVE_OWNER_STYLE_FROM_SERVER")
    print("PASS_QA32_PUBLIC_PROFILE_ROUTE_AND_PRIVATE_DATA_UNCHANGED")
