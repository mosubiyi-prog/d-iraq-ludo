# DEDA 100408 — Owner seven-point agreement, ordered and protected

Baseline: successful signed 100407 (05fa763398d717cf81eb5c68b02e276d993be2d1). Do not modify accepted 100407 or publish to Play. No Firebase deploy or award grants without audited rules and separate owner authorization. Current account comparison: Hanaa @DEDA-DWPKYD (120 weekly XP), Salem Hassan active display @DEDA-IRAQI (20 weekly XP), immutable account routing ID @DEDA-AQPYXJ.

## Mandatory sequence / acceptance gates
1. Verified premium-ID speed: one current Firebase UID + original canonical-ID cache; immediate display of previously server-confirmed active premium ID; no old-ID flicker, no authorization from cache; fresh phone still needs server proof. Test account switch, late responses and offline.
2. Paused-league user notification: when GM pausing commits server-side, show public neutral maintenance notification in fixed bottom explanatory panel (no scrolling); expected 30–90 minutes only when reason indicates maintenance, estimate not guarantee. Hide on resume; XP/diamond untouched.
3. Loading completeness: don't show account balances or friend counts from another session, zero placeholder, or intermediate restore as confirmed. Never alter real values.
4. Fast first leaderboard: show verified ranking/points before async avatar, frame and alias decoration; avoid serialized retry/redundant reads. No fabricated positions.
5. Podium medals: place 1, 2, 3 numbers smaller and translucent, anchored on portrait edge without masking faces, phone and tablet.
6. Admin alias projection: display same verified premium ID as public league for Salem, not original @DEDA-AQPYXJ; Firestore score/review/friend/grant keys stay canonical.
7. GM editable weekly prize increases: 10 separate ranks ONLY during server-verified current-week pause, minimums 150,100,50,10,10,10,10,10,10,10; positive increments only; record manager audit; no completed/finalized-week edits or already-awarded prizes; persist to Firebase with audited rules; show new values and total to all participants. Not a prize payout implementation.

## Stop gates
- Independently verify each point in order and record tests. Do not infer phone/tablet or server success from source checks alone.
- Preserve accounts, active ID, profile avatar/frame, 20/120 weekly XP, original tasks/level XP/diamonds and accepted ownership/gift access.
- If Firestore privilege or award risk appears, stop that point. Do not disable guards or claim final delivery.
- No deletion of app data and no Play release.

## Execution log
- [x] Protected 100408 branch created from successful 100407.
- [x] Point 1 isolated source implementation (fast verified ID + color; skip blocking UI alias repair). QA compile/tests still pending; do not claim phone latency pass.
- [x] Point 2 isolated source implementation (live current-week pause notice in fixed footer). QA compile/tests still pending.
- [ ] Point 3: identified real original profile wallet/friend notifier call sites (approx 31263, 31282); exact account-bound hydration still under inspection before any mutation.
- [ ] Point 4 implementation and tests.
- [ ] Point 5 implementation and tests.
- [ ] Point 6 implementation and tests.
- [ ] Point 7 implementation and tests.
- [ ] Integrated signed APK and phone/tablet QA.

## Evidence and run status (not release proof)
- Current source branch: deda-100408-seven-owner-points-ordered-no-play-2026-10-31.
- Dedicated isolated QA workflow: .github/workflows/deda-100408-seven-points-ordered-test.yml.
- Protect live 100407, no Android APK or Play release from this workflow.
- CI failures while matching generated baseline are pre-build binding checks; source corrections are scoped to the new branch. Never describe these failures as a passing test.
