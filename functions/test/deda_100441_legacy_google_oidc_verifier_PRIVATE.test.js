"use strict";
const test=require("node:test");
const assert=require("node:assert/strict");
const {generateKeyPairSync,sign}=require("node:crypto");
const {inspectSignedToken,getOfficialGoogleJwks,
  verifyProspectiveGoogleForLegacyReview,
  reviewExistingGoogleProviderReadOnly,
  createTrustedGoogleNonceStore,
  createPrivateGoogleRecoveryReviewCallable}=require(
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

const onlyAccount="07111111111", onlyId="@DEDA-ABC123";
const onlyUid="deda-legacy-owner-uid-google-synthetic";
const wrongUid="deda-foreign-owner-uid-synthetic";
function serverFixture({unlinked=false,disabled=false,customAdmin=false}={}) {
  const rows={
    ["deda_account_directory/"+onlyAccount]:{
      accountKey:onlyAccount,active:true,createdUid:onlyUid},
    ["deda_credentials/"+onlyAccount]:{
      accountKey:onlyAccount,active:true,createdUid:onlyUid,pin:"654321"},
    ["deda_share_ids/"+onlyId]:{
      publicId:onlyId,kind:"personal",active:true,ownerUid:onlyUid},
    ["users/"+onlyUid]:{accountKey:onlyAccount,sharePersonalId:onlyId},
    ["deda_social_profiles/"+onlyId]:{publicId:onlyId,ownerUid:onlyUid},
    ["deda_sessions/"+onlyUid]:{uid:onlyUid,accountKey:onlyAccount},
  };
  const calls={lookup:[],reads:[],consumed:0,writes:0};
  const auth={
    async getUserByProviderUid(provider,subject) {
      calls.lookup.push([provider,subject]);
      if(unlinked) throw Object.assign(Error("missing"),{code:"auth/user-not-found"});
      return {
        uid:onlyUid,disabled,customClaims:{admin:customAdmin},
        providerData:[{providerId:"google.com",uid:standardClaims.sub}],
      };
    },
  };
  const db={
    doc(path) {return {async get() {
      calls.reads.push(path);
      const row=rows[path];
      return {exists:row!==undefined,data:()=>row===undefined?undefined:{...row}};
    }};},
  };
  const payload=(extra={})=>({
    idToken:token(),productionConfig:config,challenge,nowMs,
    loadTrustedGoogleJwks:async()=>jwks,
    consumeOneTimeChallenge:async()=>{calls.consumed++;return true;},
    auth,db,accountKey:onlyAccount,originalId:onlyId,...extra,
  });
  return {rows,calls,auth,db,payload};
}
function noResultAuthority(result) {
  denied(result.status==="DENY"?result:{
    ...result,verifiedProspectiveGoogle:null,
  });
  assert.equal(result.mayLogin,false);
  assert.equal(result.mayCreateUid,false);
  assert.equal(result.mayLinkProvider,false);
  assert.equal(result.mayWriteFirestore,false);
  const printed=JSON.stringify(result);
  for(const value of [onlyAccount,onlyId,onlyUid,wrongUid,
      standardClaims.sub,"654321",token()]) {
    assert.equal(printed.includes(value),false);
  }
}
test("read-only Google provider review: verified subject and seven matching owner records",async()=>{
  const f=serverFixture();
  const result=await reviewExistingGoogleProviderReadOnly(f.payload());
  assert.equal(result.status,"EXISTING_GOOGLE_PROVIDER_CANONICAL_REVIEW_ONLY");
  assert.deepEqual(f.calls.lookup,[["google.com",standardClaims.sub]]);
  assert.equal(f.calls.reads.length,7);
  assert.equal(f.calls.consumed,1);
  assert.equal(f.calls.writes,0);
  noResultAuthority(result);
});
test("missing Google provider yields no Auth creation and no account reads",async()=>{
  const f=serverFixture({unlinked:true});
  const r=await reviewExistingGoogleProviderReadOnly(f.payload());
  assert.equal(r.status,"DENY");
  assert.equal(f.calls.lookup.length,1);
  assert.equal(f.calls.reads.length,0);
  assert.equal(f.calls.writes,0);
  noResultAuthority(r);
});
test("invalid Google signature/audience/nonce denied before any owner lookup",async()=>{
  for(const overrides of [
    {idToken:"not.a.signed.jwt"},
    {idToken:token({aud:"123456789012-untrusted.apps.googleusercontent.com"})},
    {idToken:token({nonce:"wrongServerNonceabcdefghijkl1234"})},
    {challenge:{...challenge,status:"used"}},
  ]) {
    const f=serverFixture();
    const result=await reviewExistingGoogleProviderReadOnly(f.payload(overrides));
    assert.equal(result.status,"DENY");
    assert.equal(f.calls.lookup.length,0);
    assert.equal(f.calls.reads.length,0);
    assert.equal(f.calls.writes,0);
    noResultAuthority(result);
  }
});
test("server nonce must be consumed exactly once; replay cannot read Google provider",async()=>{
  const f=serverFixture();
  let used=false;
  const payload=f.payload({consumeOneTimeChallenge:async()=>{
    f.calls.consumed++;
    if(used) return false;
    used=true;return true;
  }});
  const first=await reviewExistingGoogleProviderReadOnly(payload);
  const second=await reviewExistingGoogleProviderReadOnly(payload);
  assert.equal(first.status,"EXISTING_GOOGLE_PROVIDER_CANONICAL_REVIEW_ONLY");
  assert.equal(second.status,"DENY");
  assert.equal(second.reason,"NONCE_REPLAY_OR_CONSUMPTION_FAILED");
  assert.equal(f.calls.lookup.length,1);
  assert.equal(f.calls.reads.length,7);
  noResultAuthority(second);
});
test("canonical Google owner review rejects PIN registration, social, session or ID split",async()=>{
  for(const [path,field] of [
    ["deda_account_directory/"+onlyAccount,"createdUid"],
    ["deda_credentials/"+onlyAccount,"createdUid"],
    ["deda_share_ids/"+onlyId,"ownerUid"],
    ["deda_social_profiles/"+onlyId,"ownerUid"],
    ["deda_sessions/"+onlyUid,"uid"],
    ["users/"+onlyUid,"accountKey"],
  ]) {
    const f=serverFixture();
    f.rows[path][field]=wrongUid;
    const result=await reviewExistingGoogleProviderReadOnly(f.payload());
    assert.equal(result.status,"DENY",path+"."+field);
    assert.equal(result.reason,"GOOGLE_PROVIDER_OR_OWNER_NOT_VERIFIED");
    noResultAuthority(result);
  }
});
test("admin or disabled Auth user cannot become canonical Google owner",async()=>{
  for(const flag of ["disabled","customAdmin"]){
    const f=serverFixture({[flag]:true});
    noResultAuthority(await reviewExistingGoogleProviderReadOnly(f.payload()));
    assert.equal(f.calls.writes,0);
  }
  const f=serverFixture();
  f.rows["admins/"+onlyUid]={active:true};
  const result=await reviewExistingGoogleProviderReadOnly(f.payload());
  assert.equal(result.status,"DENY");
  noResultAuthority(result);
});
test("server-only Google lookup denies missing adapters and malformed account",async()=>{
  for(const overrides of [
    {auth:null},{db:null},{accountKey:"untrusted"},
    {originalId:"@DEDA-UNEXPECTEDLONG"},
  ]) {
    const f=serverFixture();
    const result=await reviewExistingGoogleProviderReadOnly(f.payload(overrides));
    assert.equal(result.status,"DENY");
    assert.equal(f.calls.lookup.length,0);
    assert.equal(f.calls.reads.length,0);
    noResultAuthority(result);
  }
});


// Server-only challenge persistence test. The in-memory transaction facade
// emulates one atomic Firestore transaction; emulator integration runs in a
// separate existing workflow with real Auth+Firestore local emulators.
function nonceDbFixture(){
  const rows=new Map(),calls={reads:0,writes:0};
  let lane=Promise.resolve();
  const snap=k=>({exists:rows.has(k),data:()=>rows.get(k)});
  const doc=k=>({key:k,get:async()=>{calls.reads++;return snap(k);}});
  const db={
    collection:name=>({doc:id=>doc(name+"/"+id)}),
    runTransaction:callback=>{
      const next=lane.then(async()=>{
        const writes=[];
        const tx={
          get:async ref=>{calls.reads++;return snap(ref.key);},
          create:(ref,data)=>writes.push(["create",ref.key,data]),
          set:(ref,data)=>writes.push(["set",ref.key,data]),
          update:(ref,data)=>writes.push(["update",ref.key,data]),
        };
        const result=await callback(tx);
        for(const [mode,key,data] of writes){
          if(mode==="create"&&rows.has(key))throw Error("already-exists");
          if(mode==="update"&&!rows.has(key))throw Error("missing");
          rows.set(key,mode==="update"?{...rows.get(key),...data}:{...data});
          calls.writes++;
        }
        return result;
      });
      lane=next.catch(()=>{});
      return next;
    },
  };
  return {db,calls,rows};
}
function nonceSetup(){
  const f=nonceDbFixture(),uid="synthetic-guest-device-uid",appId="1:123:android:testapp";
  const tokenId="synthetic-firebase-id-token-123456";
  const appToken="synthetic-appcheck-token-123456";
  let t=nowMs;
  const auth={
    async verifyIdToken(value,revoked) {
      assert.equal(revoked,true);
      if(value===tokenId)return {uid};
      if(value==="other-firebase-id-token-123")return {uid:"another-auth-uid-123"};
      throw Error("invalid-idtoken");
    },
    async getUser(value){return {uid:value,disabled:false};},
  };
  const appCheckVerifier={
    async verifyToken(v){
      if(v===appToken)return {appId};
      if(v==="other-appcheck-token-12345")return {appId:"1:123:android:foreign"};
      throw Error("invalid-appcheck");
    },
  };
  const store=createTrustedGoogleNonceStore({
    ...f,auth,appCheckVerifier,productionConfig:config,
    clock:()=>t,nonceFactory:()=>Buffer.alloc(32,0x48),
  });
  const identity={firebaseIdToken:tokenId,appCheckToken:appToken};
  return {...f,store,identity,getTime:()=>t,setTime:v=>{t=v;}};
}
test("trusted server issues digest-only nonce; reads for SAME verified Auth/AppCheck",async()=>{
  const f=nonceSetup(),issued=await f.store.issue(f.identity);
  assert(/^[A-Za-z0-9_-]{24,128}$/.test(issued.nonce));
  assert.equal(issued.createdAtMs,nowMs);
  assert.equal(f.calls.writes,2); // challenge + atomic per-UID limiter
  const all=JSON.stringify([...f.rows.values()]);
  assert.equal(all.includes(issued.nonce),false);
  assert.equal(all.includes(f.identity.firebaseIdToken),false);
  assert.equal(all.includes(f.identity.appCheckToken),false);
  assert.equal((await f.store.read({...f.identity,nonce:issued.nonce})).status,"issued");
  assert.equal(await f.store.read({
    ...f.identity,firebaseIdToken:"other-firebase-id-token-123",
    nonce:issued.nonce,
  }),null);
  assert.equal(await f.store.read({
    ...f.identity,appCheckToken:"other-appcheck-token-12345",
    nonce:issued.nonce,
  }),null);
});
test("nonce consumption is atomic; exactly one concurrent verification wins",async()=>{
  const f=nonceSetup(),issued=await f.store.issue(f.identity);
  const args={...f.identity,...issued};
  const [a,b,c]=await Promise.all([
    f.store.consume(args),f.store.consume(args),f.store.consume(args),
  ]);
  assert.deepEqual([a,b,c].filter(Boolean),[true]);
  assert.equal(await f.store.read({...f.identity,nonce:issued.nonce}),null);
  assert.equal(await f.store.consume(args),false);
  assert.equal(f.calls.writes,3); // limiter, challenge, one used-marker
});
test("nonce rate limit, expiry, bad AppCheck and foreign Firebase principal fail closed",async()=>{
  const f=nonceSetup(),issued=await f.store.issue(f.identity);
  await assert.rejects(()=>f.store.issue(f.identity),/RATE_LIMITED/);
  await assert.rejects(()=>f.store.issue({
    ...f.identity,appCheckToken:"wrong-app-check",
  }));
  await assert.rejects(()=>f.store.issue({
    ...f.identity,firebaseIdToken:"bad-token",
  }));
  assert.equal(await f.store.consume({...issued,...f.identity,
    productionOAuthAudience:"wrong-audience"}),false);
  assert.equal(await f.store.consume({...issued,...f.identity,
    firebaseIdToken:"other-firebase-id-token-123"}),false);
  f.setTime(nowMs+11*60000);
  assert.equal(await f.store.read({...f.identity,nonce:issued.nonce}),null);
  assert.equal(await f.store.consume({...issued,...f.identity}),false);
});
test("nonce store requires trusted production config and server verifiers",()=>{
  const f=nonceDbFixture();
  for(const options of [
    {productionConfig:{...config,projectId:"deda-qa-uid-lab-20261108"}},
    {productionConfig:{...config,serverApproved:false}},
    {auth:null},{appCheckVerifier:null},{db:null},
  ]) {
    const deps={db:f.db,auth:{verifyIdToken:async()=>{},getUser:async()=>{}},
      appCheckVerifier:{verifyToken:async()=>{}},productionConfig:config,...options};
    assert.throws(()=>createTrustedGoogleNonceStore(deps));
  }
});


// Pre-deployment Callable contract: no functions/index export, no production
// call, NO Auth account minting or transfers. Header tokens are independently
// verified AND must match trusted Callable Auth/AppCheck context.
class PrivateCallError extends Error {
  constructor(code,message){super(message);this.code=code;}
}
function privateReviewFixture({enabled=true}={}) {
  const f=nonceDbFixture(),u=onlyUid,appId="1:123:android:testapp";
  const idToken="fixture-firebase-id-token-123456789";
  const appToken="fixture-app-check-token-123456789";
  f.db.doc=path=>({get:async()=>{
    f.calls.reads++;
    const row=f.rows.get(path);
    return {exists:row!==undefined,data:()=>row?{...row}:undefined};
  }});
  const rows={
    ["deda_account_directory/"+onlyAccount]:{
      accountKey:onlyAccount,active:true,createdUid:u},
    ["deda_credentials/"+onlyAccount]:{
      accountKey:onlyAccount,active:true,createdUid:u,pin:"000111"},
    ["deda_share_ids/"+onlyId]:{
      publicId:onlyId,kind:"personal",active:true,ownerUid:u},
    ["users/"+u]:{accountKey:onlyAccount,sharePersonalId:onlyId},
    ["deda_social_profiles/"+onlyId]:{publicId:onlyId,ownerUid:u},
    ["deda_sessions/"+u]:{uid:u,accountKey:onlyAccount},
  };
  Object.entries(rows).forEach(([path,value])=>f.rows.set(path,value));
  const auth={
    async verifyIdToken(value,revoked){
      assert.equal(revoked,true);
      if(value!==idToken)throw Error("bad bearer");
      return {uid:u};
    },
    async getUser(uid){return {uid,disabled:false};},
    async getUserByProviderUid(p,sub){
      if(p!=="google.com"||sub!==standardClaims.sub)throw Error("unknown");
      return {uid:u,disabled:false,providerData:[
        {providerId:"google.com",uid:standardClaims.sub},
      ]};
    },
  };
  const appCheckVerifier={
    async verifyToken(value){
      if(value!==appToken)throw Error("bad App Check");
      return {appId};
    },
  };
  let opts;
  const fn=createPrivateGoogleRecoveryReviewCallable({
    onCall:(options,handler)=>{opts=options;return handler;},
    HttpsError:PrivateCallError,db:f.db,auth,appCheckVerifier,
    productionConfig:config,enabled,clock:()=>nowMs,
    nonceFactory:()=>Buffer.alloc(32,0x42),
    loadTrustedGoogleJwks:async()=>jwks,
  });
  const request=(data,overrides={})=>({
    data,auth:{uid:u},app:{appId},rawRequest:{headers:{
      authorization:"Bearer "+idToken,
      "x-firebase-appcheck":appToken,
    }},...overrides,
  });
  return {...f,fn,request,get options(){return opts;}};
}
async function privateDenied(f,request) {
  await assert.rejects(()=>f.fn(request),e=>
    e.code==="permission-denied" &&
    e.message==="google-recovery-review-unavailable");
}
test("private Google adapter defaults OFF and never touches Firestore",async()=>{
  const f=privateReviewFixture({enabled:false});
  assert.equal(f.options.enforceAppCheck,true);
  await privateDenied(f,f.request({op:"begin"}));
  assert.equal(f.calls.reads,0);
  assert.equal(f.calls.writes,0);
});
test("private Google adapter verifies both Callable and bearer identities",async()=>{
  const invalid=[
    {auth:{uid:"another-uid-caller"}},
    {app:{appId:"1:123:android:foreign"}},
    {rawRequest:{headers:{authorization:
      "Bearer fixture-firebase-id-token-123456789",
      "x-firebase-appcheck":"foreign-appcheck-token"}}},
    {rawRequest:{headers:{authorization:"Bearer foreign-token-abcdefghij",
      "x-firebase-appcheck":"fixture-app-check-token-123456789"}}},
    {rawRequest:{headers:{}}},
  ];
  for(const update of invalid){
    const f=privateReviewFixture();
    await privateDenied(f,f.request({op:"begin"},update));
    assert.equal(f.calls.writes,0);
    assert.equal(f.calls.reads,0);
  }
});
test("private Google adapter rejects unexpected user data and untrusted review",async()=>{
  for(const data of [
    null,{op:"begin",uid:onlyUid},{op:"begin",admin:true},
    {op:"review"},{op:"review",nonce},
    {op:"review",nonce,googleIdToken:token(),accountKey:onlyAccount,
      originalId:onlyId,debug:true},
    {op:"review",nonce:"X",googleIdToken:token(),accountKey:onlyAccount,
      originalId:onlyId},
    {op:"delete"},
  ]){
    const f=privateReviewFixture();
    await privateDenied(f,f.request(data));
    assert.equal(f.calls.writes,0);
  }
});
test("private Google Callable begin -> signed review returns ONLY no-login marker",async()=>{
  const f=privateReviewFixture(),first=await f.fn(f.request({op:"begin"}));
  assert.equal(first.status,"CHALLENGE_ISSUED_FOR_GOOGLE_REVIEW_ONLY");
  assert.equal(first.mayLogin,false);
  assert.equal(first.mayCreateUid,false);
  assert.equal(f.calls.writes,2);
  assert.equal(JSON.stringify([...f.rows.values()]).includes(first.nonce),
    false,"Raw nonce must not be persisted in Firestore");
  const data={op:"review",nonce:first.nonce,
    googleIdToken:token({nonce:first.nonce}),
    accountKey:onlyAccount,originalId:onlyId};
  const second=await f.fn(f.request(data));
  assert.equal(second.status,"EXISTING_GOOGLE_ACCOUNT_REVIEW_ONLY");
  assert.equal(second.mayLogin,false);
  assert.equal(second.mayCreateUid,false);
  assert.equal(second.mayLinkProvider,false);
  assert.equal(second.mayWriteFirestore,false);
  assert.equal(f.calls.writes,3);
  const output=JSON.stringify(second);
  for(const item of [onlyUid,standardClaims.sub,onlyAccount,onlyId,
    data.googleIdToken,first.nonce])assert.equal(output.includes(item),false);
  await privateDenied(f,f.request(data));
  assert.equal(f.calls.writes,3);
});
test("private Google adapter rejects unlinked provider without making an Auth user",async()=>{
  const f=privateReviewFixture();
  const first=await f.fn(f.request({op:"begin"}));
  // Correct signature but not an existing registered provider.
  const data={op:"review",nonce:first.nonce,
    googleIdToken:token({nonce:first.nonce,
      sub:"99999999999999999999"}),
    accountKey:onlyAccount,originalId:onlyId};
  await privateDenied(f,f.request(data));
  assert.equal(f.calls.writes,3); // nonce marked once
  assert.equal(f.rows.get("deda_account_directory/"+onlyAccount).createdUid,
    onlyUid);
});
test("private Google adapter rejects mismatched canonical UID and missing source",async()=>{
  const f=privateReviewFixture(),started=await f.fn(f.request({op:"begin"}));
  f.rows.get("deda_social_profiles/"+onlyId).ownerUid=wrongUid;
  await privateDenied(f,f.request({
    op:"review",nonce:started.nonce,
    googleIdToken:token({nonce:started.nonce}),
    accountKey:onlyAccount,originalId:onlyId,
  }));
  assert.equal(f.calls.writes,3);
});
