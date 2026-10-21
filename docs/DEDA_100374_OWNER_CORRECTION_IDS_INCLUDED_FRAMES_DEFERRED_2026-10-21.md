# DEDA 100374 — owner correction / accepted scope — 2026-10-21

## Critical correction from owner
The previous claim “premium IDs deferred, frames in this release” was WRONG.
**PREMIUM IDENTIFIER ISSUES MUST REMAIN IN THE NEXT 100374 FIX SET.**
**ONLY the 13 additional LAB decorative photo/avatar FRAMES are postponed.**
Keep the existing 6 profile frames (3 free + 3 locked preview) and current selected cosmetics untouched.
The four free **premium identifier cards** are NOT photo frames and are in scope to preserve/test.
Do not conflate “إطارات الصورة الشخصية” with “بطاقات المعرفات”.

## User-verified defects still in scope for the future owner QA APK
1. Sender's own `شارك موقعك` displays active alias `@DEDA-IRAQI` (PASS); recipient sees old `@DEDA-AQPYXJ` (FAIL). Preserve original canonical ID for secure routing/storage; fix only verified recipient-visible ID using trusted backend.
2. Public friend profile shows old ID, no real full premium card (FAIL); preserve current avatar, selected frame, background, badge and readability. Security: server-approved owner-specific alias only, not a client-claimed alias.
3. Admin diamond gift recipient lookup fails for active premium ID but succeeds for original ID (FAIL). Both must resolve securely to the SAME underlying original account; never credit the wrong account.
4. Owned ID ‘استخدام’ and ownership verification in owner/admin flows still need on-device success, not a mocked UI. Original ID reversibility must remain safe; no duplicate grant or account mutation.
5. ‘هداياي’ red home notification did not appear according to owner despite successful 50-gem gift receipt and claim. Review both diamond and identifier gifts, unread lifecycle and account-switch isolation. Existing 10-gem history and new 50-gem history untouched.
6. Friend public card shows hard-to-read dark name and original ID on dark background on second device. Improve contrast without changing published account data.
7. Keep functioning: 50-gem manager send via original ID, client-displayed manager debit, recipient gift receipt/claim, previous gifts, current owner account header, GPS share/delivery, avatar, frame and background visuals.
8. Cross-phone XP/gems/points/owned goods/place ownership remains a separate OPEN P0 item, NOT a claim of repaired state. Do not reset or migrate live accounts without verified trusted backend and owner review.

## Security and workflow
- Verified phone baseline: private signed APK 100373, GitHub run 39628687478.
- Immutable backup: `backup-deda-qa-32-owner-review-2026-10-21`; do NOT change it.
- Staged non-ID patches from branch `deda-100374-non-id-fixes-private-2026-10-21` may be carried forward, but the old **non-ID-only** 100374 workflow run [39645050679](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/39645050679) is an **INCOMPLETE-SCOPE build** even if GitHub CI returns success. NEVER hand it over as the owner's accepted complete correction release.
- Corrected branch `deda-100374-ids-qa32-frames-deferred-2026-10-21`. Do not create a release APK or present one as finished until identity alias/recipient lookup and owner phone tests can be shown, including required server verification with explicit approval for production-only changes.
- No production Google Play publishing, Firestore rules/Cloud Functions deployment, paid checkout, actual account wallet writes, or extra LAB frames without explicit owner authorization and suitable controls.
- No promises of all items being solved simply because the build/signature passes. Real two-account phone QA required.

**This checkpoint supersedes every prior non-ID-only scope statement.**


## Owner re-confirmed four screenshots — single premium-ID consistency acceptance gate (2026-10-21)
These four screenshots supplied again by the owner are the *original reason for the 100373/100374 fix*, not evidence to defer premium IDs:

