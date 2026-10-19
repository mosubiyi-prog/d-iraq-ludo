"use strict";

// DEDA «جمال التطبيق المتكاملة» Stage19, READ ONLY, NOT DEPLOYED.
// This file is intentionally NOT imported/exported from functions/index.js.
// A future owner-approved deployment must package the runtime source bundle,
// inject the key via Firebase Secret Manager, and separately authorize release.
// It NEVER exports any checkout, identifier use or gift callable.
const SECRET_NAME = "DEDA_STAGE19_ADMIN100_AES_KEY_B64";
const CALLABLE_NAME = "dedaStage19Exclusive100Read";
const {readFileSync} = require("node:fs");
const path = require("node:path");

function fail() { throw Error("stage19-readonly-packaging-or-secret-missing"); }
function readEncryptedManifest() {
  const file = path.join(__dirname, "runtime", "catalogs",
    "DEDA_GROUP001_ADMIN100_AES256GCM_2026-10-19.enc.json");
  try {
    const parsed = JSON.parse(readFileSync(file, "utf8"));
    if (parsed.kind !== "DEDA_ADMIN_EXCLUSIVE_CATALOG_ENCRYPTED" ||
        parsed.expected_count !== 100 ||
        parsed.alg !== "AES-256-GCM") fail();
    return Object.freeze(parsed);
  } catch (_) { fail(); }
}

function createReadOnlyStage19Callable({
  onCall, HttpsError, defineSecret, getFirestore,
  encryptedCatalog, decryptCatalog, createReader,
} = {}) {
  if (typeof onCall !== "function" || typeof HttpsError !== "function" ||
      typeof defineSecret !== "function" ||
      typeof getFirestore !== "function" ||
      typeof decryptCatalog !== "function" ||
      typeof createReader !== "function" ||
      !encryptedCatalog || encryptedCatalog.expected_count !== 100) fail();
  const secret = defineSecret(SECRET_NAME);
  if (!secret || typeof secret.value !== "function") fail();

  function abort(code) {
    throw new HttpsError(code, "deda-private-admin100-read-" + code);
  }
  const handler = async (request) => {
    const uid = request?.auth?.uid;
    // Do NOT access Secret Manager or catalogue for anonymous clients.
    if (typeof uid !== "string" ||
        !/^[A-Za-z0-9_-]{1,160}$/.test(uid)) {
      abort("unauthenticated");
    }
    if (typeof request?.app?.appId !== "string" ||
        !request.app.appId.trim()) {
      abort("permission-denied");
    }
    // No 'uid', 'role', 'accountKey' or catalogue passed by client.
    if (request.data == null || typeof request.data !== "object" ||
        Array.isArray(request.data) ||
        Object.keys(request.data).length !== 0) {
      abort("invalid-argument");
    }

    try {
      const key = secret.value();
      if (typeof key !== "string" || key.length !== 44) abort("unavailable");
      const names = decryptCatalog(encryptedCatalog, key);
      const snapshot = await createReader(getFirestore(), names)
        .readForGeneralManager(uid);
      if (snapshot?.serverConfirmed !== true ||
          snapshot.total !== 100 ||
          !Array.isArray(snapshot.identifiers) ||
          snapshot.identifiers.length !== 100 ||
          !Array.isArray(snapshot.history)) abort("failed-precondition");
      return snapshot;
    } catch (error) {
      // Keep entire internal secret, catalog and Firestore paths out of
      // callable error text, even when crypto or role checks fail.
      const safe = new Set(["unauthenticated", "permission-denied",
        "invalid-argument", "failed-precondition", "unavailable"]);
      abort(safe.has(error?.code) ? error.code : "unavailable");
    }
  };
  const callable = onCall({
    enforceAppCheck: true,
    secrets: [secret],
    memory: "256MiB",
    timeoutSeconds: 60,
    maxInstances: 2,
  }, handler);
  return Object.freeze({[CALLABLE_NAME]: callable});
}

// This is an OWNER-APPROVAL preview factory, not a production entry export.
// The runtime dependencies must be assembled by the isolated stage19 script.
function createPackagedReadOnlyStage19Callable({
  onCall, HttpsError, defineSecret, getFirestore,
} = {}) {
  const {decryptOwnerPrivate100} = require(
    "./runtime/deda_stage19_private_admin100_decrypt_server_only_2026_10_19.js");
  const {createPrivate100AdminReader} = require(
    "./runtime/deda_stage19_private_exclusive_catalog_reader_2026_10_19.js");
  return createReadOnlyStage19Callable({
    onCall, HttpsError, defineSecret, getFirestore,
    encryptedCatalog: readEncryptedManifest(),
    decryptCatalog: decryptOwnerPrivate100,
    createReader: createPrivate100AdminReader,
  });
}

module.exports = {
  createReadOnlyStage19Callable,
  createPackagedReadOnlyStage19Callable,
};
