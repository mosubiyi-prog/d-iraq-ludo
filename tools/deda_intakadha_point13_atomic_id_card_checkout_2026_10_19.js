"use strict";

// DEDA «إنت كدها» point13 — STAGING ONLY, not deployed nor exported from
// functions/index.js. A future callable wrapper must derive uid from auth,
// never accept an accountKey, phone, wallet or price from the caller.
// Tested only against demo- Firestore Emulator data.

const {createHash} = require("node:crypto");

const PRICE = 5000;
const COLORS = Object.freeze(["gold", "diamond", "royal", "pink"]);
const ID_PATTERN = /^[A-Za-z0-9_-]{8,80}$/;
const ACCOUNT_PATTERN = /^[A-Za-z0-9_-]{4,160}$/;
const PERSONAL_ID_PATTERN = /^@DEDA-[A-Z0-9]{6}$/;

function reject(code, message) {
  const error = new Error(message);
  error.code = code;
  throw error;
}

function safeBalance(value) {
  if (!Number.isSafeInteger(value) || value < 0 || value > 1073741824) {
    reject("failed-precondition", "invalid-server-wallet-balance");
  }
  return value;
}

function accountHash(accountKey) {
  return createHash("sha256").update(accountKey, "utf8").digest("hex");
}

function recordOf(document) {
  return document.exists ? document.data() || {} : {};
}

