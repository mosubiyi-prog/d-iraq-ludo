"use strict";

// Isolated, NOT DEPLOYED. Verifies a real Google OIDC ID-token signature
// against Google's trusted public JWKS. It NEVER calls Firebase signIn,
// issues Firebase tokens, selects an old DEDA UID, modifies Firestore,
// or links a Google subject to any historical account.
// The caller MUST be a trusted server with a previously generated and stored,
// single-use nonce challenge. This verifier DOES NOT prove old-account ownership.

const { createPublicKey, verify, timingSafeEqual } = require("node:crypto");

const JWKS_URL = "https://www.googleapis.com/oauth2/v3/certs";
const DEDA_PROD_PROJECT = "deda-25b88";
const QA_PROJECT = "deda-qa-uid-lab-20261108";
const MAX_JWT_SIZE = 8192;
const MAX_JWKS_BYTES = 100000;
const CLOCK_SKEW_SECONDS = 60;
const MAX_CHALLENGE_AGE_MS = 10 * 60 * 1000;
const MAX_TOKEN_AGE_SECONDS = 10 * 60;
const GOOGLE_ISSUERS = new Set([
  "https://accounts.google.com", "accounts.google.com",
]);
const AUDIENCE = /^[0-9]+-[a-zA-Z0-9_-]+\.apps\.googleusercontent\.com$/;
const B64 = /^[A-Za-z0-9_-]+$/;
const OPAQUE_NONCE = /^[A-Za-z0-9_-]{24,128}$/;
const GOOGLE_SUBJECT = /^[0-9]{6,256}$/;

function fail(reason) {
  return Object.freeze({
    status:"DENY", reason, verifiedProspectiveGoogle:null,
    mayLogin:false, mayCreateUid:false, mayLinkProvider:false,
    maySelectOwnerUid:false, mayWriteFirestore:false,
    independentOldAccountOwnershipProven:false,
  });
}

function object(v) {
  return v && typeof v === "object" && !Array.isArray(v);
}

function decodePart(segment) {
  if (!B64.test(segment) || segment.length > 8192) return null;
  try {
    const bytes = Buffer.from(segment, "base64url");
    if (bytes.length === 0 ||
        bytes.toString("base64url") !== segment) return null;
    const value = JSON.parse(bytes.toString("utf8"));
    return object(value) ? value : null;
  } catch (_) { return null; }
}
function exactNonce(a,b) {
  if (typeof a !== "string" || typeof b !== "string" ||
      !OPAQUE_NONCE.test(a) || !OPAQUE_NONCE.test(b)) return false;
  const aa=Buffer.from(a,"utf8"), bb=Buffer.from(b,"utf8");
  return aa.length===bb.length && timingSafeEqual(aa,bb);
}

function validConfiguration(c) {
  return object(c) && c.projectId === DEDA_PROD_PROJECT &&
    c.projectId !== QA_PROJECT &&
    typeof c.productionOAuthAudience === "string" &&
    AUDIENCE.test(c.productionOAuthAudience) &&
    c.serverApproved === true &&
    c.source === "trusted_server_configuration";
}

function validChallenge(challenge, expectedAudience, nowMs) {
  return object(challenge) &&
    challenge.source === "trusted_server_nonce_store" &&
    challenge.status === "issued" &&
    challenge.productionOAuthAudience === expectedAudience &&
    exactNonce(challenge.nonce, challenge.nonce) &&
    Number.isSafeInteger(challenge.createdAtMs) &&
    challenge.createdAtMs > 0 &&
    Number.isSafeInteger(nowMs) &&
    nowMs >= challenge.createdAtMs &&
    nowMs-challenge.createdAtMs <= MAX_CHALLENGE_AGE_MS;
}

