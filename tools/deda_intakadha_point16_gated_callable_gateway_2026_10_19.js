"use strict";

// DEDA point16. STAGED ONLY: NOT imported/exported by functions/index.js.
// No production writes, rules changes, deployment or APK. A later, separately
// authorized server release must inspect the Firestore rules and enable
// App Check, migrate routing and review the server-only reserved-100 manifest.
// Never trust identity/role/pricing/catalog passed by the mobile client.
const {checkoutIdCard} =
  require("./deda_intakadha_point13_atomic_id_card_checkout_2026_10_19.js");
const {readVerifiedCardState, activateVerifiedCard} =
  require("./deda_intakadha_point14_verified_card_activation_2026_10_19.js");
const {readOwnedIdentifiers, activateOwnedIdentifier,
  adminGrantReservedIdentifier, resolveIdentifierAlias} =
  require("./deda_intakadha_point15_identifier_ownership_admin_gifts_2026_10_19.js");

const methods = Object.freeze([
  "readCards", "buyCard", "activateCard",
  "readIdentifiers", "activateIdentifier", "resolveAlias", "adminGrant",
]);
const publicMethods = new Set(methods);
const idRegex = /^@DEDA-[A-Z0-9]{4,12}$/;

function err(code, message) {
  const error = new Error(message);
  error.code = code;
  throw error;
}
function keysMatch(obj, fields) {
  return obj && typeof obj === "object" && !Array.isArray(obj) &&
      Object.keys(obj).every(k => fields.includes(k)) &&
      fields.every(k => Object.prototype.hasOwnProperty.call(obj, k));
}
function verifyPayload(data, fields) {
  if (!keysMatch(data, fields)) err("invalid-argument", "unexpected-or-missing-parameters");
}
function verifyPrincipal(request) {
  if (!request || !request.auth || typeof request.auth.uid !== "string" ||
      !/^[A-Za-z0-9_-]{1,160}$/.test(request.auth.uid)) {
    err("unauthenticated", "authentication-required");
  }
  // Deliberately fail closed even in emulator unless test supplies an App
  // Check attestation. Real onCall must use enforceAppCheck: true as well.
  if (!request.app || typeof request.app.appId !== "string" ||
      !request.app.appId.trim()) {
    err("permission-denied", "app-check-required");
  }
  return request.auth.uid;
}
function noExtraData(response, allowed) {
  // Outgoing DTOs exclude private accountKey, wallet and admin scope.
  const out = {};
  for (const key of allowed) {
    if (response[key] !== undefined) out[key] = response[key];
  }
  return out;
}
function createPoint16Gateway({
  db,
  flags = {},
  privateCatalog = null,
} = {}) {
  if (!db || typeof db.runTransaction !== "function") {
    err("failed-precondition", "server-admin-firestore-required");
  }
  const config = {
    read: flags.read === true,
    cardPurchase: flags.cardPurchase === true,
    cardUse: flags.cardUse === true,
    identifierUse: flags.identifierUse === true,
    alias: flags.alias === true,
    adminGrant: flags.adminGrant === true,
  };
  // Intentionally ALL flags OFF by default. No mutable unlock function.
  async function handle(method, request) {
    if (!publicMethods.has(method)) err("unimplemented", "unsupported-operation");
    const uid = verifyPrincipal(request);
    const data = request.data === undefined ? {} : request.data;

    if (method === "readCards") {
      if (!config.read) err("unavailable", "premium-identifiers-closed");
      verifyPayload(data, []);
      const state = await readVerifiedCardState(db, {uid});
      return noExtraData(state, ["identifier", "ownedColors", "activeColor"]);
    }
    if (method === "buyCard") {
      if (!config.cardPurchase) err("unavailable", "purchases-not-launched");
      verifyPayload(data, ["color", "requestId"]);
      const state = await checkoutIdCard(db, {
        uid, color: data.color, requestId: data.requestId,
      });
      return noExtraData(state, ["transactionId", "color",
        "diamondsCharged", "serverConfirmed", "alreadyOwned"]);
    }
    if (method === "activateCard") {
      if (!config.cardUse) err("unavailable", "card-use-not-launched");
      verifyPayload(data, ["color"]);
      const state = await activateVerifiedCard(db, {uid, color: data.color});
      return noExtraData(state, ["identifier", "ownedColors", "activeColor"]);
    }
    if (method === "readIdentifiers") {
      if (!config.read) err("unavailable", "premium-identifiers-closed");
      verifyPayload(data, []);
      const state = await readOwnedIdentifiers(db, {uid});
      return {
        ...noExtraData(state, ["originalId", "activeId", "ownedIds", "serverConfirmed"]),
        accountUid: uid,
      };
    }
    if (method === "activateIdentifier") {
      if (!config.identifierUse) err("unavailable", "identifier-use-not-launched");
      verifyPayload(data, ["identifier"]);
      const state = await activateOwnedIdentifier(db, {
        uid, identifier: data.identifier,
      });
      return {
        ...noExtraData(state, ["originalId", "activeId", "ownedIds", "serverConfirmed"]),
        accountUid: uid,
      };
    }
    if (method === "resolveAlias") {
      if (!config.alias) err("unavailable", "alias-compatibility-not-verified");
      verifyPayload(data, ["identifier"]);
      if (typeof data.identifier !== "string" ||
          !idRegex.test(data.identifier)) {
        err("invalid-argument", "invalid-identifier");
      }
      const match = await resolveIdentifierAlias(db, {
        identifier: data.identifier,
      });
      // NO owner UID, accountKey, location, coordinates or shared place data.
      return match && typeof match.originalId === "string" ?
          {originalId: match.originalId} : {originalId: null};
    }
    if (method === "adminGrant") {
      if (!config.adminGrant || !privateCatalog) {
        err("unavailable", "admin-reserved-catalog-not-loaded");
      }
      verifyPayload(data, ["recipientOriginalId", "identifier", "color"]);
      const state = await adminGrantReservedIdentifier(db, {
        adminUid: uid,
        recipientOriginalId: data.recipientOriginalId,
        identifier: data.identifier,
        color: data.color,
        privateCatalog,
      });
      // Never return recipient accountKey or private catalog member list.
      return noExtraData(state, ["originalId", "activeId", "ownedIds",
        "giftedIdentifier", "assignedColor", "serverConfirmed"]);
    }
    err("unimplemented", "unsupported-operation");
  }
  return Object.freeze({handle, enabled: Object.freeze({...config})});
}

