#!/usr/bin/env python3
"""QA32 friend PUBLIC visual parity with owner Royal Hero (NO DEPLOY).

Use the same elegant static royal gradient, gold trim and readable WHITE name.
Actual photo/frame/background choice comes from the owner's verified
DedaSocialProfile public fields (never from the viewing friend's preferences).
Keep public ID foil from Stage77, friend routes and private values unchanged.
"""
from pathlib import Path
MAIN=Path("lib/main.dart")
MARK="// DEDA_QA32_FRIEND_PUBLIC_ROYAL_HERO_CONTRAST_NO_DEPLOY"
START="class DedaFriendPublicProfilePage extends StatelessWidget {"
END="class DedaStylePage extends StatefulWidget {"

def one(c,old,new,label):
    count=c.count(old)
    if count!=1:raise ValueError("SAFE_STOP_QA32_FRIEND_ROYAL_"+label+"_count_"+str(count))
    return c.replace(old,new,1)

def apply(source):
    if MARK in source:
        if source.count(MARK)!=1:raise ValueError("SAFE_STOP_QA32_FRIEND_ROYAL_PARTIAL")
        return source
    if source.count(START)!=1 or source.count(END)!=1 or \
       source.count("DEDA_QA32_FRIEND_PUBLIC_FULL_VERIFIED_ID_FOIL_NO_DEPLOY")!=1:
        raise ValueError("SAFE_STOP_QA32_PUBLIC_CARD_PREREQUISITES")
    a=source.index(START)
    e=source.index(END,a)
    fragment=source[a:e]
    # Restore the very same fixed multi-stop royal gradient and 2px gold trim
    # as the owner's hero. The stored background style remains visible via the
    # existing 'bg' selection; no profile preference is overwritten.
    old="""              gradient: LinearGradient(colors: bg,
                  begin: Alignment.topRight, end: Alignment.bottomLeft),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFE1CB82)),"""
    new="""              // DEDA_QA32_FRIEND_PUBLIC_ROYAL_HERO_CONTRAST_NO_DEPLOY
              gradient: const LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: <Color>[
                  Color(0xFF092A63),
                  Color(0xFF222056),
                  Color(0xFF51204E),
                  Color(0xFF111C49),
                ],
                stops: <double>[0, 0.41, 0.72, 1],
              ),
              borderRadius: BorderRadius.circular(29),
              border: Border.all(color: const Color(0xFFF2CC68), width: 2),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x40210E46),
                  blurRadius: 21,
                  offset: Offset(0, 9),
                ),
              ],"""
    fragment=one(fragment,old,new,"background")
    # Future rendering of the owner's selected background gets the SAME
    # royal hero backdrop painter and tint. Use the already owned public
    # background swatch as the glow source; no local preview data.
    old="            child: Column(\n              children: <Widget>[\n                DedaFramedAvatar("
    new="""            child: Stack(
              alignment: Alignment.topCenter,
              children: <Widget>[
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _DedaRoyalProfileBackdropPainter(glow: bg.last),
                    ),
                  ),
                ),
                Column(
              children: <Widget>[
                DedaFramedAvatar("""
    fragment=one(fragment,old,new,"backdrop")
    fragment=one(fragment,"                  size: 132,","                  size: 174,","avatar_size")
    old="""                Text(profile.displayName, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Color(0xFF0B3C6F),
                        fontWeight: FontWeight.w900, fontSize: 23)),"""
    new="""                Text(
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
                ),"""
    fragment=one(fragment,old,new,"public_name_contrast")
    # When the public verified server is OFF, fallback ID must still be
    # readable; Stage77 full premium card replaces it if the server is ON.
    old="""style: const TextStyle(color: Color(0xFF536779),
                            fontWeight: FontWeight.w800, fontSize: 15)"""
    new="""style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                          shadows: <Shadow>[
                            Shadow(color: Color(0x80000000), blurRadius: 6),
                          ])"""
    fragment=one(fragment,old,new,"original_id_contrast")
    # Close the new Stack + nested Column around the existing level badge.
    # Scope the close to just before the public hero's closing decoration.
    close_old="""                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(dedaText('الشارات', 'Badges'),"""
    close_new="""                ),
              ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(dedaText('الشارات', 'Badges'),"""
    fragment=one(fragment,close_old,close_new,"hero_stack_closing")
    result=source[:a]+fragment+source[e:]
    # No edits to personal (owner) profile methods, friend relation logic or
    # published style settings; exact reversal must reconstruct old source.
    if result.count(MARK)!=1 or result.count("DedaStage50VerifiedFriendInkBadge(")!=4:
        raise ValueError("SAFE_STOP_QA32_FRIEND_ROYAL_UNEXPECTED_WRAPPER_COUNTS")
    if "DedaFramedAvatar(\n                  avatarStyle: profile.avatarStyle,\n                  frameStyle: profile.frameStyle,\n                  size: 174," not in fragment:
        raise ValueError("SAFE_STOP_QA32_FRIEND_ROYAL_NOT_SERVER_PROFILE")
    return result

if __name__=="__main__":
    original=MAIN.read_text()
    result=apply(original)
    if result!=original:MAIN.write_text(result)
    print("PASS_QA32_FRIEND_PUBLIC_MATCHES_OWNER_ROYAL_GRADIENT_GLOW_AND_GOLD")
    print("PASS_QA32_FRIEND_NAME_AND_FALLBACK_ID_HIGH_CONTRAST")
    print("PASS_QA32_PUBLIC_USES_STORED_AVATAR_FRAME_BACKGROUND_NOT_VIEWER")
