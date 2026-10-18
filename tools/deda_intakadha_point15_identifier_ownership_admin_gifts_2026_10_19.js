"use strict";

// DEDA «إنت كدها» point 15 — PRIVATE STAGING ONLY. NEVER deployed.
// Public repo contains NO first-100 member names, prices or admin secrets.
// A reviewed production callable must pass uid=request.auth.uid and must
// load the owner-private 100-name catalog from trusted server configuration.
// Neither catalog, actor uid, role nor target accountKey is accepted from
// arbitrary mobile client payloads. This module does NOT touch live routing.
const {createHash} = require("node:crypto");

const ACCOUNT_PATTERN = /^[A-Za-z0-9_-]{4,160}$/;
const UID_PATTERN = /^[A-Za-z0-9_-]{1,160}$/;
const ORIGINAL_PATTERN = /^@DEDA-[A-Z0-9]{6}$/;
const PREMIUM_PATTERN = /^@DEDA-[A-Z0-9]{4,12}$/;
const DESIGN_COLORS = Object.freeze(["gold", "diamond", "royal", "pink"]);
const MAX_OWNED = 250;

function reject(code, reason) {
  const err = new Error(reason);
  err.code = code;
  throw err;
}
function record(snap) {return snap.exists ? snap.data() || {} : {};}
function hashed(value) {
  return createHash("sha256").update(value, "utf8").digest("hex");
}
function accountDoc(db, accountKey) {
  return db.collection("deda_owned_identifier_accounts").doc(hashed(accountKey));
}
function registryDoc(db, identifier) {
  return db.collection("deda_owned_identifier_registry").doc(identifier);
}
function aliasDoc(db, identifier) {
  return db.collection("deda_owned_identifier_aliases").doc(identifier);
}
function validateIdentifier(value) {
  if (typeof value !== "string" || !PREMIUM_PATTERN.test(value)) {
    reject("invalid-argument", "invalid-identifier");
  }
}
function validateShape(data, originalId, key) {
  if (!data) return {originalId, activeId: originalId, ownedIds: [originalId]};
  if (data.accountKey !== key || data.originalId !== originalId ||
      !Array.isArray(data.ownedIds) ||
      data.ownedIds.length < 1 || data.ownedIds.length > MAX_OWNED ||
      data.ownedIds[0] !== originalId ||
      new Set(data.ownedIds).size !== data.ownedIds.length ||
      !data.ownedIds.every(x => typeof x === "string" && PREMIUM_PATTERN.test(x)) ||
      typeof data.activeId !== "string" ||
      !data.ownedIds.includes(data.activeId)) {
    reject("failed-precondition", "invalid-identifier-account-ledger");
  }
  return {originalId, activeId: data.activeId, ownedIds: [...data.ownedIds]};
}

// Access: authenticated current session of same permanent DEDA account,
// including historic rotated anonymous auth UIDs registered to the same key.
async function assertVerifiedAccount(tx, db, uid) {
  if (typeof uid !== "string" || !UID_PATTERN.test(uid)) {
    reject("unauthenticated", "authenticated-session-required");
  }
  const userRef = db.collection("users").doc(uid);
  const sessionRef = db.collection("deda_sessions").doc(uid);
  const [u, s] = await Promise.all([tx.get(userRef), tx.get(sessionRef)]);
  const user = record(u), session = record(s);
  const key = user.accountKey;
  const originalId = user.sharePersonalId;
  if (!u.exists || !s.exists || typeof key !== "string" ||
      !ACCOUNT_PATTERN.test(key) || !ORIGINAL_PATTERN.test(originalId || "") ||
      session.uid !== uid || session.accountKey !== key) {
    reject("permission-denied", "verified-deda-session-required");
  }
  const share = record(await tx.get(db.collection("deda_share_ids").doc(originalId)));
  if (share.kind !== "personal" || share.publicId !== originalId ||
      share.active !== true || typeof share.ownerUid !== "string" ||
      !share.ownerUid) {
    reject("permission-denied", "registered-original-id-required");
  }
  const firstOwner = record(await tx.get(db.collection("users").doc(share.ownerUid)));
  if (firstOwner.accountKey !== key) {
    reject("permission-denied", "original-identifier-owner-mismatch");
  }
  return {key, originalId, uid};
}

