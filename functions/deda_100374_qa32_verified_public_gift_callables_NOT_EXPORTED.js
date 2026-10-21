"use strict";

/**
 * Owner review only. THESE CALLABLES ARE NOT EXPORTED IN functions/index.js.
 * Production role, AppCheck and client rollout require separate approval.
 * Purely read-only; NEVER writes IDs, transfers gems, or changes accounts.
 */
const {
  readVerifiedPublicAlias,
  resolveVerifiedGiftRecipientOriginal,
} = require("./deda_qa32_public_alias_resolver_NOT_EXPORTED.js");

function assertRequest(request, HttpsError) {
  if (!request || !request.auth || typeof request.auth.uid !== "string" ||
      !request.auth.uid.trim()) {
    throw new HttpsError("unauthenticated", "DEDA_SIGN_IN_REQUIRED");
  }
  if (!request.app || !request.app.appId) {
    throw new HttpsError("permission-denied", "DEDA_APP_CHECK_REQUIRED");
  }
  if (!request.data || typeof request.data !== "object" ||
      Array.isArray(request.data) ||
      Object.keys(request.data).length !== 1 ||
      typeof request.data.identifier !== "string" ||
      !/^@DEDA-[A-Z0-9]{4,12}$/.test(request.data.identifier)) {
    throw new HttpsError("invalid-argument", "DEDA_CANONICAL_ID_REQUIRED");
  }
  return request.data.identifier;
}

function buildReadPublicAliasCallable({onCall, HttpsError, db}) {
  if (typeof onCall !== "function" || typeof HttpsError !== "function" || !db) {
    throw new Error("SAFE_STOP_QA32_CONFIG_REQUIRED");
  }
  return onCall({enforceAppCheck:true}, async request => {
    const id=assertRequest(request,HttpsError);
    if (!/^@DEDA-[A-Z0-9]{6}$/.test(id)) {
      throw new HttpsError("invalid-argument","DEDA_ORIGINAL_ID_REQUIRED");
    }
    try {
      return await readVerifiedPublicAlias(db,id,request.auth.uid);
    } catch (e) {
      throw new HttpsError("failed-precondition","DEDA_UNVERIFIED_ALIAS");
    }
  });
}

function buildResolveGiftRecipientCallable({onCall,HttpsError,db}) {
  if (typeof onCall !== "function" || typeof HttpsError !== "function" || !db) {
    throw new Error("SAFE_STOP_QA32_CONFIG_REQUIRED");
  }
  return onCall({enforceAppCheck:true}, async request => {
    const id=assertRequest(request,HttpsError);
    const admin=await db.doc("admins/"+request.auth.uid).get();
    const a=admin.exists ? admin.data()||{} : {};
    // General-manager role, active status, and permission are REQUIRED.
    // The original actual admin system must be audited at deployment.
    // Match DEDA's existing explicit GM role names while rejecting employee,
    // deputy, disabled and suspended accounts. Missing role is NOT enough
    // for a new privileged callable even if legacy UI has looser defaults.
    const role = String(a.role || a.jobTitle || "").trim().toLowerCase();
    const allowed = new Set(["general_manager", "generalmanager",
      "manager", "director", "admin"]);
    if (a.active !== true ||
        (a.status != null && a.status !== "active") ||
        !allowed.has(role)) {
      throw new HttpsError("permission-denied","DEDA_MANAGER_ONLY");
    }
    try {
      const recipient=await resolveVerifiedGiftRecipientOriginal(
          db,id,request.auth.uid);
      return recipient || Object.freeze({
        requestedId:id,originalId:null,serverConfirmed:false,
      });
    } catch (_) {
      throw new HttpsError("failed-precondition",
          "DEDA_GIFT_RECIPIENT_OWNERSHIP_NOT_VERIFIED");
    }
  });
}

/**
 * Any authenticated, App-Check verified DEDA user may use a premium ID as
 * the add-friend or share-location recipient. The response contains ONLY a
 * canonical public routing ID. No UID/phone/wallet/private profile data.
 *
 * Original IDs retain precedence if a 6-character premium alias collides
 * with an actual canonical original ID. Client checks original first.
 */
function buildResolvePublicRecipientCallable({onCall,HttpsError,db}) {
  if (typeof onCall !== "function" || typeof HttpsError !== "function" || !db) {
    throw new Error("SAFE_STOP_QA32_CONFIG_REQUIRED");
  }
  return onCall({enforceAppCheck:true}, async request => {
    const id=assertRequest(request,HttpsError);
    try {
      const route = await resolveVerifiedGiftRecipientOriginal(
          db,id,request.auth.uid);
      return route || Object.freeze({
        requestedId:id,originalId:null,serverConfirmed:false,
      });
    } catch (_) {
      throw new HttpsError("failed-precondition","DEDA_PUBLIC_RECIPIENT_UNVERIFIED");
    }
  });
}

module.exports = {
  buildReadPublicAliasCallable,
  buildResolveGiftRecipientCallable,
  buildResolvePublicRecipientCallable,
};
