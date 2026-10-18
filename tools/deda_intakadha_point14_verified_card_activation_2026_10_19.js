"use strict";

// DEDA «إنت كدها» point14 (UNDEPLOYED). Activation is not a purchase.
// Only a backend callable is authorized to pass uid from request.auth.uid.
// Persistent activeColor belongs to the stable, server-verified DEDA account.
// No client-supplied account key, price, diamond balance or entitlement.
const {COLORS, accountHash} =
    require("./deda_intakadha_point13_atomic_id_card_checkout_2026_10_19.js");

function fail(code, message) {
  const error = new Error(message);
  error.code = code;
  throw error;
}
function data(snap) {
  return snap.exists ? snap.data() || {} : {};
}
function validUid(uid) {
  if (typeof uid !== "string" || !/^[A-Za-z0-9_-]{1,160}$/.test(uid)) {
    fail("unauthenticated", "verified-session-required");
  }
}
function checkColors(colors) {
  if (!colors || typeof colors !== "object" || Array.isArray(colors) ||
      Object.keys(colors).some((color) => !COLORS.includes(color) ||
          colors[color] !== true)) {
    fail("failed-precondition", "malformed-card-ownership");
  }
  return COLORS.filter((color) => colors[color] === true);
}
function verifiedState(key, identifier, owned, active) {
  // Active can only be shown if the same confirmed server account owns it.
  return {
    identifier,
    ownedColors: owned,
    activeColor: active && owned.includes(active) ? active : null,
  };
}

async function verifiedCardState(db, {uid, activateColor = undefined}) {
  validUid(uid);
  if (activateColor !== undefined && !COLORS.includes(activateColor)) {
    fail("invalid-argument", "invalid-card-color");
  }
  // One transaction verifies all account links and the entitlement before
  // changing the active style. A read-only call commits no writes.
  return db.runTransaction(async (tx) => {
    const userRef = db.collection("users").doc(uid);
    const sessionRef = db.collection("deda_sessions").doc(uid);
    const [userSnap, sessionSnap] = await Promise.all([
      tx.get(userRef), tx.get(sessionRef),
    ]);
    const user = data(userSnap);
    const session = data(sessionSnap);
    const account = user.accountKey;
    const personalId = user.sharePersonalId;
    if (!userSnap.exists || !sessionSnap.exists ||
        typeof account !== "string" ||
        !/^[A-Za-z0-9_-]{4,160}$/.test(account) ||
        session.uid !== uid || session.accountKey !== account ||
        typeof personalId !== "string" ||
        !/^@DEDA-[A-Z0-9]{6}$/.test(personalId)) {
      fail("permission-denied", "verified-deda-account-required");
    }
    const shareRef = db.collection("deda_share_ids").doc(personalId);
    const ownedRef = db.collection("deda_id_card_entitlements").doc(accountHash(account));
    const [shareSnap, ownedSnap] = await Promise.all([
      tx.get(shareRef), tx.get(ownedRef),
    ]);
    const share = data(shareSnap);
    if (!shareSnap.exists || share.kind !== "personal" ||
        share.active !== true || share.publicId !== personalId ||
        typeof share.ownerUid !== "string" || !share.ownerUid) {
      fail("permission-denied", "personal-id-must-be-registered");
    }
    const origRef = db.collection("users").doc(share.ownerUid);
    const orig = await tx.get(origRef);
    if (!orig.exists || data(orig).accountKey !== account) {
      fail("permission-denied", "personal-id-owner-account-mismatch");
    }
    const entitlement = data(ownedSnap);
    if (ownedSnap.exists && entitlement.accountKey !== account) {
      fail("failed-precondition", "entitlement-account-mismatch");
    }
    const owned = ownedSnap.exists ?
      checkColors(entitlement.colors || {}) : [];
    const current = entitlement.activeColor;
    if (current !== undefined && current !== null &&
        (typeof current !== "string" || !COLORS.includes(current))) {
      fail("failed-precondition", "invalid-persisted-active-style");
    }
    if (activateColor === undefined) {
      return verifiedState(account, personalId, owned, current);
    }
    if (!ownedSnap.exists || !owned.includes(activateColor)) {
      fail("permission-denied", "cannot-use-card-not-owned-by-account");
    }
    if (current !== activateColor) {
      tx.update(ownedRef, {
        activeColor: activateColor,
        updatedAt: new Date(),
      });
    }
    return verifiedState(account, personalId, owned, activateColor);
  }, {maxAttempts: 7});
}
async function readVerifiedCardState(db, {uid}) {
  return verifiedCardState(db, {uid});
}
async function activateVerifiedCard(db, {uid, color}) {
  return verifiedCardState(db, {uid, activateColor: color});
}

module.exports = {
  readVerifiedCardState, activateVerifiedCard,
};
