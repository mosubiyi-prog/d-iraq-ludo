"use strict";

/**
 * DEDA stage10 — EMULATOR-ONLY PERSONAL SHARE EVENT VERIFICATION.
 *
 * Proves a matching Firestore location-share document was persisted under
 * authenticated Firestore rules. This does NOT prove GPS truth, that anyone
 * read the share, or membership in Telegram/other social platforms.
 *
 * No Cloud Function is exported/deployed. No real wallet gets credit.
 * Client identity comes ONLY from a future Firebase onCall request.auth.
 */
const {Timestamp} = require("firebase-admin/firestore");
const {
  PROJECT, SHADOW_COLLECTIONS, eventId, eligiblePublishedTask,
  simulateVerifiedDailyReward,
} = require("./deda_daily_reward_shadow_ledger.js");
const {iraqDayId} = require("./deda_daily_task_publisher.js");

const SLOT = "share_personal_location";
const PROOF_KIND = "stage10_checked_personal_share";
const ID_PATTERN = /^[A-Za-z0-9_-]{6,60}$/;

function requireSandbox(db) {
  if (!process.env.FIRESTORE_EMULATOR_HOST ||
      process.env.GCLOUD_PROJECT !== PROJECT ||
      !db || typeof db.runTransaction !== "function") {
    throw Error("STAGE10_EMULATOR_ONLY_DO_NOT_PAY");
  }
}

function parseVerifiedRequest(request) {
  const uid = request && request.auth && request.auth.uid;
  if (typeof uid !== "string" ||
      !/^[A-Za-z0-9_-]{1,128}$/.test(uid) ||
      request.auth.token?.firebase?.sign_in_provider === "anonymous") {
    return {ok: false, reason: "auth-required"};
  }
  // Real enforcement will require an exported onCall(enforceAppCheck:true).
  if (!request.app || typeof request.app.appId !== "string" ||
      request.app.appId.length < 4) {
    return {ok: false, reason: "app-check-required"};
  }
  const data = request.data;
  if (!data || typeof data !== "object" || Array.isArray(data) ||
      Object.getPrototypeOf(data) !== Object.prototype ||
      Object.keys(data).length !== 2 ||
      !Object.prototype.hasOwnProperty.call(data, "shareId") ||
      !Object.prototype.hasOwnProperty.call(data, "confirm") ||
      data.confirm !== true ||
      typeof data.shareId !== "string" ||
      !ID_PATTERN.test(data.shareId)) {
    return {ok: false, reason: "invalid-request"};
  }
  return {ok: true, uid, shareId: data.shareId};
}

function millis(value) {
  return value && typeof value.toMillis === "function" ?
    value.toMillis() : NaN;
}

function genuinePersonalShare({
  share, sender, senderId, recipientId, uid, shareId, config, now,
}) {
  if (!share || !sender || !senderId || !recipientId) return false;
  if (share.senderUid !== uid || share.shareType !== "current" ||
      share.placeId !== "" || share.placeName !== "" ||
      share.senderPublicId !== sender.sharePersonalId ||
      share.senderName !== sender.name ||
      share.recipientPublicId === share.senderPublicId ||
      share.status === "deleted" ||
      !["pending", "accepted", "rejected"].includes(share.status) ||
      ![15, 30, 60].includes(share.durationMinutes)) return false;
  if (senderId.ownerUid !== uid || senderId.kind !== "personal" ||
      senderId.active !== true ||
      senderId.publicId !== share.senderPublicId ||
      recipientId.kind !== "personal" ||
      recipientId.active !== true ||
      recipientId.publicId !== share.recipientPublicId ||
      typeof recipientId.ownerUid !== "string" ||
      recipientId.ownerUid === uid) return false;

  const time = millis(share.createdAt);
  const expires = millis(share.expiresAt);
  const publishAt = millis(config.publishedAt);
  const nowTime = now.getTime();
  const latitude = share.latitude;
  const longitude = share.longitude;
  return !!shareId &&
    Number.isFinite(time) && time >= publishAt && time <= nowTime &&
    iraqDayId(time) === iraqDayId(now) &&
    Number.isFinite(expires) && expires > time &&
    expires <= time + 61 * 60 * 1000 &&
    typeof latitude === "number" && Number.isFinite(latitude) &&
    latitude >= -90 && latitude <= 90 &&
    typeof longitude === "number" && Number.isFinite(longitude) &&
    longitude >= -180 && longitude <= 180;
}

