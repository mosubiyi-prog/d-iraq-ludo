# Bound social section preparation — 25 October 2026 Baghdad

Status: PASS. Source859a85a5469886b0153253784f4735cf48c48fec; CI40197265239 passed all five jobs on the first attempt. Original100380 source binding, default-off review configuration, no APK/deployment.

## Actual callsites changed

- `_DedaFriendsPageState._prepare`: calls the shared protected entry before publishing the existing original social session; existing failed-entry retry remains.
- `_DedaFriendRequestsPageState._prepare`: same protection, plus failure state/retry control instead of swallowing the error and leaving an indefinite loading indicator.
- `_DedaAddFriendPageState._prepare`: same protection, retaining its original preparation-failure message/search retry behavior.

`runDedaProtectedSectionEntry` uses the EXISTING `DedaAuthSessionController`; no extra gate, automatic retry, queue, sign-in implementation, permission cache or backend is introduced. It captures the canonical account key, the existing DedaPreferences account intent epoch and mounted/logged-in state. Return to the same account after A→B→A does not revive the old result. Existing runtime timeout ends waiting while retaining its lane until the original action settles. A second entry fails busy instead of repeating an outstanding SDK operation.

Readiness uses the existing policy: missing SDK user may enter anonymousPreparation and must still complete ORIGINAL owner/session proof; anonymous owner uses ownerRestore; authenticated admin cannot be silently converted by opening a personal section. The original appearance/progress/inventory and social-session preparation are checked through the existing wait hooks before/after awaits. Server ownership checks and original social profile/write behavior remain the authority.

Restore option `--section-entry` ensures the complete auth-runtime source binding is present, then applies exact source anchors. Runtime definitions DEDA_STABILITY_AUTH_RUNTIME=true and DEDA_STABILITY_SECTION_ENTRY=true enable the review path; absence keeps the section helper on the original preparation path. The section option composes with prior lazy sections. The requests retry UI is included in the generated source; it does not retry a purchase, grant, accept/reject/send or relation mutation.

## Verified checks

Python71/71 (69 previous +2 source-binding checks): three callsites, dependency/epoch/error path, combination with lazy sections, refused unbound/double binding. Flutter tests exercise delegated lane, competing entries, admin preservation, missing SDK with original proof required, account A→B→A, disposed screen, timeout with retained original operation, explicit retry after completed failure, and the ACTUAL friends/requests widgets showing retry rather than permanent loading with no logged-in owner. Controller cases use fake operations; actual-widget cases exercise failed initialization only, not real Firebase success.

## Scope and remaining acceptance

This binds the three entry preparations; it does not cover every section, their full stream lifecycles, notification markSeen, all account-switch display states, map/network policies or account data migration. No phone/tablet app acceptance or millisecond performance result exists from these tests. The configured signed review APK and full integration acceptance remain required. Existing financial/continuity/lazy-entry work is preserved. No production rule/service/account/balance or signing/platform setting changed. Unrelated local avatar artwork is excluded.

Checkpoint: checkpoint-stability-before-social-entry-guard-2026-10-25 at33f2eb518cf06100779a598fd14220e5c8f0d74e.

## CI result

https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/40197265239 — all5jobs passed. New protected-entry tests10/10:8 controlled-controller cases plus2 ACTUAL friends/requests failed-entry Widget cases, including tapping retry and confirming no permanent spinner. Strict analysis of the new module/test passed without issues. Python71/71; preserved UI38, auth/place94, prior lazy Widget8, reader/store28 and combined coordinator43 remain successful in applicable modes. Server regression Node388/388 and Emulator203/203 remains passing. No new native run was needed for these source-bound UI/gate changes; this is not native acceptance of the complete social success path.

The review build must restore the bound source and enable the required definitions; source success does not mean the APK installed on the owner's phone has changed. Other sections and full stream/lifecycle/account restoration acceptance remain open.
