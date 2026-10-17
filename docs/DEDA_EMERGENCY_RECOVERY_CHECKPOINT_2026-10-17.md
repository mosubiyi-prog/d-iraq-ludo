# DEDA emergency recovery checkpoint — 2026-10-17
## Owner's priority
STOP new frames, royal avatars and premium ID work. Restore opening the application without deleting or resetting phone data. A second, separate future task is to audit account recovery after uninstall/change of phone. Do not bundle the two efforts.

## Verified source and builds
- Repo: mosubiyi-prog/d-iraq-ludo
- Last owner-tested baseline before profile experiment: 100340, branch `deda-100340-play-aab-owner-review-2026-10-15`, head `b9c2181ac01ef942e05bcdbcf40ce0dbeb34e5c9`. Signed AAB GitHub Actions run 38666295959 succeeded, but that does not prove every phone state.
- Broken on owner device: 100347 signed private APK (run 39047547635, successful build/CI), generated from 100342 feature source; it does **NOT** include startup gates/diagnostics introduced in 100345/100346.
- Owner has tested reboot, force-stop, cache clear (0 bytes), and installing 100347 again. App stays on green Android launch logo for >= 60 seconds.
- Owner created Android bug report but raw ZIP was not reviewed; do not claim that its contents establish any root cause.
- Prior on-device 100345/100346 diagnostics were described as failing during account restoration / opening local storage, but the exact underlying exception and reason are **not verified** in this checkpoint.
- 100346 read-only avatar migration and nonblocking startup scripts are on branch `point7-compact-ids-sticky-preview-frames-2026-10-17`, and are NOT part of 100347. Avoid blindly transplanting patches.

## Non-negotiable safety
- Do not ask the owner to uninstall, clear app storage, sign out, or downgrade 100347: uninstall may destroy local user data including task history, avatar/frame selections, auth/session and wallet state; Android usually rejects over-install of lower versionCode.
- Never publish to Play, deploy Firebase, mutate production rules/data, or change package/signature automatically.
- 100340 owner-tested baseline must remain unmodified. Only work on this isolated branch.
- The repo's raw `lib/main.dart` is not the finished APK's assembled source. The 100340 signed-build workflow reconstructs the tested main.dart. Review **assembled** source in the workflow.
- Any candidate installed as an in-place update must have versionCode >100347, matching package and compatible signing; analyze/test its behavior (including with pre-existing user data) and inspect Android launch before claiming fixed.
- Preserve all account, UID, local prefs, task, diamond, maps, friends, and owned-place data. Do not migrate/reset user data without a verified rollback and ownership path.
- No new features. Don't issue a fresh APK solely because GitHub CI passed: CI does not validate actual user-device launch.

## Next engineering steps
1. Trace original 100340 cold boot and SharedPreferences/Firebase startup, compare 100341-347 reconstruction/changes. Review crash evidence if safely obtainable without another long user workflow.
2. Build an isolated no-reset nonblocking startup/diagnostics patch on 100340 pipeline if necessary; explicitly preserve original user prefs, and fail visibly and recoverably rather than showing a permanent Android launch splash.
3. Run relevant Flutter tests, emulator instrumentation where available, compare generated source, signing and APK. Ideally test on a separate QA device/Android emulator with an existing local-data fixture.
4. Only offer owner ONE clearly scoped, data-preserving in-place QA update after evidence checks. Do not equate build success to launch success.
5. Separately audit cloud-vs-local retention/recovery for each user resource; never promise full restore after reinstall before end-to-end tests.
