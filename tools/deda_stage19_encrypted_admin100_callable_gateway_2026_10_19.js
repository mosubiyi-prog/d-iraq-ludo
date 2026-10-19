"use strict";

// Staged server-only callable facade for Stage19 encrypted Group001.
// NOT imported/exported in production functions/index.js and all flags OFF.
// Caller must supply the owner PRIVATE AES-256-GCM key from Firebase Secret
// Manager; never accept catalog, key, UID, role, colors or prices as auth proof
// from the mobile device.
const {decryptOwnerPrivate100} =
  require("./deda_stage19_private_admin100_decrypt_server_only_2026_10_19.js");
const {createPrivate100AdminReader} =
  require("./deda_stage19_private_exclusive_catalog_reader_2026_10_19.js");
const {createStage19ManagerActions} =
  require("./deda_stage19_private_fixed_color_manager_actions_2026_10_19.js");
const COLORS = new Set(["gold","diamond","royal","pink"]);
const EXCLUSIVE = /^@DEDA-[A-Z0-9]{4,12}$/;
const ORIGINAL = /^@DEDA-[A-Z0-9]{6}$/;

function stop(code="permission-denied") {
  const e = new Error("deda-stage19-" + code);
  e.code = code;
  throw e;
}
function keys(data, allowed) {
  return !!data && typeof data === "object" &&
    !Array.isArray(data) &&
    Object.keys(data).length === allowed.length &&
    Object.keys(data).every(k => allowed.includes(k));
}
function principal(req) {
  const uid = req && req.auth && req.auth.uid;
  if (typeof uid !== "string" || !/^[A-Za-z0-9_-]{1,160}$/.test(uid)) {
    stop("unauthenticated");
  }
  if (!req.app || typeof req.app.appId !== "string" ||
      !req.app.appId.trim()) stop();
  return uid;
}

function createStage19ExclusiveGateway({
  db, encryptedCatalog, ownerPrivateKeyB64,
  flags = {},
} = {}) {
  // NEVER accept partially decrypted data or public catalog client payload.
  const names = decryptOwnerPrivate100(encryptedCatalog, ownerPrivateKeyB64);
  const reader = createPrivate100AdminReader(db, names);
  const writer = createStage19ManagerActions(db, names);
  const enabled = Object.freeze({
    read: flags.read === true,
    managerUse: flags.managerUse === true,
    gift: flags.gift === true,
  });
  return Object.freeze({
    enabled,
    async handle(method, req) {
      if (!["read", "selfUse", "gift"].includes(method)) stop("unimplemented");
      const uid = principal(req);
      const data = req.data === undefined ? {} : req.data;
      if (method === "read") {
        if (!enabled.read) stop("unavailable");
        if (!keys(data, [])) stop("invalid-argument");
        // No output with UID, raw accountKey, hidden admin access grants,
        // Firebase reference or secret. ALL 100 ONLY after server role check.
        return reader.readForGeneralManager(uid);
      }
      if (method === "selfUse") {
        if (!enabled.managerUse) stop("unavailable");
        if (!keys(data, ["identifier", "color"]) ||
            !EXCLUSIVE.test(data.identifier || "") ||
            !COLORS.has(data.color)) stop("invalid-argument");
        return writer.selfUse({
          adminUid: uid, identifier: data.identifier, color: data.color,
        });
      }
      if (!enabled.gift) stop("unavailable");
      if (!keys(data, ["identifier", "color", "recipientOriginalId"]) ||
          !EXCLUSIVE.test(data.identifier || "") ||
          !ORIGINAL.test(data.recipientOriginalId || "") ||
          !COLORS.has(data.color)) stop("invalid-argument");
      return writer.gift({
        adminUid: uid, identifier: data.identifier, color: data.color,
        recipientOriginalId: data.recipientOriginalId,
      });
    },
  });
}

function stage19CallableDefinitions(gateway, {onCall, HttpsError}) {
  if (!gateway || typeof gateway.handle !== "function" ||
      typeof onCall !== "function" || typeof HttpsError !== "function") {
    stop("failed-precondition");
  }
  const result = {};
  for (const [method, name] of Object.entries({
    read: "dedaStage19Exclusive100Read",
    selfUse: "dedaStage19Exclusive100SelfUse",
    gift: "dedaStage19Exclusive100Gift",
  })) {
    result[name] = onCall({
      enforceAppCheck: true,
      memory: "256MiB",
      timeoutSeconds: 45,
    }, async(req) => {
      try {
        return await gateway.handle(method, req);
      } catch(e) {
        const safe = new Set(["unavailable", "unauthenticated",
          "permission-denied", "invalid-argument", "failed-precondition",
          "already-exists", "resource-exhausted", "unimplemented"]);
        throw new HttpsError(safe.has(e?.code) ? e.code : "internal",
          "deda-stage19-secure-action-blocked");
      }
    });
  }
  return Object.freeze(result);
}
module.exports = {createStage19ExclusiveGateway, stage19CallableDefinitions};
