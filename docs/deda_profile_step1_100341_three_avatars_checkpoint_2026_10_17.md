# DEDA | Royal Profile Step 1: 3 approved avatars | 2026-10-17

## User-approved scope
Implement points 1–8 of the next profile release, with the three portraits as the first and highest priority. Keep existing background and real wallet/level engines, move the appbar copy button to EDIT (copy remains in ID chip), and show the real current ID read-only inside Edit Profile. Do NOT activate premium ID switching; it is independently specified in `docs/deda_active_owned_identifiers_decision_2026_10_17.md`.

## Recovery / source
- Stable recovery: `backup-deda-100340-before-profile-royal-2026-10-17`, SHA `b9c2181ac01ef942e05bcdbcf40ce0dbeb34e5c9`.
- Work branch: `profile-royal-step1-3avatars-4frames-2026-10-17`.
- The approved first royal hero in private QA 100340 was actually installed and user screenshot reviewed; NO Play publication.
- Raw `lib/main.dart` is NOT the assembled app. Reconstruct via 100340 approved workflow first, then apply `tools/stage_deda_royal_hero_2026_10_17.py`, then `tools/stage_deda_royal_avatars_step1_2026_10_17.py`.
- Royal source-only compile 100340 previously succeeded in run 38982080679, private signed 100340 APK run 38982310753 succeeded.

## Exact artwork committed on development branch
These are the original three 1536x1536 JPEG bytes the owner approved; not re-generated or redrawn:
- `assets/deda_royal_avatars/deda_avatar_male_royal.jpg` blob SHA `1b3e8457e2a9f05e665f46b442f3ec2100c6d399`.
- `assets/deda_royal_avatars/deda_avatar_female_royal.jpg` blob SHA `4d77fd546aaab9aec9b46c2ab0c645e3044ca488`.
- `assets/deda_royal_avatars/deda_avatar_couple_royal.jpg` blob SHA `e3763118b218fc51d2697bb1ba96e9d8c0b8d864`.
- Asset commit `25930d0e200aab92cb9686081e716e8dbab99f3c` verified all three blobs against the local source bytes.
- All images remain separate from overlaid cosmetics/frames; Flutter Image.asset high-quality circular rendering.

## User account backward compatibility
- New catalog: 0=male, 1=female, 2=couple, 3..5=existing classic visible.
- Previous explicitly saved catalog values 0,1,2 migrate once and exclusively into hidden catalog styles 6,7,8 respectively, so those previously selected classic portraits retain their identity when updating. New users default to 0 royal male.
- Save appearance sets a migration version flag; all old frame styles stay unchanged. No wallet/level/mates/purchases or Firebase rules involved.
- New edit profile displays real DEDA personal ID but deliberately offers NO pretend activation control for premium identifiers.
- Portraits follow current `DedaFramedAvatar` painter; first set is a measurement/reference stage, not 4 new animated frames.

## Current QA
- Patch file committed as `tools/stage_deda_royal_avatars_step1_2026_10_17.py`, commit `d4223a678ac5e14f63d506435f8f6f4611067782`. Local guard comparison PASS for all protected wallet functions, avatar migration, and three assets.
- Additional Flutter tests committed `test/deda_royal_avatar_choice_100341_test.dart`, commit `35288f1baeb9ac2bf42699593e9247672f26c3e5`; these require execution in rebuilt-source CI before release approval.
- GitHub Action QA for private 100341 signed APK (NOT FOR PLAY): https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/38988987835 . The initial QA command failed on workflow Python formatting; corrected on a follow-up commit, and full migration/diamond tests are included. Current QA run 38988987835 is pending/in progress; **do not claim success until checked**.
- Workflow `.github/workflows/qa-deda-profile-step1-royal-hero-private-apk-no-deploy.yml` compiles private APK v100341 and verifies image SHA256 from inside final APK; only after source rebuild + safety checks. Code of UI and image status cannot be validated visually until a real phone screenshot from signed APK is inspected and owner accepts it.

## Immediate next steps
1. Check QA run 38988733315 result and job logs. If failed, diagnose/fix without touching stable branch or real data.
2. Run new Flutter migration test file in post-reconstruction context (CI) for old image preservation and all three selected choices.
3. Verify private APK signature/package/version and included images; provide direct download only if built successfully.
4. Ask owner to try on test device and share screenshots of edit gallery, each large portrait inside frame, and main profile. Owner approval required.
5. Save exact SHA/build/test outcome in `/DEDA/Project_Checkpoints` for chat recovery. Do not publish to Play without explicit approval.