function inspectSignedToken({idToken, productionConfig, challenge, jwks, nowMs}) {
  if (!validConfiguration(productionConfig)) return fail("UNTRUSTED_PRODUCTION_OAUTH_CONFIG");
  const aud=productionConfig.productionOAuthAudience;
  if (!validChallenge(challenge,aud,nowMs)) return fail("NO_CURRENT_SERVER_NONCE");
  if (typeof idToken !== "string" ||
      idToken.length < 100 || idToken.length > MAX_JWT_SIZE) {
    return fail("MALFORMED_GOOGLE_ID_TOKEN");
  }
  const segments=idToken.split(".");
  if (segments.length!==3 || segments.some(x=>!B64.test(x))) {
    return fail("MALFORMED_GOOGLE_ID_TOKEN");
  }
  const header=decodePart(segments[0]), claims=decodePart(segments[1]);
  if (!header || !claims || header.alg!=="RS256" ||
      (header.typ!==undefined && header.typ!=="JWT") ||
      typeof header.kid!=="string" || header.kid.length<1 ||
      header.kid.length>256 || header.crit!==undefined ||
      header.jwk!==undefined || header.jku!==undefined ||
      header.x5u!==undefined) return fail("UNTRUSTED_GOOGLE_TOKEN_HEADER");
  if (!object(jwks) || !Array.isArray(jwks.keys) || jwks.keys.length>25) {
    return fail("GOOGLE_JWKS_UNAVAILABLE");
  }
  const matching=jwks.keys.filter(key=>object(key) && key.kid===header.kid &&
    key.kty==="RSA" && (key.alg===undefined || key.alg==="RS256") &&
    (key.use===undefined || key.use==="sig") &&
    B64.test(key.n||"") && B64.test(key.e||""));
  if (matching.length!==1 ||
      Buffer.from(matching[0].n,"base64url").length<256) {
    return fail("UNTRUSTED_GOOGLE_SIGNING_KEY");
  }
  let signatureValid=false;
  try {
    const publicKey=createPublicKey({key:{
      kty:"RSA", n:matching[0].n, e:matching[0].e
    },format:"jwk"});
    signatureValid=verify("RSA-SHA256",
      Buffer.from(segments[0]+"."+segments[1],"utf8"),
      publicKey,Buffer.from(segments[2],"base64url"));
  } catch (_) { return fail("GOOGLE_SIGNATURE_VERIFICATION_FAILED"); }
  if (!signatureValid) return fail("GOOGLE_SIGNATURE_VERIFICATION_FAILED");

  const nowSeconds=Math.floor(nowMs/1000);
  const iat=claims.iat, exp=claims.exp;
  if (!GOOGLE_ISSUERS.has(claims.iss) ||
      claims.aud!==aud ||
      (claims.azp!==undefined && claims.azp!==aud) ||
      typeof claims.sub!=="string" || !GOOGLE_SUBJECT.test(claims.sub) ||
      !Number.isSafeInteger(iat) || !Number.isSafeInteger(exp) ||
      iat<=0 || exp<=iat ||
      iat>nowSeconds+CLOCK_SKEW_SECONDS ||
      iat<nowSeconds-MAX_TOKEN_AGE_SECONDS ||
      iat<Math.floor(challenge.createdAtMs/1000)-CLOCK_SKEW_SECONDS ||
      exp<=nowSeconds-CLOCK_SKEW_SECONDS ||
      (claims.nbf!==undefined && (!Number.isSafeInteger(claims.nbf) ||
        claims.nbf>nowSeconds+CLOCK_SKEW_SECONDS)) ||
      !exactNonce(claims.nonce,challenge.nonce)) {
    return fail("GOOGLE_TOKEN_CLAIMS_OR_NONCE_INVALID");
  }

  // This is an AUTHENTICATED GOOGLE SUBJECT, not old DEDA ownership proof.
  // Do not send the token, subject, claims or signing key to clients/logs.
  return Object.freeze({
    status:"SIGNED_GOOGLE_IDENTITY_VALID_NONCE_NOT_YET_CONSUMED",
    reason:"REQUIRES_ONE_TIME_CHALLENGE_CONSUMPTION",
    googleClaims: Object.freeze({
      issuer:"https://accounts.google.com",
      audience:aud,
      subject:claims.sub,
      verifiedAtMs:nowMs,
    }),
    independentOldAccountOwnershipProven:false,
    mayLogin:false, mayCreateUid:false, mayLinkProvider:false,
    maySelectOwnerUid:false, mayWriteFirestore:false,
  });
}

