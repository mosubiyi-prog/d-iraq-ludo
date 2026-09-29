# DEDA — Task Engine + Points System
Date: 2026-09-29

## Stable visual baseline
- Visual baseline: Build 217.
- Do not redesign the current Tasks page while implementing the engine.
- Task cards are fixed templates. Weekly content may change without changing the card layout.
- A task carries its own title, subtitle, icon, icon color/background, action type, completion rule and points.

## Core rule
The Tasks page is a viewer/launcher only. Completion is decided by one central Task Engine from real successful app events.

A task is NOT completed because its button was tapped. It completes only after the required action succeeds.

## Current scoring
- Every completed task: +5 points.
- Every correct traffic-guidance quiz answer: +5 points.
- Wrong quiz answer: +0.
- A weekly task awards its points only once for that weekly cycle.
- Total accumulated points never reset when weekly tasks reset.
- The Profile page already has the official "Points / النقاط" section; that is the single user-facing home for the accumulated balance.

## Canonical task events
Initial event names:
- map_opened
- current_location_shared
- registered_place_shared
- received_place_opened
- saved_place_opened
- added_place_reviewed
- traffic_quiz_completed
- long_trip_completed

Additional traffic event:
- traffic_quiz_correct_answer

## Completion examples
- "شارك مكانك الشخصي": award only after the location share is actually sent successfully.
- "شارك إدارة/موقع مكانك": separate from personal location share; award only after a registered place is shared successfully.
- "افتح الخريطة": can complete from any valid navigation path that truly opens the map, not only from the Tasks page.
- "افتح أي مكان تمت مشاركته معك": opening the inbox/list alone is not enough; a received share must be opened into the map/place flow.
- "زيارة مكان محفوظ": opening the saved list alone is not enough; a saved place must be opened.
- "مراجعة مكان مضاف": completion is tied to the real review/open action defined by the feature.
- One real user flow may complete more than one related task only when each task's own condition is genuinely satisfied.

## Identity and anti-duplication
- Every task has a stable taskId independent from its display text.
- Every weekly cycle has a stable weekId.
- Completion key = account + weekId + taskId.
- The same completion key can award points once only.
- Failed/cancelled actions never award points.
- Reopening/repeating an already completed weekly task never awards the same 5 points again.

## Weekly renewal
- Later, active weekly task definitions will be loaded from Firebase/Firestore.
- The app determines the active week and displays that week's content inside the fixed templates.
- Starting a new week creates a fresh progress cycle; it does not delete old history or accumulated points.
- The exact weekly rollover day/time remains configurable before production rollout.

## Data separation
Keep these concerns separate:
1. Weekly task definitions.
2. User weekly progress.
3. Accumulated points balance.
4. Immutable/append-only points ledger entries.

The ledger should explain every award, for example:
- +5 — current_location_shared — task:<taskId>
- +5 — traffic_quiz_correct_answer — question:<questionId>

## Reliability
- Local state may be used as a short offline cache.
- Cloud state is authoritative once backend rules are deployed.
- If a valid action succeeds while network sync fails, queue/retry the award instead of double-awarding.
- Point award and task completion should be committed atomically on the backend where possible.

## Implementation order
1. Preserve Build 217 and create a checkpoint before engine work.
2. Add central event/task model and stable task IDs.
3. Add safe local progress/points store for development.
4. Add backend transaction + Firestore rules for account-scoped progress and points.
5. Wire the first three events: map_opened, current_location_shared, received_place_opened.
6. Test event success/failure + duplicate protection.
7. Wire remaining tasks one by one.
8. Connect Profile "النقاط" to the real accumulated balance/history.
9. Add the 5-question traffic-guidance quiz and +5 per correct answer.
10. Add weekly Firebase task-definition rotation only after the engine is stable.

## Safety rule for this repository
- Avoid broad global replacements in lib/main.dart.
- Scope edits to unique classes/functions/markers.
- Create a checkpoint before each risky stage.
- Build and test a small stage before adding the next group of events.
