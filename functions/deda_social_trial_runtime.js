"use strict";

/**
 * DEDA trial social publishing (config only). Real backend requires explicit
 * deployment after emulator/security review. All identity and time values come
 * from Firebase Auth + the server, NEVER from request.data.
 * No wallet operations, reward claims, or Telegram membership assumptions.
 */
const {FieldValue} = require("firebase-admin/firestore");
const policy = require("./deda_social_task_stage2.js");
const ADMIN = "deda_social_admin_state";
const PUBLIC = "deda_social_task_public";
const AUDIT = "deda_social_task_audit";
const DOC = "featured";
const WINDOW_MS = 20 * 60 * 1000;

function revisionOf(value) {
  if (!Number.isSafeInteger(value) || value < 0) throw Error("invalid-revision");
  return value;
}
function manager(actor) {
  policy.dayId(new Date());
  if (!actor || !actor.uid || actor.role !== "general_manager" ||
      actor.active !== true || actor.serverVerified !== true) {
    throw Error("general-manager-server-verification-required");
  }
}
function response(task) {
  if (!task) return {exists: false, revision: 0};
  return {exists: true, ...task};
}
async function command(db, {actor, input, now = new Date()}) {
  manager(actor);
  policy.dayId(now);
  if (!db || typeof db.runTransaction !== "function") {
    throw Error("admin-sdk-firestore-required");
  }
  if (!input || typeof input !== "object" || Array.isArray(input)) {
    throw Error("invalid-input");
  }
  const op = input.op;
  if (!["get", "save", "schedule", "cancel"].includes(op)) {
    throw Error("unsupported-operation");
  }
  const ref = db.collection(ADMIN).doc(DOC);
  if (op === "get") {
    const snap = await ref.get();
    return response(snap.exists ? snap.data() : null);
  }
  const expected = revisionOf(input.expectedRevision);
  const audit = db.collection(AUDIT).doc();
  return db.runTransaction(async (tx) => {
    const previous = await tx.get(ref);
    const old = previous.exists ? previous.data() : null;
    if ((old?.revision ?? 0) !== expected) throw Error("revision-conflict");
    let next;
    if (op === "save") {
      next = policy.saveDraft({
        previous: old,
        draft: input.draft,
        actor,
        now,
      });
    } else if (op === "schedule") {
      if (!old) throw Error("missing-draft");
      next = policy.scheduleDraft({
        draft: old, day: input.day, actor, now,
      });
    } else {
      if (!old) throw Error("missing-scheduled-task");
      next = policy.cancelSchedule({task: old, actor, now});
    }
    if (previous.exists) tx.update(ref, next);
    else tx.create(ref, next);
    tx.create(audit, {
      taskId: DOC, op, actorUid: actor.uid, previousRevision: expected,
      revision: next.revision, day: next.effectiveDay || "",
      createdAt: FieldValue.serverTimestamp(),
    });
    return response(next);
  });
}
async function publishDue(db, now = new Date()) {
  const date = now instanceof Date ? now : new Date(now);
  const day = policy.dayId(date);
  const start = policy.iraqMidnightUtc(day).getTime();
  // Publish only shortly after Baghdad midnight, never midway through a day.
  if (date.getTime() < start || date.getTime() >= start + WINDOW_MS) {
    return {outcome: "outside-midnight-window"};
  }
  const admin = db.collection(ADMIN).doc(DOC);
  const publicRef = db.collection(PUBLIC).doc(DOC);
  const history = db.collection(AUDIT).doc("publish_" + day);
  return db.runTransaction(async (tx) => {
    const [source, existing, historySnap] = await Promise.all([
      tx.get(admin), tx.get(publicRef), tx.get(history),
    ]);
    if (!source.exists) return {outcome: "no-draft"};
    const task = source.data();
    if (task.status !== "scheduled" || task.effectiveDay !== day ||
        task.effectiveAtUtc !== policy.iraqMidnightUtc(day).toISOString()) {
      return {outcome: "not-due"};
    }
    if (historySnap.exists ||
        (existing.exists && existing.data().publishedDay === day)) {
      return {outcome: "already-published"};
    }
    const decided = policy.publishDueConfig({task, now: date});
    if (decided.outcome !== "published-config-only") {
      return {outcome: decided.outcome};
    }
    const published = {
      taskId: DOC, platform: task.platform, action: task.action,
      title: task.title, url: task.url,
      rewardUnit: task.rewardUnit, rewardAmount: task.rewardAmount,
      doubleWithRewardedAd: task.doubleWithRewardedAd,
      otherPlatform: task.otherPlatform || "",
      otherAction: task.otherAction || "",
      publishedDay: day,
      sourceRevision: task.revision,
      publishedAt: FieldValue.serverTimestamp(),
      rewardsEnabled: false,
      rewardClaimMode: "blocked-until-trusted-proof-and-ssv-ledger",
    };
    tx.update(admin, decided.task);
    tx.set(publicRef, published);
    tx.create(history, {
      taskId: DOC, op: "publish-config-only", publishedDay: day,
      sourceRevision: task.revision, publishedAt: FieldValue.serverTimestamp(),
      priorPublic: existing.exists ? {
        title: existing.data().title, publishedDay: existing.data().publishedDay,
      } : null,
    });
    return {outcome: "published-config-only", publishedDay: day};
  });
}
module.exports = {ADMIN, PUBLIC, AUDIT, DOC, command, publishDue};
