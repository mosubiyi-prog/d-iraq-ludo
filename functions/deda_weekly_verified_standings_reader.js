"use strict";
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {defineSecret} = require("firebase-functions/params");
const {getAuth} = require("firebase-admin/auth");
const {getFirestore} = require("firebase-admin/firestore");
const {readVerifiedWeeklyStandings, WeeklyNotReady} =
  require("./deda_weekly_verified_standings_reader_core");

const leagueSourceKey = defineSecret("DEDA_WEEKLY_VERIFIED_PUBLICATION_HMAC_KEY");
exports.dedaWeeklyVerifiedStandingsV1 = onCall({
  enforceAppCheck: true,
  secrets: [leagueSourceKey],
  timeoutSeconds: 30,
  memory: "256MiB",
}, async request => {
  try {
    return await readVerifiedWeeklyStandings({
      request, auth: getAuth(), db: getFirestore(),
      secret: leagueSourceKey.value(),
    });
  } catch (error) {
    if (error instanceof WeeklyNotReady) {
      throw new HttpsError("failed-precondition",
        "weekly-verified-source-not-ready");
    }
    console.error("DEDA_WEEKLY_VERIFIED_READ_UNAVAILABLE");
    throw new HttpsError("unavailable", "weekly-source-unavailable");
  }
});