1. **Received location:** `سالم حسن` successfully sends his location, original ID `@DEDA-AQPYXJ` appears on receiver card while sender's OWN verified share screen shows active `@DEDA-IRAQI`. Retain original identifier for account routing; receiver display must independently resolve trusted active alias. Two historically separate intentional location shares are NOT duplicates.
2. **Friend public profile:** portrait with jeweled pink frame and gradient background appears, but old `@DEDA-AQPYXJ` replaces activated alias, the premium card foil is missing and the dark text is unreadable. Correct both genuine live verified alias+foil and readable name, without removing original owner portrait/frame/background/badge or exposing private account data.
3. **GM `هدايا الجواهر`, canonical:** `@DEDA-AQPYXJ` resolves to `سالم حسن` level 1 and supports the already validated historic/new gem gift.
4. **GM `هدايا الجواهر`, premium:** `@DEDA-IRAQI` results in `لم يتم العثور على حساب شخصي بهذا المعرف`. Must resolve server-verified premium ID to *exactly the same* original account, never grant gems to a different recipient, never overwrite gift history.

**Cross-surface acceptance**: owner-visible account and sending location use current alias; receiver location, friend public header+authentic color/foil, GM verified recipient lookup, and owned ID Use/Gift/Claim all agree on account ownership. Test against two real accounts on owner phone/tablet, positive and negative authorization, original ID fallback/revert and switching accounts. Existing original stable routing is immutable. Do not pass because own account alone looks right.

**Scope**: Fix ID system and gift notification/contrast. **Defer ONLY 13 new LAB avatar/profile FRAMES** (not the existing 6, not the four premium identifier card color designs). Keep 100373 backup; the non-ID-only 100374 workflow is outdated scope and is *not* an accepted release even if it succeeds.

**Backend safety blocker**: cross-account active premium alias read uses `dedaPremiumReadPublicIdentifierStyle`, currently gated OFF and not deployed. A correct secure deployment to the live environment requires its own permission and security review; do NOT silently enable Firebase Functions/rules or substitute insecure client-field aliases. If not approved, report that relevant acceptance item remains OPEN instead of claiming it fixed.


## 100374 partial APK built — NOT all owner-accepted premium IDs (2026-10-21)
- GitHub Actions [run 39645050679](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/39645050679) **COMPLETED SUCCESS** on the **old non-ID branch** commit `af8ba4749040f4ebc3c33c66d8945a6a1f5f6960`, including exact original signing and APK verification. Artifact ID `12368291193`, internal APK name `DEDA-100374-QA32-STAGE82-PRIVATE-OWNER-ONLY.apk`, size `75,250,243` bytes.
- Downloaded and verified user-output SHA256 against artifact SHA256SUMS.txt in the model session, created `DEDA-100374-PRIVATE-NON-ID-QA.apk`. The artifact's source still **excludes** live authenticated premium alias resolving and admin premium ID gift lookup, and therefore must **NOT** be claimed as completed owner-requested 100374. Can be used as an **interim private technical test only**.
- Owner's requested next stage after the fully accepted ID-fix release: precisely `16` LAB frames total, `3` existing royal frames FREE (convert prior locked-preview to actually usable free), `13` more added with authentic artwork, **LOCKED and EACH bought once for exactly 1000 diamonds**; match legacy 850x850 asset art, 111x111 interior sizing, luxury wave, jewelry glints/light rays, pinned preview, secure durable per-account ownership. Full precise spec saved in [DEDA_NEXT_PHASE_16_LAB_FRAMES_3_FREE_13_AT_1000_DIAMONDS_OWNER_SPEC_2026-10-21.md](https://github.com/mosubiyi-prog/d-iraq-ludo/blob/deda-100374-ids-qa32-frames-deferred-2026-10-21/docs/DEDA_NEXT_PHASE_16_LAB_FRAMES_3_FREE_13_AT_1000_DIAMONDS_OWNER_SPEC_2026-10-21.md).
- Frame phase is **PLAN ONLY**, not executed. No server deploy, Play publishing or live wallet modification. Owner backup and baseline untouched.
