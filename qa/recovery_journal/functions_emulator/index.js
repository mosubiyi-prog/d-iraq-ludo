"use strict";

// DEDA 100436 QA ONLY. Copied at runtime to RUNNER_TEMP, never to
// functions/index.js, never deployed, never a production App Check bypass.
//
// Real HTTPS callable transport receives a REAL Auth Emulator ID token,
// decodes it through Firebase Functions Emulator, and then uses the original
// candidate issuer with a FAKE QA app context. The emulator test verifies
// Firebase Auth + Functions + Firestore wiring; App Check remains UNTESTED.
// Never use this wrapper outside a demo- local Emulator project.

const {onCall, HttpsError} = require("firebase-functions/v2/https");
const candidate = require(
    "./deda_linked_owner_session_grant_issuer_CANDIDATE_NOT_EXPORTED.js");

exports.dedaIssueLinkedOriginalUidDeviceGrantQa = onCall(
    {enforceAppCheck: false, timeoutSeconds: 20},
    async (request) => {
      if (process.env.GCLOUD_PROJECT?.startsWith("demo-") !== true ||
          process.env.FIRESTORE_EMULATOR_HOST == null ||
          process.env.FIREBASE_AUTH_EMULATOR_HOST == null ||
          !request.auth?.uid) {
        throw new HttpsError("permission-denied",
            "qa-only-emulator-auth-required");
      }
      // Deliberate test harness bypass: no valid App Check is presented.
      // Original candidate implementation still requires request.app.appId.
      return candidate.__privateIssueLinkedOwnerGrantForQaOnly({
        ...request, app: {appId: "qa-only-appcheck-not-verified"},
      });
    });

// This raw production candidate remains default App-Check enforced and is
// exported only to let Emulator tests exercise its denial behaviour.
exports.dedaIssueLinkedOriginalUidDeviceGrant =
    candidate.dedaIssueLinkedOriginalUidDeviceGrant;
