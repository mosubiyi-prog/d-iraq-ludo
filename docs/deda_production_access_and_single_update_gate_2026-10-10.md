# DEDA — Play Production access and unified update readiness (2026-10-10)

## Google Play milestone (user confirmed with screenshot)
The DEDA Google Play Console dashboard clearly displayed:
"Congratulations! Your app has been granted Google Play production access."
This is permission to submit a Production-track release; it is **NOT** confirmation that an APK/AAB is already available publicly or that the pending app version was reviewed/approved.

The owner is working on the other Google Play preparation steps in a separate ChatGPT conversation. Coordinate by citing this shared GitHub checkpoint. Neither this branch nor its QA workflows should upload to the store automatically.

## Owner-approved one-build scope
A single future signed internal APK for owner field testing, before Google Play Production AAB and review:
1. General-manager ON/OFF, auto-publish NEW full place submissions around 30 seconds after request; old requests remain manual and OFF restores manual.
2. General-manager ON/OFF, 10-second forgotten-PIN self-service via trusted prior installation secret (same original no-extra-step user experience); do not issue third-party PINs from phone/name alone, unknown devices fall back manual; WhatsApp/SMS phone OTP is intentionally deferred until real user scale.
3. Compact responsive DEDA administration dashboard cards; stop Arabic text overflow.
4. REAL Telegram social follow verification and real one-time 10-diamond user reward, separate from manager/admin gift wallet; bot admin, secure Telegram identity link, protected transactions.
5. RELEASE-BLOCKING REGRESSION added 2026-10-10: a rewarded ad showed "3 diamonds granted", but GM profile remained 999600. The old profile stat renders manager personal wallet INSTEAD of ordinary earned/gifted ad balance. Display-only fix should show manager-personal + ordinary earned/gifted while never changing wallet storage or administrative gift budget.

## Source, tests and build safety
Accepted installed internal rollback: 100327, branch deda-social-firestore-no-functions-100327-2026-10-09.
Only next release branch: deda-next-four-items-stage0-2026-10-10.
Policy tests, admin Flutter/rules tests and rewarded diamond helper tests passed as separately linked in project checkpoint.
A new NO-APK golden-reconstruction QA workflow tests the display fix AFTER rebuilding the actual golden app source, rather than only checking isolated math:
https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/38002271993
Wait for it to finish and review logs before claiming full golden reconstruction succeeded.

## Outstanding HARD GATES
- Cloud Functions cannot yet deploy in deda-25b88 because of Google Cloud billing/Cloud Build/Artifact Registry prerequisites encountered during 100326. Server-only auto-publishing and automatic PIN issuance must be deployed and genuinely tested; currently only source/QA.
- On/Off manager toggles remain OFF when trusted deployed worker status is absent. Do not show false green live indicators.
- Telegram Bot API membership verification, its bot/identity connection and backend wallet ledger are NOT live. Ten-diamond label is PREVIEW ONLY; do not credit for opening a link.
- The accepted APK 100327 has not magically gained any unshipped source fix; profile 3-diamond fix is next-release branch only.
- Even after a signed APK exists, owner MUST install/inspect a test copy; verify visible wallet before/after real rewarded ad, switched place approval timing and user PIN recovery, a test Telegram member/claim, manager display, tablet responsive UI, existing GPS/navigation, original eight tasks, daily-login rewards.
- Prepare a Play-ready .aab only after owner approval of the verified APK. Explicitly verify signing, increasing versionCode, security/Data Safety/privacy disclosures and Google Play review. Do not assume production is already live.

No production Firebase deploy, no APK/AAB or public release has been initiated by this checkpoint.
