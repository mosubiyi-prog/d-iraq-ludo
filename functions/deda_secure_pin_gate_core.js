"use strict";
// Server-side PIN verification gate. This is not account migration or wallet authorization.
// Never trust client-supplied UID, account session, installId or trustedInstallIds.
const {createHash, createHmac, timingSafeEqual} = require("node:crypto");

const WINDOW_MS = 15 * 60 * 1000;
const DAY_MS = 24 * 60 * 60 * 1000;
const WINDOW_LIMIT = 5;
const DAY_LIMIT = 20;

class PinDenied extends Error {
  constructor() { super("identity-preflight-denied"); this.name = "PinDenied"; }
}
const deny = () => { throw new PinDenied(); };
const validInput = (data) => {
  if (!data || typeof data !== "object" || Array.isArray(data)) return false;
  const fields = Object.keys(data).sort();
  return fields.length === 2 && fields[0] === "accountKey" &&
    fields[1] === "pin" &&
    typeof data.accountKey === "string" &&
    /^[0-9]{8,15}$/.test(data.accountKey) &&
    typeof data.pin === "string" && /^[0-9]{6}$/.test(data.pin);
};
function checkSecret(secret) {
  if (typeof secret !== "string" || Buffer.byteLength(secret, "utf8") < 32) {
    throw new Error("SECURE_PIN_GATE_CONFIG_MISSING");
  }
}
function rateDocumentId(secret, accountKey) {
  checkSecret(secret);
  return createHmac("sha256", secret).update("deda_pin_rate_v1:" + accountKey).digest("hex");
}
function samePin(a, b) {
  // Hash fixed-format values before constant-time compare; no PIN stored in new docs.
  const x = typeof a === "string" ? a : "";
  const y = typeof b === "string" ? b : "";
  return timingSafeEqual(
      createHash("sha256").update(x).digest(),
      createHash("sha256").update(y).digest(),
  );
}
function currentRate(raw, now) {
  const r = raw && typeof raw === "object" ? raw : {};
  const windowStartMs = Number.isSafeInteger(r.windowStartMs) ? r.windowStartMs : now;
  const dayStartMs = Number.isSafeInteger(r.dayStartMs) ? r.dayStartMs : now;
  const windowExpired = now < windowStartMs || now - windowStartMs >= WINDOW_MS;
  const dayExpired = now < dayStartMs || now - dayStartMs >= DAY_MS;
  return {
    failures: windowExpired ? 0 : (Number.isSafeInteger(r.failures) ? r.failures : 0),
    windowStartMs: windowExpired ? now : windowStartMs,
    dayFailures: dayExpired ? 0 : (Number.isSafeInteger(r.dayFailures) ? r.dayFailures : 0),
    dayStartMs: dayExpired ? now : dayStartMs,
    lockedUntilMs: Number.isSafeInteger(r.lockedUntilMs) ? r.lockedUntilMs : 0,
  };
}
function accountDocuments(db, accountKey, uid, secret) {
  return {
    rate: db.doc("deda_secure_pin_account_limits/" + rateDocumentId(secret, accountKey)),
    binding: db.doc("deda_secure_account_bindings/" + uid),
    credential: db.doc("deda_credentials/" + accountKey),
    directory: db.doc("deda_account_directory/" + accountKey),
    profile: db.doc("deda_account_profiles/" + accountKey),
  };
}
async function securePinPreflight({request, db, auth, secret, nowMs = Date.now()}) {
  checkSecret(secret); // Fail closed on missing production Secret Manager configuration.
  if (!Number.isSafeInteger(nowMs) || nowMs <= 0 || !db || !auth) deny();
  const uid = request?.auth?.uid;
  const provider = request?.auth?.token?.firebase?.sign_in_provider;
  // Firebase callable verifies Auth JWT and App Check token before reaching this code.
  if (typeof uid !== "string" || !/^[A-Za-z0-9_-]{6,128}$/.test(uid) ||
      provider !== "anonymous" ||
      typeof request?.app?.appId !== "string" || !request.app.appId ||
      !validInput(request.data)) deny();

  let user;
  try { user = await auth.getUser(uid); } catch (_) { deny(); }
  if (!user || user.disabled || user.uid !== uid || user.email ||
      (Array.isArray(user.providerData) && user.providerData.length)) deny();

  const accountKey = request.data.accountKey;
  const suppliedPin = request.data.pin;
  const refs = accountDocuments(db, accountKey, uid, secret);
  let outcome;
  try {
    outcome = await db.runTransaction(async (tx) => {
      // All reads precede all writes for Firestore transaction correctness.
      const [limitSnap, bindingSnap, credentialSnap, directorySnap, profileSnap] =
        await Promise.all([tx.get(refs.rate), tx.get(refs.binding),
          tx.get(refs.credential), tx.get(refs.directory), tx.get(refs.profile)]);
      const state = currentRate(limitSnap.exists ? limitSnap.data() : {}, nowMs);
      if (state.lockedUntilMs > nowMs ||
          (state.dayFailures >= DAY_LIMIT && nowMs - state.dayStartMs < DAY_MS)) {
        return "DENIED";
      }
      const credential = credentialSnap.exists ? credentialSnap.data() : null;
      const directory = directorySnap.exists ? directorySnap.data() : null;
      const profile = profileSnap.exists ? profileSnap.data() : null;
      const valid = credential?.active === true && directory?.active === true &&
        credential?.accountKey === accountKey && directory?.accountKey === accountKey &&
        typeof directory?.createdUid === "string" && directory.createdUid.length > 0 &&
        profile?.accountKey === accountKey &&
        typeof credential?.pin === "string" && /^[0-9]{6}$/.test(credential.pin) &&
        samePin(credential.pin, suppliedPin);
      if (!valid) {
        const failures = state.failures + 1;
        const dayFailures = state.dayFailures + 1;
        tx.set(refs.rate, {
          windowStartMs: state.windowStartMs, failures,
          dayStartMs: state.dayStartMs, dayFailures,
          lockedUntilMs: failures >= WINDOW_LIMIT ? nowMs + WINDOW_MS : 0,
          updatedAtMs: nowMs,
        });
        return "DENIED";
      }
      if (bindingSnap.exists) {
        const bound = bindingSnap.data() || {};
        if (bound.uid !== uid || bound.accountKey !== accountKey ||
            bound.status !== "PIN_VERIFIED_HOLD") return "DENIED";
      } else {
        // This is a private backend verification receipt, NOT a DEDA session.
        tx.create(refs.binding, {
          uid, accountKey, status: "PIN_VERIFIED_HOLD",
          identityMethod: "server-checked-pin-with-app-check",
          canRestoreAssets: false, canMigrate: false,
          canCreditXp: false, canCreditDiamonds: false,
          canIssueGift: false, createdAtMs: nowMs,
        });
      }
      tx.set(refs.rate, {
        failures: 0, windowStartMs: nowMs,
        dayFailures: state.dayFailures, dayStartMs: state.dayStartMs,
        lockedUntilMs: 0, updatedAtMs: nowMs,
      });
      return "VERIFIED_HOLD";
    }, {maxAttempts: 5});
  } catch (error) {
    // Never return raw Firestore errors, PINs or account existence to a caller.
    if (error instanceof PinDenied) throw error;
    throw new Error("SECURE_PIN_GATE_BACKEND_UNAVAILABLE");
  }
  if (outcome !== "VERIFIED_HOLD") deny();
  return {
    status: "PIN_VERIFIED_HOLD", serverOwned: true,
    productionMigrationEnabled: false, canRestoreAssets: false,
    canCreditXp: false, canCreditDiamonds: false, canIssueGift: false,
  };
}
module.exports = {PinDenied, validInput, rateDocumentId, currentRate,
  securePinPreflight, WINDOW_MS, DAY_MS, WINDOW_LIMIT, DAY_LIMIT};
