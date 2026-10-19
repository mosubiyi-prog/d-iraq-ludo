"use strict";

// Stage19 PRIVATE read model. Never imported or exported by functions/index.js.
// PRIVATE full 100 suffixes are injected by authorized SERVER configuration
// only, never put in app assets, public GitHub files, logs, or query params.
const {createHash} = require("node:crypto");
const {privateReservedCatalog} =
    require("./deda_intakadha_point15_identifier_ownership_admin_gifts_2026_10_19.js");

const SUFFIX = /^[A-Z0-9]{4,12}$/;
const ORIGINAL = /^@DEDA-[A-Z0-9]{6}$/;
const KEY = /^[A-Za-z0-9_-]{4,160}$/;
const UID = /^[A-Za-z0-9_-]{1,160}$/;
const COLORS = new Set(["gold", "diamond", "royal", "pink"]);

function fail(code, message) {
  const e = new Error(message);
  e.code = code;
  throw e;
}
function record(snapshot) {
  return snapshot.exists ? snapshot.data() || {} : {};
}
function hash(value) {
  return createHash("sha256").update(value, "utf8").digest("hex");
}
function createPrivate100AdminReader(db, privateSuffixes) {
  if (!db || typeof db.runTransaction !== "function" ||
      !Array.isArray(privateSuffixes) || privateSuffixes.length !== 100 ||
      !privateSuffixes.every(x => typeof x === "string" && SUFFIX.test(x)) ||
      new Set(privateSuffixes).size !== 100) {
    fail("failed-precondition", "owner-private-100-required");
  }
  // Leverage the existing strict private grant-catalog construction.
  privateReservedCatalog(privateSuffixes);
  const identifiers = privateSuffixes.map(x => "@DEDA-" + x);
  return Object.freeze({
    async readForGeneralManager(uid) {
      if (typeof uid !== "string" || !UID.test(uid)) {
        fail("unauthenticated", "verified-uid-required");
      }
      return db.runTransaction(async (tx) => {
        const users = db.collection("users");
        const [userSnap, sessionSnap] = await Promise.all([
          tx.get(users.doc(uid)),
          tx.get(db.collection("deda_sessions").doc(uid)),
        ]);
        const user = record(userSnap), session = record(sessionSnap);
        const key = user.accountKey, original = user.sharePersonalId;
        if (!userSnap.exists || !sessionSnap.exists ||
            typeof key !== "string" || !KEY.test(key) ||
            typeof original !== "string" || !ORIGINAL.test(original) ||
            session.uid !== uid || session.accountKey !== key) {
          fail("permission-denied", "verified-admin-session-required");
        }
        const [shareSnap, accessSnap] = await Promise.all([
          tx.get(db.collection("deda_share_ids").doc(original)),
          tx.get(db.collection("admin_entry_access").doc(key)),
        ]);
        const share = record(shareSnap), access = record(accessSnap);
        if (!shareSnap.exists || share.kind !== "personal" ||
            share.publicId !== original || share.active !== true ||
            typeof share.ownerUid !== "string" || !share.ownerUid ||
            !accessSnap.exists || access.accountKey !== key ||
            access.active !== true || access.status !== "active" ||
            access.allowedRole !== "general_manager" ||
            access.accessType !== "general_manager_gateway") {
          fail("permission-denied", "verified-general-manager-only");
        }
        const originalOwner = await tx.get(users.doc(share.ownerUid));
        if (!originalOwner.exists || record(originalOwner).accountKey !== key) {
          fail("permission-denied", "admin-original-id-owner-mismatch");
        }
        // Only after verified manager credentials do we inspect exclusive IDs.
        const registries = await Promise.all(identifiers.map(id =>
          tx.get(db.collection("deda_owned_identifier_registry").doc(id))));
        const rows = [];
        const history = [];
        for (let i = 0; i < identifiers.length; i++) {
          const identifier = identifiers[i];
          const reg = record(registries[i]);
          if (!registries[i].exists) {
            rows.push({sequence: i + 1, identifier, status: "available",
              permanentColor: null, ownerOriginalId: null});
            continue;
          }
          if (reg.identifier !== identifier || reg.status !== "owned" ||
              !COLORS.has(reg.assignedColor) ||
              typeof reg.accountKey !== "string" || !KEY.test(reg.accountKey) ||
              !ORIGINAL.test(reg.originalId || "") ||
              !["general_manager_gift", "general_manager_self_use"]
                  .includes(reg.acquisition)) {
            fail("failed-precondition", "invalid-exclusive-color-or-ownership");
          }
          const receiptSnap = await tx.get(
              db.collection("deda_admin_identifier_grants").doc(
                hash(reg.accountKey + ":" + identifier)));
          const receipt = record(receiptSnap);
          if (!receiptSnap.exists || receipt.accountKey !== reg.accountKey ||
              receipt.identifier !== identifier ||
              receipt.originalId !== reg.originalId ||
              receipt.color !== reg.assignedColor) {
            fail("failed-precondition", "exclusive-grant-audit-proof-missing");
          }
          const kind = reg.acquisition === "general_manager_self_use"
            ? "self_used" : "gifted";
          const dt = receipt.createdAt;
          const date = dt instanceof Date ? dt :
            dt && typeof dt.toDate === "function" ? dt.toDate() : null;
          if (!(date instanceof Date) || Number.isNaN(date.getTime())) {
            fail("failed-precondition", "missing-exact-grant-timestamp");
          }
          rows.push({sequence: i + 1, identifier, status: kind,
            permanentColor: reg.assignedColor,
            ownerOriginalId: reg.originalId});
          history.push({identifier, recipientOriginalId: reg.originalId,
            color: reg.assignedColor, kind, grantedAt: date.toISOString()});
        }
        history.sort((a, b) => b.grantedAt.localeCompare(a.grantedAt));
        return {total: 100, serverConfirmed: true,
          identifiers: rows, history};
      }, {maxAttempts: 5});
    },
  });
}
module.exports = {createPrivate100AdminReader};