async function checkoutIdCard(db, {uid, color, requestId}) {
  if (typeof uid !== "string" || uid.length < 1 || uid.length > 160) {
    reject("unauthenticated", "verified-account-session-required");
  }
  if (!COLORS.includes(color) || typeof requestId !== "string" ||
      !ID_PATTERN.test(requestId)) {
    reject("invalid-argument", "invalid-design-or-request-id");
  }

  const userRef = db.collection("users").doc(uid);
  const sessionRef = db.collection("deda_sessions").doc(uid);

  // No trust in a client-supplied ID, accountKey, wallet, amount or claims.
  // Include session reads IN the transaction: auth state cannot switch
  // between preflight and wallet/entitlement commit.
  return db.runTransaction(async (tx) => {
    const [userSnapshot, sessionSnapshot] = await Promise.all([
      tx.get(userRef), tx.get(sessionRef),
    ]);
    const user = recordOf(userSnapshot);
    const session = recordOf(sessionSnapshot);
    const key = user.accountKey;
    const publicId = user.sharePersonalId;
    if (!userSnapshot.exists || !sessionSnapshot.exists ||
        typeof key !== "string" || !ACCOUNT_PATTERN.test(key) ||
        session.accountKey !== key ||
        session.uid !== uid || user.accountKey !== key ||
        typeof publicId !== "string" || !PERSONAL_ID_PATTERN.test(publicId)) {
      reject("permission-denied", "verified-session-and-personal-id-required");
    }

    const hash = accountHash(key);
    const shareRef = db.collection("deda_share_ids").doc(publicId);
    const entitlementRef = db.collection("deda_id_card_entitlements").doc(hash);
    const receiptRef = db.collection("deda_id_card_purchase_requests")
        .doc(hash).collection("requests").doc(requestId);
    const giftRef = db.collection("deda_diamond_gift_balances").doc(publicId);
    const gmEntryRef = db.collection("admin_entry_access").doc(key);
    const gmWalletRef = db.collection("deda_gm_personal_diamond_wallets").doc(key);

    const [shareSnap, receiptSnap, ownedSnap, giftedSnap, gmEntrySnap, gmSnap] =
        await Promise.all([
          tx.get(shareRef), tx.get(receiptRef), tx.get(entitlementRef),
          tx.get(giftRef), tx.get(gmEntryRef), tx.get(gmWalletRef),
        ]);
    const share = recordOf(shareSnap);
    if (!shareSnap.exists || share.kind !== "personal" ||
        share.active !== true || share.publicId !== publicId ||
        typeof share.ownerUid !== "string" || !share.ownerUid.trim()) {
      reject("permission-denied", "registered-personal-id-required");
    }
    // Old Firebase UIDs may rotate when the same DEDA account logs back in.
    // Check the account key of the originally registered share owner.
    const registeredOwnerRef = db.collection("users").doc(share.ownerUid);
    const registeredOwnerSnap = await tx.get(registeredOwnerRef);
    if (!registeredOwnerSnap.exists ||
        recordOf(registeredOwnerSnap).accountKey !== key) {
      reject("permission-denied", "personal-id-owner-mismatch");
    }

    const existingReceipt = recordOf(receiptSnap);
    if (receiptSnap.exists) {
      if (existingReceipt.accountKey !== key ||
          existingReceipt.color !== color ||
          existingReceipt.serverConfirmed !== true ||
          typeof existingReceipt.transactionId !== "string" ||
          !existingReceipt.transactionId) {
        reject("failed-precondition", "request-id-reused-for-another-operation");
      }
      // Exactly-once response even after lost connectivity or retries.
      return {
        transactionId: existingReceipt.transactionId,
        color, diamondsCharged: existingReceipt.diamondsCharged,
        serverConfirmed: true, alreadyOwned: existingReceipt.alreadyOwned === true,
      };
    }
    const entitlement = recordOf(ownedSnap);
    if (ownedSnap.exists && entitlement.accountKey !== key) {
      reject("failed-precondition", "entitlement-account-mismatch");
    }
    const colors = entitlement.colors || {};
    if (colors && (typeof colors !== "object" || Array.isArray(colors))) {
      reject("failed-precondition", "malformed-entitlement");
    }
    const alreadyOwned = colors[color] === true;

    // Only server-authoritative balances can be spent. Older local
    // SharedPreferences diamonds are NOT migrated, claimed or charged here.
    const giftData = recordOf(giftedSnap);
    if (giftedSnap.exists && giftData.publicId !== publicId) {
      reject("failed-precondition", "gift-wallet-personal-id-mismatch");
    }
    const giftBalance = giftedSnap.exists ? safeBalance(giftData.balance) : 0;

    const entry = recordOf(gmEntrySnap);
    const eligibleGM = gmEntrySnap.exists &&
        entry.accountKey === key && entry.active === true &&
        entry.status === "active" && entry.allowedRole === "general_manager" &&
        entry.accessType === "general_manager_gateway";
    const personal = recordOf(gmSnap);
    if (gmSnap.exists && personal.accountKey !== key) {
      reject("failed-precondition", "manager-wallet-account-mismatch");
    }
    const gmBalance = eligibleGM && gmSnap.exists ?
      safeBalance(personal.balance) : 0;

    const charge = alreadyOwned ? 0 : PRICE;
    if (charge > giftBalance + gmBalance) {
      reject("failed-precondition",
          "insufficient-verified-server-diamonds-local-wallet-excluded");
    }
    const fromGifts = Math.min(giftBalance, charge);
    const fromGm = charge - fromGifts;
    const transactionId = accountHash(key + ":" + requestId + ":" + color);
    const now = new Date();

    // Reads finished. ALL writes execute as a single Firestore transaction.
    if (fromGifts > 0) {
      tx.update(giftRef, {
        balance: giftBalance - fromGifts,
        updatedAt: now,
      });
    }
    if (fromGm > 0) {
      tx.update(gmWalletRef, {
        balance: gmBalance - fromGm,
        updatedAt: now,
      });
    }
    if (!alreadyOwned) {
      tx.set(entitlementRef, {
        accountKey: key,
        colors: {...colors, [color]: true},
        updatedAt: now,
        ...(!ownedSnap.exists ? {createdAt: now} : {}),
      }, {merge: true});
    }
    tx.create(receiptRef, {
      accountKey: key,
      publicId,
      color,
      transactionId,
      requestId,
      diamondsCharged: charge,
      giftCharged: fromGifts,
      gmPersonalCharged: fromGm,
      alreadyOwned,
      serverConfirmed: true,
      createdAt: now,
    });
    return {
      transactionId, color, diamondsCharged: charge,
      serverConfirmed: true, alreadyOwned,
    };
  }, {maxAttempts: 7});
}

// Expose safe lookup for account-validated entitlement refresh in a LATER
// stage; no client-side direct Firestore reads or writes are authorized.
async function readOwnedCards(db, {uid}) {
  if (typeof uid !== "string" || !uid) {
    reject("unauthenticated", "verified-account-session-required");
  }
  const [user, session] = await Promise.all([
    db.collection("users").doc(uid).get(),
    db.collection("deda_sessions").doc(uid).get(),
  ]);
  if (!user.exists || !session.exists ||
      typeof user.data().accountKey !== "string" ||
      !ACCOUNT_PATTERN.test(user.data().accountKey) ||
      session.data().accountKey !== user.data().accountKey ||
      session.data().uid !== uid) {
    reject("permission-denied", "verified-session-required");
  }
  const hash = accountHash(user.data().accountKey);
  const snapshot = await db.collection("deda_id_card_entitlements").doc(hash).get();
  const row = recordOf(snapshot);
  if (snapshot.exists && row.accountKey !== user.data().accountKey) {
    reject("failed-precondition", "entitlement-account-mismatch");
  }
  return COLORS.filter((color) => (row.colors || {})[color] === true);
}

module.exports = {
  PRICE, COLORS, checkoutIdCard, readOwnedCards, accountHash,
};
