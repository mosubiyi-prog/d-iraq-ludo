"use strict";

// DEDA Owner19 Stage50 — PRIVATE READ-ONLY public identifier style resolver.
// NOT imported/exported by production functions/index.js. ALL flags OFF.
// A user searching an original/owned premium ID can be shown its owner's
// VERIFIED active display ID + permanent GM color. This is NEVER permission
// to view, share, subscribe to or navigate anyone's location.
// No phone, UID, accountKey, wallet, followers, admin list or private catalog
// is ever included in the output sent to the requesting app.
const {createHash} = require("node:crypto");

const ID = /^@DEDA-[A-Z0-9]{4,12}$/;
const ORIGINAL = /^@DEDA-[A-Z0-9]{6}$/;
const UID = /^[A-Za-z0-9_-]{1,160}$/;
const KEY = /^[A-Za-z0-9_-]{4,160}$/;
const COLORS = new Set(["gold", "diamond", "royal", "pink"]);
const GM_KINDS = new Set(["general_manager_gift", "general_manager_self_use"]);
const MAX_OWNED = 250;
const sha = x => createHash("sha256").update(x, "utf8").digest("hex");

function stop(code = "failed-precondition") {
  const error = new Error("deda-stage50-verified-public-ink-closed");
  error.code = code;
  throw error;
}
function record(s) { return s.exists ? s.data() || {} : {}; }
function ref(db, col, id) { return db.collection(col).doc(id); }

function verifyLedger(row, original, key) {
  if (row.accountKey !== key || row.originalId !== original ||
      !Array.isArray(row.ownedIds) ||
      row.ownedIds.length < 1 || row.ownedIds.length > MAX_OWNED ||
      row.ownedIds[0] !== original ||
      new Set(row.ownedIds).size !== row.ownedIds.length ||
      !row.ownedIds.every(x => typeof x === "string" && ID.test(x)) ||
      typeof row.activeId !== "string" ||
      !row.ownedIds.includes(row.activeId)) stop();
}

async function verifiedOwnedPremium(tx, db, identifier, original, key) {
  const [rSnap, aSnap, collisionSnap] = await Promise.all([
    tx.get(ref(db, "deda_owned_identifier_registry", identifier)),
    tx.get(ref(db, "deda_owned_identifier_aliases", identifier)),
    tx.get(ref(db, "deda_share_ids", identifier)),
  ]);
  const r = record(rSnap), a = record(aSnap);
  if (!rSnap.exists || !aSnap.exists || collisionSnap.exists ||
      r.status !== "owned" || r.identifier !== identifier ||
      r.accountKey !== key || r.originalId !== original ||
      a.kind !== "permanent_alias" || a.identifier !== identifier ||
      a.accountKey !== key || a.originalId !== original) stop();
  return r;
}

