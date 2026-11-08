# DEDA Stage 8 — Independent Android Google UID device lab (NOT DEDA)

Status: **SOURCE/QA ONLY**. This is a separate Flutter application,
Android package **com.deda.qa.uiddevice**, NOT the original published
**com.diraq.ludo.d_iraq_ludo**. The production app project is **deda-25b88**.
No Firebase project was created, no Google OAuth was exercised on physical
devices, no APK was built, and no Google Play submission was made by this work.

## What this tests, and what it deliberately cannot test

The goal is to verify in the future, using TWO physical test devices and
ONE dedicated Google test account, that Google login to a SEPARATE Firebase
QA project leads to the **same Firebase Auth UID** on both devices.

The app displays only a short SHA-256 UID fingerprint. It does NOT handle
DEDA phone registration, six-digit PIN, friends, ID, admin, Firestore,
diamonds, gifts, weekly league, restore, or migration. A successful
Google login is **not proof that the user owns a typed phone number**.
It never attempts to fix historical A/B/C identities.

The app is blocked at launch if the special QA Firebase project config is
missing or looks like the DEDA production Firebase project. It never
initializes Firebase Auth before the guard and a tester's explicit tap.

## Required independently provisioned environment

* A NEW Firebase project dedicated to test use. Its project ID must
  begin with **deda-qa-uid-lab-** followed by 4-40 lowercase letters,
  digits or dashes. Do not reuse **deda-25b88**.
* Register an Android app with package **com.deda.qa.uiddevice** in
  that QA project. Android OAuth signing certificates must match the
  **test debug signer** on the devices/builds.
* Enable Google as the sign-in provider **only in the QA Firebase Auth
  project** and create/associate the corresponding Web OAuth client ID.
* Use a Google test account that has **no DEDA account relationship**.
  The test must not use the owner's original logged-in DEDA phone
  or original user's credentials.
* Do not use live DEDA Firebase Rules, production google-services.json,
  actual phone/PIN, production signing key or user data.

No QA project, Android SHA fingerprints, OAuth clients or private
credentials were provisioned by this stage; those steps cannot be inferred.

## External configuration contract

Create a JSON file OUTSIDE this repository, with these keys (placeholders,
not values):

```json
{
  "LAB_QA_PROJECT_ID": "deda-qa-uid-lab-youruniqueid",
  "LAB_QA_FIREBASE_APP_ID": "1:YOUR_QA_SENDER_ID:android:YOUR_QA_APP_HEX",
  "LAB_QA_SENDER_ID": "YOUR_QA_SENDER_ID",
  "LAB_QA_API_KEY": "YOUR_QA_FIREBASE_API_KEY",
  "LAB_QA_GOOGLE_WEB_CLIENT_ID": "YOUR_QA_WEB_OAUTH_ID.apps.googleusercontent.com"
}
```

Never commit the JSON file and never send tokens/Google account passwords
to ChatGPT or GitHub. Those values are build-time QA config; the QR,
OAuth identity, real Google user and Auth ID token remain on your devices
and isolated QA Firebase project.

Validate locally:

```bash
python3 qa/stage8_uid_device_lab/tools/preflight_qa_config.py \
  --repo-root . --config /outside/repo/your-qa-config.json
```

The validator checks that none of the QA project/app/API/OAuth IDs match
the root repository's original production google-services.json. It never
prints Firebase keys.

## QA test signature guard — approved on 2026-11-09

The owner approved preparation/build of an isolated QA test APK only. The
registered QA Android SHA-1 is `D7:7C:C5:49:40:B4:1D:BF:56:74:45:98:7A:1D:C9:EF:24:12:EB:39`.
The separately backed-up QA debug keystore has alias `androiddebugkey`.
It is **not** the DEDA production signing key.

The build script now requires the **operator-local** environment variable
`DEDA_STAGE8_QA_SIGNING_KEYSTORE` to point at the dedicated QA key file
**outside this Git repository**. It verifies the key SHA-1 before building,
re-signs the generated Android **debug** APK with the QA key, then uses
`apksigner verify --print-certs` to reject any mismatched output.
The debug-key passwords are used only locally; never put this keystore,
a QA Firebase config JSON, Google tokens, or production secrets in GitHub.

The current development environment does not have the Flutter SDK; QA CI
passes source/guard tests but does **not** produce a signed APK. Do not
describe a test APK as built until an approved Flutter/Android SDK runner
has executed the script with the separate QA configuration and signing key,
and the resulting APK has passed signing verification.

## Owner-approved test APK procedure — NOT EXECUTED

Only after an explicit separate QA build approval and after the distinct
QA Firebase project has been provisioned, from the repository root:

```bash
DEDA_STAGE8_OWNER_APPROVED_QA_BUILD=YES_STAGE8_QA_ONLY \
DEDA_STAGE8_QA_SIGNING_KEYSTORE=/outside/repo/deda-uid-qa-debug.keystore \
  bash qa/stage8_uid_device_lab/tools/prepare_qa_android_apk_EXPLICIT_OPT_IN.sh \
  /outside/repo/your-qa-config.json /outside/repo/qa-output
```

The script creates a NEW Flutter Android project in a temporary directory,
validates its **actual Android applicationId**, refuses a production config,
runs tests, and creates a **debug** QA APK outside this repository. It
never uses the original DEDA signer, never installs an APK automatically,
and never calls Firebase deploy or Play publishing.

### Future device A / device B acceptance run

1. Record that normal DEDA on the owner's phone is left untouched; use
   two separate test devices, or separately approved clean test profiles.
2. Install **only the QA lab Android package**, never overwrite DEDA.
3. Tap Google chooser and pick the SAME pre-arranged test Google account
   on both. Check the app reports QA_GOOGLE_UID_VERIFIED_NO_DEDA_ACCOUNT_CREATED.
   Fingerprints must be identical; exact UID must match within the QA
   Firebase Auth console.
4. Select another test Google account, verify the fingerprint differs.
5. Exercise Google chooser cancel, multiple Google accounts, network
   interruption, app restart, expired session and rapid repeated taps.
6. Verify the QA Firebase project has only QA Auth users, that original
   Firebase project and DEDA apps were untouched, and remove the QA
   package on test devices if desired.

If a Google sign-in fails because SHA/OAuth/project config is missing,
**STOP** and correct the QA project only — never point the lab to production.

### Known limitations

This stage's automated tests check that the isolated Android source is
well-formed, separate, and blocked without config. They cannot assert
that Google's actual account chooser or OAuth flow has worked on a
physical Android phone. No claim of real Google login success should be
made until the device test has been run and observed. A Firebase project
naming convention is a local safety guard, not a substitute for actual
Firebase IAM/project verification.

Production user accounts, PIN login, the admin gateway, wallets, identity
IDs, gifts and weekly rewards remain outside the scope of this lab.
