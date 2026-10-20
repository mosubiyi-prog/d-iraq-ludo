"use strict";

// Stage47 — PRIVATE, READ-ONLY, NOT EXPORTED/NOT DEPLOYED in functions/index.js.
// Server-authoritative color for the user's ACTIVE premium ID. Other people's
// inventory, colors, location, phone number, accountKey and admin list are
// never returned to the phone. The client must not supply UID, role or color.
const {createHash} = require("node:crypto");

const UID = /^[A-Za-z0-9_-]{1,160}$/;
const KEY = /^[A-Za-z0-9_-]{4,160}$/;
const ORIGINAL = /^@DEDA-[A-Z0-9]{6}$/;
const PREMIUM = /^@DEDA-[A-Z0-9]{4,12}$/;
const COLORS = new Set(["gold", "diamond", "royal", "pink"]);
const GRANTS = new Set(["general_manager_self_use", "general_manager_gift"]);
const MAX_OWNED = 250;

function fail(code = "failed-precondition") {
  const e = new Error("deda-stage47-verified-identifier-ink-unavailable");
  e.code = code;
  throw e;
}
function data(snapshot) {return snapshot.exists ? snapshot.data() || {} : {};}
function hash(value) {
  return createHash("sha256").update(value, "utf8").digest("hex");
}
function checkOwnerLedger(ledger, key, original) {
  if (ledger.accountKey !== key || ledger.originalId !== original ||
      !Array.isArray(ledger.ownedIds) ||
      ledger.ownedIds.length < 1 || ledger.ownedIds.length > MAX_OWNED ||
      ledger.ownedIds[0] !== original ||
      new Set(ledger.ownedIds).size !== ledger.ownedIds.length ||
      ledger.ownedIds.some(x => typeof x !== "string" || !PREMIUM.test(x)) ||
      typeof ledger.activeId !== "string" ||
      !ledger.ownedIds.includes(ledger.activeId)) fail();
  return ledger.activeId;
}

async function readVerifiedActiveIdentifierInk(db, {uid} = {}) {
  if (!db || typeof db.runTransaction !== "function" ||
      typeof uid !== "string" || !UID.test(uid)) fail("unauthenticated");
  return db.runTransaction(async tx => {
    const [userSnap, sessionSnap] = await Promise.all([
      tx.get(db.collection("users").doc(uid)),
      tx.get(db.collection("deda_sessions").doc(uid)),
    ]);
    const user = data(userSnap), session = data(sessionSnap);
    const key = user.accountKey, original = user.sharePersonalId;
    if (!userSnap.exists || !sessionSnap.exists ||
        typeof key !== "string" || !KEY.test(key) ||
        typeof original !== "string" || !ORIGINAL.test(original) ||
        session.uid !== uid || session.accountKey !== key) {
      fail("permission-denied");
    }
    const shareSnap = await tx.get(db.collection("deda_share_ids").doc(original));
    const share = data(shareSnap);
    if (!shareSnap.exists || share.kind !== "personal" ||
        share.active !== true || share.publicId !== original ||
        typeof share.ownerUid !== "string" || !UID.test(share.ownerUid)) {
      fail("permission-denied");
    }
    const historicOwnerSnap = await tx.get(
      db.collection("users").doc(share.ownerUid));
    if (!historicOwnerSnap.exists ||
        data(historicOwnerSnap).accountKey !== key) fail("permission-denied");

    const accountSnap = await tx.get(db.collection(
      "deda_owned_identifier_accounts").doc(hash(key)));
    const active = accountSnap.exists ?
      checkOwnerLedger(data(accountSnap), key, original) : original;
    let color = null;
    if (active !== original) {
      // An active ID must be globally owned by this SAME account, not just
      // present in a client-requested string or a stale local active slot.
      const [regSnap, aliasSnap, collisionSnap] = await Promise.all([
        tx.get(db.collection("deda_owned_identifier_registry").doc(active)),
        tx.get(db.collection("deda_owned_identifier_aliases").doc(active)),
        tx.get(db.collection("deda_share_ids").doc(active)),
      ]);
      const reg = data(regSnap), alias = data(aliasSnap);
      if (!regSnap.exists || !aliasSnap.exists || collisionSnap.exists ||
          reg.status !== "owned" || reg.identifier !== active ||
          reg.accountKey !== key || reg.originalId !== original ||
          alias.kind !== "permanent_alias" ||
          alias.identifier !== active || alias.accountKey !== key ||
          alias.originalId !== original) fail();
      if (GRANTS.has(reg.acquisition)) {
        if (!COLORS.has(reg.assignedColor)) fail();
        const receiptSnap = await tx.get(
          db.collection("deda_admin_identifier_grants").doc(
            hash(key + ":" + active)));
        const receipt = data(receiptSnap);
        if (!receiptSnap.exists || receipt.accountKey !== key ||
            receipt.identifier !== active || receipt.originalId !== original ||
            receipt.color !== reg.assignedColor) fail();
        color = reg.assignedColor;
      } else if (reg.assignedColor != null) {
        // Purchased Group002 IDs can use paid cosmetic styles separately.
        // A forged or unreviewed server category must not inherit GM ink.
        fail();
      }
    }
    return Object.freeze({
      serverConfirmed: true, accountUid: uid,
      originalId: original, activeId: active,
      permanentColor: color,
    });
  }, {maxAttempts: 5});
}

/// Factory only: caller must explicitly opt in after release approval.
/// Zero production exports or Firebase side effects in this module.
function buildVerifiedInkReadCallable({db, onCall, HttpsError,
  enabled = false} = {}) {
  if (typeof onCall !== "function" || typeof HttpsError !== "function" ||
      !db || typeof db.runTransaction !== "function") fail();
  return onCall({
    enforceAppCheck: true, memory: "256MiB", timeoutSeconds: 30,
  }, async request => {
    try {
      if (!enabled) fail("unavailable");
      if (!request?.auth?.uid || !UID.test(request.auth.uid)) {
        fail("unauthenticated");
      }
      if (typeof request.app?.appId !== "string" ||
          !request.app.appId.trim()) fail("permission-denied");
      const input = request.data === undefined ? {} : request.data;
      if (!input || typeof input !== "object" ||
          Array.isArray(input) || Object.keys(input).length !== 0) {
        fail("invalid-argument");
      }
      return await readVerifiedActiveIdentifierInk(db, {
        uid: request.auth.uid,
      });
    } catch (e) {
      const safe = new Set(["unavailable", "unauthenticated",
        "permission-denied", "invalid-argument", "failed-precondition"]);
      throw new HttpsError(safe.has(e?.code) ? e.code : "internal",
        "deda-verified-identifier-ink-blocked");
    }
  });
}

module.exports = {
  readVerifiedActiveIdentifierInk, buildVerifiedInkReadCallable,
};