/**
 * Network endpoint is fixed to Google, HTTPS certificate checked by Node.
 * Never use a client-supplied JWKS URL and never allow redirects.
 */
async function getOfficialGoogleJwks({fetchImpl=fetch}={}) {
  const res=await fetchImpl(JWKS_URL,{
    method:"GET",redirect:"error",signal:AbortSignal.timeout(5000),
    headers:{accept:"application/json"},
  });
  if (!res || res.status!==200 ||
      Number(res.headers?.get("content-length")||0)>MAX_JWKS_BYTES ||
      !res.body) throw Error("GOOGLE_JWKS_FETCH_DENIED");
  const chunks=[];
  let total=0;
  for await(const chunk of res.body) {
    const part=Buffer.from(chunk);total+=part.length;
    if (total>MAX_JWKS_BYTES) throw Error("GOOGLE_JWKS_TOO_LARGE");
    chunks.push(part);
  }
  const data=JSON.parse(Buffer.concat(chunks).toString("utf8"));
  if (!object(data) || !Array.isArray(data.keys)) {
    throw Error("GOOGLE_JWKS_INVALID");
  }
  return data;
}

/**
 * TRUSTED-SERVER-ONLY review. A Google token must be signed, nonce-bound,
 * and the challenge consumed ONCE with an atomic server transaction.
 * No implementation of get/consume exists in production yet.
 * Return contains NO sensitive Google subject, UID, email or tokens.
 */
async function verifyProspectiveGoogleForLegacyReview({
  idToken, productionConfig, challenge, nowMs,
  loadTrustedGoogleJwks=getOfficialGoogleJwks,
  consumeOneTimeChallenge,
}={}) {
  if (typeof loadTrustedGoogleJwks!=="function" ||
      typeof consumeOneTimeChallenge!=="function") {
    return fail("SERVER_NONCE_CONSUMER_NOT_CONFIGURED");
  }
  if (!validConfiguration(productionConfig) ||
      !validChallenge(challenge,productionConfig.productionOAuthAudience,nowMs)) {
    return fail("UNTRUSTED_PRODUCTION_CONFIGURATION_OR_NONCE");
  }
  try {
    const keys=await loadTrustedGoogleJwks();
    const checked=inspectSignedToken({idToken,productionConfig,challenge,
      jwks:keys,nowMs});
    if (!checked.googleClaims) return checked;
    // Caller must enforce a unique key & atomic mark-used action.
    // A false/throw result DENIES; never silently retry or issue a session.
    const consumed=await consumeOneTimeChallenge({
      nonce:challenge.nonce,
      createdAtMs:challenge.createdAtMs,
      productionOAuthAudience:productionConfig.productionOAuthAudience,
    });
    if (consumed!==true) return fail("NONCE_REPLAY_OR_CONSUMPTION_FAILED");
    return Object.freeze({
      status:"GOOGLE_ONLY_VERIFIED_FOR_SEPARATE_LEGACY_OWNER_REVIEW",
      verifiedProspectiveGoogle:Object.freeze({
        verifier:"trusted_google_oidc_backend",
        issuer:"https://accounts.google.com",
        audience:checked.googleClaims.audience,
        oauthClientProjectId:DEDA_PROD_PROJECT,
        audienceVerified:true,
        nonceVerified:true,
        freshAndUnexpired:true,
        subjectVerified:true,
        providerId:"google.com",
        verified:true,
      }),
      independentOldAccountOwnershipProven:false,
      mayLogin:false,mayCreateUid:false,mayLinkProvider:false,
      maySelectOwnerUid:false,mayWriteFirestore:false,
    });
  } catch (_) {return fail("GOOGLE_IDENTITY_VERIFICATION_UNAVAILABLE");}
}

module.exports={
  inspectSignedToken,
  getOfficialGoogleJwks,
  verifyProspectiveGoogleForLegacyReview,
};
