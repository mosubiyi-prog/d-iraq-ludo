"use strict";
/*
 * DEDA recovery step 2 / narrow, SAFE subset:
 * Server restores only account display fields from an existing canonical
 * profile into a DIFFERENT authenticated anonymous UID.  PIN/installation
 * strings never authorize this action. The caller must already have a fresh
 * server-issued, AppCheck-protected Step1 PIN binding.
 *
 * This module intentionally does NOT move/copy XP, level, diamonds, social
 * coins, premium IDs, purchased/free frames, purchases, points, gifts,
 * friend edges, places, or locally cached task records.
 *
 * There is no automatic approval of money/migration from legacy client state.
 */
const {createHash} = require("node:crypto");

const TTL_MS = 10 * 60 * 1000;
const DIGITS = /^[0-9]{8,15}$/;
const UID = /^[A-Za-z0-9_-]{6,128}$/;
const ACCOUNT_TYPES = new Set(["user", "placeOwner"]);
class RecoveryHold extends Error {
  constructor() {
    super("recovery-identity-or-source-unverified");
    this.name = "RecoveryHold";
  }
}
const hold = () => { throw new RecoveryHold(); };
const dataOf = (snapshot) => snapshot.exists ? snapshot.data() : null;
const safeText = (v, maximum) =>
  typeof v === "string" && v.trim().length > 0 &&
  v.trim().length <= maximum && !/[\u0000-\u001f\u007f]/.test(v);
