"use strict";

/**
 * DEDA launch setting: when GENERAL MANAGER enables automatic publication,
 * approve NEW complete place requests after 30s, WITHOUT staff/content review.
 *
 * These are technical integrity checks, not moderation. Older pending
 * requests, edits, unbound accounts and incomplete submissions remain manual.
 * Evaluation must happen in a PRIVILEGED backend transaction, never Flutter.
 */
const REQUIRED = ["placeName", "phone", "governorate", "address",
  "openingHours", "description", "category", "accountKey", "ownerUid"];
const MIN_DELAY_MS = 30 * 1000;

function ms(v) {
  if (v && typeof v.toMillis === "function") return v.toMillis();
  if (v instanceof Date) return v.getTime();
  return NaN;
}

function assess({request, settings, serverNowMs, exactTrustedOwner}) {
  const stop = (reason) => ({eligible: false, reason});
  if (settings?.enabled !== true) return stop("auto-off");
  if (!request || request.status !== "pending" ||
      request.requestType !== "create") return stop("manual-or-edit");
  const enabledAt = ms(settings.enabledAt);
  const createdAt = ms(request.createdAt);
  if (!Number.isFinite(createdAt) || !Number.isFinite(enabledAt) ||
      !Number.isFinite(serverNowMs) ||
      createdAt <= enabledAt || createdAt > serverNowMs) {
    return stop("request-was-not-new-when-switched-on");
  }
  if (serverNowMs - createdAt < MIN_DELAY_MS) return stop("wait-30-seconds");
  if (exactTrustedOwner !== true) return stop("unverified-account-owner");
  if (REQUIRED.some((k) => typeof request[k] !== "string" ||
      request[k].trim().length === 0)) return stop("missing-required-data");
  if (request.category === "other" &&
      !String(request.otherCategoryText || "").trim()) {
    return stop("other-category-empty");
  }
  const {latitude: lat, longitude: lng} = request;
  if (typeof lat !== "number" || typeof lng !== "number" ||
      !Number.isFinite(lat) || !Number.isFinite(lng) ||
      lat < 29 || lat > 38.8 || lng < 38.5 || lng > 49.2) {
    return stop("invalid-location");
  }
  return {eligible: true, reason: "ready-for-auto-publication"};
}

module.exports = {assess, MIN_DELAY_MS};
