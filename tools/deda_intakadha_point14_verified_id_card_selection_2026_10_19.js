"use strict";

// DEDA «إنت كدها» point14. ISOLATED, EMULATOR-ONLY, NOT DEPLOYED.
// The future authenticated callable MUST derive uid from request.auth.uid.
// NEVER accept uid, accountKey, wallet, balance, owned colors or price from
// the client. No direct Firestore client permission to this private ledger.
const {accountHash, COLORS} =
    require("./deda_intakadha_point13_atomic_id_card_checkout_2026_10_19.js");

const ACCOUNT = /^[A-Za-z0-9_-]{4,160}$/;
const PERSONAL_ID = /^@DEDA-[A-Z0-9]{6}$/;
function fail(code, message) {
  const err = new Error(message);
  err.code = code;
  throw err;
}
function data(snap) {return snap.exists ? (snap.data() || {}) : {};}

async function assertAccount(tx, db, uid) {
  if (typeof uid !== "string" || !uid || uid.length > 160) {
    fail("unauthenticated", "verified-user-required");
  }
  const userRef = db.collection("users").doc(uid);
  const sessionRef = db.collection("deda_sessions").doc(uid);
  const [userSnap, sessionSnap] = await Promise.all([
    tx.get(userRef), tx.get(sessionRef),
  ]);
  const user = data(userSnap);
  const session = data(sessionSnap);
  const accountKey = user.accountKey;
  const publicId = user.sharePersonalId;
  if (!userSnap.exists || !sessionSnap.exists ||
      typeof accountKey !== "string" || !ACCOUNT.test(accountKey) ||
      session.uid !== uid || session.accountKey !== accountKey ||
      typeof publicId !== "string" || !PERSONAL_ID.test(publicId)) {
    fail("permission-denied", "verified-session-required");
  }
  const shareRef = db.collection("deda_share_ids").doc(publicId);
  const shareSnap = await tx.get(shareRef);
  const share = data(shareSnap);
  if (!shareSnap.exists || share.publicId !== publicId ||
      share.kind !== "personal" || share.active !== true ||
      typeof share.ownerUid !== "string" || !share.ownerUid) {
    fail("permission-denied", "registered-personal-id-required");
  }
  const registered = await tx.get(db.collection("users").doc(share.ownerUid));
  if (!registered.exists || data(registered).accountKey !== accountKey) {
    fail("permission-denied", "personal-id-owner-mismatch");
  }
  return {accountKey, publicId};
}

function verifiedState(snapshot, accountKey, publicId) {
  const row = data(snapshot);
  if (snapshot.exists && row.accountKey !== accountKey) {
    fail("failed-precondition", "entitlement-owner-mismatch");
  }
  const colors = row.colors || {};
  if (typeof colors !== "object" || Array.isArray(colors)) {
    fail("failed-precondition", "invalid-entitlement-map");
  }
  const ownedColors = COLORS.filter(c => colors[c] === true);
  const activeColor = row.activeColor ?? null;
  if (activeColor !== null &&
      (!COLORS.includes(activeColor) || !ownedColors.includes(activeColor))) {
    fail("failed-precondition", "invalid-active-card-not-owned");
  }
  return {ownedColors, activeColor, publicId, serverConfirmed: true};
}

// Always fetch server-owned cards. No state is inferred from cached preferences.
async function readCardSelection(db, {uid}) {
  return db.runTransaction(async tx => {
    const {accountKey, publicId} = await assertAccount(tx, db, uid);
    const ref = db.collection("deda_id_card_entitlements").doc(accountHash(accountKey));
    return verifiedState(await tx.get(ref), accountKey, publicId);
  }, {maxAttempts: 5});
}

// Only an already-owned design may be selected. No diamonds are touched.
// Single activeColor field means EXACTLY zero or one selected design.
async function activateOwnedCard(db, {uid, color}) {
  if (!COLORS.includes(color)) {
    fail("invalid-argument", "unknown-card-design");
  }
  return db.runTransaction(async tx => {
    const {accountKey, publicId} = await assertAccount(tx, db, uid);
    const ref = db.collection("deda_id_card_entitlements").doc(accountHash(accountKey));
    const snap = await tx.get(ref);
    const old = verifiedState(snap, accountKey, publicId);
    if (!old.ownedColors.includes(color)) {
      fail("permission-denied", "card-not-owned-by-current-account");
    }
    if (old.activeColor === color) return old; // repeat costs/writes nothing
    tx.update(ref, {activeColor: color, selectedAt: new Date()});
    return {...old, activeColor: color};
  }, {maxAttempts: 7});
}

module.exports = {activateOwnedCard, readCardSelection};