// This factory deliberately does NOT call initializeApp, import production
// functions/index.js, export Firebase functions, or enable feature flags.
// The caller has to explicitly wire each callable later and include
// enforceAppCheck:true. Mockable injection allows local emulator tests.
function buildStagedCallableDefinitions(gateway, {onCall, HttpsError}) {
  if (typeof onCall !== "function" || typeof HttpsError !== "function" ||
      !gateway || typeof gateway.handle !== "function") {
    err("failed-precondition", "firebase-callable-api-required");
  }
  const names = {
    readCards: "dedaPremiumReadCards",
    buyCard: "dedaPremiumBuyCard",
    activateCard: "dedaPremiumActivateCard",
    readIdentifiers: "dedaPremiumReadIdentifiers",
    activateIdentifier: "dedaPremiumActivateIdentifier",
    resolveAlias: "dedaPremiumResolveAlias",
    adminGrant: "dedaPremiumAdminGrantReserved",
  };
  const exports = {};
  for (const method of methods) {
    exports[names[method]] = onCall({
      enforceAppCheck: true,
      memory: "256MiB",
      timeoutSeconds: 30,
    }, async (request) => {
      try {
        return await gateway.handle(method, request);
      } catch (error) {
        const safe = new Set([
          "unauthenticated", "permission-denied", "invalid-argument",
          "failed-precondition", "already-exists", "resource-exhausted",
          "unavailable", "unimplemented",
        ]);
        const code = safe.has(error && error.code) ? error.code : "internal";
        // Never return raw exception, account key, wallet or Firestore doc.
        throw new HttpsError(code, "deda-premium-" + code);
      }
    });
  }
  return Object.freeze(exports);
}

module.exports = {createPoint16Gateway, buildStagedCallableDefinitions};
