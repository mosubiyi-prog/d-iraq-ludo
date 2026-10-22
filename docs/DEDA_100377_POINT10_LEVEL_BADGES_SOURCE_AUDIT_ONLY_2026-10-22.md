# DEDA 100377 Point10 — LEVEL badges vs purchased cosmetic badges (audit only)
Date: 2026-10-22 | Same 13-point sequential branch | No release/APK/Firebase deploy

## Owner's exact Point10 intent
Six automatically earned, *LEVEL*-based badges:
فضية / ذهبية / زمردية / ماسية / ملكية / أسطورية.
The following Point11 screen «شاراتك وإنجازاتك» will show the six, unlock status, progress and explanation.
Do NOT copy decorative purchased-store badge entitlements into level achievements or re-price any existing owned cosmetics.

## Existing source of truth and distinction
- Reconstructed signed app pipeline includes `tools/profile_level_task_points_100276_2026_10_05.py` followed by `tools/profile_level_xp_fix_100277_2026_10_05.py`. The **final** patch explicitly restores `DedaSocialProgressWallet.levelForXp(xp)` and `xpNotifier` as actual level authority. Task points and money are separate from XP. Do not revert or conflate.
- Existing `tools/style_badges_frames_100273_2026_10_05.py` has six SHOP COSMETIC IDs: `badge_member`, `badge_spark`, `badge_elite`, `badge_royal`, `badge_season1`, `badge_legendary`. They have an owned/active inventory flow and purchasable labels, and are NOT the six new level achievements.
- UI currently says `مستوى ذهبي • $profileLevel` as an established profile label. The word ذهبي does NOT establish a numerical badge-unlock tier; the original level value must come from the verified level/Xp source.
- Owner-approved exact *numerical level thresholds* for Silver/Gold/Emerald/Diamond/Royal/Legendary have not been found in the checkpoint. Never guess thresholds, grant all six at first login, rewrite XP, or lock an already owned purchased badge due to an achievement level.

## Acceptance before claiming Point10 implemented
1. Design one distinct immutable achievement identifier for each of the six LEVEL badges without collisions with existing purchased `dedaStyleBadgeIds`.
2. Confirm level source from verified authenticated account snapshot, separate from task-points, diamond/gold wallet, the current six purchased badges, and daily login stats.
3. Use owner-approved exact six-tier threshold mapping, handle boundary levels, account switch, reopen and second device; no fabricated level restoration.
4. Level badge is automatically earned only on authentic threshold proof, without purchases or manual use; existing 100-milestone XP/level mechanics and all cosmetic inventory remain untouched.
5. Point11 achievements page shows honest locked/unlocked/progress after Point10 policy is verified.
6. Flutter/source/emulator checks and signed two-account phone/tablet QA before final acceptance.

STATUS: source audit/preflight ONLY — no UI or unlock policy implementation, no changes to users or backend. Point09 cross-device persistence still requires separate authoritative server restoration; Point05 exact three moonlit assets also pending.
