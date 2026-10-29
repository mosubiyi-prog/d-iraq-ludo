"use strict";
/**
 * DEDA account-recovery escrow: IMMUTABLE copy of current ORIGINAL
 * Firestore-visible legacy candidates for later owner-approved reconciliation.
 *
 * No spendable grants.  No copying to new UID.  No client-selected source UID.
 * Historic local SharedPreferences cannot be read by this server.
 * Candidate values remain UNTRUSTED even when they match across devices.
 */
const {createHash, createHmac} = require("node:crypto");

const ACCOUNT = /^[0-9]{8,15}$/;
const UID = /^[A-Za-z0-9_-]{6,128}$/;
const PUBLIC_ID = /^@DEDA-[A-Za-z0-9_-]{3,32}$/;
const FRESH_MS = 10 * 60 * 1000;
const MAX_ESCROW_BYTES = 125000;
const FIELDS = Object.freeze([
  "accountKey", "name", "phone", "accountType",
  "sharePersonalId", "sharePlaceId", "premiumId", "originalId",
  "level", "xp", "coins", "diamonds", "points",
  "balance", "earnedDiamonds", "ownedFrames", "purchasedFrames",
  "frames", "frameStyle", "avatarStyle", "profileAvatarStyle",
  "profileFrameStyle", "profileBackgroundStyle", "selectedPremiumId",
  "levelPoints", "totalPoints", "lastClaimGiftId", "lastGiftId",
  "createdAt", "updatedAt",
]);
const BALANCE_FIELDS = Object.freeze([
  "accountKey", "diamonds", "balance", "xp", "coins", "points",
  "level", "earnedDiamonds", "frames", "ownedFrames", "purchasedFrames",
  "premiumId", "lastGiftId", "lastClaimGiftId", "createdAt", "updatedAt",
]);
const RISK_KEYS = /pin|password|token|secret|credential|install|fcm|push|privatekey/i;
class RecoveryEscrowHold extends Error {
  constructor(reason = "recovery-escrow-unavailable") {
    super(reason);
    this.name = "RecoveryEscrowHold";
  }
}
const fail = (why) => { throw new RecoveryEscrowHold(why); };
const data = (snap) => snap.exists ? snap.data() : null;
const safeRecord = (v) => v && typeof v === "object" && !Array.isArray(v);
const isValidAmount = (v) => Number.isSafeInteger(v) && v >= 0;
const jsonClone = (obj) => JSON.parse(JSON.stringify(obj, (_key, value) => {
  if (value && typeof value.toMillis === "function") {
    return {timestampMs: value.toMillis()};
  }
  return value;
}));
function subset(v, fields) {
  if (!safeRecord(v)) return null;
  const out = {};
  for (const f of fields) {
    if (RISK_KEYS.test(f)) continue;
    if (Object.hasOwn(v, f)) out[f] = v[f];
  }
  return jsonClone(out);
}
function stable(v) {
  if (v === null || typeof v !== "object") return v;
  if (Array.isArray(v)) return v.map(stable);
  return Object.fromEntries(Object.keys(v).sort().map(k => [k, stable(v[k])]));
}
function checkSecret(secret) {
  if (typeof secret !== "string" || Buffer.byteLength(secret, "utf8") < 32) {
    throw new Error("ESCROW_SECRET_NOT_CONFIGURED");
  }
}
function hmac(secret, domain, value) {
  return createHmac("sha256", secret).update(domain + ":" + value).digest("hex");
}
function present(v) { return v === null ? "MISSING" : "CANDIDATE_UNVERIFIED"; }
function summary(escrow) {
  return Object.freeze({
    status: "LEGACY_SNAPSHOT_ESCROWED_NO_TRANSFER",
    replay: false,
    categories: escrow.categories,
    accountAssetsTransferred: false,
    diamondsCredited: false,
    pointsCredited: false,
    framesGranted: false,
    idReassigned: false,
    sourceWriterFenced: false,
    localDataRecovered: false,
    fullRecoveryComplete: false,
  });
}
/**
 * Return values never disclose raw assets, original UID, alias or phone.
 * Backend-only receipt remains inaccessible to mobile SDK (original rules).
 */