async function validateVerifiedOwned(tx, db, key, state) {
  const premiums = state.ownedIds.filter(x => x !== state.originalId);
  const refs = premiums.map(id => registryDoc(db, id));
  const aliases = premiums.map(id => aliasDoc(db, id));
  const snaps = await Promise.all([...refs, ...aliases].map(ref => tx.get(ref)));
  for (let i = 0; i < premiums.length; i++) {
    const owner = record(snaps[i]), alias = record(snaps[i + premiums.length]);
    if (!snaps[i].exists || !snaps[i + premiums.length].exists ||
        owner.accountKey !== key || owner.identifier !== premiums[i] ||
        owner.originalId !== state.originalId ||
        owner.status !== "owned" ||
        alias.accountKey !== key || alias.identifier !== premiums[i] ||
        alias.originalId !== state.originalId || alias.kind !== "permanent_alias") {
      reject("failed-precondition", "ownership-or-alias-proof-mismatch");
    }
  }
}

async function readOwnedIdentifiers(db, {uid}) {
  return db.runTransaction(async (tx) => {
    const user = await assertVerifiedAccount(tx, db, uid);
    const ref = accountDoc(db, user.key);
    const snap = await tx.get(ref);
    const state = validateShape(snap.exists ? record(snap) : null,
        user.originalId, user.key);
    await validateVerifiedOwned(tx, db, user.key, state);
    return {...state, serverConfirmed: true};
  }, {maxAttempts: 5});
}

// Switching never transfers/removes ownership and never changes auth UID.
// The resulting activeId is only a staged server ledger field; existing
// app-wide search, friend and location routes MUST NOT use it until the
// point16 migration/compatibility/security tests have passed.
async function activateOwnedIdentifier(db, {uid, identifier}) {
  validateIdentifier(identifier);
  return db.runTransaction(async (tx) => {
    const user = await assertVerifiedAccount(tx, db, uid);
    const ref = accountDoc(db, user.key);
    const snap = await tx.get(ref);
    const state = validateShape(snap.exists ? record(snap) : null,
        user.originalId, user.key);
    await validateVerifiedOwned(tx, db, user.key, state);
    if (!state.ownedIds.includes(identifier)) {
      reject("permission-denied", "identifier-not-owned");
    }
    if (state.activeId === identifier) return {...state, serverConfirmed: true};
    const updated = {accountKey: user.key, originalId: user.originalId,
      ownedIds: state.ownedIds, activeId: identifier, updatedAt: new Date()};
    if (snap.exists) tx.update(ref, {
      activeId: identifier, updatedAt: updated.updatedAt,
    });
    else tx.create(ref, {...updated, createdAt: updated.updatedAt});
    return {...state, activeId: identifier, serverConfirmed: true};
  }, {maxAttempts: 7});
}

// Construct this server-only catalog from a separately protected 100-name
// file; never serialize names to mobile, public repository, or client config.
// Deliberately rejects unset or partial lists (fail closed).
function privateReservedCatalog(names) {
  if (!Array.isArray(names) || names.length !== 100 ||
      !names.every(x => typeof x === "string" &&
        /^[A-Z0-9]{4,12}$/.test(x)) ||
      new Set(names).size !== 100) {
    reject("failed-precondition", "verified-private-100-admin-catalog-required");
  }
  const allowed = new Set(names.map(name => "@DEDA-" + name));
  return Object.freeze({
    contains(identifier) {return allowed.has(identifier);},
    count: allowed.size,
  });
}

