"use strict";

// STAGE19 PRIVATE SERVER DRAFT ONLY — no production exports/deploy.
// Future Firebase onCall MUST require request.auth.uid, enforceAppCheck and
// admin_entry_access. Never take manager role, accountKey or private names
// from the mobile client; all permanent color writes occur server-side.
const {createHash} = require("node:crypto");
const {privateReservedCatalog, adminGrantReservedIdentifier} =
  require("./deda_intakadha_point15_identifier_ownership_admin_gifts_2026_10_19.js");

const UID = /^[A-Za-z0-9_-]{1,160}$/;
const KEY = /^[A-Za-z0-9_-]{4,160}$/;
const ORIGINAL = /^@DEDA-[A-Z0-9]{6}$/;
const PREMIUM = /^@DEDA-[A-Z0-9]{4,12}$/;
const COLORS = Object.freeze(["gold", "diamond", "royal", "pink"]);
const MAX_OWNED = 250;

function fail(code, reason) {
  const error = new Error(reason);
  error.code = code;
  throw error;
}
function data(s) {return s.exists ? s.data() || {} : {};}
function hashed(s) {return createHash("sha256").update(s, "utf8").digest("hex");}

function createStage19ManagerActions(db, privateSuffixes) {
  if (!db || typeof db.runTransaction !== "function") {
    fail("failed-precondition", "verified-server-db-required");
  }
  // Not a list shipped to clients or a public GitHub source file.
  const privateCatalog = privateReservedCatalog(privateSuffixes);

  function verifyChoice(identifier, color) {
    if (typeof identifier !== "string" || !PREMIUM.test(identifier) ||
        !privateCatalog.contains(identifier) || !COLORS.includes(color)) {
      fail("permission-denied", "invalid-admin-reserved-id-or-color");
    }
  }

  async function selfUse({adminUid, identifier, color}) {
    verifyChoice(identifier, color);
    if (typeof adminUid !== "string" || !UID.test(adminUid)) {
      fail("unauthenticated", "verified-manager-session-required");
    }
    return db.runTransaction(async (tx) => {
      const userRef = db.collection("users").doc(adminUid);
      const sessionRef = db.collection("deda_sessions").doc(adminUid);
      const [userSnap, sessionSnap] = await Promise.all([
        tx.get(userRef), tx.get(sessionRef),
      ]);
      const user = data(userSnap), session = data(sessionSnap);
      const key = user.accountKey, originalId = user.sharePersonalId;
      if (!userSnap.exists || !sessionSnap.exists ||
          typeof key !== "string" || !KEY.test(key) ||
          typeof originalId !== "string" || !ORIGINAL.test(originalId) ||
          session.uid !== adminUid || session.accountKey !== key) {
        fail("permission-denied", "verified-account-and-session-required");
      }
      const shareRef = db.collection("deda_share_ids").doc(originalId);
      const accessRef = db.collection("admin_entry_access").doc(key);
      const [shareSnap, accessSnap, adminSnap] = await Promise.all([
        tx.get(shareRef), tx.get(accessRef),
        tx.get(db.collection("admins").doc(adminUid)),
      ]);
      const share = data(shareSnap), access = data(accessSnap);
      const admin = data(adminSnap);
      if (!shareSnap.exists || share.publicId !== originalId ||
          share.kind !== "personal" || share.active !== true ||
          typeof share.ownerUid !== "string" || !share.ownerUid ||
          !accessSnap.exists || access.accountKey !== key ||
          access.active !== true || access.status !== "active" ||
          access.allowedRole !== "general_manager" ||
          access.accessType !== "general_manager_gateway" ||
          !adminSnap.exists || admin.active !== true ||
          admin.status !== "active" || admin.role !== "general_manager") {
        fail("permission-denied", "verified-general-manager-required");
      }
      const originalOwner = await tx.get(
          db.collection("users").doc(share.ownerUid));
      if (!originalOwner.exists || data(originalOwner).accountKey !== key) {
        fail("permission-denied", "manager-original-account-mismatch");
      }

      const accountHash = hashed(key);
      const ledgerRef = db.collection("deda_owned_identifier_accounts")
        .doc(accountHash);
      const registryRef = db.collection("deda_owned_identifier_registry")
        .doc(identifier);
      const aliasRef = db.collection("deda_owned_identifier_aliases")
        .doc(identifier);
      const collisionRef = db.collection("deda_share_ids").doc(identifier);
      const receiptRef = db.collection("deda_admin_identifier_grants")
        .doc(hashed(key + ":" + identifier));
      const [ledgerSnap, registrySnap, aliasSnap, collisionSnap, receiptSnap] =
        await Promise.all([ledgerRef, registryRef, aliasRef, collisionRef,
          receiptRef].map(ref => tx.get(ref)));
      if (registrySnap.exists || aliasSnap.exists || collisionSnap.exists ||
          receiptSnap.exists) {
        fail("already-exists", "exclusive-id-used-or-gifted");
      }
      const old = data(ledgerSnap);
      const ownedIds = ledgerSnap.exists ? old.ownedIds : [originalId];
      if (ledgerSnap.exists &&
          (old.accountKey !== key || old.originalId !== originalId ||
           !Array.isArray(ownedIds) || ownedIds[0] !== originalId ||
           ownedIds.length < 1 || ownedIds.length >= MAX_OWNED ||
           new Set(ownedIds).size !== ownedIds.length ||
           !ownedIds.every(x => typeof x === "string" && PREMIUM.test(x)) ||
           !ownedIds.includes(old.activeId))) {
        fail("failed-precondition", "invalid-owner-ledger");
      }
      if (ownedIds.length >= MAX_OWNED || ownedIds.includes(identifier)) {
        fail("resource-exhausted", "owned-id-duplicate-or-limit");
      }
      const priorPremiums = ownedIds.slice(1);
      const prior = await Promise.all([
        ...priorPremiums.map(id => db.collection(
          "deda_owned_identifier_registry").doc(id)),
        ...priorPremiums.map(id => db.collection(
          "deda_owned_identifier_aliases").doc(id)),
      ].map(ref => tx.get(ref)));
      for (let i = 0; i < priorPremiums.length; i++) {
        const id = priorPremiums[i];
        const reg = data(prior[i]), alias = data(prior[i + priorPremiums.length]);
        if (!prior[i].exists || !prior[i + priorPremiums.length].exists ||
            reg.accountKey !== key || reg.identifier !== id ||
            reg.originalId !== originalId || reg.status !== "owned" ||
            alias.accountKey !== key || alias.identifier !== id ||
            alias.originalId !== originalId ||
            alias.kind !== "permanent_alias") {
          fail("failed-precondition", "existing-ownership-proof-invalid");
        }
      }
      // Every read precedes every write. These creates cannot overwrite an
      // already-used ID or color. Firestore retries transaction on contention.
      const now = new Date();
      tx.create(registryRef, {
        identifier, accountKey: key, originalId, status: "owned",
        acquisition: "general_manager_self_use", assignedColor: color,
        createdAt: now,
      });
      tx.create(aliasRef, {
        identifier, accountKey: key, originalId,
        kind: "permanent_alias", createdAt: now,
      });
      if (ledgerSnap.exists) {
        tx.update(ledgerRef, {
          ownedIds: [...ownedIds, identifier],
          activeId: identifier, updatedAt: now,
        });
      } else {
        tx.create(ledgerRef, {
          accountKey: key, originalId,
          activeId: identifier, ownedIds: [originalId, identifier],
          createdAt: now, updatedAt: now,
        });
      }
      tx.create(receiptRef, {
        accountKey: key, identifier, originalId,
        color, kind: "self_used", createdAt: now,
        grantedByAccountKey: key,
      });
      return {identifier, permanentColor: color,
        originalId, activeId: identifier, serverConfirmed: true};
    }, {maxAttempts: 7});
  }

  async function gift({adminUid, recipientOriginalId, identifier, color}) {
    verifyChoice(identifier, color);
    if (typeof adminUid !== "string" || !UID.test(adminUid) ||
        typeof recipientOriginalId !== "string" ||
        !ORIGINAL.test(recipientOriginalId)) {
      fail("permission-denied", "verified-manager-and-recipient-required");
    }
    // Existing point15 transaction already locks exactly ONE assignedColor
    // with tx.create registry/alias/grant receipt, verifies recipient account,
    // validates manager role and rejects all global collisions.
    const verified = await adminGrantReservedIdentifier(db, {
      adminUid, recipientOriginalId, identifier, color, privateCatalog,
      requireCanonicalManager: true,
    });
    if (verified.serverConfirmed !== true ||
        verified.giftedIdentifier !== identifier ||
        verified.assignedColor !== color) {
      fail("failed-precondition", "gift-was-not-server-verified");
    }
    return {identifier, permanentColor: color,
      recipientOriginalId, serverConfirmed: true};
  }

  return Object.freeze({selfUse, gift});
}
module.exports = {createStage19ManagerActions};
