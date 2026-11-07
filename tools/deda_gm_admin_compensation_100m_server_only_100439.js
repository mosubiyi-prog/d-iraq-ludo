"use strict";

/**
 * REVIEW-ONLY trusted Admin SDK allocation helper for DEDA 100439.
 * NOT an HTTP function, NOT scheduled, NOT called by the mobile application.
 * It must never run until the owner independently authorizes the server
 * funding operation and the matching debit-only rules have been reviewed.
 *
 * Set the verified existing general manager ADMIN gift wallet to an EXACT
 * 100m available balance, never personal gems or any recipient account.
 * Credit only the shortfall once (100m - the real pre-existing balance).
 * A server-only approval document + one immutable audit receipt are mandatory.
 */
const OLD_CAP = 1_000_000;
const NEW_CAP = 100_000_000;
const ADDITION = NEW_CAP - OLD_CAP;
const UID = /^[a-zA-Z0-9_-]{4,160}$/;

function deny(reason) {
  const e = new Error("gm-compensation-100m-denied:" + reason);
  e.code = "failed-precondition";
  throw e;
}
function row(snapshot) {
  return snapshot.exists ? (snapshot.data() || {}) : null;
}
function validateBalance(data) {
  if (!data || !Number.isSafeInteger(data.initialBalance) ||
      data.initialBalance !== OLD_CAP ||
      !Number.isSafeInteger(data.balance) ||
      data.balance < 0 || data.balance > OLD_CAP) {
    deny("unexpected-existing-admin-wallet");
  }
}
function validApproval(data, uid) {
  return data && data.adminUid === uid &&
    data.status === "approved" && data.ownerApproved === true &&
    data.provenanceReviewed === true &&
    data.scope === "gm_admin_compensation_only" &&
    data.fromCapDiamonds === OLD_CAP && data.toCapDiamonds === NEW_CAP &&
    data.addDiamonds === ADDITION &&
    typeof data.approvedBy === "string" && data.approvedBy.length > 2;
}

/**
 * Exported for unit tests and an explicit, later owner-reviewed server job.
 * No Firebase init, credentials, or side effects on import.
 */
async function allocateApprovedManagerCompensation(db, {uid, now = new Date()} = {}) {
  if (!db || typeof db.runTransaction !== "function" ||
      typeof db.collection !== "function") deny("server-database-required");
  if (typeof uid !== "string" || !UID.test(uid)) deny("invalid-admin-uid");
  if (!(now instanceof Date) || !Number.isFinite(now.getTime())) deny("invalid-time");
  return db.runTransaction(async tx => {
    const adminRef = db.collection("admins").doc(uid);
    const walletRef = db.collection("deda_admin_diamond_wallets").doc(uid);
    // These approval and audit paths are server-only (no client write rule).
    const approvalRef = db.collection("deda_gm_admin_compensation_approvals").doc(uid);
    const auditRef = db.collection("deda_gm_admin_compensation_allocations").doc(uid);
    const [adminSnapshot, walletSnapshot, approvalSnapshot, auditSnapshot] =
      await Promise.all([tx.get(adminRef), tx.get(walletRef),
                         tx.get(approvalRef), tx.get(auditRef)]);
    const admin = row(adminSnapshot);
    const wallet = row(walletSnapshot);
    const approval = row(approvalSnapshot);
    const audit = row(auditSnapshot);
    if (!admin || admin.role !== "general_manager" ||
        admin.active !== true || admin.status !== "active") {
      deny("verified-active-general-manager-required");
    }
    if (!validApproval(approval, uid)) deny("independent-owner-approval-required");
    if (!wallet || wallet.adminUid !== uid) deny("original-admin-wallet-required");

    if (audit) {
      // Idempotency: do not refund spent credit if the same job is retried.
      if (audit.adminUid !== uid ||
          audit.capIncreaseDiamonds !== ADDITION ||
          !Number.isSafeInteger(audit.addDiamonds) ||
          audit.addDiamonds !== NEW_CAP - audit.balanceBefore ||
          audit.balanceAfter !== NEW_CAP ||
          audit.toCapDiamonds !== NEW_CAP ||
          wallet.initialBalance !== NEW_CAP ||
          !Number.isSafeInteger(wallet.balance) ||
          wallet.balance < 0 || wallet.balance > NEW_CAP) {
        deny("allocation-receipt-wallet-conflict");
      }
      return Object.freeze({alreadyAllocated: true, diamondsAdded: 0,
        balance: wallet.balance, capDiamonds: NEW_CAP, serverProofOnly: true});
    }

    validateBalance(wallet);
    const newBalance = NEW_CAP;
    const credited = NEW_CAP - wallet.balance;
    tx.update(walletRef, {
      initialBalance: NEW_CAP,
      balance: newBalance,
      updatedAt: now,
      compensationAllocationId: uid,
    });
    tx.create(auditRef, {
      adminUid: uid,
      scope: "gm_admin_compensation_only",
      fromCapDiamonds: OLD_CAP,
      toCapDiamonds: NEW_CAP,
      balanceBefore: wallet.balance,
      balanceAfter: newBalance,
      addDiamonds: credited,
      capIncreaseDiamonds: ADDITION,
      approvedBy: approval.approvedBy,
      createdAt: now,
    });
    return Object.freeze({alreadyAllocated: false, diamondsAdded: credited,
      balance: newBalance, capDiamonds: NEW_CAP, serverProofOnly: true});
  });
}
module.exports = {OLD_CAP, NEW_CAP, ADDITION,
  allocateApprovedManagerCompensation};
