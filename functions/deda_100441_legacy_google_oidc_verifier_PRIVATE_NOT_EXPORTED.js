"use strict";

// Isolated, NOT DEPLOYED. Verifies a real Google OIDC ID-token signature
// against Google's trusted public JWKS. It NEVER calls Firebase signIn,
// issues Firebase tokens, selects an old DEDA UID, modifies Firestore,
// or links a Google subject to any historical account.
// The caller MUST be a trusted server with a previously generated and stored,
// single-use nonce challenge. This verifier DOES NOT prove old-account ownership.

const { createPublicKey, verify, timingSafeEqual, randomBytes, createHash } = require("node:crypto");
const { inspectCanonicalUid } = require(
  "./deda_100441_canonical_uid_anti_split_preflight_PRIVATE_NOT_EXPORTED.js"
);

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
// Common trusted-server gate. Return the Google subject ONLY inside this
// process, after signature, production audience and one-time nonce verification.
// Do not use any client-provided subject or OAuth email as ownership evidence.
async function consumeSignedGoogleSubject({
  idToken, productionConfig, challenge, nowMs,
  loadTrustedGoogleJwks, consumeOneTimeChallenge,
}) {
  if (typeof loadTrustedGoogleJwks!=="function" ||
      typeof consumeOneTimeChallenge!=="function") {
    return {denial:fail("SERVER_NONCE_CONSUMER_NOT_CONFIGURED")};
  }
  if (!validConfiguration(productionConfig) ||
      !validChallenge(challenge,productionConfig.productionOAuthAudience,nowMs)) {
    return {denial:fail("UNTRUSTED_PRODUCTION_CONFIGURATION_OR_NONCE")};
  }
  try {
    const keys=await loadTrustedGoogleJwks();
    const checked=inspectSignedToken({idToken,productionConfig,challenge,
      jwks:keys,nowMs});
    if (!checked.googleClaims) return {denial:checked};
    const consumed=await consumeOneTimeChallenge({
      nonce:challenge.nonce,
      createdAtMs:challenge.createdAtMs,
      productionOAuthAudience:productionConfig.productionOAuthAudience,
    });
    if (consumed!==true) return {denial:fail("NONCE_REPLAY_OR_CONSUMPTION_FAILED")};
    return {claims:checked.googleClaims};
  } catch (_) {
    return {denial:fail("GOOGLE_IDENTITY_VERIFICATION_UNAVAILABLE")};
  }
}