const digits = (s) => String(s).replace(/[^0-9]/g, "");
function validatedSource(profile, source, accountKey) {
  if (!profile || profile.accountKey !== accountKey ||
      !safeText(profile.name, 80) ||
      !safeText(profile.phone, 32) || digits(profile.phone) !== accountKey ||
      !ACCOUNT_TYPES.has(profile.accountType)) return null;
  if (!source || source.accountKey !== accountKey) return null;
  // The profile and source UID are two separately stored legacy records.
  // Neither is sufficient proof for digital assets or purchased privileges.
  if (source.name && source.name.trim() !== profile.name.trim()) return null;
  return {
    name: profile.name.trim(), phone: profile.phone.trim(),
    accountType: profile.accountType,
  };
}
function matchesSafeTarget(data, profile, accountKey) {
  return data.accountKey === accountKey &&
    data.name === profile.name && data.phone === profile.phone &&
    data.accountType === profile.accountType;
}
const response = (state) => ({
  status: state,
  profilePresent: true,
  restoredProfileFields: state === "PROFILE_RESTORED" ? 3 : 0,
  spendableAssetsRestored: false,
  pointsRestored: false,
  levelRestored: false,
  purchasedFramesRestored: false,
  premiumIdsRestored: false,
  diamondsRestored: false,
  giftsRestored: false,
  socialEdgesRestored: false,
  fullAccountRecoveryComplete: false,
  // Explicitly warn app never to represent this response as complete recovery.
  nextGate: "VERIFIED_ASSET_LEDGER_AND_LEGACY_WRITER_CUTOVER_REQUIRED",
});
async function recoverSafeProfile({request, db, auth, nowMs = Date.now()}) {
  const uid = request?.auth?.uid;
  const provider = request?.auth?.token?.firebase?.sign_in_provider;
  if (!db || !auth || !Number.isSafeInteger(nowMs) || nowMs <= 0 ||
      typeof uid !== "string" || !UID.test(uid) ||
      provider !== "anonymous" ||
      typeof request?.app?.appId !== "string" || !request.app.appId ||
      !request.data || typeof request.data !== "object" ||
      Array.isArray(request.data) ||
      Object.keys(request.data).length !== 1 ||
      !Object.hasOwn(request.data, "accountKey") ||
      typeof request.data.accountKey !== "string" ||
      !DIGITS.test(request.data.accountKey)) hold();

  try {
    const firebaseUser = await auth.getUser(uid);
    if (!firebaseUser || firebaseUser.uid !== uid || firebaseUser.disabled ||
        firebaseUser.email ||
        (Array.isArray(firebaseUser.providerData) &&
          firebaseUser.providerData.length)) hold();
  } catch (error) {
    if (error instanceof RecoveryHold) throw error;
    hold();
  }
  const accountKey = request.data.accountKey;
  const bindingRef = db.doc("deda_secure_account_bindings/" + uid);
  const directoryRef = db.doc("deda_account_directory/" + accountKey);
  const profileRef = db.doc("deda_account_profiles/" + accountKey);
  const targetRef = db.doc("users/" + uid);
  const receiptRef = db.doc("deda_secure_profile_restore_receipts/" + uid);
  try {
    return await db.runTransaction(async (tx) => {
      // Firestore transactions: perform reads BEFORE writes.
      const [bindingSnap, directorySnap, profileSnap, targetSnap, receiptSnap] =
        await Promise.all([
          tx.get(bindingRef), tx.get(directoryRef), tx.get(profileRef),
          tx.get(targetRef), tx.get(receiptRef),
        ]);
      const binding = dataOf(bindingSnap);
      const directory = dataOf(directorySnap);
      if (!binding || binding.uid !== uid ||
          binding.accountKey !== accountKey ||
          binding.status !== "PIN_VERIFIED_HOLD" ||
          binding.canMigrate !== false || binding.canRestoreAssets !== false ||
          !Number.isSafeInteger(binding.createdAtMs) ||
          nowMs < binding.createdAtMs ||
          nowMs - binding.createdAtMs > TTL_MS ||
          !directory || directory.active !== true ||
          directory.accountKey !== accountKey ||
          typeof directory.createdUid !== "string" ||
          !UID.test(directory.createdUid)) hold();

      // A second phone receives display identity only; never copy the
      // creator's original user wallet or rewrite that creator's user doc.
      const sourceUid = directory.createdUid;
      const sourceSnap = await tx.get(db.doc("users/" + sourceUid));
      const canonical = validatedSource(
        dataOf(profileSnap), dataOf(sourceSnap), accountKey,
      );
      if (!canonical) hold();

      const originalTarget = dataOf(targetSnap);
      if (originalTarget && !matchesSafeTarget(
        originalTarget, canonical, accountKey,
      )) hold();
      const sourceSignature = createHash("sha256").update(JSON.stringify({
        accountKey, sourceUid, canonical,
      })).digest("hex");
      const prior = dataOf(receiptSnap);
      if (prior) {
        if (prior.uid !== uid || prior.accountKey !== accountKey ||
            prior.sourceSignature !== sourceSignature ||
            prior.status !== "PROFILE_ONLY_NO_ASSETS" ||
            !originalTarget) hold();
        return response("PROFILE_ALREADY_RESTORED");
      }

      // Source UID's own profile is untouched. Existing target is preserved.
      if (!originalTarget) {
        tx.create(targetRef, {
          accountKey, ...canonical,
          authMethod: "deda_server_verified_profile_only_v1",
          createdAt: new Date(nowMs),
          updatedAt: new Date(nowMs),
        });
      }
      tx.create(receiptRef, {
        uid, accountKey, sourceSignature,
        status: "PROFILE_ONLY_NO_ASSETS",
        createdAtMs: nowMs,
        canCopyAssets: false,
        canCreditDiamonds: false,
        canGrantPremiumId: false,
        canCreditXp: false,
      });
      return response(originalTarget ?
        "PROFILE_ALREADY_PRESENT" : "PROFILE_RESTORED");
    }, {maxAttempts: 5});
  } catch (error) {
    if (error instanceof RecoveryHold) throw error;
    throw new Error("RECOVERY_PROFILE_BACKEND_UNAVAILABLE");
  }
}
module.exports = {
  recoverSafeProfile, RecoveryHold, validatedSource, matchesSafeTarget,
  TTL_MS,
};
