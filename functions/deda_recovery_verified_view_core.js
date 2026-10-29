"use strict";
/*
 * DEDA point 2 — verified read-only cross-device recovery projection.
 *
 * This code NEVER copies or credits a wallet, premium ID, frame or XP.
 * A signed review is NOT automatically generated from legacy snapshots.
 * Only a separate, explicitly approved server reconciler may issue one.
 *
 * Original old-APK writers are not fenced. Until they are, responses always
 * report readOnly=true, spendingAllowed=false and fullRecoveryComplete=false.
 */
const {createHmac, timingSafeEqual} = require("node:crypto");
const ACCOUNT = /^[0-9]{8,15}$/;
const UID = /^[A-Za-z0-9_-]{6,128}$/;
const HASH = /^[0-9a-f]{64}$/;
const PREMIUM = /^@DEDA-[A-Za-z0-9_-]{3,32}$/;
const ID = /^[A-Za-z0-9_-]{1,64}$/;
const FRESH_MS = 10 * 60 * 1000;
const MAX_FRAMES = 64;
class RecoveryReviewRequired extends Error {
  constructor() {
    super("verified-recovery-review-required");
    this.name = "RecoveryReviewRequired";
  }
}
const hold = () => {throw new RecoveryReviewRequired();};
const docData = (s) => s.exists ? s.data() : null;
function validateSecret(secret) {
  if (typeof secret !== "string" || Buffer.byteLength(secret, "utf8") < 32) {
    throw Error("VERIFIED_RECOVERY_SECRET_MISSING");
  }
}
function signReview(secret, accountKey, review) {
  validateSecret(secret);
  const canon = JSON.stringify([
    "deda-recovery-reviewed-view-v1", accountKey, review.reviewId,
    review.migrationId, review.progressVersion, review.progressBaseline,
    review.points, review.xp, review.coins, review.earnedDiamonds,
    review.diamondGiftBalance, review.premiumId, review.frameIds,
    review.legacyWriterFenceId, review.settlementId, review.reviewedAtMs,
  ]);
  return createHmac("sha256", secret).update(canon).digest("hex");
}
function sameHash(a, b) {
  if (typeof a !== "string" || !HASH.test(a) || !HASH.test(b)) return false;
  return timingSafeEqual(Buffer.from(a, "hex"), Buffer.from(b, "hex"));
}
function canonicalReview(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) hold();
  const strings = ["reviewId", "migrationId", "progressBaseline",
    "legacyWriterFenceId", "settlementId"];
  for (const key of strings) {
    if (typeof value[key] !== "string" || !ID.test(value[key]) &&
      !(key === "progressBaseline" && HASH.test(value[key]))) hold();
  }
  // Baseline is SHA256 by original verified progress schema.
  if (!HASH.test(value.progressBaseline) || !ID.test(value.reviewId) ||
      !ID.test(value.migrationId) || !ID.test(value.legacyWriterFenceId) ||
      !ID.test(value.settlementId)) hold();
  for (const key of ["points", "xp", "coins", "earnedDiamonds",
    "diamondGiftBalance"]) {
    if (!Number.isSafeInteger(value[key]) || value[key] < 0) hold();
  }
  if (!Number.isSafeInteger(value.progressVersion) ||
      value.progressVersion < 1 ||
      !Number.isSafeInteger(value.reviewedAtMs) ||
      value.reviewedAtMs <= 0 || value.reviewedAtMs > Date.now() + 86400000 ||
      (value.premiumId !== null && (typeof value.premiumId !== "string" ||
        !PREMIUM.test(value.premiumId))) ||
      !Array.isArray(value.frameIds) || value.frameIds.length > MAX_FRAMES ||
      value.frameIds.some(id => typeof id !== "string" || !ID.test(id)) ||
      [...new Set(value.frameIds)].length !== value.frameIds.length ||
      [...value.frameIds].sort().join("\0") !== value.frameIds.join("\0")) hold();
  return value;
}
function response(review) {
  return Object.freeze({
    status: "REVIEWED_SERVER_SNAPSHOT_READ_ONLY",
    readOnly: true,
    walletWritePerformed: false,
    premiumIdReassigned: false,
    framesGranted: false,
    fullRecoveryComplete: false,
    points: review.points, xp: review.xp, coins: review.coins,
    earnedDiamonds: review.earnedDiamonds,
    separatelyReviewedGiftDiamonds: review.diamondGiftBalance,
    premiumId: review.premiumId,
    frameIds: [...review.frameIds],
    reviewId: review.reviewId,
    warning: "LEGACY_WRITER_CUTOVER_AND_LIVE_ENTITLEMENT_SETTLEMENT_REQUIRED",
  });
}
async function readReviewedRecovery({request, db, auth, secret, nowMs = Date.now()}) {
  validateSecret(secret);
  const uid = request?.auth?.uid;
  if (!db || !auth || !Number.isSafeInteger(nowMs) || nowMs <= 0 ||
      !UID.test(uid || "") ||
      request?.auth?.token?.firebase?.sign_in_provider !== "anonymous" ||
      typeof request?.app?.appId !== "string" || !request.app.appId ||
      !request.data || typeof request.data !== "object" ||
      Array.isArray(request.data) ||
      Object.keys(request.data).length !== 1 ||
      typeof request.data.accountKey !== "string" ||
      !ACCOUNT.test(request.data.accountKey)) hold();
  let user;
  try {user = await auth.getUser(uid);} catch (_) {hold();}
  if (!user || user.uid !== uid || user.disabled || user.email ||
      (Array.isArray(user.providerData) && user.providerData.length)) hold();

  const accountKey = request.data.accountKey;
  const ref = (path) => db.doc(path);
  try {
    return await db.runTransaction(async tx => {
      const [bindingS, directoryS, progressS, migrationS, reviewS] =
        await Promise.all([
          tx.get(ref("deda_secure_account_bindings/" + uid)),
          tx.get(ref("deda_account_directory/" + accountKey)),
          tx.get(ref("deda_verified_progress/" + accountKey)),
          tx.get(ref("deda_progress_migrations/" + accountKey)),
          tx.get(ref("deda_recovery_authoritative_reviews/" + accountKey)),
        ]);
      const binding = docData(bindingS), directory = docData(directoryS);
      const progress = docData(progressS), migration = docData(migrationS);
      const raw = docData(reviewS);
      const lastVerified = binding?.lastVerifiedAtMs ?? binding?.createdAtMs;
      if (!binding || binding.uid !== uid ||
          binding.accountKey !== accountKey ||
          binding.status !== "PIN_VERIFIED_HOLD" ||
          binding.canRestoreAssets !== false || binding.canMigrate !== false ||
          !Number.isSafeInteger(binding.createdAtMs) ||
          !Number.isSafeInteger(lastVerified) ||
          lastVerified < binding.createdAtMs ||
          nowMs < lastVerified || nowMs - lastVerified > FRESH_MS ||
          !directory || directory.active !== true ||
          directory.accountKey !== accountKey ||
          !UID.test(directory.createdUid || "") ||
          !progress || progress.accountKey !== accountKey ||
          progress.format !== 1 ||
          !migration || migration.accountKey !== accountKey ||
          migration.format !== 1 || migration.phase !== "cutover-complete" ||
          !raw || raw.accountKey !== accountKey ||
          raw.status !== "SERVER_RECONCILED_REVIEW_ONLY" ||
          raw.legacyWriterFenced !== true ||
          raw.paymentProviderReviewed !== true ||
          raw.idAndFramesReviewed !== true ||
          raw.issuer !== "deda-reviewed-recovery-v1" ||
          !HASH.test(raw.signature || "")) hold();

      const review = canonicalReview(raw);
      if (review.migrationId !== migration.migrationId ||
          review.settlementId !== migration.settlementId ||
          review.progressVersion !== progress.version ||
          review.progressBaseline !== progress.initializedBy ||
          !progress.balances || progress.balances.points !== review.points ||
          progress.balances.xp !== review.xp ||
          progress.balances.coins !== review.coins ||
          progress.balances.earnedDiamonds !== review.earnedDiamonds ||
          !sameHash(review.signature, signReview(secret, accountKey, review))) hold();
      // No writes. Returning a reviewed snapshot must NEVER be interpreted
      // as a monetary transfer or wallet entitlement by the app.
      return response(review);
    }, {maxAttempts: 5, readOnly: true});
  } catch (error) {
    if (error instanceof RecoveryReviewRequired) throw error;
    throw Error("RECOVERY_REVIEWED_SNAPSHOT_UNAVAILABLE");
  }
}
module.exports = {
  readReviewedRecovery, RecoveryReviewRequired, signReview, canonicalReview,
  FRESH_MS,
};