// No user-supplied accountKey, UID or color: the visible style derives
// only from canonical original public ID, current owned-ledger and receipts.
async function readVerifiedPublicIdentifierInk(db, {identifier} = {}) {
  if (!db || typeof db.runTransaction !== "function" ||
      typeof identifier !== "string" || !ID.test(identifier)) {
    stop("invalid-argument");
  }
  return db.runTransaction(async tx => {
    const originalCandidate = await tx.get(
      ref(db, "deda_share_ids", identifier));
    let original = identifier;
    let expectedKey = null;
    // An ID not directly in original directory may be a verified alias.
    if (!originalCandidate.exists) {
      const [rSnap, aSnap] = await Promise.all([
        tx.get(ref(db, "deda_owned_identifier_registry", identifier)),
        tx.get(ref(db, "deda_owned_identifier_aliases", identifier)),
      ]);
      if (!rSnap.exists || !aSnap.exists) return null;
      const r = record(rSnap), a = record(aSnap);
      if (r.status !== "owned" || r.identifier !== identifier ||
          a.kind !== "permanent_alias" ||
          a.identifier !== identifier ||
          typeof r.accountKey !== "string" || !KEY.test(r.accountKey) ||
          r.accountKey !== a.accountKey ||
          typeof r.originalId !== "string" || !ORIGINAL.test(r.originalId) ||
          r.originalId !== a.originalId) stop();
      original = r.originalId;
      expectedKey = r.accountKey;
    }
    const originalSnap = original === identifier ? originalCandidate :
      await tx.get(ref(db, "deda_share_ids", original));
    const share = record(originalSnap);
    if (!originalSnap.exists || share.active !== true ||
        share.kind !== "personal" || share.publicId !== original ||
        typeof share.ownerUid !== "string" || !UID.test(share.ownerUid) ||
        !ORIGINAL.test(original)) return null;

    // The actual original owner can have an historic rotated Firebase UID.
    const ownerSnap = await tx.get(ref(db, "users", share.ownerUid));
    const owner = record(ownerSnap), key = owner.accountKey;
    if (!ownerSnap.exists || typeof key !== "string" || !KEY.test(key) ||
        owner.sharePersonalId !== original ||
        (expectedKey !== null && expectedKey !== key)) stop();

    const ledgerSnap = await tx.get(
      ref(db, "deda_owned_identifier_accounts", sha(key)));
    if (!ledgerSnap.exists) {
      // No new premium ledger: canonical public ID is still valid.
      if (original !== identifier) return null;
      return Object.freeze({
        serverConfirmed: true, requestedId: identifier,
        displayId: original, permanentColor: null,
      });
    }
    const ledger = record(ledgerSnap);
    verifyLedger(ledger, original, key);
    if (identifier !== original && !ledger.ownedIds.includes(identifier)) {
      stop();
    }
    const active = ledger.activeId;
    let color = null;
    if (active !== original) {
      const registry = await verifiedOwnedPremium(
        tx, db, active, original, key);
      if (GM_KINDS.has(registry.acquisition)) {
        if (!COLORS.has(registry.assignedColor)) stop();
        const giftSnap = await tx.get(ref(
          db, "deda_admin_identifier_grants", sha(key + ":" + active)));
        const gift = record(giftSnap);
        if (!giftSnap.exists || gift.identifier !== active ||
            gift.accountKey !== key || gift.originalId !== original ||
            gift.color !== registry.assignedColor) stop();
        color = registry.assignedColor;
      } else if (registry.assignedColor !== undefined &&
          registry.assignedColor !== null) {
        // Bought Group002 cosmetics require a distinct verified receipt.
        stop();
      }
    }
    return Object.freeze({
      serverConfirmed: true, requestedId: identifier,
      displayId: active, permanentColor: color,
    });
  }, {maxAttempts: 5});
}

// INERT factory, NEVER export in production without owner acceptance.
// AppCheck + logged-in Firebase user are mandatory, no requester lookup
// on behalf of unauthenticated persons, no arbitrary client object keys.
function buildStage50PublicInkCallable({
  db, onCall, HttpsError, enabled = false,
} = {}) {
  if (!db || typeof db.runTransaction !== "function" ||
      typeof onCall !== "function" || typeof HttpsError !== "function") stop();
  return onCall({
    enforceAppCheck: true, memory: "256MiB", timeoutSeconds: 30,
  }, async request => {
    try {
      if (!enabled) stop("unavailable");
      if (typeof request?.auth?.uid !== "string" ||
          !UID.test(request.auth.uid)) stop("unauthenticated");
      if (typeof request?.app?.appId !== "string" ||
          !request.app.appId.trim()) stop("permission-denied");
      const input = request.data;
      if (!input || typeof input !== "object" || Array.isArray(input) ||
          Object.keys(input).length !== 1 ||
          typeof input.identifier !== "string" || !ID.test(input.identifier)) {
        stop("invalid-argument");
      }
      const outcome = await readVerifiedPublicIdentifierInk(db, {
        identifier: input.identifier,
      });
      return outcome || {serverConfirmed: false,
        requestedId: input.identifier, displayId: null, permanentColor: null};
    } catch (e) {
      const allowed = new Set(["invalid-argument", "unauthenticated",
        "permission-denied", "failed-precondition", "unavailable"]);
      throw new HttpsError(allowed.has(e?.code) ? e.code : "internal",
        "deda-public-premium-ink-not-ready");
    }
  });
}

module.exports = {
  readVerifiedPublicIdentifierInk,
  buildStage50PublicInkCallable,
};
