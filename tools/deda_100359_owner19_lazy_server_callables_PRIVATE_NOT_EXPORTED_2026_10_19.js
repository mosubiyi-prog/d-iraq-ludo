"use strict";

// Owner-19 server adapter, NOT EXPORTED/NOT DEPLOYED in functions/index.js.
// On-call server secret stays inaccessible to anonymous/unattested requests.
// The unencrypted 100-list is NEVER shipped to the mobile app or public code.
// Settings default OFF. Cloud Functions deployment and wallet migration require
// separate audited owner release, no automatic mutation of real accounts.
const {createOwner19Gateway, OWNER_NAMES} =
  require("./deda_100359_owner19_combined_gateway_private_2026_10_19.js");

const STAGE16 = Object.freeze({
  readCards: "dedaPremiumReadCards",
  buyCard: "dedaPremiumBuyCard",
  activateCard: "dedaPremiumActivateCard",
  readIdentifiers: "dedaPremiumReadIdentifiers",
  activateIdentifier: "dedaPremiumActivateIdentifier",
  resolveAlias: "dedaPremiumResolveAlias",
  adminGrant: "dedaPremiumAdminGrantReserved",
});
const STAGE16_FLAGS = Object.freeze({
  readCards: "read",
  buyCard: "cardPurchase",
  activateCard: "cardUse",
  readIdentifiers: "read",
  activateIdentifier: "identifierUse",
  resolveAlias: "alias",
  adminGrant: "adminGrant",
});
function secureError(code) {
  const err = new Error("deda-owner19-" + code); err.code = code; return err;
}
function requirePrincipal(req) {
  if (!req || typeof req.auth?.uid !== "string" ||
      !/^[A-Za-z0-9_-]{1,160}$/.test(req.auth.uid)) {
    throw secureError("unauthenticated");
  }
  if (typeof req.app?.appId !== "string" || !req.app.appId.trim()) {
    throw secureError("permission-denied");
  }
}
function approved(method, flags) {
  if (Object.hasOwn(OWNER_NAMES, method)) return flags[method] === true;
  if (Object.hasOwn(STAGE16_FLAGS, method)) {
    return flags.point16?.[STAGE16_FLAGS[method]] === true;
  }
  return false;
}
function createLazyOwner19Callables({
  onCall, HttpsError, secret, decryptPrivate100, readEncryptedManifest,
  getFirestore, approvedGroup002, flags = {},
} = {}) {
  if (typeof onCall !== "function" ||
      typeof HttpsError !== "function" ||
      !secret || typeof secret.value !== "function" ||
      typeof decryptPrivate100 !== "function" ||
      typeof readEncryptedManifest !== "function" ||
      typeof getFirestore !== "function" ||
      typeof approvedGroup002 !== "function") {
    throw secureError("failed-precondition");
  }
  const callables = {};
  async function wrap(method, req) {
    try {
      // These two preconditions happen BEFORE secret value or catalog access.
      requirePrincipal(req);
      if (!approved(method, flags)) throw secureError("unavailable");
      const key = secret.value();
      if (typeof key !== "string" || key.length === 0) {
        throw secureError("unavailable");
      }
      const suffixes = decryptPrivate100(readEncryptedManifest(), key);
      // Approval is server-only; client proposals cannot approve stock.
      const saleNames = approvedGroup002();
      const gateway = createOwner19Gateway({
        db: getFirestore(),
        exclusiveSuffixes: suffixes,
        approvedSellableSuffixes: saleNames,
        flags,
      });
      const result = Object.hasOwn(OWNER_NAMES, method) ?
        await gateway.handle(method, req) :
        await gateway.stage16.handle(method, req);
      return result;
    } catch (err) {
      const safe = new Set(["unauthenticated", "permission-denied",
        "invalid-argument", "failed-precondition", "unavailable",
        "already-exists", "resource-exhausted", "unimplemented"]);
      const code = safe.has(err?.code) ? err.code : "internal";
      // Never expose wallet paths, admin list or encrypted manifest details.
      throw new HttpsError(code, "deda-owner19-" + code);
    }
  }
  const methods = {...OWNER_NAMES, ...STAGE16};
  for (const [method, name] of Object.entries(methods)) {
    callables[name] = onCall({
      enforceAppCheck: true,
      secrets: [secret],
      memory: "256MiB",
      timeoutSeconds: 60,
    }, req => wrap(method, req));
  }
  return Object.freeze(callables);
}
module.exports = {createLazyOwner19Callables, STAGE16, requirePrincipal};
