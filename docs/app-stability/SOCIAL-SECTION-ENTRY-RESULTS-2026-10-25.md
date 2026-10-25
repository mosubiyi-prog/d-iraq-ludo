# Bound social section preparation — 25 October 2026 Baghdad

Status: local Python71/71 passed; Flutter and source CI pending. Original100380 source binding, default-off review configuration, no APK/deployment.

## Actual callsites changed

- `_DedaFriendsPageState._prepare`: calls the shared protected entry before publishing the existing original social session; existing failed-entry retry remains.
- `_DedaFriendRequestsPageState._prepare`: same protection, plus failure state/retry control instead of swallowing the error and leaving an indefinite loading indicator.
- `_DedaAddFriendPageState._prepare`: same protection, retaining its original preparation-failure message/search retry behavior.

`runDedaProtectedSectionEntry` uses the EXISTING `DedaAuthSessionController`; no extra gate, automatic retry, queue, sign-in implementation, permission cache or backend is introduced. It captures the canonical account key, the existing DedaPreferences account intent epoch and mounted/logged-in state. Return to the same account after A→B→A does not revive the old result. Existing runtime timeout ends waiting while retaining its lane until the original action settles. A second entry fails busy instead of repeating an outstanding SDK operation.

Readiness uses the existing policy: missing SDK user may enter anonymousPreparation and must still complete ORIGINAL owner/session proof; anonymous owner uses ownerRestore; authenticated admin cannot be silently converted by opening a personal section. The original appearance/progress/inventory and social-session preparation are checked through the existing wait hooks before/after awaits. Server ownership checks and original social profile/write behavior remain the authority.

Restore option `--section-entry` ensures the complete auth-runtime source binding is present, then applies exact source anchors. Runtime definitions DEDA_STABILITY_AUTH_RUNTIME=true and DEDA_STABILITY_SECTION_ENTRY=true enable the review path; absence keeps the section helper on the original preparation path. The section option composes with prior lazy sections. The requests retry UI is included in the generated source; it does not retry a purchase, grant, accept/reject/send or relation mutation.

## Verification planned

Python71/71 (69 previous +2 source-binding checks): three callsites, dependency/epoch/error path, combination with lazy sections, refused unbound/double binding. Flutter tests exercise delegated lane, competing entries, admin preservation, missing SDK with original proof required, account A→B→A, disposed screen, timeout with retained original operation, explicit retry after completed failure, and the ACTUAL friends/requests widgets showing retry rather than permanent loading with no logged-in owner. Controller cases use fake operations; actual-widget cases exercise failed initialization only, not real Firebase success.

## Scope and remaining acceptance

This binds the three entry preparations; it does not cover every section, their full stream lifecycles, notification markSeen, all account-switch display states, map/network policies or account data migration. No phone/tablet app acceptance or millisecond performance result exists from these tests. The configured signed review APK and full integration acceptance remain required. Existing financial/continuity/lazy-entry work is preserved. No production rule/service/account/balance or signing/platform setting changed. Unrelated local avatar artwork is excluded.

Checkpoint: checkpoint-stability-before-social-entry-guard-2026-10-25 at33f2eb518cf06100779a598fd14220e5c8f0d74e.
