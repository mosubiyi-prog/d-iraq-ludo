# Location identity and GPS account continuation — 25 October 2026 Baghdad

Accepted within the scope below. Not final owner delivery.

Source: `df9760ab580546973640a595ca277d653190cc8d`.
Checkpoint: `checkpoint-stability-before-location-identity-2026-10-25` at `fec11fb055f08feabfbe04d1abaf19c535c60135`.

## Behavior

- Share and received-location identity loading captures the page account epoch, phone, name and account type before asynchronous preparation. It uses the existing complete auth lane and rejects stale results, errors and finalizers.
- Sending snapshots recipient/options/IDs/name before GPS. A changed account, logout, page disposal or changed SDK principal cannot continue into sending for a different account. GPS permission dialogs remain outside the auth lane; the existing plugin request timeout is retained.
- Sending and task recording use one existing lane. Backend rules, expiry, alias routing, deliberate repeated shares and existing reward behavior are retained. No retry or new financial activation.
- This does not complete all received-page actions or subscriptions, financial restoration, secondary-data synchronization or remaining application sections.

## Evidence

- [Source QA](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/40227881219): all five jobs passed; Python88. New actual-page widget cases5/5 and strict analysis passed: same-account recipient validation; changed-account rejection; logout rejection; same-account GPS continuation; changed-account GPS continuation. These use no Firebase app and a mocked Android GPS channel, not live account writes.
- [Signed app pair](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/40227881356): control and candidate passed compilation, exact source/package/configuration/artwork and original certificate checks.
- [Offline Android16](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/40228298195): both exact APKs passed three launches and in-place update with external IPv4/IPv6 blocked before launch. Both login screenshots reviewed. No observed fatal signature.

Artifact12612382964 ZIP SHA256: `d6096eb8f48160d4b0414d32f1bc52a5f148e7b5d276eb32e650199fb5f2e7af`, downloaded and verified.
Control APK SHA256: `c6cb56af41b3086b283bbf0cc9f48aca4a2ddf829fbe8f29831e56e1e655b649`.
Candidate APK SHA256: `703c9faf363190a5f32b0f0788e1efff893deddf988e6f68f6d816bbb6099d6a`.
The raw result is `LOCATION-IDENTITY-NATIVE-RESULTS-2026-10-25.json`.

Android timings measure logged-out Activity launch only. They do not establish authenticated-section speed, complete device migration, physical phone/tablet acceptance or final delivery. Financial restore remains off. No production deployment or live account/balance mutation.
