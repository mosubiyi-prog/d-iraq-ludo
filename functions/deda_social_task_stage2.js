"use strict";

/**
 * DEDA social-task lifecycle policy, STAGING ONLY.
 *
 * This module is deliberately NOT exported as a production Firebase Function.
 * All transitions consume server-supplied time and an already authenticated
 * general-manager identity. Do not accept those two inputs from a client.
 * Opening a social URL is NOT completion evidence.
 */
const PLATFORM_DOMAINS = Object.freeze({
  facebook: ["facebook.com", "fb.com", "fb.watch"],
  telegram: ["t.me", "telegram.me"],
  youtube: ["youtube.com", "youtu.be"],
  instagram: ["instagram.com"],
  tiktok: ["tiktok.com"],
});
const PLATFORMS = Object.freeze([
  "facebook", "telegram", "youtube", "instagram", "tiktok", "other",
]);
const ACTIONS = Object.freeze([
  "follow", "like_post", "watch_video", "like_video", "other",
]);
const UNITS = Object.freeze(["points", "coins", "diamonds"]);
const IRAQ_OFFSET_MS = 3 * 60 * 60 * 1000;
const MAX_REWARD = 5000;

function insist(ok, reason) {
  if (!ok) throw Error(reason);
}
function dayId(date) {
  insist(date instanceof Date && Number.isFinite(date.getTime()),
      "trusted-server-clock-required");
  return new Date(date.getTime() + IRAQ_OFFSET_MS)
      .toISOString().slice(0, 10);
}
function validDay(day) {
  if (typeof day !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(day)) return false;
  const d = new Date(day + "T00:00:00.000Z");
  return !Number.isNaN(d.getTime()) && d.toISOString().slice(0, 10) === day;
}
function iraqMidnightUtc(day) {
  insist(validDay(day), "invalid-iraq-day");
  return new Date(Date.parse(day + "T00:00:00.000Z") - IRAQ_OFFSET_MS);
}
function trustedManager(actor) {
  insist(actor && typeof actor.uid === "string" && actor.uid.length > 0 &&
      actor.role === "general_manager" && actor.active === true &&
      actor.serverVerified === true, "general-manager-server-verification-required");
}
function safeUrl(url, platform) {
  try {
    const parsed = new URL(url);
    if (parsed.protocol !== "https:" || parsed.username || parsed.password ||
        parsed.port && parsed.port !== "443" || parsed.hash ||
        !parsed.hostname.includes(".") || parsed.hostname.endsWith(".local")) {
      return false;
    }
    const host = parsed.hostname.toLowerCase();
    if (/^(?:\d{1,3}\.){3}\d{1,3}$/.test(host) || host === "localhost") {
      return false;
    }
    if (platform === "other") return true;
    return PLATFORM_DOMAINS[platform]?.some(
        (domain) => host === domain || host.endsWith("." + domain)) || false;
  } catch (_) { return false; }
}
function validateDraft(draft) {
  insist(draft && typeof draft === "object", "missing-draft");
  insist(PLATFORMS.includes(draft.platform), "unsupported-platform");
  insist(ACTIONS.includes(draft.action), "unsupported-interaction");
  insist(typeof draft.title === "string" && draft.title.trim() === draft.title &&
      draft.title.length >= 3 && draft.title.length <= 80, "invalid-title");
  insist(typeof draft.url === "string" &&
      draft.url.length <= 500 && safeUrl(draft.url, draft.platform),
      "invalid-platform-url");
  insist(UNITS.includes(draft.rewardUnit), "unsupported-reward-unit");
  insist(Number.isSafeInteger(draft.rewardAmount) &&
      draft.rewardAmount > 0 && draft.rewardAmount <= MAX_REWARD,
      "reward-outside-limits");
  insist(typeof draft.doubleWithRewardedAd === "boolean", "invalid-ad-option");
  if (draft.platform === "other") {
    insist(typeof draft.otherPlatform === "string" &&
      draft.otherPlatform.trim().length >= 3 &&
      draft.otherPlatform.trim().length <= 70, "missing-custom-platform");
  }
  if (draft.action === "other") {
    insist(typeof draft.otherAction === "string" &&
      draft.otherAction.trim().length >= 3 &&
      draft.otherAction.trim().length <= 70, "missing-custom-action");
  }
  return {
    platform: draft.platform, action: draft.action,
    title: draft.title, url: draft.url, rewardUnit: draft.rewardUnit,
    rewardAmount: draft.rewardAmount,
    doubleWithRewardedAd: draft.doubleWithRewardedAd,
    otherPlatform: draft.platform === "other" ? draft.otherPlatform.trim() : "",
    otherAction: draft.action === "other" ? draft.otherAction.trim() : "",
  };
}
function saveDraft({previous, draft, actor, now}) {
  trustedManager(actor);
  dayId(now);
  if (previous) {
    insist(previous.status === "draft" || previous.status === "cancelled",
        "scheduled-or-published-cannot-be-edited");
  }
  return {
    ...validateDraft(draft),
    status: "draft",
    revision: previous ? previous.revision + 1 : 1,
    updatedBy: actor.uid, updatedAt: now.toISOString(),
    published: false, rewardsEnabled: false,
  };
}
function scheduleDraft({draft, day, actor, now}) {
  trustedManager(actor);
  insist(draft && draft.status === "draft", "draft-required");
  insist(validDay(day) && day > dayId(now), "future-iraq-day-required");
  return {
    ...draft, status: "scheduled",
    effectiveDay: day, effectiveAtUtc: iraqMidnightUtc(day).toISOString(),
    revision: draft.revision + 1,
    updatedBy: actor.uid, updatedAt: now.toISOString(),
    published: false, rewardsEnabled: false,
  };
}
function cancelSchedule({task, actor, now}) {
  trustedManager(actor);
  insist(task && task.status === "scheduled", "not-scheduled");
  insist(now instanceof Date && Number.isFinite(now.getTime()),
      "trusted-server-clock-required");
  insist(now < new Date(task.effectiveAtUtc), "too-late-to-cancel");
  return {
    ...task, status: "cancelled",
    revision: task.revision + 1,
    updatedBy: actor.uid, updatedAt: now.toISOString(),
    published: false, rewardsEnabled: false,
  };
}
function publishDueConfig({task, now}) {
  dayId(now);
  if (!task || task.status !== "scheduled") {
    return {outcome: "not-scheduled", task};
  }
  if (now < new Date(task.effectiveAtUtc)) {
    return {outcome: "not-due", task};
  }
  return {
    outcome: "published-config-only",
    task: {...task, status: "published", published: true,
      publishedAt: now.toISOString(), revision: task.revision + 1,
      // Never grant from a scheduled config, a URL visit or a client flag.
      rewardsEnabled: false,
      rewardClaimMode: "blocked-until-trusted-proof-and-ssv-ledger"},
  };
}
function rewardDecision({task, completionProof, adProof, ledgerEntries}) {
  if (!task || task.status !== "published" || task.rewardsEnabled !== true) {
    return {outcome: "rewards-disabled"};
  }
  if (!completionProof || completionProof.serverVerified !== true ||
      completionProof.source !== "trusted-platform-verifier" ||
      completionProof.taskRevision !== task.revision ||
      !completionProof.uniqueEventId ||
      completionProof.uid !== task.uid) {
    return {outcome: "completion-not-verified"};
  }
  if (ledgerEntries?.has(completionProof.uniqueEventId)) {
    return {outcome: "already-awarded"};
  }
  // SSV callback verification and the live wallet ledger are NOT implemented.
  return {outcome: "live-wallet-ledger-not-ready",
    adBonus: adProof?.serverVerified === true ? "blocked" : "unverified"};
}
function previewReward({amount, unit, doubleWithRewardedAd}) {
  insist(Number.isSafeInteger(amount) && amount > 0 &&
      amount <= MAX_REWARD && UNITS.includes(unit) &&
      typeof doubleWithRewardedAd === "boolean", "invalid-preview-reward");
  return {
    base: amount, unit, bonusIfVerifiedAd: doubleWithRewardedAd ? amount : 0,
    potentialTotal: amount * (doubleWithRewardedAd ? 2 : 1),
    payable: false,
  };
}
module.exports = {
  PLATFORMS, ACTIONS, UNITS, dayId, validDay, iraqMidnightUtc, safeUrl,
  validateDraft, saveDraft, scheduleDraft, cancelSchedule,
  publishDueConfig, rewardDecision, previewReward,
};
