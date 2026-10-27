# DEDA 100391 — Owner phone result: premium ID faster (2026-10-27)

**Actual physical-phone evidence:** owner-provided 9.2-second recording `1000100953.mp4`. Owner confirms, "نجح وبوقت اقل". This is NOT merely a GitHub build PASS.

## Observed frames
- At entry to personal profile around 4–5 seconds of recording, profile initially renders `جارٍ التحقق من المعرّف...`.
- At around 6 seconds, valid golden royal premium alias `@DEDA-IRAQI` is visible. Continues visible in following seconds.
- User notices meaningful time reduction. **Do not claim instantaneous / zero placeholder or full server-side ID verification on brand-new devices.**
- XP level stays Level 2, 120/150 in recording.
- Transient cross-section profile values: diamond card shows `993895` initially then `993955`; friends briefly `0` then `2`. These are UI-level changes on recording, not evidence of any backend earned-diamond write. Do NOT award/correct/spend 60 gems by assumption.
- Phone owner has therefore validated **improved account-specific local verified ID preload** for Stage16 100391. Keep as successful reference for identifier-speed improvement, while separate stale balance/friends projection and remaining initial ID placeholder are unresolved.
- Never touch original stable 100387, original signed 100388, manager wallet, gift pools, level XP, Firestore rules or Play rollout as part of preserving this checkpoint.

## Build provenance
- Protected source branch `deda-id-stage16-measured-startup-100391-private-qa-2026-10-27`.
- Private signed original-app GitHub Actions build `40577390210` PASS and owner-installed APK `DEDA-100391-ORIGINAL-ID-MEASURED-FAST-PRIVATE-QA.apk`.
- Correct fix: preload verified, UID-scoped local premium alias in **actual DEDA_STABILITY_STARTUP_METRICS=true** launch callback before `runApp`. The earlier 100389 mistakenly patched only an inactive startup branch.

## Next issue (separate protected work only)
Deduplicate and unify backend-authoritative financial UI subscriptions in Tasks, Profile, and Frames/Badges Shop without changing or guessing real balances; handle initial profile 0->2 friend count only when authenticated scope consistent. Protect client-server canonical identifiers and cross-device continuity.

No publication to Play, no server write.
