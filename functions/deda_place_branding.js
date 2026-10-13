"use strict";

// Owner-chosen *colour only*, callable-by-owner with server verification.
// This file never changes certificates, coordinates, names, or status.
// Adding it to GitHub does NOT deploy a function.
const {requirePlaceId, verifiedAccountKey} = require("./deda_place_engagement.js");

function requirePaletteIndex(value) {
  if (!Number.isInteger(value) || value < 0 || value > 13) {
    const err = new Error("invalid-place-theme");
    err.code = "invalid-argument";
    throw err;
  }
  return value;
}

async function setPlaceTheme(db, {uid, placeId: rawId, themeIndex: input}) {
  const placeId = requirePlaceId(rawId);
  const themeIndex = requirePaletteIndex(input);
  const accountKey = await verifiedAccountKey(db, uid);
  if (!uid || !accountKey) {
    const err = new Error("verified-owner-session-required");
    err.code = "permission-denied";
    throw err;
  }
  const ref = db.collection("published_places").doc(placeId);
  return db.runTransaction(async (tx) => {
    const snapshot = await tx.get(ref);
    const place = snapshot.exists ? snapshot.data() || {} : {};
    const owned = snapshot.exists &&
        (place.ownerUid === uid || place.accountKey === accountKey);
    if (!owned || place.published !== true ||
        place.hiddenByManager === true || place.deleted === true ||
        place.status === "deleted") {
      const err = new Error("published-owner-place-required");
      err.code = "permission-denied";
      throw err;
    }
    if (place.themeIndex !== themeIndex) {
      tx.update(ref, {themeIndex});
    }
    return {placeId, themeIndex};
  });
}

module.exports = {setPlaceTheme, requirePaletteIndex};