async function verifyProspectiveGoogleForLegacyReview({
  idToken, productionConfig, challenge, nowMs,
  loadTrustedGoogleJwks=getOfficialGoogleJwks,
  consumeOneTimeChallenge,
}={}) {
  const checked=await consumeSignedGoogleSubject({
    idToken,productionConfig,challenge,nowMs,
    loadTrustedGoogleJwks,consumeOneTimeChallenge,
  });
  if (checked.denial) return checked.denial;
  return Object.freeze({
    status:"GOOGLE_ONLY_VERIFIED_FOR_SEPARATE_LEGACY_OWNER_REVIEW",
    verifiedProspectiveGoogle:Object.freeze({
      verifier:"trusted_google_oidc_backend",
      issuer:"https://accounts.google.com",
      audience:checked.claims.audience,
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
}

/**
 * ONLY PRIVATE TRUSTED-SERVER REVIEW; NEVER A CLIENT LOGIN OR NEW-UID PATH.
 * Look up a previously linked Google provider with read-only Auth,
 * AFTER a signature-checked, nonce-consumed Google OIDC identity. This never
 * grants owner privileges, returns a UID or creates any Auth principal.
 * Input accountKey/originalId are routing hints, NOT proof.
 *
 * A future external endpoint would separately require real App Check, a
 * server-issued/atomically consumed nonce, abuse limits and approval.
 */
async function reviewExistingGoogleProviderReadOnly({
  idToken, productionConfig, challenge, nowMs,
  loadTrustedGoogleJwks=getOfficialGoogleJwks,
  consumeOneTimeChallenge,
  auth, db, accountKey, originalId,
}={}) {
  const ACCOUNT=/^(?:07\d{9}|9647\d{9})$/;
  const ORIGINAL=/^@DEDA-[A-Z0-9]{6}$/;
  const UID=/^[A-Za-z0-9:_-]{6,128}$/;
  if (typeof auth?.getUserByProviderUid!=="function" ||
      typeof db?.doc!=="function" ||
      !ACCOUNT.test(accountKey||"") || !ORIGINAL.test(originalId||"")) {
    return fail("TRUSTED_SERVER_PROVIDER_LOOKUP_UNAVAILABLE");
  }
  const checked=await consumeSignedGoogleSubject({
    idToken,productionConfig,challenge,nowMs,
    loadTrustedGoogleJwks,consumeOneTimeChallenge,
  });
  if (checked.denial) return checked.denial;
  try {
    // Unlike Identity Toolkit signInWithIdp, this is a READ-ONLY lookup.
    // Unknown Google subjects are denied without an Auth registration.
    const subject=checked.claims.subject;
    const user=await auth.getUserByProviderUid("google.com",subject);
    if (!user || user.disabled===true || !UID.test(user.uid||"") ||
        !Array.isArray(user.providerData) ||
        user.providerData.filter(p=>p?.providerId==="google.com" &&
          p.uid===subject).length!==1) {
      return fail("GOOGLE_PROVIDER_OR_OWNER_NOT_VERIFIED");
    }
    const uid=user.uid;
    const paths=[
      "deda_account_directory/"+accountKey,
      "deda_credentials/"+accountKey,
      "deda_share_ids/"+originalId,
      "users/"+uid,
      "deda_social_profiles/"+originalId,
      "deda_sessions/"+uid,
      "admins/"+uid,
    ];
    const snaps=await Promise.all(paths.map(p=>db.doc(p).get()));
    const data=i=>snaps[i]?.exists===true &&
      typeof snaps[i].data==="function" ? snaps[i].data() : null;
    if (data(6) || user.customClaims?.admin===true) {
      return fail("GOOGLE_PROVIDER_OR_OWNER_NOT_VERIFIED");
    }
    const directory=data(0), credentials=data(1), route=data(2);
    const projection=data(3), social=data(4), session=data(5);
    // NEVER pass the stored PIN to the pure identity checker.
    const result=inspectCanonicalUid({
      accountKey,originalId,
      directory:directory ? {accountKey:directory.accountKey,
        createdUid:directory.createdUid,active:directory.active} : null,
      credentials:credentials ? {accountKey:credentials.accountKey,
        createdUid:credentials.createdUid,active:credentials.active} : null,
      route:route ? {publicId:route.publicId,kind:route.kind,
        active:route.active,ownerUid:route.ownerUid} : null,
      user:projection ? {accountKey:projection.accountKey,
        sharePersonalId:projection.sharePersonalId} : null,
      social:social ? {publicId:social.publicId,ownerUid:social.ownerUid} : null,
      session:session ? {uid:session.uid,accountKey:session.accountKey} : null,
      liveAuthUid:uid,authProvider:"google.com",
    });
    if (result.status!=="MATCH_CANDIDATE") {
      return fail("GOOGLE_PROVIDER_OR_OWNER_NOT_VERIFIED");
    }
    // This is a server-INTERNAL review result, not a sign-in grant.
    // No UID, Google subject, account number, ID, PIN or token in output.
    return Object.freeze({
      status:"EXISTING_GOOGLE_PROVIDER_CANONICAL_REVIEW_ONLY",
      reason:"REQUIRES_SEPARATE_SIGN_IN_AND_OWNER_REVIEW",
      verifiedProspectiveGoogle:null,
      independentOldAccountOwnershipProven:false,
      mayLogin:false,mayCreateUid:false,mayLinkProvider:false,
      maySelectOwnerUid:false,mayWriteFirestore:false,
    });
  } catch (_) {
    // Treat not-found, disabled, split, unavailable or racing records the
    // same way; never imply account creation or claim ownership.
    return fail("GOOGLE_PROVIDER_OR_OWNER_NOT_VERIFIED");
  }
}


/**
 * SERVER-ONLY, NOT DEPLOYED: an Auth+AppCheck-bound Google OIDC challenge.
 * The raw random nonce leaves the server ONLY as a public OAuth challenge.
 * Firestore stores its SHA-256 digest, never tokens, raw nonce, PIN or Google
 * subject. No account, provider, wallet, session or privileges are modified.
 *
 * A future Callable must verify its own identity, App Check and abuse limits.
 * This isolated primitive is not an endpoint and cannot authorize login.
 */
function createTrustedGoogleNonceStore({
  db, auth, appCheckVerifier, productionConfig, clock=Date.now,
  nonceFactory=randomBytes,
}={}) {
  if (!validConfiguration(productionConfig) ||
      typeof db?.collection!=="function" ||
      typeof db?.runTransaction!=="function" ||
      typeof auth?.verifyIdToken!=="function" ||
      typeof auth?.getUser!=="function" ||
      typeof appCheckVerifier?.verifyToken!=="function" ||
      typeof clock!=="function" || typeof nonceFactory!=="function") {
    throw Error("GOOGLE_NONCE_STORE_NOT_TRUSTED_OR_CONFIGURED");
  }

  const collection=db.collection("deda_100441_google_oidc_challenges");
  const instant=()=>{
    const t=clock();
    if (!Number.isSafeInteger(t) || t<=0) throw Error("UNTRUSTED_SERVER_CLOCK");
    return t;
  };
  const hash=v=>createHash("sha256").update(v,"utf8").digest("hex");
  const nonceRef=nonce=>collection.doc("nonce_"+hash(nonce));
  const limiterRef=uid=>collection.doc("requester_"+hash(uid));
  const asRecord=snap=>snap?.exists===true &&
      typeof snap.data==="function" ? snap.data() : null;

  async function requester({firebaseIdToken,appCheckToken}) {
    if (typeof firebaseIdToken!=="string" ||
        firebaseIdToken.length<16 || firebaseIdToken.length>8192 ||
        typeof appCheckToken!=="string" ||
        appCheckToken.length<8 || appCheckToken.length>8192) {
      throw Error("GOOGLE_CHALLENGE_MISSING_VERIFIED_REQUESTER");
    }
    // True Firebase Admin verification is mandatory; no user-supplied UID.
    const [decoded,check]=await Promise.all([
      auth.verifyIdToken(firebaseIdToken,true),
      appCheckVerifier.verifyToken(appCheckToken),
    ]);
    const uid=decoded?.uid, appId=check?.appId;
    if (typeof uid!=="string" || !/^[A-Za-z0-9:_-]{6,128}$/.test(uid) ||
        typeof appId!=="string" ||
        !/^[A-Za-z0-9:._-]{8,256}$/.test(appId)) {
      throw Error("GOOGLE_CHALLENGE_REQUESTER_INVALID");
    }
    const user=await auth.getUser(uid);
    if (!user || user.uid!==uid || user.disabled===true) {
      throw Error("GOOGLE_CHALLENGE_REQUESTER_NOT_ACTIVE");
    }
    return {uid,appId};
  }

  function matching(row,caller,audience,nowMs) {
    return row && row.status==="issued" &&
      row.projectId===DEDA_PROD_PROJECT &&
      row.productionOAuthAudience===audience &&
      row.requesterUid===caller.uid && row.requesterAppId===caller.appId &&
      Number.isSafeInteger(row.createdAtMs) && row.createdAtMs>0 &&
      nowMs>=row.createdAtMs &&
      nowMs-row.createdAtMs<=MAX_CHALLENGE_AGE_MS;
  }

  async function issue({firebaseIdToken,appCheckToken}={}) {
    const who=await requester({firebaseIdToken,appCheckToken});
    const nowMs=instant();
    const bytes=nonceFactory(32);
    if (!Buffer.isBuffer(bytes) || bytes.length!==32) {
      throw Error("GOOGLE_CHALLENGE_SECURE_RANDOM_REQUIRED");
    }
    const nonce=bytes.toString("base64url");
    if (!OPAQUE_NONCE.test(nonce)) {
      throw Error("GOOGLE_CHALLENGE_RANDOM_ENCODING_INVALID");
    }
    const challengeRef=nonceRef(nonce), limitRef=limiterRef(who.uid);
    await db.runTransaction(async tx=>{
      const last=asRecord(await tx.get(limitRef));
      if (last && Number.isSafeInteger(last.lastIssuedAtMs) &&
          nowMs>=last.lastIssuedAtMs &&
          nowMs-last.lastIssuedAtMs<60000) {
        throw Error("GOOGLE_CHALLENGE_REQUESTER_RATE_LIMITED");
      }
      // Both writes happen atomically: no partially issued challenge.
      tx.create(challengeRef,{
        status:"issued",projectId:DEDA_PROD_PROJECT,
        productionOAuthAudience:productionConfig.productionOAuthAudience,
        requesterUid:who.uid,requesterAppId:who.appId,
        createdAtMs:nowMs,
        expiresAtMs:nowMs+MAX_CHALLENGE_AGE_MS,
      });
      tx.set(limitRef,{
        lastIssuedAtMs:nowMs, requesterUid:who.uid,
      });
    });
    return Object.freeze({
      nonce,createdAtMs:nowMs,
      productionOAuthAudience:productionConfig.productionOAuthAudience,
    });
  }

  async function read({nonce,firebaseIdToken,appCheckToken}={}) {
    if (typeof nonce!=="string" || !OPAQUE_NONCE.test(nonce)) return null;
    try {
      const who=await requester({firebaseIdToken,appCheckToken});
      const row=asRecord(await nonceRef(nonce).get());
      if (!matching(row,who,productionConfig.productionOAuthAudience,
          instant())) return null;
      // Source and status are derived from a genuine Admin Firestore read.
      return Object.freeze({
        source:"trusted_server_nonce_store",status:"issued",
        nonce,createdAtMs:row.createdAtMs,
        productionOAuthAudience:row.productionOAuthAudience,
      });
    } catch (_) {return null;}
  }

  async function consume({nonce,createdAtMs,productionOAuthAudience,
    firebaseIdToken,appCheckToken}={}) {
    if (typeof nonce!=="string" || !OPAQUE_NONCE.test(nonce) ||
        !Number.isSafeInteger(createdAtMs) ||
        productionOAuthAudience!==productionConfig.productionOAuthAudience) {
      return false;
    }
    try {
      const who=await requester({firebaseIdToken,appCheckToken});
      const nowMs=instant(), ref=nonceRef(nonce);
      return await db.runTransaction(async tx=>{
        const row=asRecord(await tx.get(ref));
        if (!matching(row,who,productionOAuthAudience,nowMs) ||
            row.createdAtMs!==createdAtMs) return false;
        // Atomic compare-and-mark-used: exactly one concurrent verifier wins.
        tx.update(ref,{status:"used",usedAtMs:nowMs});
        return true;
      })===true;
    } catch (_) {return false;}
  }

  return Object.freeze({issue,read,consume});
}

/**
 * INTERNAL, NOT EXPORTED AS A FIREBASE CALLABLE: binds one verified Firebase
 * requester + AppCheck app to the stored nonce AND to the Google OIDC review.
 * An arbitrary challenge object cannot be substituted by a client. The Google
 * subject is obtained only from a signed, audience/nonce-bound ID token.
 *
 * This NEVER signs in, returns the historical Firebase UID, creates an Auth
 * account, updates data or grants owner privileges. The returned classification
 * is INTERNAL ONLY and cannot serve as a login capability.
 */
async function reviewExistingGoogleWithStoredNonce({
  idToken, nonce, firebaseIdToken, appCheckToken,
  productionConfig, auth, db, appCheckVerifier,
  accountKey, originalId, clock=Date.now, 
  loadTrustedGoogleJwks=getOfficialGoogleJwks,
}={}) {
  if (typeof nonce!=="string" || !OPAQUE_NONCE.test(nonce)) {
    return fail("NO_TRUSTED_SERVER_GOOGLE_CHALLENGE");
  }
  try {
    const store=createTrustedGoogleNonceStore({
      auth, db, appCheckVerifier, productionConfig, clock,
    });
    const requester={firebaseIdToken,appCheckToken};
    // Challenge is loaded from the trusted database, NEVER request.data.
    const challenge=await store.read({...requester,nonce});
    if (!challenge) return fail("NO_TRUSTED_SERVER_GOOGLE_CHALLENGE");
    return await reviewExistingGoogleProviderReadOnly({
      idToken,productionConfig,challenge,nowMs:clock(),
      loadTrustedGoogleJwks,
      consumeOneTimeChallenge:entry=>store.consume({...entry,...requester}),
      auth,db,accountKey,originalId,
    });
  } catch (_) {
    return fail("TRUSTED_SERVER_GOOGLE_REVIEW_UNAVAILABLE");
  }
}


/**
 * ISOLATED CALLABLE ADAPTER, NOT EXPORTED FROM functions/index.js.
 * This is a proposal for a later owner-approved deployment, NOT a live
 * endpoint, account sign-in, custom token service, or UID migration.
 *
 * Enforce the Callable Firebase Auth / AppCheck principal AND independently
 * revalidate raw header tokens. Never accept those bearer tokens in data.
 * "begin" issues a server-bound challenge. "review" returns only a denial
 * or an internal review marker, NEVER an Auth UID or login capability.
 */
function createPrivateGoogleRecoveryReviewCallable({
  onCall, HttpsError, db, auth, appCheckVerifier,
  productionConfig, enabled=false, clock=Date.now,
  nonceFactory=randomBytes,
  loadTrustedGoogleJwks=getOfficialGoogleJwks,
}={}) {
  if (typeof onCall!=="function" || typeof HttpsError!=="function" ||
      typeof auth?.verifyIdToken!=="function" ||
      typeof appCheckVerifier?.verifyToken!=="function" ||
      typeof db?.collection!=="function" ||
      typeof db?.runTransaction!=="function" ||
      typeof db?.doc!=="function" ||
      typeof clock!=="function" ||
      typeof nonceFactory!=="function" ||
      typeof loadTrustedGoogleJwks!=="function") {
    throw Error("GOOGLE_PRIVATE_REVIEW_CALLABLE_CONFIGURATION_INVALID");
  }
  const deny=()=>{throw new HttpsError(
    "permission-denied","google-recovery-review-unavailable");
  };
  return onCall({enforceAppCheck:true},async request=>{
    // OFF is an absolute no-I/O default. There is NO production registration.
    if (enabled!==true || !validConfiguration(productionConfig)) deny();
    const d=request?.data, uid=request?.auth?.uid,
      appId=request?.app?.appId,
      h=request?.rawRequest?.headers;
    if (!object(d) || typeof uid!=="string" ||
        !/^[A-Za-z0-9:_-]{6,128}$/.test(uid) ||
        typeof appId!=="string" ||
        !/^[A-Za-z0-9:._-]{8,256}$/.test(appId)) deny();
    const authHeader=h?.authorization, appHeader=h?.["x-firebase-appcheck"];
    if (typeof authHeader!=="string" ||
        !/^Bearer [A-Za-z0-9._-]{16,8192}$/.test(authHeader) ||
        typeof appHeader!=="string" || appHeader.length<8 ||
        appHeader.length>8192) deny();
    const firebaseIdToken=authHeader.slice(7),appCheckToken=appHeader;
    const op=d.op;
    if (op==="begin") {
      if (Object.keys(d).length!==1) deny();
    } else if (op==="review") {
      if (Object.keys(d).length!==5 ||
          !["op","nonce","googleIdToken","accountKey","originalId"]
            .every(k=>Object.hasOwn(d,k)) ||
          typeof d.nonce!=="string" || !OPAQUE_NONCE.test(d.nonce) ||
          typeof d.googleIdToken!=="string" ||
          d.googleIdToken.length<100 ||
          d.googleIdToken.length>MAX_JWT_SIZE ||
          typeof d.accountKey!=="string" ||
          !/^(?:07\d{9}|9647\d{9})$/.test(d.accountKey) ||
          typeof d.originalId!=="string" ||
          !/^@DEDA-[A-Z0-9]{6}$/.test(d.originalId)) deny();
    } else {
      deny();
    }
    try {
      // Enforce the headers' verified identities equal the Callable context:
      // a different account's ID token or a foreign app may not be supplied.
      const [verifiedAuth,verifiedApp]=await Promise.all([
        auth.verifyIdToken(firebaseIdToken,true),
        appCheckVerifier.verifyToken(appCheckToken),
      ]);
      if (verifiedAuth?.uid!==uid || verifiedApp?.appId!==appId) deny();
      const store=createTrustedGoogleNonceStore({
        db,auth,appCheckVerifier,productionConfig,clock,nonceFactory,
      });
      if (op==="begin") {
        const challenge=await store.issue({firebaseIdToken,appCheckToken});
        return Object.freeze({
          status:"CHALLENGE_ISSUED_FOR_GOOGLE_REVIEW_ONLY",
          nonce:challenge.nonce,
          createdAtMs:challenge.createdAtMs,
          productionOAuthAudience:challenge.productionOAuthAudience,
          mayLogin:false,mayCreateUid:false,mayLinkProvider:false,
          mayWriteFirestore:false,
        });
      }
      // The current result is REVIEW ONLY. Even a valid Google provider
      // can disappear between review and a later Firebase Auth sign-in:
      // this cannot itself authorize a creating client login.
      const outcome=await reviewExistingGoogleWithStoredNonce({
        idToken:d.googleIdToken,nonce:d.nonce,
        firebaseIdToken,appCheckToken,productionConfig,
        appCheckVerifier,auth,db,clock,loadTrustedGoogleJwks,
        accountKey:d.accountKey,originalId:d.originalId,
      });
      if (outcome.status!=="EXISTING_GOOGLE_PROVIDER_CANONICAL_REVIEW_ONLY") {
        deny();
      }
      return Object.freeze({
        status:"EXISTING_GOOGLE_ACCOUNT_REVIEW_ONLY",
        mayLogin:false,mayCreateUid:false,mayLinkProvider:false,
        mayWriteFirestore:false,independentOldAccountOwnershipProven:false,
      });
    } catch (_) {
      // No UID, provider subject, PIN, Google token or lookup reason exposed.
      deny();
    }
  });
}

module.exports={
  inspectSignedToken,
  getOfficialGoogleJwks,
  verifyProspectiveGoogleForLegacyReview,
  reviewExistingGoogleProviderReadOnly,
  createTrustedGoogleNonceStore,
  reviewExistingGoogleWithStoredNonce,
  createPrivateGoogleRecoveryReviewCallable,
};
