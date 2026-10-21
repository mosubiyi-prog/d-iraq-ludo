"use strict";

/**
 * QA32 public-facing ACTIVE alias resolver (NOT exported/deployed).
 *
 * Minimal response only: four keys required by the already-staged Stage50
 * client. No phone/UID, friends, diamonds, wallet, place, gift ledger or
 * internal account key can be returned.
 *
 * Wrapper, when separately reviewed and deployed, MUST pass request.auth.uid
 * as trustedAuthUid and enforce App Check. Never accept a client-supplied UID.
 */
const ORIGINAL = /^@DEDA-[A-Z0-9]{6}$/;
const ALIAS = /^@DEDA-[A-Z0-9]{4,12}$/;
const COLORS = new Set(["gold", "diamond", "royal", "pink"]);

function fallback(originalId) {
  return Object.freeze({
    requestedId: originalId,
    displayId: null,
    permanentColor: null,
    serverConfirmed: false,
  });
}

async function readVerifiedPublicAlias(db, originalId, trustedAuthUid) {
  if (typeof trustedAuthUid !== "string" || !trustedAuthUid.trim()) {
    throw new Error("SAFE_STOP_QA32_PUBLIC_ALIAS_AUTH_REQUIRED");
  }
  if (typeof originalId !== "string" || !ORIGINAL.test(originalId)) {
    throw new Error("SAFE_STOP_QA32_PUBLIC_ALIAS_ORIGINAL_ID_INVALID");
  }
  if (!db || typeof db.doc !== "function") {
    throw new Error("SAFE_STOP_QA32_PUBLIC_ALIAS_DB_REQUIRED");
  }
  const route = await db.doc("deda_share_ids/" + originalId).get();
  const profile = route.exists ? route.data() || {} : {};
  if (profile.publicId !== originalId || profile.kind !== "personal" ||
      profile.active !== true || typeof profile.ownerUid !== "string" ||
      !profile.ownerUid) {
    return fallback(originalId);
  }
  const selected = await db.doc(
      "deda_stage71_active_identifier/" + originalId).get();
  if (!selected.exists) return fallback(originalId);
  const record = selected.data() || {};
  if (record.originalId !== originalId ||
      typeof record.activeId !== "string") {
    throw new Error("SAFE_STOP_QA32_PUBLIC_ALIAS_CORRUPT_SELECTION");
  }
  if (record.activeId === originalId) return fallback(originalId);
  if (!ALIAS.test(record.activeId)) {
    throw new Error("SAFE_STOP_QA32_PUBLIC_ALIAS_ID_FORMAT");
  }
  const grant = await db.doc(
      "deda_stage71_granted_registry/" + record.activeId).get();
  const g = grant.exists ? grant.data() || {} : {};
  if (g.identifier !== record.activeId ||
      g.recipientOriginalId !== originalId ||
      (g.kind !== "gifted" && g.kind !== "self_used") ||
      !COLORS.has(g.baseColor) ||
      (g.group !== "001" && g.group !== "002")) {
    throw new Error("SAFE_STOP_QA32_PUBLIC_ALIAS_UNVERIFIED_OWNER");
  }
  if (g.kind === "gifted") {
    const receipt = await db.doc(
        "deda_stage74_id_gift_receipts/" + record.activeId).get();
    const r = receipt.exists ? receipt.data() || {} : {};
    if (r.identifier !== record.activeId ||
        r.originalId !== originalId || r.group !== g.group ||
        !r.receivedAt) {
      throw new Error("SAFE_STOP_QA32_PUBLIC_ALIAS_GIFT_NOT_RECEIVED");
    }
  }
  return Object.freeze({
    requestedId: originalId,
    displayId: record.activeId,
    permanentColor: g.baseColor,
    serverConfirmed: true,
  });
}

module.exports = {readVerifiedPublicAlias};
