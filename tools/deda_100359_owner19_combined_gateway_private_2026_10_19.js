"use strict";

// DEDA owner 19-fix staging: compose the previously audited atomic operations.
// UNDEPLOYED. This module is never imported by functions/index.js.
// Raw exclusive names and sale approval only arrive from a server-only source.
// All methods are OFF by default, including read. Do not enable by changing
// APK flags alone. No client-supplied uid, role, balance, price or catalog.
const {createPoint16Gateway, buildStagedCallableDefinitions} =
  require("./deda_intakadha_point16_gated_callable_gateway_2026_10_19.js");
const {privateReservedCatalog} =
  require("./deda_intakadha_point15_identifier_ownership_admin_gifts_2026_10_19.js");
const {createApprovedSaleCatalog, checkoutVerifiedIdentifier} =
  require("./deda_stage18_private_atomic_identifier_checkout_2026_10_19.js");
const {createStage19ManagerActions} =
  require("./deda_stage19_private_fixed_color_manager_actions_2026_10_19.js");
const {createPrivate100AdminReader} =
  require("./deda_stage19_private_exclusive_catalog_reader_2026_10_19.js");

const UID_RE = /^[A-Za-z0-9_-]{1,160}$/;
const ID_RE = /^@DEDA-[A-Z0-9]{6}$/;
const REQUEST_RE = /^[A-Za-z0-9_-]{8,80}$/;
const OWNER_NAMES = Object.freeze({
  readExclusive: "dedaStage19Exclusive100Read",
  gmSelfUse: "dedaStage19Exclusive100SelfUse",
  gmGift: "dedaStage19Exclusive100Grant",
  buyIdentifier: "dedaPremiumBuyIdentifier",
});
const METHODS = Object.freeze(Object.keys(OWNER_NAMES));
function reject(code) {
  const err = new Error("deda-owner19-" + code);
  err.code = code;
  throw err;
}
function authenticated(request) {
  if (!request || !UID_RE.test(request.auth?.uid || "")) {
    reject("unauthenticated");
  }
  if (!request.app || typeof request.app.appId !== "string" ||
      request.app.appId.trim().length === 0) {
    reject("permission-denied");
  }
  return request.auth.uid;
}
function shape(input, keys) {
  if (!input || typeof input !== "object" || Array.isArray(input) ||
      Object.keys(input).length !== keys.length ||
      !keys.every(key => Object.hasOwn(input, key))) {
    reject("invalid-argument");
  }
}
function verifiedId(id) {
  if (typeof id !== "string" || !ID_RE.test(id)) reject("invalid-argument");
}
function verifiedColor(color) {
  if (!["gold", "diamond", "royal", "pink"].includes(color)) {
    reject("invalid-argument");
  }
}
function responseSubset(result, keys) {
  if (!result || result.serverConfirmed !== true) {
    reject("failed-precondition");
  }
  const output = {};
  for (const key of keys) if (result[key] !== undefined) output[key] = result[key];
  return output;
}
function createOwner19Gateway({
  db, exclusiveSuffixes, approvedSellableSuffixes, flags = {},
} = {}) {
  // Production catalog would be decrypted inside a server Secret Manager
  // secured function. No data fallback, no public JSON, no APK catalog.
  if (!db || typeof db.runTransaction !== "function" ||
      !Array.isArray(exclusiveSuffixes) ||
      exclusiveSuffixes.length !== 100 ||
      new Set(exclusiveSuffixes).size !== 100) {
    reject("failed-precondition");
  }
  if (!Array.isArray(approvedSellableSuffixes)) {
    reject("failed-precondition");
  }
  const reservedCatalog = privateReservedCatalog(exclusiveSuffixes);
  const reader = createPrivate100AdminReader(db, exclusiveSuffixes);
  const manager = createStage19ManagerActions(db, exclusiveSuffixes);
  const saleCatalog = approvedSellableSuffixes.length === 0 ? null :
    createApprovedSaleCatalog({
      approvedSuffixes: approvedSellableSuffixes,
      reservedSuffixes: exclusiveSuffixes,
    });
  const stage16 = createPoint16Gateway({
    db, privateCatalog: reservedCatalog, flags: flags.point16 || {},
  });
  const enabled = Object.freeze({
    readExclusive: flags.readExclusive === true,
    gmSelfUse: flags.gmSelfUse === true,
    gmGift: flags.gmGift === true,
    buyIdentifier: flags.buyIdentifier === true,
  });
  async function handle(method, request) {
    if (!METHODS.includes(method)) reject("unimplemented");
    const uid = authenticated(request);
    const data = request.data === undefined ? {} : request.data;
    if (!enabled[method]) reject("unavailable");

    if (method === "readExclusive") {
      shape(data, []);
      return responseSubset(await reader.readForGeneralManager(uid),
        ["serverConfirmed", "total", "identifiers", "history"]);
    }
    if (method === "gmSelfUse") {
      shape(data, ["identifier", "color"]);
      verifiedId(data.identifier); verifiedColor(data.color);
      return responseSubset(await manager.selfUse({
        adminUid: uid, identifier: data.identifier, color: data.color,
      }), ["serverConfirmed", "identifier", "permanentColor", "activeId",
        "originalId"]);
    }
    if (method === "gmGift") {
      shape(data, ["identifier", "color", "recipientOriginalId"]);
      verifiedId(data.identifier); verifiedId(data.recipientOriginalId);
      verifiedColor(data.color);
      return responseSubset(await manager.gift({
        adminUid: uid, identifier: data.identifier,
        color: data.color, recipientOriginalId: data.recipientOriginalId,
      }), ["serverConfirmed", "identifier", "permanentColor",
        "recipientOriginalId"]);
    }
    if (method === "buyIdentifier") {
      shape(data, ["identifier", "requestId"]);
      verifiedId(data.identifier);
      if (typeof data.requestId !== "string" ||
          !REQUEST_RE.test(data.requestId)) reject("invalid-argument");
      if (!saleCatalog) reject("unavailable");
      return responseSubset(await checkoutVerifiedIdentifier(db, {
        uid, identifier: data.identifier, requestId: data.requestId,
        approvedCatalog: saleCatalog,
      }), ["serverConfirmed", "identifier", "transactionId",
        "diamondsCharged", "alreadyOwned"]);
    }
    reject("unimplemented");
  }
  return Object.freeze({enabled, handle, stage16, saleInventoryReady: !!saleCatalog});
}
function callableFactory(gateway, {onCall, HttpsError, defineSecret, secret} = {}) {
  if (!gateway || typeof gateway.handle !== "function" ||
      typeof onCall !== "function" || typeof HttpsError !== "function" ||
      !secret || typeof secret.value !== "function") {
    reject("failed-precondition");
  }
  // This factory only defines functions for reviewed server packaging; it
  // does NOT export to Firebase or read secrets in unauthenticated handlers.
  const out = {};
  for (const method of METHODS) {
    out[OWNER_NAMES[method]] = onCall({
      enforceAppCheck: true, secrets: [secret],
      memory: "256MiB", timeoutSeconds: 60,
    }, async request => {
      try {
        return await gateway.handle(method, request);
      } catch (err) {
        const safe = new Set(["unauthenticated", "permission-denied",
          "invalid-argument", "failed-precondition", "unavailable",
          "already-exists", "resource-exhausted", "unimplemented"]);
        const code = safe.has(err?.code) ? err.code : "internal";
        throw new HttpsError(code, "deda-owner19-" + code);
      }
    });
  }
  return Object.freeze({
    ...buildStagedCallableDefinitions(gateway.stage16, {onCall, HttpsError}),
    ...out,
  });
}
module.exports = {createOwner19Gateway, callableFactory, OWNER_NAMES};
