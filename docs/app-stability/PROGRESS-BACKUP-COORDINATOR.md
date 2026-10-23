# Pending evidence backup coordinator — not activated in the app

24 October 2026, Baghdad. This composes existing local capture and server evidence APIs; no live callsite is enabled and it does not restore balances.

## Data flow

1. Verify the current anonymous SDK principal, account session and users account from server metadata, with the same installation and account-intent epoch.
2. Read the account-scoped pending journal. If it exists, retain the exact previous intent, even if local data or the proposed ID has changed.
3. Otherwise read the three existing financial progress source records without altering them and write/read back an immutable request in `deda_progress_backup_pending_v1_<accountKey>`.
4. On explicit upload, prove the account again and read the exact server capture first. A network/cache/security/proof error never authorizes resubmission. Only an authoritative missing capture permits save, and only for the same original UID/install.
5. Compare full raw capture and source UID/install with server readback. Only then compare/remove the SAME pending journal record. No source progress preference is deleted or applied. Return whether pending cleanup succeeded separately from the verified evidence.

A lost write response leaves the journal available after coordinator recreation/restart. A new UID of the same verified account may reconcile a previously committed capture, preserving its original provenance. A missing capture from an old UID/install is held rather than relabelled or silently replaced. That unresolved-origin case needs a future reviewed recovery policy; no automatic loss or financial acceptance is hidden behind a success state.

One coordinator lane remains busy until the original asynchronous work settles, including after UI timeout. Expiry prevents further dispatch and success publication; an already-dispatched write can still commit. Its journal stays for later server reconciliation. There is no retry loop or SDK sign-in/out.

## Storage and proof boundaries

The real SharedPreferences journal serializes mutations across its instances IN ONE ISOLATE; it is not a multi-isolate/process CAS and must not be wired as one. Concurrent different requests conflict rather than overwrite a pending record. Native disk persistence and Firebase plugin transport still need integration/device validation. A plugin successful boolean/readback and a mocked preference test are not a power-loss durability guarantee.

The evidence store now verifies users.accountKey as well as the existing deda_sessions/UID/install proof. Cached/pending absence is rejected BEFORE treating a capture as server-missing; missing owner documents yield a proof error, never the capture-not-found signal. These checks do not replace server security rules.

Only three scoped financial source texts are captured. They remain UNTRUSTED evidence; this is not verified balance, legacy baseline approval, SSV/provider verification, purchase ownership or automatic restore. General device favorites/private places/drafts are explicitly excluded. The coordinator does not take a transaction-consistent snapshot of three concurrently changing preference keys; real producer quiescence/event versions remain required before financial approval.

## Validation status

Local Python restoration tests: 17/17, including exact original main/Backend/PinAuth preservation and refusal to add platform/rules configuration. CI run [40038151995](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/40038151995), source dcee8c023aa2d81f9675c7194d38a2858cdc5d91, passed all four jobs. Decoded logs confirm 29/29 coordinator/journal cases and 40/40 evidence-store cases, strict analysis without issues, and 17 restoration tests. All previous groups remained green (including 78 Node and 72 emulator cases). The inherited 181 main source issues remain. Full numeric summary: BACKUP-COORDINATOR-QA-2026-10-24.json. Existing build/signing workflows, main/Backend/PinAuth, runtime source snapshot, Firebase rules and account data are unchanged. `--progress-backup-coordinator` adds the module and its six archive/owner dependencies to a disposable QA source tree only. All previous checks remain in the workflow.

## Next activation prerequisites

Actual Firebase transport/rules merge test; account-intent and SDK observer lifecycle wiring; stable capture-ID factory and a shared application instance; defined treatment of origin-changed pending requests; real producer synchronization for coherent capture; nonfinancial account-aware data store/adoption; verified legacy baseline/event cutover; then bounded app pilot and two-device acceptance. No APK, deployment or production data change is part of this commit.
