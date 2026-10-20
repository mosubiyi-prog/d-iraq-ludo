"use strict";

// DEDA Stage18 — OFFLINE SERVER STAGING ONLY; NOT imported by functions/index.js.
// No client-supplied price, account key, ownership, role or wallet.
// Never use Group002 proposals as an automatic sales catalog.
// An explicitly reviewed server configuration must supply ALL 100 reserved
// Group001 suffixes and individually owner-approved sellable Group002 suffixes.
const {createHash} = require("node:crypto");
const PRICE_DIAMONDS = 10000;
const ACCOUNT_RE = /^[A-Za-z0-9_-]{4,160}$/;
const UID_RE = /^[A-Za-z0-9_-]{1,160}$/;
const REQUEST_RE = /^[A-Za-z0-9_-]{8,80}$/;
const ORIGINAL_RE = /^@DEDA-[A-Z0-9]{6}$/;
const SALE_RE = /^@DEDA-[A-Z0-9]{6}$/;
// Existing account inventory can also include owner-exclusive Group001 IDs
// of 4–12 characters. Only NEW Group002 sale selections stay six-character.
const OWNED_RE = /^@DEDA-[A-Z0-9]{4,12}$/;
const SUFFIX_RE = /^[A-Z0-9]{6}$/;
const EXCLUSIVE_SUFFIX_RE = /^[A-Z0-9]{4,12}$/;
const MAX_OWNED = 250;
const approvedCatalogInstances = new WeakSet();

function fail(code, message) {
  const e = new Error(message);
  e.code = code;
  throw e;
}
function data(snapshot) {
  return snapshot.exists ? snapshot.data() || {} : {};
}
function hash(value) {
  return createHash("sha256").update(value, "utf8").digest("hex");
}
function balance(value) {
  if (!Number.isSafeInteger(value) || value < 0 || value > 1073741824) {
    fail("failed-precondition", "untrusted-server-balance");
  }
  return value;
}
function safeSuffixes(values, expectedCount, label, pattern = SUFFIX_RE) {
  if (!Array.isArray(values) ||
      (expectedCount === null ? values.length < 1 || values.length > 100
        : values.length !== expectedCount) ||
      !values.every(x => typeof x === "string" && pattern.test(x)) ||
      new Set(values).size !== values.length) {
    fail("failed-precondition", "invalid-" + label + "-catalog");
  }
  return new Set(values.map(x => "@DEDA-" + x));
}

// OWNER-REVIEWED server inputs only, NEVER caller input or raw proposal JSON.
// The constructor deliberately fails without an entire private reserved 100.
function createApprovedSaleCatalog({approvedSuffixes, reservedSuffixes} = {}) {
  const reserved = safeSuffixes(reservedSuffixes, 100, "private-reserved", EXCLUSIVE_SUFFIX_RE);
  const approved = safeSuffixes(approvedSuffixes, null, "approved-sale");
  for (const identifier of approved) {
    if (reserved.has(identifier)) {
      fail("failed-precondition", "reserved-identifier-cannot-be-listed");
    }
  }
  const catalog = Object.freeze({
    count: approved.size,
    allows(identifier) {
      return approved.has(identifier) && !reserved.has(identifier);
    },
  });
  approvedCatalogInstances.add(catalog);
  return catalog;
}

function validateOwnedLedger(snapshot, key, original) {
  if (!snapshot.exists) {
    return {originalId: original, activeId: original, ownedIds: [original]};
  }
  const row = data(snapshot);
  if (row.accountKey !== key || row.originalId !== original ||
      !Array.isArray(row.ownedIds) || row.ownedIds[0] !== original ||
      row.ownedIds.length < 1 || row.ownedIds.length > MAX_OWNED ||
      new Set(row.ownedIds).size !== row.ownedIds.length ||
      !row.ownedIds.every(x => typeof x === "string" && OWNED_RE.test(x)) ||
      !row.ownedIds.includes(row.activeId)) {
    fail("failed-precondition", "unverified-owned-identifier-ledger");
  }
  return {originalId: original, activeId: row.activeId,
    ownedIds: [...row.ownedIds]};
}

