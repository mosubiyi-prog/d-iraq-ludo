# DEDA weekly podium owner visual review — V2 checkpoint (2026-10-27)

## Request and proven owner feedback
The first **standalone** preview APK (GitHub Actions 40547751828) installed and the owner sent two actual mobile screenshots. The list fit without scrolling, but the visual quality was below the ONE approved luxurious dark-blue/gold reference: generic avatars, plain medals/podium, cramped rows and unrefined viewer panel. Owner ordered completion of remaining points.

## This isolated source branch
`deda-weekly-owner-visual-polish-v2-safe-preview-2026-10-27`
from `deda-weekly-leaderboard-owner-ui-preview-apk-isolated-2026-10-27`.
Changes remain confined to **newly added** Flutter leaderboard page, independent preview main and NEW V2 GitHub build workflow; original signed DEDA 100387 commit `a0dd340e8843162ac5fb89784cb54d0be82b23ec` untouched.

1. Sample podium / leaderboard avatars now display **existing original DEDA royal-portrait artwork** from `assets/deda_owner_avatars_20261023` (male/female/couple). These are explicitly demo imagery and repeat for example users; real profiles must use server-provided authorized current avatar. No invented actual player/phone or user data.
2. First-place crown, first-place laurel-like ornaments, color-specific crowns for second and third, improved gold/silver/bronze glowing circular avatar frames, rank medallions and tier-specific podium card gradients, without using any app account or wallet.
3. Gold avatar rings in ranks 4–10 and personal panel, increased visual contrast, CTA trend glyph on personal card.
4. Personal card displays the user's **active DEDA ID under name** (even in the demo example), and retains rank and earned weekly XP. Layout remains one centered fixed viewport for phone and tablet: scrolling is FORBIDDEN in ranking page.
5. V2 CI compiles real standalone Android preview package `iq.deda.weeklypreviewv2` (different from BOTH official `com.diraq.ludo.d_iraq_ludo` and previous `iq.deda.weeklypreview`). This avoids keystore/signature conflicts and preserves original installs. It copies only the three existing example portraits, adds explicit Flutter assets, runs five phone/tablet launcher-and-ranking widget tests, then makes download-only APK artifact. NO Firebase SDK/auth/session, NO task/XP/diamond writer, NO Play deployment, NO original signing key.

## Practical acceptance
- Owner must test visual clarity, portrait/podium fidelity and name/ID spacing on actual phone and tablet; automated Flutter tests don't prove pixel-identical artwork to original owner's reference screenshot.
- Current preview uses **sample scores, current/previous tabs and sample diamonds ONLY**, not real player/league backend. The display states `معاينة تجريبية — بيانات توضيحية فقط` on top and `معاينة تصميم فقط؛ الأسماء والنقاط والجوائز وهمية.` in the footer.
- Actual live leaderboard integration and 370 earned-diamond weekly rewards **still incomplete**: need trusted Cloud proof of successfully claimed daily task AND applied +20 LEVEL XP, same canonical account across phones, privileged server calendar/ranking snapshots, server-only once-per-week prize ledger and separate owner security approval before any real deployment. Never derive public scores from local 5-point traffic answers or untrusted client XP totals; historical XP and level never reset.

Build QA target:
https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/40551203259

No claims of APK build success until GitHub Actions conclusion and uploaded APK artifact are confirmed.
