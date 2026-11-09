"use strict";
const test=require("node:test");
const assert=require("node:assert/strict");
const {generateKeyPairSync,sign}=require("node:crypto");
const {inspectSignedToken,getOfficialGoogleJwks,
  verifyProspectiveGoogleForLegacyReview}=require(
  "../deda_100441_legacy_google_oidc_verifier_PRIVATE_NOT_EXPORTED.js"
);
const nowMs=1800000000000;
const nonce="syntheticServerNonceabcdefghijkl1234567";
const audience="123456789012-productionrecovery.apps.googleusercontent.com";
const config={projectId:"deda-25b88",source:"trusted_server_configuration",
  serverApproved:true,productionOAuthAudience:audience};
const challenge={source:"trusted_server_nonce_store",status:"issued",
  createdAtMs:nowMs-10000,productionOAuthAudience:audience,nonce};
const {privateKey,publicKey}=generateKeyPairSync("rsa",{modulusLength:2048});
const jwk=publicKey.export({format:"jwk"});
const jwks={keys:[{...jwk,kid:"synthetic_google_rsa_1",alg:"RS256",use:"sig"}]};
const b64=x=>Buffer.from(JSON.stringify(x),"utf8").toString("base64url");
const standardClaims={
  iss:"https://accounts.google.com",
  aud:audience,
  sub:"101010101010101010101",
  nonce,
  iat:Math.floor(nowMs/1000)-5,
  exp:Math.floor(nowMs/1000)+300,
};
function token(claims={},header={}) {
  const a=b64({alg:"RS256",kid:"synthetic_google_rsa_1",typ:"JWT",...header});
  const b=b64({...standardClaims,...claims});
  const c=sign("RSA-SHA256",Buffer.from(a+"."+b),privateKey)
    .toString("base64url");
  return a+"."+b+"."+c;
}
function inspect(overrides={}) {
  return inspectSignedToken({idToken:token(),
    productionConfig:config,challenge,jwks,nowMs,...overrides});
}
function denied(r) {
  assert.equal(r.mayLogin,false);
  assert.equal(r.mayCreateUid,false);
  assert.equal(r.mayLinkProvider,false);
  assert.equal(r.maySelectOwnerUid,false);
  assert.equal(r.mayWriteFirestore,false);
  assert.equal(r.independentOldAccountOwnershipProven,false);
  assert.equal(r.verifiedProspectiveGoogle??null,null);
}
test("signed Google OIDC ID token + correct server nonce passes CRYPTO ONLY",()=>{
  const r=inspect();
  assert.equal(r.status,
    "SIGNED_GOOGLE_IDENTITY_VALID_NONCE_NOT_YET_CONSUMED");
  assert.equal(r.googleClaims.subject,standardClaims.sub);
  assert.equal(r.mayLogin,false);
  assert.equal(r.mayLinkProvider,false);
  assert.equal(r.independentOldAccountOwnershipProven,false);
});
test("tampered signature rejected by crypto",()=>{
  const original=token();
  const parts=original.split(".");
  parts[1]=b64({...standardClaims,sub:"9999999999999999"});
  const r=inspect({idToken:parts.join(".")});
  assert.equal(r.status,"DENY");
  assert.equal(r.reason,"GOOGLE_SIGNATURE_VERIFICATION_FAILED");
  denied(r);
});
test("wrong key & unknown kid refused",()=>{
  for(const x of [{jwks:{keys:[]}},
    {idToken:token({}, {kid:"untrusted"})},
    {jwks:{keys:[{...jwk,kid:"synthetic_google_rsa_1",n:"YQ"}]}}]) {
    denied(inspect(x));
  }
});
test("symmetric algorithm, embedded jwk, untrusted header rejected",()=>{
  for(const h of [{alg:"HS256"},{alg:"none"},{jwk},
    {jku:"https://fake.invalid/keys"},{crit:["kid"]},{typ:"not-jwt"}]) {
    denied(inspect({idToken:token({},h)}));
  }
});
test("claims require precise Google issuer, audience, azp and subject",()=>{
  for(const c of [{iss:"https://attacker.invalid"},
    {aud:"123456789012-qa.apps.googleusercontent.com"},
    {aud:[audience]},{azp:"123456789012-qa.apps.googleusercontent.com"},
    {sub:"user@example.com"},{sub:""}]) {
    const r=inspect({idToken:token(c)});
    assert.equal(r.reason,"GOOGLE_TOKEN_CLAIMS_OR_NONCE_INVALID");
    denied(r);
  }
});
test("signed but wrong nonce cannot bypass server challenge",()=>{
  denied(inspect({idToken:token({nonce:"differentServerNonce12345678901234"})}));
});
test("expired, future, ancient, not-yet-valid tokens all rejected",()=>{
  const now=Math.floor(nowMs/1000);
  for(const c of [{exp:now-90},{iat:now+500},{iat:now-2000},
    {iat:now-3600,exp:now+100},{nbf:now+500}]) {
    denied(inspect({idToken:token(c)}));
  }
});
test("stale, replayed or wrong-OAuth server challenge blocked",()=>{
  for(const c of [
    {...challenge,createdAtMs:nowMs-11*60000},
    {...challenge,status:"used"},
    {...challenge,source:"client"},
    {...challenge,productionOAuthAudience:"different"},
    {...challenge,nonce:"short"},
  ]) denied(inspect({challenge:c}));
});
test("QA Firebase config and QA OAuth audience forbidden",()=>{
  for(const c of [
    {...config,projectId:"deda-qa-uid-lab-20261108"},
    {...config,serverApproved:false},
    {...config,source:"user"},
    {...config,productionOAuthAudience:"wrong-id"},
  ]) denied(inspect({productionConfig:c}));
});
test("invalid token lengths, malformed JWT or base64 refuse",()=>{
  for(const idToken of ["","a.b.c","x".repeat(10000),"x.y",null,
    "aaa.!bbb.ccc"]) denied(inspect({idToken}));
});
test("official JWKS helper pins Google HTTPS URL, rejects redirects",async()=>{
  let url,opts;
  const fakeFetch=async(a,b)=>{
    url=a;opts=b;
    return {status:200,headers:{get:()=>null},
      body:(async function*(){yield Buffer.from(JSON.stringify(jwks));})()};
  };
  const obj=await getOfficialGoogleJwks({fetchImpl:fakeFetch});
  assert.deepEqual(obj,jwks);
  assert.equal(url,"https://www.googleapis.com/oauth2/v3/certs");
  assert.equal(opts.redirect,"error");
  assert.equal(opts.method,"GET");
  await assert.rejects(
    ()=>getOfficialGoogleJwks({fetchImpl:async()=>({status:302})})
  );
});
test("after signature verification still BLOCK without one-time challenge consumer",async()=>{
  const r=await verifyProspectiveGoogleForLegacyReview({
    idToken:token(),productionConfig:config,challenge,nowMs,
    loadTrustedGoogleJwks:async()=>jwks,
  });
  denied(r);
  assert.equal(r.reason,"SERVER_NONCE_CONSUMER_NOT_CONFIGURED");
});
test("replayed nonce denied, even with valid signed token",async()=>{
  let used=false;
  const f=()=>verifyProspectiveGoogleForLegacyReview({
    idToken:token(),productionConfig:config,challenge,nowMs,
    loadTrustedGoogleJwks:async()=>jwks,
    consumeOneTimeChallenge:async()=>{if(used)return false; used=true;return true;},
  });
  const first=await f();
  assert.equal(first.status,"GOOGLE_ONLY_VERIFIED_FOR_SEPARATE_LEGACY_OWNER_REVIEW");
  assert.equal(first.verifiedProspectiveGoogle.verified,true);
  assert.equal(first.mayLinkProvider,false);
  assert.equal(first.mayLogin,false);
  assert.equal(first.independentOldAccountOwnershipProven,false);
  for(const field of ["sub","email","idToken","phone","oldUid","nonce"]) {
    assert.equal(field in first,false);
  }
  const second=await f();
  denied(second);
  assert.equal(second.reason,"NONCE_REPLAY_OR_CONSUMPTION_FAILED");
});
test("failed JWKS retrieval cannot authorize a verified Google identity",async()=>{
  const r=await verifyProspectiveGoogleForLegacyReview({
    idToken:token(),productionConfig:config,challenge,nowMs,
    loadTrustedGoogleJwks:async()=>{throw Error("offline");},
    consumeOneTimeChallenge:async()=>true,
  });
  denied(r);
});
test("fake signed JWT cannot use attacker-supplied public key",()=>{
  const {privateKey:otherPrivate,publicKey:otherPublic}=
    generateKeyPairSync("rsa",{modulusLength:2048});
  const a=b64({alg:"RS256",kid:"synthetic_google_rsa_1",typ:"JWT"});
  const b=b64(standardClaims);
  const c=sign("RSA-SHA256",Buffer.from(a+"."+b),otherPrivate).toString("base64url");
  const r=inspect({idToken:a+"."+b+"."+c});
  assert.equal(r.reason,"GOOGLE_SIGNATURE_VERIFICATION_FAILED");
  denied(r);
});
