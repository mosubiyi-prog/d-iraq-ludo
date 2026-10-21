#!/usr/bin/env python3
"""QA32: royal public-friend card high-contrast parity, safe source-only stage.

Run after the single full-foil profile patch. The SOURCE OF TRUTH for avatar,
frame and background is the *owner's verified public DedaSocialProfile*, NOT
viewer's locally persisted preferences. No account/wallet/registry writes.

This patch matches the DART-FORMATTED reconstructed 100359 source, not the
earlier unformatted historical template. Each edited field is fail-closed and
scoped to the one public friend-profile widget.
"""
import re
from pathlib import Path

MAIN=Path("lib/main.dart")
MARK="// DEDA_QA32_FRIEND_PUBLIC_ROYAL_HERO_CONTRAST_NO_DEPLOY"
START="class DedaFriendPublicProfilePage extends StatelessWidget {"
END="class DedaStylePage extends StatefulWidget {"

def one_sub(source, pattern, replacement, what):
    result,n=re.subn(pattern,lambda m:replacement,source,count=2,flags=re.DOTALL)
    if n!=1:
        raise ValueError("SAFE_STOP_QA32_ROYAL_"+what+"_count_"+str(n)+
                         " public_excerpt="+repr(source[:2300]))
    return result

def apply(source):
    if MARK in source:
        if source.count(MARK)!=1:
            raise ValueError("SAFE_STOP_QA32_PUBLIC_ROYAL_PARTIAL")
        return source
    if source.count(START)!=1 or source.count(END)!=1 or \
       source.count("DEDA_QA32_FRIEND_PUBLIC_FULL_VERIFIED_ID_FOIL_NO_DEPLOY")!=1:
        raise ValueError("SAFE_STOP_QA32_PUBLIC_ROYAL_SOURCE_CHANGED")
    begin=source.index(START)
    end=source.index(END,begin)
    frag=source[begin:end]

    # Preserve the exact crown foil, original public ID, owner frame/avatar,
    # social badges, level, and all user actions.
    if frag.count("DedaStage50VerifiedFriendInkBadge(")!=1 or \
       frag.count("DedaFramedAvatar(")!=1 or \
       frag.count("profile.avatarStyle")<1 or \
       frag.count("profile.frameStyle")<1 or \
       frag.count("final bg = dedaProfileBackgroundColors(profile.backgroundStyle);")!=1:
        raise ValueError("SAFE_STOP_QA32_PUBLIC_ROYAL_PROFILE_COMPONENTS")

    # Use the same royal four stop palette and trim as owner. The last panel
    # tone preserves an understated tint from the owner's chosen background.
    # Reformat-safe delimiters; strictly constrain source to old expected
    # bg gradient and border colors inside public profile.
    bgpat=(r"gradient:\s*LinearGradient\(\s*"
           r"colors:\s*bg,\s*"
           r"begin:\s*Alignment\.topRight,\s*"
           r"end:\s*Alignment\.bottomLeft,\s*\),\s*"
           r"borderRadius:\s*BorderRadius\.circular\(24\),\s*"
           r"border:\s*Border\.all\(\s*"
           r"color:\s*const\s+Color\(0xFFE1CB82\)\s*,?\s*\),")
    bgnew="""// DEDA_QA32_FRIEND_PUBLIC_ROYAL_HERO_CONTRAST_NO_DEPLOY
              gradient: LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: <Color>[
                  const Color(0xFF092A63),
                  const Color(0xFF222056),
                  const Color(0xFF51204E),
                  Color.alphaBlend(
                    bg.last.withOpacity(0.14),
                    const Color(0xFF111C49),
                  ),
                ],
                stops: const <double>[0, 0.41, 0.72, 1],
              ),
              borderRadius: BorderRadius.circular(29),
              border: Border.all(
                color: const Color(0xFFF2CC68), width: 2,
              ),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x40210E46),
                  blurRadius: 21,
                  offset: Offset(0, 9),
                ),
              ],"""
    frag=one_sub(frag,bgpat,bgnew,"old_background")
    frag=one_sub(frag,r"(\bsize:\s*)132(\s*,)","size: 174,","avatar_size")

    namepat=(r"Text\(\s*profile\.displayName\s*,\s*"
             r"maxLines:\s*1\s*,\s*overflow:\s*TextOverflow\.ellipsis\s*,\s*"
             r"style:\s*const\s+TextStyle\(\s*"
             r"color:\s*Color\(0xFF0B3C6F\)\s*,\s*"
             r"fontWeight:\s*FontWeight\.w900\s*,\s*fontSize:\s*23\s*\)\s*\)")
    namenew="""Text(
                  profile.displayName,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 25,
                    shadows: <Shadow>[
                      Shadow(color: Color(0x80000000), blurRadius: 8),
                    ],
                  ),
                )"""
    frag=one_sub(frag,namepat,namenew,"old_public_name")

    # The canonical original-ID fallback remains legible when the public
    # verified premium style callable is OFF; do not draw a counterfeit foil.
    inkpat=(r"color:\s*Color\(0xFF536779\)\s*,\s*"
            r"fontWeight:\s*FontWeight\.w800\s*,\s*fontSize:\s*15")
    inknew="""color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                      shadows: const <Shadow>[
                        Shadow(color: Color(0x80000000), blurRadius: 6),
                      ]"""
    frag=one_sub(frag,inkpat,inknew,"old_original_id_ink")

    if frag.count(MARK)!=1 or frag.count("DedaStage50VerifiedFriendInkBadge(")!=1:
        raise ValueError("SAFE_STOP_QA32_PUBLIC_ROYAL_UNRELATED_EDIT")
    updated=source[:begin]+frag+source[end:]
    if updated[:begin]!=source[:begin] or updated[begin+len(frag):]!=source[end:]:
        raise ValueError("SAFE_STOP_QA32_PUBLIC_ROYAL_OUTSIDE_SCOPE")
    return updated

if __name__=="__main__":
    before=MAIN.read_text()
    after=apply(before)
    if before!=after:MAIN.write_text(after)
    print("PASS_QA32_PUBLIC_OWNER_ROYAL_GRADIENT_WHITE_NAME_SAFE_BG_TINT")
    print("PASS_QA32_PUBLIC_USES_OWNER_AVATAR_FRAME_BACKGROUND_NOT_VIEWER")
    print("PASS_QA32_PUBLIC_ORIGINAL_FALLBACK_REMAINS_NON_PREMIUM")