async function checkoutVerifiedIdentifier(db, {
  uid, identifier, requestId, approvedCatalog,
} = {}) {
  if (!db || typeof db.runTransaction !== "function" ||
      !approvedCatalogInstances.has(approvedCatalog)) {
    fail("unavailable", "verified-server-sale-catalog-required");
  }
  if (typeof uid !== "string" || !UID_RE.test(uid)) {
    fail("unauthenticated", "server-authentication-required");
  }
  if (typeof identifier !== "string" || !SALE_RE.test(identifier) ||
      !approvedCatalog.allows(identifier) ||
      typeof requestId !== "string" || !REQUEST_RE.test(requestId)) {
    fail("permission-denied", "identifier-not-approved-for-sale");
  }

  return db.runTransaction(async (tx) => {
    const users = db.collection("users");
    const uref = users.doc(uid);
    const sessionRef = db.collection("deda_sessions").doc(uid);
    const [userSnap, sessionSnap] = await Promise.all([
      tx.get(uref), tx.get(sessionRef),
    ]);
    const user = data(userSnap), session = data(sessionSnap);
    const key = user.accountKey, original = user.sharePersonalId;
    if (!userSnap.exists || !sessionSnap.exists ||
        typeof key !== "string" || !ACCOUNT_RE.test(key) ||
        typeof original !== "string" || !ORIGINAL_RE.test(original) ||
        session.accountKey !== key || session.uid !== uid) {
      fail("permission-denied", "verified-account-and-session-required");
    }
    const shareRef = db.collection("deda_share_ids").doc(original);
    const shareSnap = await tx.get(shareRef), share = data(shareSnap);
    if (!shareSnap.exists || share.kind !== "personal" ||
        share.active !== true || share.publicId !== original ||
        typeof share.ownerUid !== "string" || !share.ownerUid) {
      fail("permission-denied", "original-identifier-proof-required");
    }
    // The original share UID can predate the current anonymous auth UID.
    const registered = await tx.get(users.doc(share.ownerUid));
    if (!registered.exists || data(registered).accountKey !== key) {
      fail("permission-denied", "original-account-owner-mismatch");
    }

    const accountHash = hash(key);
    const ledgerRef = db.collection("deda_owned_identifier_accounts").doc(accountHash);
    const registeredRef = db.collection("deda_owned_identifier_registry").doc(identifier);
    const aliasRef = db.collection("deda_owned_identifier_aliases").doc(identifier);
    const collisionRef = db.collection("deda_share_ids").doc(identifier);
    const saleRef = db.collection("deda_verified_id_sale_catalog").doc(identifier);
    const receiptRef = db.collection("deda_id_purchase_requests").doc(accountHash)
        .collection("requests").doc(requestId);
    const giftRef = db.collection("deda_diamond_gift_balances").doc(original);
    const gmAccessRef = db.collection("admin_entry_access").doc(key);
    const gmAdminRef = db.collection("admins").doc(uid);
    const gmWalletRef = db.collection("deda_gm_personal_diamond_wallets").doc(key);

    const [ledgerSnap, regSnap, aliasSnap, collisionSnap, saleSnap,
      receiptSnap, giftSnap, gmAccessSnap, gmAdminSnap, gmWalletSnap] = await Promise.all([
      tx.get(ledgerRef), tx.get(registeredRef), tx.get(aliasRef),
      tx.get(collisionRef), tx.get(saleRef), tx.get(receiptRef),
      tx.get(giftRef), tx.get(gmAccessRef), tx.get(gmAdminRef),
      tx.get(gmWalletRef),
    ]);
    if (receiptSnap.exists) {
      const old = data(receiptSnap);
      if (old.accountKey !== key || old.identifier !== identifier ||
          old.requestId !== requestId || old.diamondsCharged !== PRICE_DIAMONDS ||
          old.serverConfirmed !== true || typeof old.transactionId !== "string" ||
          !old.transactionId) {
        fail("failed-precondition", "request-id-conflicts-with-existing-receipt");
      }
      return {identifier, transactionId: old.transactionId,
        diamondsCharged: PRICE_DIAMONDS, serverConfirmed: true,
        alreadyOwned: false};
    }
    const ledger = validateOwnedLedger(ledgerSnap, key, original);
    if (ledger.ownedIds.includes(identifier) || regSnap.exists ||
        aliasSnap.exists || collisionSnap.exists) {
      fail("already-exists", "identifier-already-registered-or-owned");
    }
    if (ledger.ownedIds.length >= MAX_OWNED) {
      fail("resource-exhausted", "identifier-ownership-cap-reached");
    }

    // A raw Group002 proposal does NOT pass: approved server inventory doc
    // must have been explicitly reviewed, unlocked and priced by server.
    const sale = data(saleSnap);
    if (!saleSnap.exists || sale.identifier !== identifier ||
        sale.group !== "002" || sale.status !== "verified_available" ||
        sale.ownerApproved !== true || sale.priceDiamonds !== PRICE_DIAMONDS) {
      fail("failed-precondition", "server-verified-inventory-not-for-sale");
    }

    // Never debit old locally stored ad/task diamonds. Migration is a
    // separate owner-reviewed prerequisite before this can be enabled live.
    const gifted = data(giftSnap);
    if (giftSnap.exists && gifted.publicId !== original) {
      fail("failed-precondition", "gift-wallet-original-id-mismatch");
    }
    const gifts = giftSnap.exists ? balance(gifted.balance) : 0;
    const gmAccess = data(gmAccessSnap), gmWallet = data(gmWalletSnap);
    const currentGM = data(gmAdminSnap);
    if (gmWalletSnap.exists && gmWallet.accountKey !== key) {
      fail("failed-precondition", "gm-personal-wallet-owner-mismatch");
    }
    const isGM = gmAccessSnap.exists && gmAccess.accountKey === key &&
        gmAccess.active === true && gmAccess.status === "active" &&
        gmAccess.allowedRole === "general_manager" &&
        gmAccess.accessType === "general_manager_gateway" &&
        gmAdminSnap.exists && currentGM.active === true &&
        currentGM.status === "active" &&
        currentGM.role === "general_manager";
    const personal = isGM && gmWalletSnap.exists ? balance(gmWallet.balance) : 0;
    if (PRICE_DIAMONDS > gifts + personal) {
      fail("failed-precondition", "insufficient-verified-diamonds-local-excluded");
    }
    const fromGift = Math.min(gifts, PRICE_DIAMONDS);
    const fromGM = PRICE_DIAMONDS - fromGift;

    // Verify all older premium IDs before touching wallet/ownership.
    for (const prior of ledger.ownedIds.slice(1)) {
      const [pRegSnap, pAliasSnap] = await Promise.all([
        tx.get(db.collection("deda_owned_identifier_registry").doc(prior)),
        tx.get(db.collection("deda_owned_identifier_aliases").doc(prior)),
      ]);
      const pReg = data(pRegSnap), pAlias = data(pAliasSnap);
      if (!pRegSnap.exists || !pAliasSnap.exists ||
          pReg.identifier !== prior || pReg.accountKey !== key ||
          pReg.originalId !== original || pReg.status !== "owned" ||
          pAlias.identifier !== prior || pAlias.accountKey !== key ||
          pAlias.originalId !== original || pAlias.kind !== "permanent_alias") {
        fail("failed-precondition", "prior-owned-identifier-proof-invalid");
      }
    }

    // All reads finish before the first mutation: one atomic Firestore tx.
    const now = new Date();
    const transactionId = hash(key + ":" + requestId + ":" + identifier);
    if (fromGift > 0) {
      tx.update(giftRef, {balance: gifts - fromGift, updatedAt: now});
    }
    if (fromGM > 0) {
      tx.update(gmWalletRef, {balance: personal - fromGM, updatedAt: now});
    }
    tx.create(registeredRef, {
      identifier, accountKey: key, originalId: original,
      status: "owned", acquisition: "diamond_purchase",
      createdAt: now,
    });
    tx.create(aliasRef, {
      identifier, accountKey: key, originalId: original,
      kind: "permanent_alias", createdAt: now,
    });
    if (ledgerSnap.exists) {
      tx.update(ledgerRef, {
        ownedIds: [...ledger.ownedIds, identifier], updatedAt: now,
      });
    } else {
      tx.create(ledgerRef, {
        accountKey: key, originalId: original, activeId: original,
        ownedIds: [original, identifier], createdAt: now, updatedAt: now,
      });
    }
    tx.update(saleRef, {
      status: "sold", ownerAccountHash: accountHash, soldAt: now,
    });
    tx.create(receiptRef, {
      accountKey: key, originalId: original, identifier,
      requestId, transactionId, diamondsCharged: PRICE_DIAMONDS,
      giftCharged: fromGift, gmPersonalCharged: fromGM,
      serverConfirmed: true, createdAt: now,
    });
    return {identifier, transactionId,
      diamondsCharged: PRICE_DIAMONDS, serverConfirmed: true,
      alreadyOwned: false};
  }, {maxAttempts: 7});
}
module.exports = {PRICE_DIAMONDS, createApprovedSaleCatalog,
  checkoutVerifiedIdentifier};
