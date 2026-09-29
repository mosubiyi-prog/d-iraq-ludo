# DEDA stop point — Build 221 — 2026-09-29

## Stable build
- Working branch: `task-engine-points-2026-09-29`
- Successful build: **Build 221**
- Build commit: `0e60d0dbbbbbcc1aa6db560ea1832175649fff27`
- GitHub Actions run: `36618790372`
- Artifact id: `11058336966`
- Artifact: `DEDA-Android-builds`
- Build 221 checkpoint: `checkpoint-build221-daily-reward-ui-2026-09-29`
- Pre-change checkpoint: `checkpoint-build220-before-daily-reward-ui-2026-09-29`

## Confirmed before Build 221
Build 220 was tested on device:
- Opening the map completed the “open map” task from 0/1 to 1/1.
- +5 task points were added.
- Profile points showed 5.
- Profile points dialog showed the real balance correctly.

## Build 221 changes to test next
1. Task text readability
   - Task cards slightly taller.
   - Task subtitles can use two lines.
   - Action buttons slightly smaller to free text space.
   - Goal: no clipped/unclear task descriptions.

2. Daily login reward
   - Daily login reward value is **10 points**.
   - Reward stays pending on the daily-login card until the user presses **استلام**.
   - Simply logging in must NOT add the 10 points.
   - Pressing **استلام** adds 10 points to the same profile points balance.
   - The same daily reward cannot be claimed twice on the same day.
   - After claiming, the button becomes the claimed/done state.
   - A compact **+10 نقاط** indicator is visible in the daily-login card.

3. Traffic task placeholder
   - The “اختبر مهاراتك” task remains in a fixed task slot with stable id `traffic_skills`.
   - The actual quiz question bank, traffic sign images, question rotation, and no-repeat logic are NOT implemented yet.
   - This fixed slot should be kept so the quiz can be added later without redesigning the task page.

## Points rules currently agreed
- Normal completed task: **+5 points**
- Daily login reward: **+10 points**, only after pressing **استلام**
- Correct traffic quiz answer: **+5 points**
- Traffic quiz completion task itself: +5 once the quiz is completed
- Profile points are accumulated in one balance.
- Weekly task renewal must not erase accumulated profile points.

## Immediate test when returning
Current known balance before claiming Build 221 daily reward is expected to be **5 points** on the test account/device.

Test in this order:
1. Install/open Build 221.
2. Open Tasks.
3. Confirm task texts are no longer clipped or unclear.
4. Confirm “+10 نقاط” is visible on the daily-login card.
5. Before pressing “استلام”, confirm profile balance is still 5.
6. Press “استلام”.
7. Open profile and confirm balance becomes 15.
8. Return to Tasks and confirm the daily reward cannot be claimed a second time.

## Next development stage after Build 221 passes device test
Prepare the permanent architecture so weekly task changes do not require a new Google Play APK:
- Keep task-card templates fixed in the app.
- Load weekly task definition/content from Firebase/Firestore.
- Use a stable `weekId` for each weekly cycle.
- Preserve old progress/history and start fresh progress for the new week.
- Keep the traffic-skills task as a fixed slot.
- Make the future traffic question bank updateable remotely.
- Use Firebase Storage for new traffic-sign images, with local fallback/basic assets where useful.
- Do not require a Play Store app update merely to move from week 1 to week 2.

## Safety rules
- Do not redesign the approved Tasks UI unless explicitly requested.
- Preserve exact patch-sensitive source markers used by GitHub Actions scripts.
- Avoid broad replaceAll edits in huge `lib/main.dart`.
- Make risky edits by uniquely scoped blocks only.
- Keep a checkpoint before and after risky stages.
- Build and device-test before calling a new stage stable.

## Stop status
**Paused here intentionally.**
Resume from Build 221 device test first. Do not start Firebase weekly-task architecture until Build 221 is confirmed on the phone.