function makeVerifier({db, serverNow} = {}) {
  requireSandbox(db);
  if (typeof serverNow !== "function") throw Error("server-clock-required");

  return async function verifyAndSimulate(request) {
    requireSandbox(db);
    const actor = parseVerifiedRequest(request);
    if (!actor.ok) return {outcome: actor.reason};
    const instant = serverNow();
    if (!(instant instanceof Date) || !Number.isFinite(instant.getTime())) {
      throw Error("invalid-server-clock");
    }
    const now = new Date(instant.getTime());
    const day = iraqDayId(now);
    const eventRef = db.collection(SHADOW_COLLECTIONS.events)
        .doc(eventId(actor.uid, day, SLOT));
    const configRef = db.collection("deda_daily_published_task_slots").doc(SLOT);
    const shareRef = db.collection("deda_location_shares").doc(actor.shareId);
    const senderRef = db.collection("users").doc(actor.uid);

    const verification = await db.runTransaction(async (tx) => {
      const [configSnap, shareSnap, senderSnap, alreadySnap] =
          await Promise.all([
            tx.get(configRef), tx.get(shareRef),
            tx.get(senderRef), tx.get(eventRef),
          ]);
      if (!configSnap.exists ||
          !eligiblePublishedTask(configSnap.data(), SLOT, day, now)) {
        return "inactive-task";
      }
      if (!shareSnap.exists || !senderSnap.exists) return "no-valid-share";
      const share = shareSnap.data();
      if (share.senderUid !== actor.uid ||
          typeof share.senderPublicId !== "string" ||
          typeof share.recipientPublicId !== "string" ||
          !ID_PATTERN.test(share.senderPublicId) ||
          !ID_PATTERN.test(share.recipientPublicId)) {
        return "no-valid-share";
      }
      const [senderIdSnap, recipientIdSnap] = await Promise.all([
        tx.get(db.collection("deda_share_ids").doc(share.senderPublicId)),
        tx.get(db.collection("deda_share_ids").doc(share.recipientPublicId)),
      ]);
      if (!senderIdSnap.exists || !recipientIdSnap.exists ||
          !genuinePersonalShare({
            share, sender: senderSnap.data(),
            senderId: senderIdSnap.data(),
            recipientId: recipientIdSnap.data(),
            uid: actor.uid, shareId: actor.shareId,
            config: configSnap.data(), now,
          })) {
        return "no-valid-share";
      }
      if (alreadySnap.exists) {
        const saved = alreadySnap.data();
        if (saved.fixtureSource !== PROOF_KIND ||
            saved.sourceShareId !== actor.shareId) {
          return "already-verified-different-share";
        }
        return "previously-verified";
      }
      tx.create(eventRef, {
        uid: actor.uid,
        slotId: SLOT,
        dayId: day,
        action: SLOT,
        publicationId: configSnap.data().publicationId,
        sourcePreviewRevision: configSnap.data().sourcePreviewRevision,
        eventState: "verified",
        fixtureSource: PROOF_KIND,
        serverVerified: true,
        sourceShareId: actor.shareId,
        verifiedAt: Timestamp.fromDate(now),
      });
      return "verified-personal-share";
    });

    if (verification !== "verified-personal-share" &&
        verification !== "previously-verified") {
      return {outcome: verification};
    }
    // Stage 9 grant stays SHADOW ONLY; it atomically dedupes the balance.
    const reward = await simulateVerifiedDailyReward(db, {
      uid: actor.uid, slotId: SLOT, trustedNow: serverNow(),
    });
    return {outcome: verification, shadow: reward.outcome};
  };
}

module.exports = {
  SLOT,
  PROOF_KIND,
  parseVerifiedRequest,
  genuinePersonalShare,
  makeVerifier,
};
