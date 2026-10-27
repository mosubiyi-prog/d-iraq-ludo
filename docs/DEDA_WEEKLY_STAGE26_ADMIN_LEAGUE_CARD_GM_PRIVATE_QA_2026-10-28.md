# DEDA Stage26 — Dedicated league management card INSIDE original administration (private, no deploy)

Date: 2026-10-28
Parent branch: `deda-weekly-stage25-monthly-top10-admin-history-shadow-no-deploy-2026-10-28`
Parent SHA: `dba173c55f8a350b40c9f28966a3a41ca522c96d`
Protected work branch: `deda-weekly-stage26-admin-league-card-gm-gated-private-no-deploy-2026-10-28`

## What is implemented in source
- Inside the original `lib/admin_pages.dart` administration dashboard, add one compact navy `إدارة الدوري` tile in the existing responsive 3-column phone / 4–6-column tablet grid, using the original admin card widget without changing other cards.
- The tile is visible **only** when the trusted original admin profile reports `general_manager` **and** `active` status. This is not delegated to the public user screen or new permission keys.
- Opening the tile routes to `lib/deda_admin_league_page.dart`; the destination rechecks current admin profile `forceRefresh: true` and refuses to display the page on missing/expired/inactive/non-manager access. It also rechecks on app resume. No data is queried during denied states.
- Authorized manager sees a **clearly labelled PRIVATE QA placeholder** with these six agreed sections: launch/stop control, top-10 rankings, podium top 3, weekly history and monthly archive, planned weekly prizes, and blocked reward settlement explanation.
- Start/stop buttons are **actually disabled**, not mock toggles that misleadingly imply a live league. Ranking lists do NOT contain fabricated player names, scores or accounts. Weekly prize amounts are the previously approved **150/100/50/10×7 = 370 diamonds maximum** (when there are 10 winners), visibly noted as uncredited proposed amounts.
- The Stage25 monthly archive is already a separately tested server-side *prototype*, NOT an active admin database. This stage does not pretend a production manager archive already exists.

## What is NOT complete / launch remains BLOCKED
- Real server-owned XP task issuer, same-account cross-device identity, real ranked players and owned frames, authenticated public profile/friend action callbacks, read-only server snapshots, real general-manager-only Firestore collection rules and monthly archive persistence, audited spendable earned-wallet payout, duplicate-safe real settlement, and real 2-device owner acceptance.
- Stage26 is intentionally an admin UI/router stage only; manager live toggle and prize payout **must stay disabled** until every backend gate is separately proven and explicitly approved.
- No `functions/index.js`, `firestore.rules`, `lib/main.dart`, profile, map, tasks, friends, level XP, balances or wallet changes. No APK/AAB creation, real user writes, Firebase or Play deploy.

## Automated QA
Workflow `.github/workflows/qa-deda-weekly-stage26-admin-league-card-no-deploy.yml` checks the exact admin entry and role/status gate, reauthorization, no-write and protected-core changes, builds the new widget in an **isolated Flutter harness** with a compile-only stub for existing `DedaBackend`, and tests Arabic sections, truly disabled controls, honest reward labels and three Android phone/tablet viewport sizes. The stub DOES NOT replace the original DEDA backend in any repository source or shipping app.

Even green CI means **only safe private manager UI validated**, not real admin authentication integration or Play launch.
