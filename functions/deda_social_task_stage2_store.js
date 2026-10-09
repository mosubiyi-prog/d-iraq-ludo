"use strict";

/**
 * Emulator-only persistent admin workflow for social tasks. Not exported from
 * production functions/index.js and never deployed to the real project.
 * Caller identity MUST come from verified Firebase Auth on the SERVER.
 */
const policy = require("./deda_social_task_stage2.js");
const DEMO_PROJECT = "demo-deda-social-stage2";
const COLLECTION = "deda_stage2_social_admin_drafts";
const PUBLISHED = "deda_stage2_social_public_config_only";
const AUDIT = "deda_stage2_social_audit";

function requireEmulator(db) {
  if (!process.env.FIRESTORE_EMULATOR_HOST ||
      process.env.GCLOUD_PROJECT !== DEMO_PROJECT ||
      !db || typeof db.runTransaction !== "function") {
    throw Error("SOCIAL_STAGE2_EMULATOR_ONLY_NO_PRODUCTION");
  }
}
function snapshot(id, data) {
  return {id, ...(data || {})};
}
function identity(uid) {
  if (typeof uid !== "string" || !/^[a-zA-Z0-9_-]{1,128}$/.test(uid)) {
    throw Error("server-auth-uid-required");
  }
}
function taskIdentity(taskId) {
  if (typeof taskId !== "string" ||
      !/^[a-zA-Z0-9_-]{1,80}$/.test(taskId)) throw Error("invalid-task-id");
}
async function authorizedManager(db, authUid) {
  identity(authUid);
  const doc = await db.collection("admins").doc(authUid).get();
  const data = doc.exists ? doc.data() : null;
  const actor = {
    uid: authUid, role: data?.role, active: data?.active === true,
    serverVerified: doc.exists,
  };
  if (!doc.exists || data?.status !== "active") {
    throw Error("general-manager-server-verification-required");
  }
  policy.saveDraft({
    draft: {
      platform: "telegram", action: "follow",
      title: "authorization check", url: "https://t.me/safe",
      rewardUnit: "points", rewardAmount: 1,
      doubleWithRewardedAd: false,
    }, actor, now: new Date("2026-01-01T00:00:00Z"),
  });
  return actor;
}
async function save(db, {authUid, taskId, draft, expectedRevision, now}) {
  requireEmulator(db);
  taskIdentity(taskId);
  const actor = await authorizedManager(db, authUid);
  const ref = db.collection(COLLECTION).doc(taskId);
  const audit = db.collection(AUDIT).doc();
  return db.runTransaction(async (tx) => {
    const before = await tx.get(ref);
    const old = before.exists ? before.data() : null;
    if ((old?.revision ?? 0) !== expectedRevision) {
      throw Error("revision-conflict");
    }
    const values = policy.saveDraft({previous: old, draft, actor, now});
    if (before.exists) tx.update(ref, values);
    else tx.create(ref, {...values, createdBy: authUid});
    tx.create(audit, {taskId, action: "save", actorUid: authUid,
      oldRevision: expectedRevision, newRevision: values.revision,
      atUtc: now.toISOString()});
    return snapshot(taskId, values);
  });
}
async function schedule(db, {authUid, taskId, expectedRevision, day, now}) {
  requireEmulator(db);
  taskIdentity(taskId);
  const actor = await authorizedManager(db, authUid);
  const ref = db.collection(COLLECTION).doc(taskId);
  const audit = db.collection(AUDIT).doc();
  return db.runTransaction(async (tx) => {
    const before = await tx.get(ref);
    if (!before.exists) throw Error("missing-draft");
    const old = before.data();
    if (old.revision !== expectedRevision) throw Error("revision-conflict");
    const next = policy.scheduleDraft({draft: old, day, actor, now});
    tx.update(ref, next);
    tx.create(audit, {taskId, action: "schedule", actorUid: authUid,
      day, atUtc: now.toISOString()});
    return snapshot(taskId, next);
  });
}
async function cancel(db, {authUid, taskId, expectedRevision, now}) {
  requireEmulator(db);
  taskIdentity(taskId);
  const actor = await authorizedManager(db, authUid);
  const ref = db.collection(COLLECTION).doc(taskId);
  const audit = db.collection(AUDIT).doc();
  return db.runTransaction(async (tx) => {
    const before = await tx.get(ref);
    if (!before.exists) throw Error("missing-scheduled-task");
    const old = before.data();
    if (old.revision !== expectedRevision) throw Error("revision-conflict");
    const next = policy.cancelSchedule({task: old, actor, now});
    tx.update(ref, next);
    tx.create(audit, {taskId, action: "cancel", actorUid: authUid,
      atUtc: now.toISOString()});
    return snapshot(taskId, next);
  });
}
async function publishDue(db, {now}) {
  requireEmulator(db);
  policy.dayId(now);
  const pending = await db.collection(COLLECTION)
      .where("status", "==", "scheduled").limit(100).get();
  const outcomes = [];
  for (const item of pending.docs) {
    const ref = db.collection(COLLECTION).doc(item.id);
    const published = db.collection(PUBLISHED).doc(item.id);
    const audit = db.collection(AUDIT).doc();
    const outcome = await db.runTransaction(async (tx) => {
      const [current, existing] = await Promise.all([
        tx.get(ref), tx.get(published),
      ]);
      if (!current.exists) return "missing-task";
      const result = policy.publishDueConfig({
        task: current.data(), now,
      });
      if (result.outcome !== "published-config-only") return result.outcome;
      if (existing.exists &&
          existing.data()?.revision >= result.task.revision) {
        return "already-published";
      }
      tx.update(ref, result.task);
      tx.set(published, {
        ...result.task, taskId: item.id, shadowOnly: true,
        rewardsEnabled: false, rewardClaimMode: "disabled",
      });
      tx.create(audit, {taskId: item.id, action: "publish-config-only",
        atUtc: now.toISOString()});
      return "published-config-only";
    });
    outcomes.push({taskId: item.id, outcome});
  }
  return outcomes;
}

module.exports = {
  DEMO_PROJECT, COLLECTION, PUBLISHED, AUDIT,
  requireEmulator, authorizedManager, save, schedule, cancel, publishDue,
};
