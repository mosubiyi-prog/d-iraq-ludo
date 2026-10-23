# DEDA 100380 — six-note repair checkpoint

Owner explicitly authorized careful implementation after final badge clarification. Started from signed 100379 source, with backup branch `backup-deda-100379-before-six-notes-2026-10-23`; work branch `deda-100380-six-notes-fixes-2026-10-23`.

1. Badge: approved original RGB sheet remains byte-for-byte unchanged. New display alpha mask removes exterior background only. Existing 58px profile geometry and position retained. All six ranks need rendered visual QA.
2. Paid frame button: one-line scaled label and explicit padding in 42px button prevent price clipping at narrow 96px cells and larger text. Native 1000 price and checkout unchanged.
3. Editor ID: existing UID-scoped verified owner identity resolver now feeds current-ID card. Removed stale separate-activation message.
4. Equip: fresh owned receipt check -> account appearance save -> server readback of selected styles -> main profile notifier. No purchase or wallet callback in equip. Owned paid frames first under avatars; verified owned cards lose lock and active button reads مستخدم. Failed/changed-account/unknown confirmation cannot report success. Original preference keys preserved; stale same-account restore invalidated by revision.
5. Public preview uses same verified owner identity. Received location sender label subscribes to minimal public active-alias projection with UID and server-metadata guards. Canonical saved sender/recipient IDs and map routing unchanged; existing public verified resolver still accepts active alias for send/receive. Read-only live check confirmed AQPYXJ -> IRAQI and reverse route both exist with correct four-field schema. Actual two-device sending/receiving requires owner QA with the new APK installed on both devices; do not claim this has been device-verified.
6. Admin user listing groups session records under stable accountKey (phone fallback for legacy); canonical profile createdAt determines descending first-registration order. Latest session supplies current display metadata only. No deletions, login changes, account writes or changes to permissions.

Initial isolated test run: analyzer no blocking errors, 29 tests passed; two editor tests could not find original legacy PNG assets in the shortened source reconstruction. QA workflow updated to extract ONLY exact artwork from the previously signed 100379 APK. No keys/signing contents exported.

Delivery pending: full regression + six-rank pixel/visual QA, signed 100380 build, same-certificate verification against 100379, Android16 previous-to-new install and cold launch. No Play upload or Firebase rule deployment is part of this six-note build. Existing successful wallet/avatars/ranks/admin200 behavior preserved.

Previous signing-material export incident remains disclosed in the earlier 100379 report. This phase never exports Android/signing files, and retains the existing certificate for an installable update. Any future signing change requires separate review.
