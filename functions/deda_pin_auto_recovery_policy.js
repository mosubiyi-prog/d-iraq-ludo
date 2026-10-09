"use strict";

/**
 * Owner request #2: TEN-SECOND forgotten-PIN recovery eligibility.
 * This policy NEVER generates or exposes PINs.
 *
 * Bare phone, user-entered name and a locally generated installation ID
 * are NOT proof of ownership. All requirements must come from server-side
 * verification before any privileged reset. Default is MANUAL.
 */
function ms(v) {
  return v && typeof v.toMillis === "function" ? v.toMillis() :
    v instanceof Date ? v.getTime() : NaN;
}

function decide({request, setting, ready, serverNow, serverProof,
  attemptCountLastHour, latestRequestId}) {
  const manual = (reason) => ({eligible: false, outcome: "manual-review", reason});
  if (ready !== true || setting?.enabled !== true) {
    return manual("mode-or-server-off");
  }
  if (!request || request.status !== "new" ||
      request.type === "admin" || request.purpose === "admin_password_reset") {
    return manual("not-new-public-pin-request");
  }
  const enabledAt = ms(setting.enabledAt);
  const createdAt = ms(request.createdAt);
  if (!Number.isFinite(createdAt) || !Number.isFinite(enabledAt) ||
      createdAt <= enabledAt) return manual("pre-existing-request");
  const now = ms(serverNow);
  if (!Number.isFinite(now) || now - createdAt < 10000 ||
      now - createdAt > 30 * 60 * 1000) {
    return manual("not-within-ten-second-validity-window");
  }
  if (!request.requesterUid || !request.accountKey ||
      !request.requesterInstallId) return manual("missing-request");
  if (request.riskLevel !== "low" || request.accountFound !== true ||
      request.sameDevice !== true || request.nameMatches !== true) {
    return manual("risk-or-identity-review");
  }
  if (!serverProof || serverProof.valid !== true ||
      serverProof.uid !== request.requesterUid ||
      serverProof.accountKey !== request.accountKey ||
      serverProof.revoked !== false ||
      serverProof.kind !== "verified-credential-proof") {
    return manual("no-strong-server-verified-owner-proof");
  }
  if (attemptCountLastHour !== 1 ||
      latestRequestId !== request.requestId) return manual("replay-or-rate-limit");
  return {eligible: true, outcome: "eligible-for-server-only-issuance",
    reason: "verified-strong-proof-after-ten-seconds"};
}

module.exports={decide};
