"use strict";

/**
 * DEDA Stage 8: prototype authenticated callable adapter (NOT DEPLOYED).
 *
 * SECURITY BOUNDARY:
 * - Firebase onCall verifies Authentication and App Check when exported.
 * - Only request.auth.uid is used for the manager identity.
 * - The Firestore transaction reads the active general-manager role again.
 * - Only serverNow() provides time; client-supplied dates/UIDs are rejected.
 * - The stage 7 service only schedules tomorrow's private preview.
 * - No production function is exported from functions/index.js yet.
 */
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {getFirestore} = require("firebase-admin/firestore");
const {SLOTS} = require("./deda_daily_task_publisher.js");
const {schedulePreviousDailyTask} = require("./deda_daily_task_restore.js");

const PUBLICATION_PATTERN = /^[0-9]{8}__([a-z_]+)$/;

function validateClientRequest(request) {
  const uid = request?.auth?.uid;
  if (typeof uid !== "string" || uid.length === 0 || uid.length > 128 ||
      request.auth?.token?.firebase?.sign_in_provider === "anonymous") {
    throw new HttpsError("unauthenticated", "verified-sign-in-required");
  }

  // This app claim is verified by the onCall framework ONLY after deployment
  // with enforceAppCheck:true. Unit tests simulate the trusted context.
  if (typeof request?.app?.appId !== "string" ||
      request.app.appId.length === 0) {
    throw new HttpsError("failed-precondition", "app-check-required");
  }

  const data = request?.data;
  if (data == null || typeof data !== "object" ||
      Array.isArray(data) || Object.getPrototypeOf(data) !== Object.prototype) {
    throw new HttpsError("invalid-argument", "invalid-restoration-payload");
  }
  // Forbid masquerading as another manager or controlling the server clock.
  // Requires explicit confirmation from the future admin UI.
  const names = Object.keys(data);
  if (names.length !== 3 ||
      !names.every((k) =>
        ["slotId", "publicationId", "confirmRestore"].includes(k)) ||
      data.confirmRestore !== true) {
    throw new HttpsError("invalid-argument", "unexpected-restoration-fields");
  }
  const {slotId, publicationId} = data;
  if (typeof slotId !== "string" || !SLOTS.includes(slotId) ||
      typeof publicationId !== "string" || publicationId.length > 100 ||
      !PUBLICATION_PATTERN.test(publicationId) ||
      publicationId !== publicationId.slice(0, 10) + slotId) {
    throw new HttpsError("invalid-argument", "invalid-restoration-source");
  }
  return {slotId, publicationId, requesterUid: uid};
}

function createRestoreRequestHandler({db, serverNow} = {}) {
  if (!db || typeof db.runTransaction !== "function" ||
      typeof serverNow !== "function") {
    throw Error("trusted-server-dependencies-required");
  }
  return async (request) => {
    const params = validateClientRequest(request);
    const instant = serverNow();
    if (!(instant instanceof Date) || !Number.isFinite(instant.getTime())) {
      throw new HttpsError("internal", "trusted-server-clock-unavailable");
    }
    let outcome;
    try {
      outcome = await schedulePreviousDailyTask(db, {
        ...params, trustedNow: instant,
      });
    } catch (_) {
      // Never disclose internal role documents, history, or Firestore details.
      throw new HttpsError("internal", "restore-temporarily-unavailable");
    }

    switch (outcome.outcome) {
      case "scheduled":
        return {
          status: "scheduled",
          slotId: params.slotId,
          effectiveAt: outcome.effectiveAt,
        };
      case "already-scheduled":
        return {status: "already-scheduled", slotId: params.slotId};
      case "general-manager-required":
        throw new HttpsError("permission-denied", "general-manager-required");
      case "conflict-pending-schedule":
        throw new HttpsError("aborted", "pending-task-change-conflict");
      case "too-close-to-midnight":
      case "stale-or-missing-publication":
      case "invalid-previous-configuration":
        throw new HttpsError("failed-precondition", outcome.outcome);
      default:
        throw new HttpsError("invalid-argument", "invalid-restoration-request");
    }
  };
}

/**
 * An actual Firebase v2 callable declaration, deliberately UNEXPORTED.
 * The app-check token is validated by Firebase Functions, not by request.data.
 * This function is never invoked in functions/index.js and cannot deploy yet.
 * The operator must check App Check rollout before exposing it to clients.
 */
function createUnpublishedRestoreCallable() {
  return onCall(
      {enforceAppCheck: true},
      createRestoreRequestHandler({
        db: getFirestore(),
        serverNow: () => new Date(),
      }),
  );
}

module.exports = {
  validateClientRequest,
  createRestoreRequestHandler,
  createUnpublishedRestoreCallable,
};
