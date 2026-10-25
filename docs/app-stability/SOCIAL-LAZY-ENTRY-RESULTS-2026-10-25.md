# Social hub entry: defer hidden tab initialization — 25 October 2026 Baghdad

Status: Python69 passed locally; Flutter/source CI pending. Review opt-in, not a released app or measured phone speedup.

## Concrete source behavior

The original100380 SocialHub mounts five children in IndexedStack when entering the profile/social section. Friends, incoming requests and add-friend each start dedaEnsurePersonalSocialSession from initState; style starts its three-way wallet/inventory load. These start even though the initial selected page is only the profile. These are actual source callsites, not a claim about exact RPC totals or observed milliseconds.

`DedaLazySectionStack` keeps the original fixed slots and mounts only the selected child initially. Each tab mounts on first selection, then retains its State on later switches just like a previously mounted IndexedStack child. Parent configuration changes propagate; closing the host disposes visited children. Unvisited children never enter initState. The disabled path mounts all five children, preserving original behavior. There is no identity/permission cache, auth operation, timer, wallet write or new subscription in this container.

The exact-source restore option `--lazy-sections` changes only the social hub stack name/explicit flag and adds an import/module. Python verifies that reversing those exact edits restores byte-identical main and refuses drift/double application. It composes after existing auth/backup/startup bindings without removing them. Default restore remains immutable. Runtime define DEDA_STABILITY_LAZY_SECTIONS is false by default; measured-pilot QA opts in.

## Important behavior boundary

The hub-wide incoming-request notification watcher remains in its original place. Existing tab callbacks and children are unchanged. IncomingRequestsPage.initState, including its markCurrentIncomingSeen side effect, now runs only when that page is first visited; it no longer marks requests seen merely because a hidden tab mounted during profile entry. Wallet/inventory initialization in the unvisited style tab is deferred until that tab opens. After visiting, hidden pages remain mounted and their existing subscriptions are not suspended by this change. This is deferred startup, not a global network cache or a guarantee that every app section is faster.

## Validation and acceptance

Python69/69 (66 previous +3 binding checks). Planned Flutter Widget checks cover initial1 versus original5 probe-State initializations, first visit/revisit state, live parent inputs, direct request-tab jump, disposal, opt-in toggling and fresh reopening. These are mount-count and retained-state assertions, not Android timing or live Firebase tests. The source QA checks the actual restored main under the enabled define and preserves existing account/ownership/UI tests.

A measured before/after on the same Android device and a review APK are still required to claim user-visible speedup. Use identical source base and comparable network conditions; report actual timings when available, not fake-clock or CI duration. No whole-app performance claim or completion of account restoration follows from this step.

All previous financial/auth/account continuity work is retained. No Firebase rules/Functions, production account/balance, Android/signing configuration or APK is changed. Unrelated local avatar artwork is excluded. Checkpoint before: checkpoint-stability-before-social-lazy-entry-2026-10-25 at cced3397f9a4ffb6c8e45e2195e313a40e166ed4.
