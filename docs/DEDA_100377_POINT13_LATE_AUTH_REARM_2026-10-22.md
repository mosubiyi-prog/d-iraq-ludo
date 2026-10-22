# DEDA Point13 — late Firebase activation in owner premium identifier, safe fallback
2026-10-22; development branch only; source test running.

## Confirmed source defect
Prior DedaQa32ActiveAccountScope.initState returned without subscribing to
DedaStage71ActiveIdRefresh whenever Firebase.apps was empty. If the account
page mounted before initializeApp, it could never refresh automatically on
later sign-in or owner alias notification: it displayed original ID forever,
even on an otherwise authorized account.

## Source repair
Commit 0f9e170d: lib/deda_qa32_active_account_scope.dart
- Register original ID/active owner notifier unconditionally and listen for
  new authenticated sessions once Firebase becomes ready.
- Reattach when dependencies update, owner ID changes or app resumes. All
  old async results are protected by _epoch + original ID + current UID.
- On unverified/offline/mismatched identity continue canonical original ID
  fallback, rather than trusting previously cached premium account labels.
- Cancel auth stream and observer on dispose.
- No backend rules, 200 manager grants, wallet, points, order or level changes;
  premium switches remain safely OFF until independently verified permission.

Commit a46b35e6: source-only regression in
test/test_deda_100377_point13_all_surfaces_source.py confirms lifecycle rearm,
owner UID/source checks, and no local alias bypass.

## Verification and rollout
Earlier merged Point12 exact reconstructed source CI:
https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/39821521013 SUCCESS.

New Point13 + all 13-point source-gated regression:
https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/39823520219
Check final status. A successful source QA is NOT two-account phone/tablet
acceptance and NOT a mandate to publish any previously unverified 200 IDs.

## Exact owner six rank badge reference saved locally
The owner provided 1536x1024 3x2 six-tier badge image (gold, silver, emerald,
diamond, royal, legendary). Six 512x512 image-panel crops were saved in
working environment as /mnt/data/DEDA_6_LEVEL_BADGES_OWNER_REFERENCE_2026-10-22.zip.
Those cropped reference files are NOT yet in GitHub app assets and have
NOT been integrated or granted. Library backup upload was prevented by the
user's library storage quota; originals are still present in conversation.
No substitute badge paintings were created.
