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
           r"end:\s*Alignment\.bottomLeft\s*,?\s*\),\s*"
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
              // Preserve the existing profile shadow; no duplicate field."""
    frag=one_sub(frag,bgpat,bgnew,"old_background")
    # The original user public-profile avatar has changed size across prior
    # stages; locate the ONE actual DedaFramedAvatar and update its existing
    # size rather than assuming an obsolete exact 132px constant.
    avatar_match=re.search(r"DedaFramedAvatar\(",frag)
    if avatar_match is None or frag.count("DedaFramedAvatar(")!=1:
        raise ValueError("SAFE_STOP_QA32_ROYAL_OWNER_AVATAR_NOT_UNIQUE")
    avatar_end=frag.find(")",avatar_match.end())
    if avatar_end < 0 or avatar_end-avatar_match.end()>450:
        raise ValueError("SAFE_STOP_QA32_ROYAL_OWNER_AVATAR_BOUNDS")
    avatar=frag[avatar_match.start():avatar_end+1]
    avatar_new=one_sub(
        avatar, r"\bsize:\s*[0-9]+(?:\.[0-9]+)?\s*,",
        "size: 174,", "owner_avatar_size",
    )
    frag=(frag[:avatar_match.start()]+avatar_new+
          frag[avatar_end+1:])

    # Only edit the owner's existing public display-name Text widget.
    # Historical patches may have changed its fontSize/spacing already.
    names=list(re.finditer(r"Text\(\s*profile\.displayName\s*,",frag))
    if len(names)!=1:
        raise ValueError("SAFE_STOP_QA32_ROYAL_PUBLIC_NAME_NOT_UNIQUE")
    name_start=names[0].start()
    name_end=frag.find("const SizedBox(",name_start)
    if name_end < name_start or name_end-name_start > 1100:
        raise ValueError("SAFE_STOP_QA32_ROYAL_PUBLIC_NAME_BOUNDS")
    old_name=frag[name_start:name_end]
    styled=old_name
    if "textAlign:" not in styled:
        styled=one_sub(styled,r"profile\.displayName\s*,",
                       "profile.displayName, textAlign: TextAlign.center,",
                       "public_name_center")
    styled=one_sub(styled,r"maxLines:\s*[0-9]+",
                   "maxLines: 2","public_name_max_lines")
    styled=one_sub(styled,r"color:\s*(?:const\s+)?Color\(0x[0-9A-Fa-f]{8}\)",
                   "color: Colors.white","public_name_white")
    styled=one_sub(styled,r"fontSize:\s*[0-9]+(?:\.[0-9]+)?",
                   "fontSize: 25","public_name_size")
    frag=frag[:name_start]+styled+frag[name_end:]

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
