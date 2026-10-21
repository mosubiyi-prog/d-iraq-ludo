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