async function captureLegacyAccountEscrow({request, db, auth, secret, nowMs = Date.now()}) {
  checkSecret(secret);
  const uid = request?.auth?.uid;
  const provider = request?.auth?.token?.firebase?.sign_in_provider;
  if (!db || !auth || !Number.isSafeInteger(nowMs) || nowMs <= 0 ||
      typeof uid !== "string" || !UID.test(uid) ||
      provider !== "anonymous" ||
      typeof request?.app?.appId !== "string" || !request.app.appId ||
      !safeRecord(request.data) || Object.keys(request.data).length !== 1 ||
      !Object.hasOwn(request.data, "accountKey") ||
      typeof request.data.accountKey !== "string" ||
      !ACCOUNT.test(request.data.accountKey)) fail("AUTH_OR_INPUT_DENIED");

  let user;
  try { user = await auth.getUser(uid); } catch (_) { fail("AUTH_OR_INPUT_DENIED"); }
  if (!user || user.uid !== uid || user.disabled || user.email ||
      (Array.isArray(user.providerData) && user.providerData.length)) {
    fail("AUTH_OR_INPUT_DENIED");
  }
  const key = request.data.accountKey;
  const ref = (path) => db.doc(path);
  const receiptId = hmac(secret, "recovery-escrow-v1", key + ":" + uid);
  const receiptRef = ref("deda_secure_legacy_recovery_escrow/" + receiptId);
  const dirRef = ref("deda_account_directory/" + key);
  const profileRef = ref("deda_account_profiles/" + key);
  const bindingRef = ref("deda_secure_account_bindings/" + uid);
  const progressRef = ref("deda_verified_progress/" + key);
  const migrationRef = ref("deda_progress_migrations/" + key);

  try {
    return await db.runTransaction(async (tx) => {
      const [oldEscrow, bindingS, dirS, profileS, progressS, migrationS] =
        await Promise.all([receiptRef, bindingRef, dirRef, profileRef,
          progressRef, migrationRef].map(r => tx.get(r)));
      const b = data(bindingS), d = data(dirS), p = data(profileS);
      if (!b || b.uid !== uid || b.accountKey !== key ||
          b.status !== "PIN_VERIFIED_HOLD" ||
          b.canMigrate !== false || b.canRestoreAssets !== false ||
          !Number.isSafeInteger(b.createdAtMs) ||
          !Number.isSafeInteger(b.lastVerifiedAtMs ?? b.createdAtMs) ||
          (b.lastVerifiedAtMs ?? b.createdAtMs) < b.createdAtMs ||
          nowMs < (b.lastVerifiedAtMs ?? b.createdAtMs) ||
          nowMs - (b.lastVerifiedAtMs ?? b.createdAtMs) > FRESH_MS ||
          !d || d.active !== true || d.accountKey !== key ||
          typeof d.createdUid !== "string" || !UID.test(d.createdUid) ||
          !p || p.accountKey !== key) fail("UNVERIFIED_OWNER");

      const oldUid = d.createdUid;
      // Caller does not select source UID or asset paths.
      const [sourceS, targetS, sourceWalletS, targetWalletS] =
        await Promise.all([
          tx.get(ref("users/" + oldUid)),
          tx.get(ref("users/" + uid)),
          tx.get(ref("users/" + oldUid + "/wallet/original")),
          tx.get(ref("users/" + uid + "/wallet/original")),
        ]);
      const source = data(sourceS), target = data(targetS);
      const sourceWallet = data(sourceWalletS), targetWallet = data(targetWalletS);
      if (!source || source.accountKey !== key ||
          (target && target.accountKey !== key) ||
          (sourceWallet && sourceWallet.accountKey &&
            sourceWallet.accountKey !== key) ||
          (targetWallet && targetWallet.accountKey &&
            targetWallet.accountKey !== key)) fail("SOURCE_OR_TARGET_CONFLICT");
      const publicId = source.sharePersonalId;
      if (publicId != null && (typeof publicId !== "string" ||
          !PUBLIC_ID.test(publicId))) fail("INVALID_ORIGINAL_PUBLIC_ID");
      const [aliasS, giftBalanceS] = publicId
        ? await Promise.all([
            tx.get(ref("deda_share_ids/" + publicId)),
            tx.get(ref("deda_diamond_gift_balances/" + publicId)),
          ])
        : [null, null];
      const alias = aliasS ? data(aliasS) : null;
      const giftBalance = giftBalanceS ? data(giftBalanceS) : null;
      const aliasConfirmed = !!(alias && alias.publicId === publicId &&
        alias.ownerUid === oldUid && alias.kind === "personal" &&
        alias.active === true);

      // Do not treat even a verified-looking ledger as spendable without the
      // separate signed migration / purchase settlement and legacy writer fence.
      const untrustedSnapshot = {
        originalUserCandidate: subset(source, FIELDS),
        originalWalletCandidate: subset(sourceWallet, BALANCE_FIELDS),
        targetUserBeforeRecovery: subset(target, FIELDS),
        targetWalletBeforeRecovery: subset(targetWallet, BALANCE_FIELDS),
        canonicalProfileCandidate: subset(p, [
          "accountKey", "name", "phone", "accountType", "createdAt", "updatedAt",
        ]),
        verifiedProgressRecordCandidate: subset(data(progressS), [
          "format", "accountKey", "version", "balances", "initializedBy",
        ]),
        migrationRecordCandidate: subset(data(migrationS), [
          "format", "accountKey", "phase", "evidenceDigest", "baselineEventKey",
          "settlementId",
        ]),
        giftBalanceCandidate: aliasConfirmed ? subset(giftBalance, [
          "balance", "lastClaimGiftId", "updatedAt",
        ]) : null,
      };
      const categories = {
        originalUser: present(untrustedSnapshot.originalUserCandidate),
        originalWallet: present(untrustedSnapshot.originalWalletCandidate),
        targetWallet: present(untrustedSnapshot.targetWalletBeforeRecovery),
        progress: present(untrustedSnapshot.verifiedProgressRecordCandidate),
        migration: present(untrustedSnapshot.migrationRecordCandidate),
        personalId: publicId ? (aliasConfirmed ?
          "ALIAS_OWNER_MATCH_UNVERIFIED_ENTITLEMENT" : "ALIAS_OWNERSHIP_CONFLICT") :
          "MISSING",
        giftBalance: present(untrustedSnapshot.giftBalanceCandidate),
        localTaskPoints: "NOT_AVAILABLE_TO_SERVER",
        localXpAndCoins: "NOT_AVAILABLE_TO_SERVER",
        localEarnedDiamonds: "NOT_AVAILABLE_TO_SERVER",
        framePurchases: "PAYMENT_PROVIDER_PROOF_REQUIRED",
      };
      const content = stable(untrustedSnapshot);
      const encoded = JSON.stringify(content);
      if (Buffer.byteLength(encoded, "utf8") > MAX_ESCROW_BYTES) {
        fail("SOURCE_TOO_LARGE_FOR_SAFE_ESCROW");
      }
      const sourceDigest = hmac(secret, "legacy-candidate-content-v1", encoded);
      const existing = data(oldEscrow);
      if (existing) {
        if (existing.format !== 1 ||
            existing.accountDigest !== hmac(secret, "canonical-account", key) ||
            existing.recipientDigest !== hmac(secret, "recipient-uid", uid) ||
            existing.sourceDigest !== sourceDigest ||
            existing.status !== "UNTRUSTED_ESCROW_NO_TRANSFER") {
          fail("SOURCE_CHANGED_REVIEW_REQUIRED");
        }
        return Object.freeze({...summary(existing),
          status: "LEGACY_SNAPSHOT_ALREADY_ESCROWED", replay: true});
      }
      const receipt = {
        format: 1, status: "UNTRUSTED_ESCROW_NO_TRANSFER",
        accountDigest: hmac(secret, "canonical-account", key),
        sourceUidDigest: hmac(secret, "original-uid", oldUid),
        recipientDigest: hmac(secret, "recipient-uid", uid),
        sourceDigest, categories, untrustedSnapshot: content,
        archivedAtMs: nowMs, // raw ownership data is escrowed, NOT settled
        canRestoreWallet: false, canRestoreDiamonds: false,
        canRestoreFrames: false, canRestoreXp: false, canRestorePremiumId: false,
        canReassignGiftBalance: false, canMigrate: false,
        dataTransferred: false,
      };
      tx.create(receiptRef, receipt);
      return summary(receipt);
    }, {maxAttempts: 5});
  } catch (error) {
    if (error instanceof RecoveryEscrowHold) throw error;
    throw new Error("RECOVERY_ESCROW_BACKEND_UNAVAILABLE");
  }
}
module.exports = {
  captureLegacyAccountEscrow, RecoveryEscrowHold,
  FRESH_MS, MAX_ESCROW_BYTES, hmac, subset, stable,
};
