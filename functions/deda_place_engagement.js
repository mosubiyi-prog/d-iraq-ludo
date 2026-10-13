"use strict";

// DEDA 100332 private staging: server-authoritative place follow/like counts.
// No deployment is performed by adding this file.
const {createHash} = require("node:crypto");

function requirePlaceId(input) {
  const placeId = String(input || "").trim();
  if (!/^[A-Za-z0-9_-]{8,160}$/.test(placeId)) {
    const error = new Error("invalid-place-id");
    error.code = "invalid-argument";
    throw error;
  }
  return placeId;
}

function valuesOf(doc) {
  return doc.exists ? doc.data() || {} : {};
}
function asCount(value) {
  return Number.isSafeInteger(value) && value >= 0 ? value : 0;
}
function output(row, metrics) {
  return {
    following: row.following === true,
    liked: row.liked === true,
    followers: asCount(metrics.followers),
    likes: asCount(metrics.likes),
  };
}

async function verifiedAccountKey(db, uid) {
  if (!uid) return "";
  const [session, user] = await Promise.all([
    db.collection("deda_sessions").doc(uid).get(),
    db.collection("users").doc(uid).get(),
  ]);
  const sessionKey = String(valuesOf(session).accountKey || "").trim();
  const userKey = String(valuesOf(user).accountKey || "").trim();
  // Both records must agree: do not use a self-written profile to impersonate
  // other accounts or count one account from multiple rotated anonymous UIDs.
  return sessionKey && userKey && sessionKey === userKey ? sessionKey : "";
}

function reactionKey(accountKey) {
  return createHash("sha256").update(accountKey, "utf8").digest("hex");
}

function paths(db, placeId, accountKey) {
  return {
    place: db.collection("published_places").doc(placeId),
    metrics: db.collection("deda_place_engagement_totals").doc(placeId),
    reaction: accountKey ?
      db.collection("deda_place_engagement").doc(placeId)
          .collection("users").doc(reactionKey(accountKey)) : null,
  };
}

function published(data) {
  return data.published === true &&
    data.hiddenByManager !== true && data.deleted !== true &&
    data.status !== "deleted";
}

async function readPlaceEngagement(db, {placeId: rawId, uid}) {
  const placeId = requirePlaceId(rawId);
  const accountKey = await verifiedAccountKey(db, uid);
  const p = paths(db, placeId, accountKey);
  const [place, metrics, row] = await Promise.all([
    p.place.get(), p.metrics.get(), p.reaction ? p.reaction.get() : null,
  ]);
  if (!place.exists || !published(valuesOf(place))) {
    const err = new Error("place-not-published");
    err.code = "not-found";
    throw err;
  }
  return output(row ? valuesOf(row) : {}, valuesOf(metrics));
}

async function setPlaceEngagement(db, {placeId: rawId, uid, kind, active}) {
  const placeId = requirePlaceId(rawId);
  if (!["follow", "like"].includes(kind) || typeof active !== "boolean") {
    const err = new Error("invalid-reaction");
    err.code = "invalid-argument";
    throw err;
  }
  const accountKey = await verifiedAccountKey(db, uid);
  if (!accountKey) {
    const err = new Error("verified-session-required");
    err.code = "permission-denied";
    throw err;
  }
  const p = paths(db, placeId, accountKey);
  const key = kind === "follow" ? "following" : "liked";
  const counter = kind === "follow" ? "followers" : "likes";
  // Transaction protects counts against races and double-taps. The actor
  // cannot supply an amount or write another user's reaction row.
  return db.runTransaction(async (transaction) => {
    const [place, oldRow, totals] = await Promise.all([
      transaction.get(p.place),
      transaction.get(p.reaction),
      transaction.get(p.metrics),
    ]);
    if (!place.exists || !published(valuesOf(place))) {
      const err = new Error("place-not-published");
      err.code = "not-found";
      throw err;
    }
    const row = valuesOf(oldRow);
    const old = row[key] === true;
    const counts = valuesOf(totals);
    let followers = asCount(counts.followers);
    let likes = asCount(counts.likes);
    if (old !== active) {
      const current = counter === "followers" ? followers : likes;
      const updated = Math.max(0, current + (active ? 1 : -1));
      if (counter === "followers") followers = updated;
      else likes = updated;
      transaction.set(p.reaction, {
        ...row,
        [key]: active,
        updatedAt: new Date(),
      }, {merge: true});
      transaction.set(p.metrics, {
        followers,
        likes,
        updatedAt: new Date(),
      }, {merge: true});
    }
    return output({...row, [key]: active}, {followers, likes});
  });
}

module.exports = {
  readPlaceEngagement, setPlaceEngagement,
  requirePlaceId, verifiedAccountKey, asCount,
};
