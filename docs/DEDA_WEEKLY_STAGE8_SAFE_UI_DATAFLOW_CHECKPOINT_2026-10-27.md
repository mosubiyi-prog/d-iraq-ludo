# DEDA weekly leaderboard — stage 8 tested fixed-screen dataflow checkpoint
Date: 2026-10-27 | Source-only development | **NO APK / NO FIREBASE / NO PLAY DEPLOY**

## Accepted owner requirements — DO NOT CHANGE
- Preserve signed DEDA 100387 accepted on the phone/Play Protect. Immutable base: `a0dd340e8843162ac5fb89784cb54d0be82b23ec`.
- The owner's one navy/gold leaderboard image is the ONLY approved design reference: same layout, podium, rows, personal position, prize information, spacing and relative sizes. No page or internal list scrolling. Scale to display the entire page across device sizes without clipping.
- Completely remove the Restaurants shortcut/card and its home action in both restored-home layouts; put the Leaderboard shortcut in its exact place. Restaurant search remains available on Map.
- Weekly score counts **only verified LEVEL XP earned from claiming daily task rewards**, **20 XP per successful task claim** in actual verified 100387 source. Ordinary 5 task points, 10 login points, 5 per correct traffic answer are NOT standalone level XP. XP write might fail independently; an ordinary task award is not proof of earned XP.
- Rank current/previous weeks, show actual top 10 plus own personal rank beyond top 10, dynamic updates, gold "النقاط المكتسبة", and prizes 150/100/50/10x7 = 370 diamonds weekly, once only. Lifetime XP, level and wallets never reset or change from a weekly rollover. No display of users' private phone, UID or installation ID.

## Done in new isolated stage8 branch
Branch: `deda-weekly-leaderboard-stage8-safe-ui-dataflow-no-deploy-2026-10-27` branched from passed stage7. No changes to the original checked-in app code.
- `lib/deda_weekly_leaderboard_safe_screen.dart`: guarded, fixed-layout screen shell backed by the already tested Flutter server snapshot DTO.
- Defaults to **NO injected backend loader**, so network is never contacted and results stay explicitly "pending verification" instead of showing counterfeit ranking data.
- If/when a reviewed verified remote loader is supplied later, it decodes only the privacy-redacted current + previous server leaderboard pair; rejects malformed, client-forged or absent responses.
- The screen discards late results if user logs out, changes phone/account or loses session authorization. A throwing account guard fails CLOSED.
- Optional already-existing XP ValueNotifier refresh and optional future authorized polling (minimum 15s) support dynamic ranking once a REAL approved server exists. All refresh and app-resume subscriptions/timers are disposed safely.
- `tools/app_stability/bind_weekly_leaderboard_stage8.py`: upgrades exactly two stage2 restored home routes to open the safe screen and copies ONLY the new pure Flutter UI/DTO. Does not edit task, level, quiz, backend, admin, Firestore, Firebase, monetary files or the 100387 original. Rejects direct repository modification or second application.
- `tools/app_stability/tests/test_weekly_leaderboard_stage8.py`: actual immutable source restore with existing DEDA auth/progress/task binders, then stage2 restaurant tile replacement, then stage8 safe route. Confirms both home routes, no legacy restaurant quick tile and byte-identical original account/quiz/social/pubspec files.
- `test/deda_weekly_leaderboard_safe_screen_test.dart`: no endpoint means no fake users, single non-scroll screen on 320×568 phone, valid safe score, logout race rejects late data, forged result rejected, XP-notifier read refresh, bad account guard rejected.
- `.github/workflows/qa-deda-weekly-stage8-safe-ui-dataflow-no-deploy.yml` runs immutable original 100387 diff guard, restored workspace integration, regression backend tests, Flutter analyzer and actual widget tests.

## Verified QA
Stage7 read-only snapshot server/frontend PASS:
https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/40538972983

Stage8 guarded UI + restored home route + widget QA final PASS:
https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/40540790530

All preceding experiment code remains NOT DEPLOYED. A first stage8 widget test mis-expected one display of the first-place user when correctly visible twice in the podium and own rank card; adjusted test, then full GitHub Actions PASS. This was a test expectation, not user-facing UI regression.

## Critical not-yet-done (don't label finished)
1. **Actual trusted Cloud XP issuer**: backend must validate each daily task proof and authoritative credit of 20 LEVEL XP. DEDA's current approved task XP lives locally; a client-provided success bool or visible XP is not reliable financial competition proof. Need integration with server-owned identity and progress ledger, without losing existing balances on a new phone.
2. **Actual approved identity attestation** for same canonical account after phone/UID rotation; prior stage6 code models future server document but does not issue it. No unjustified new Firebase rule deployment or phone migrations.
3. **Production weekly ranker + trusted config**: previous week/current week seven-day boundaries must be owner-approved, stored centrally, and emit privacy-safe server-issued snapshots. The stage7 Flutter decoder and stage8 screen are prewired DATA contracts, not connected live endpoints.
4. **Real spendable diamond wallet transactions**: confirm production wallet and identity; grant 370 total to 10 eligible finishers atomically once per week, unique (weekId, canonicalAccountKey), with replay protection and audit. Preserve GM personal/test/gift wallets and don't use any local test balance.
5. **One signed private APK** including ALL user-approved changes only after backend security/rules and emulator tests; owner phone checks real users, pixel spacing vs original screenshot, no scrolling, Play Protect and task/level/account regression. No public Play deployment without separate owner decision.

No endpoint exported into `functions/index.js`. No firestore.rules update, account/XP/diamond change, install or production release. Stage8 acceptance: **CODE & TESTS PASS; LIVE WEEKLY BOARD + DIAMOND PAYOUT + APK NOT COMPLETE**.
