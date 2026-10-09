"use strict";

/**
 * Owner request #1 — eligibility policy for NEW place requests only.
 *
 * Pure fail-closed checks. This does NOT publish a place by itself.
 * The privileged server worker must check saved manager settings and
 * duplicate evidence in a transaction before calling this policy.
 * It is unsafe to call from Android (client cannot grant approvals).
 */
const REQUIRED = ["placeName", "phone", "governorate", "address",
  "openingHours", "description", "category", "accountKey", "ownerUid"];

function norm(v) {
  return String(v || "").trim().replace(/\s+/g, " ").toLocaleLowerCase("ar");
}
function millis(v) {
  if (v && typeof v.toMillis === "function") return v.toMillis();
  if (v instanceof Date) return v.getTime();
  return Number.NaN;
}
function distanceMeters(a, b) {
  const r = 6371000, rad = (x) => x * Math.PI / 180;
  const dLat = rad(b.latitude - a.latitude);
  const dLon = rad(b.longitude - a.longitude);
  const h = Math.sin(dLat / 2) ** 2 +
    Math.cos(rad(a.latitude)) * Math.cos(rad(b.latitude)) * Math.sin(dLon / 2) ** 2;
  return 2 * r * Math.asin(Math.min(1, Math.sqrt(h)));
}

/** Returns true ONLY if owner authorized auto and server has enough proof. */
function assess({request, settings, publishedInProvince, provinceScanComplete,
  serverNowMs, exactTrustedOwner}) {
  const reason = (why) => ({eligible: false, reason: why});
  if (!settings || settings.enabled !== true) return reason("mode-off");
  const switched = millis(settings.enabledAt);
  const submitted = millis(request && request.createdAt);
  if (!Number.isFinite(submitted) || !Number.isFinite(switched) ||
      submitted <= switched || submitted > serverNowMs + 10000 ||
      submitted < serverNowMs - 24 * 3600 * 1000) {
    return reason("not-new-after-enabling");
  }
  if (request.status !== "pending" || request.requestType !== "create") {
    return reason("manual-for-edits-or-nonpending");
  }
  if (exactTrustedOwner !== true) return reason("owner-unverified");
  if (REQUIRED.some((key) => !norm(request[key]))) {
    return reason("required-field-missing");
  }
  if (request.category === "other" && !norm(request.otherCategoryText)) {
    return reason("custom-category-missing");
  }
  const lat = request.latitude, lng = request.longitude;
  // A broad geographical safeguard; a real verified address is still required.
  if (typeof lat !== "number" || typeof lng !== "number" ||
      !Number.isFinite(lat) || !Number.isFinite(lng) ||
      lat < 29 || lat > 38.8 || lng < 38.5 || lng > 49.2) {
    return reason("coordinate-outside-iraq");
  }
  if (request.suspicious === true || request.reportedAsDuplicate === true) {
    return reason("fraud-risk-flag");
  }
  if (!provinceScanComplete || !Array.isArray(publishedInProvince)) {
    return reason("cannot-prove-nonduplicate");
  }
  const ownName = norm(request.placeName);
  for (const old of publishedInProvince) {
    if (!old || old.published !== true) continue;
    if (norm(old.accountKey) && norm(old.accountKey) === norm(request.accountKey) &&
        norm(old.placeName) === ownName) return reason("owner-duplicate");
    if (norm(old.placeName) !== ownName) continue;
    if (typeof old.latitude !== "number" || typeof old.longitude !== "number") {
      return reason("name-match-unknown-location");
    }
    if (distanceMeters({latitude: lat, longitude: lng}, old) < 300) {
      return reason("nearby-name-duplicate");
    }
  }
  return {eligible: true, reason: "passed-conservative-review"};
}

module.exports = {assess, norm, distanceMeters};