async function adminGrantReservedIdentifier(db, {
  adminUid, recipientOriginalId, identifier, color, privateCatalog,
}) {
  validateIdentifier(identifier);
  if (!ORIGINAL_PATTERN.test(recipientOriginalId || "") ||
      !DESIGN_COLORS.includes(color) ||
      !privateCatalog || privateCatalog.count !== 100 ||
      typeof privateCatalog.contains !== "function" ||
      !privateCatalog.contains(identifier)) {
    reject("permission-denied", "only-owner-private-admin-catalog-grants");
  }
  return db.runTransaction(async (tx) => {
    const actor = await assertVerifiedAccount(tx, db, adminUid);
    const accessSnap = await tx.get(
        db.collection("admin_entry_access").doc(actor.key));
    const access = record(accessSnap);
    if (!accessSnap.exists || access.accountKey !== actor.key ||
        access.active !== true || access.status !== "active" ||
        access.allowedRole !== "general_manager" ||
        access.accessType !== "general_manager_gateway") {
      reject("permission-denied", "only-verified-general-manager-can-grant");
    }

    // Recipient selected by ORIGINAL registered public ID, not client-supplied
    // accountKey or Firebase UID. No location sharing permissions are given.
    const shareSnap = await tx.get(
        db.collection("deda_share_ids").doc(recipientOriginalId));
    const share = record(shareSnap);
    if (!shareSnap.exists || share.kind !== "personal" ||
        share.active !== true || share.publicId !== recipientOriginalId ||
        typeof share.ownerUid !== "string" || !share.ownerUid) {
      reject("permission-denied", "recipient-original-registration-required");
    }
    const ownerSnap = await tx.get(db.collection("users").doc(share.ownerUid));
    const targetKey = record(ownerSnap).accountKey;
    if (!ownerSnap.exists || typeof targetKey !== "string" ||
        !ACCOUNT_PATTERN.test(targetKey) ||
        record(ownerSnap).sharePersonalId !== recipientOriginalId) {
      reject("permission-denied", "recipient-account-verification-required");
    }

    const targetRef = accountDoc(db, targetKey);
    const registryRef = registryDoc(db, identifier);
    const aliasRef = aliasDoc(db, identifier);
    const collisionRef = db.collection("deda_share_ids").doc(identifier);
    const [targetSnap, registrySnap, aliasSnap, collisionSnap] =
        await Promise.all([tx.get(targetRef), tx.get(registryRef),
          tx.get(aliasRef), tx.get(collisionRef)]);
    if (registrySnap.exists || aliasSnap.exists || collisionSnap.exists) {
      reject("already-exists", "identifier-globally-reserved-or-owned");
    }
    const state = validateShape(targetSnap.exists ? record(targetSnap) : null,
        recipientOriginalId, targetKey);
    await validateVerifiedOwned(tx, db, targetKey, state);
    if (state.ownedIds.length >= MAX_OWNED) {
      reject("resource-exhausted", "identifier-holdings-limit");
    }
    const now = new Date();
    const ownedIds = [...state.ownedIds, identifier];
    const receiptId = hashed(targetKey + ":" + identifier);
    const giftRef = db.collection("deda_admin_identifier_grants").doc(receiptId);
    const oldGift = await tx.get(giftRef);
    if (oldGift.exists) reject("already-exists", "grant-receipt-already-present");

    // Every read finished before the first write. Atomic global reservation.
    tx.create(registryRef, {
      identifier, accountKey: targetKey, originalId: recipientOriginalId,
      status: "owned", acquisition: "general_manager_gift",
      assignedColor: color, grantedByAccountKey: actor.key, createdAt: now,
    });
    tx.create(aliasRef, {
      identifier, accountKey: targetKey, originalId: recipientOriginalId,
      kind: "permanent_alias", createdAt: now,
    });
    const next = {
      accountKey: targetKey, originalId: recipientOriginalId,
      activeId: state.activeId, ownedIds, updatedAt: now,
    };
    if (targetSnap.exists) tx.update(targetRef, {
      ownedIds, updatedAt: now,
    });
    else tx.create(targetRef, {...next, createdAt: now});
    tx.create(giftRef, {
      accountKey: targetKey, identifier, originalId: recipientOriginalId,
      color, grantedByAccountKey: actor.key, createdAt: now,
    });
    return {
      originalId: recipientOriginalId, activeId: state.activeId,
      ownedIds, giftedIdentifier: identifier, assignedColor: color,
      serverConfirmed: true,
    };
  }, {maxAttempts: 7});
}

// Trusted SERVER-ONLY identity/alias resolver, not location access.
// Never expose this method as permission to view/share a recipient's location.
async function resolveIdentifierAlias(db, {identifier}) {
  validateIdentifier(identifier);
  const direct = await db.collection("deda_share_ids").doc(identifier).get();
  if (direct.exists) {
    const share = record(direct);
    if (share.publicId !== identifier || share.kind !== "personal" ||
        share.active !== true) return null;
    const owner = await db.collection("users").doc(share.ownerUid || "").get();
    if (!owner.exists || typeof record(owner).accountKey !== "string") return null;
    return {originalId: identifier, accountKey: record(owner).accountKey};
  }
  const reg = await registryDoc(db, identifier).get();
  const alias = await aliasDoc(db, identifier).get();
  if (!reg.exists || !alias.exists) return null;
  const r = record(reg), a = record(alias);
  if (r.status !== "owned" || r.accountKey !== a.accountKey ||
      a.identifier !== identifier || r.identifier !== identifier ||
      a.originalId !== r.originalId || a.kind !== "permanent_alias") return null;
  return {originalId: r.originalId, accountKey: r.accountKey};
}

module.exports = {readOwnedIdentifiers, activateOwnedIdentifier,
  adminGrantReservedIdentifier, privateReservedCatalog, resolveIdentifierAlias,
  hashed, DESIGN_COLORS};
