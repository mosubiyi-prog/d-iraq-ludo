"use strict";
const test=require("node:test");
const assert=require("node:assert/strict");
const {generateKeyPairSync,sign}=require("node:crypto");
const {
  DedaExistingGoogleOwnerHold,verifiedGoogleSubject,
  issueExistingUidOnly,createPrivateExistingGoogleCallable,
}=require("../deda_google_existing_uid_token_exchange_PRIVATE_NOT_EXPORTED.js");

const {publicKey,privateKey}=generateKeyPairSync("rsa",{modulusLength:2048});
const pub=publicKey.export({format:"jwk"});
const kid="test-google-key";
const jwks={keys:[{kty:"RSA",kid,alg:"RS256",use:"sig",n:pub.n,e:pub.e}]};
const audience="1234567-dedaexisting.apps.googleusercontent.com";
const uid="immutable-original-firebase-uid";
const account="9647712345678";
const original="@DEDA-ABC123";
const subject="12345678901234567890";
const nowMs=Date.UTC(2026,10,14,10,0,0);
const nowSeconds=Math.floor(nowMs/1000);
function signed(payload={}) {
  const header=Buffer.from(JSON.stringify({typ:"JWT",alg:"RS256",kid}))
      .toString("base64url");
  const claims=Buffer.from(JSON.stringify({
    iss:"https://accounts.google.com",aud:audience,sub:subject,
    email_verified:true,iat:nowSeconds,exp:nowSeconds+3500,...payload,
  })).toString("base64url");
  const message=header+"."+claims;
  const signature=sign("RSA-SHA256",Buffer.from(message),privateKey).toString("base64url");
  return message+"."+signature;
}
function docs() {return {
  ["users/"+uid]:{accountKey:account,sharePersonalId:original,accountType:"user"},
  ["deda_account_directory/"+account]:{accountKey:account,createdUid:uid,active:true},
  ["deda_credentials/"+account]:{accountKey:account,createdUid:uid,active:true,
    pin:"not-to-be-exposed"},
  ["deda_share_ids/"+original]:{publicId:original,ownerUid:uid,kind:"personal",active:true},
  ["deda_sessions/"+uid]:{uid,accountKey:account,installId:"original-install"},
  ["deda_social_profiles/"+original]:{publicId:original,ownerUid:uid},
};}
function harness() {
  const store=new Map(Object.entries(docs()));
  const writes=[],issued=[];
  let authCalls=0,missingProvider=false,changedProviderAfterRead=false;
  let user={uid,disabled:false,metadata:{creationTime:"2026-01-01"},
    customClaims:{},providerData:[{providerId:"google.com",uid:subject,email:"owner@gmail.com"}]};
  function row(path) {
    const has=store.has(path);
    return {exists:has,data:()=>has?store.get(path):undefined};
  }
  const db={
    doc(path){return {path,async get(){return row(path)}};},
    async runTransaction(fn){
      const changes=[];
      const tx={get:async ref=>row(ref.path),set(ref,value){changes.push([ref.path,value])}};
      const result=await fn(tx);
      for(const [path,value] of changes){store.set(path,value);writes.push(path);}
      return result;
    },
  };
  const auth={
    async getUserByProviderUid(provider,sub) {
      authCalls++;
      if(provider!=="google.com" || sub!==subject || missingProvider)
        throw Error("not found");
      return user;
    },
    async getUser(checkUid) {
      authCalls++;
      if(checkUid!==uid)throw Error("not found");
      if(changedProviderAfterRead) return {...user,providerData:[]};
      return user;
    },
    async createCustomToken(checkUid,claims) {
      assert.equal(checkUid,uid);
      assert.equal(claims.dedaExistingGoogleUid,true);
      issued.push(checkUid);
      return "signed-custom-token-for-original-uid";
    },
  };
  return {db,auth,store,writes,issued,
    setMissingProvider(v){missingProvider=v;},
    setUser(v){user=v;},
    setChangedProviderAfterRead(v){changedProviderAfterRead=v;},
    authCalls(){return authCalls;}};
}
const login=(h,token=signed(),overrides={})=>issueExistingUidOnly({
  idToken:token,audience,jwks,auth:h.auth,db:h.db,nowMs,...overrides,
});
async function rejects(promise){await assert.rejects(promise,DedaExistingGoogleOwnerHold);}

test("valid signed Google + existing linked provider yields EXACT original UID token, no owner writes",async()=>{
  const h=harness();const result=await login(h);
  assert.deepEqual(result,{originalUid:uid,customToken:"signed-custom-token-for-original-uid",
    accountKey:account,originalId:original});
  assert.deepEqual(h.issued,[uid]);
  assert.deepEqual(h.writes.filter(x=>!x.startsWith("deda_google_existing_uid_login_limits/")),[]);
  assert.equal(h.store.get("deda_credentials/"+account).pin,"not-to-be-exposed");
});
test("cryptographic Google proof rejects changed signature, audience, issuer, stale & new-account token",()=>{
  const valid=signed();const [h,p,s]=valid.split(".");
  const modifiedPayload=Buffer.from(JSON.stringify({aud:audience,sub:subject,
    iat:nowSeconds,exp:nowSeconds+3500,iss:"https://accounts.google.com",
    email_verified:false})).toString("base64url");
  for(const token of [h+"."+modifiedPayload+"."+s,"a.b.c",signed({aud:"foreign"}),
    signed({iss:"https://attacker.invalid"}),signed({email_verified:false}),
    signed({sub:"not-digits"}),signed({iat:nowSeconds-3700}),
    signed({exp:nowSeconds-10}),signed({nbf:nowSeconds+100})]){
    assert.throws(()=>verifiedGoogleSubject({idToken:token,audience,jwks,nowMs}),
      DedaExistingGoogleOwnerHold);
  }
  assert.equal(verifiedGoogleSubject({idToken:valid,audience,jwks,nowMs}).subject,subject);
});
test("new/unlinked Google subject cannot mint any DEDA UID",async()=>{
  const h=harness();h.setMissingProvider(true);
  await rejects(login(h));assert.deepEqual(h.issued,[]);
  assert.deepEqual(h.writes,[]);
});
test("historical UID cannot be guessed via client-supplied phone, account or email",async()=>{
  const h=harness();
  await rejects(login(h,signed({sub:"99999999999999999"})));
  assert.deepEqual(h.issued,[]);
});
test("all mismatched original route, credential, profile, session and admin fail closed",async()=>{
  const changes=[
    ["deda_account_directory/"+account,"createdUid","split-uid"],
    ["deda_credentials/"+account,"createdUid","split-uid"],
    ["deda_share_ids/"+original,"ownerUid","split-uid"],
    ["deda_sessions/"+uid,"uid","split-uid"],
    ["deda_social_profiles/"+original,"ownerUid","split-uid"],
    ["users/"+uid,"accountKey","9647800000000"],
    ["users/"+uid,"sharePersonalId","@DEDA-FOREIGN"],
    ["deda_account_directory/"+account,"active",false],
    ["deda_credentials/"+account,"active",false],
  ];
  for(const [path,key,value] of changes){
    const h=harness();h.store.set(path,{...h.store.get(path),[key]:value});
    await rejects(login(h));
    assert.deepEqual(h.issued,[]);
    assert.deepEqual(h.writes,[]);
  }
  const admin=harness();admin.store.set("admins/"+uid,{role:"manager"});
  await rejects(login(admin));assert.deepEqual(admin.issued,[]);
  const disabled=harness();disabled.setUser({uid,disabled:true,
    providerData:[{providerId:"google.com",uid:subject}]});
  await rejects(login(disabled));assert.deepEqual(disabled.issued,[]);
});
test("missing mandatory original records always HOLD, never create a new profile or UID",async()=>{
  for(const path of ["users/"+uid,"deda_account_directory/"+account,
    "deda_credentials/"+account,"deda_share_ids/"+original,
    "deda_sessions/"+uid]){
    const h=harness();h.store.delete(path);
    await rejects(login(h));assert.deepEqual(h.issued,[]);
    assert.deepEqual(h.writes,[]);
  }
});
test("provider revoked between readback and issue cannot receive a token",async()=>{
  const h=harness();h.setChangedProviderAfterRead(true);
  await rejects(login(h));assert.deepEqual(h.issued,[]);
});
test("server persistent per-Google-provider rate limit blocks sixth attempt",async()=>{
  const h=harness();for(let i=0;i<5;i++)assert.equal((await login(h)).originalUid,uid);
  await rejects(login(h));
  assert.equal(h.issued.length,5);
  assert.equal(h.writes.length,5);
  assert.ok(h.writes.every(p=>p.startsWith("deda_google_existing_uid_login_limits/")));
});
test("missing rate limiter / unavailable database refuses token instead of bypass",async()=>{
  const h=harness();
  await assert.rejects(login(h,signed(),{reserveAttempt:async()=>{
    throw Error("network-down");
  }}));
  assert.deepEqual(h.issued,[]);
});
test("Cloud Function requires AppCheck and cannot overwrite a signed-in user",async()=>{
  const h=harness();
  class HttpsError extends Error {constructor(code,message){super(message);this.code=code;}}
  let options;
  const handler=createPrivateExistingGoogleCallable({
    onCall:(opts,fn)=>{options=opts;return fn;},HttpsError,
    auth:h.auth,db:h.db,productionAudience:audience,
    getJwks:async()=>jwks,now:()=>nowMs,
  });
  assert.equal(options.enforceAppCheck,true);
  await assert.rejects(handler({data:{googleIdToken:signed()}}),HttpsError);
  await assert.rejects(handler({app:{appId:"trusted-app"},
    auth:{uid:"existing-admin",token:{firebase:{sign_in_provider:"password"}}},
    data:{googleIdToken:signed()}}),HttpsError);
  await assert.rejects(handler({app:{appId:"trusted-app"},
    data:{googleIdToken:signed(),requestedUid:"victim"}}),HttpsError);
  assert.deepEqual(h.issued,[]);
  const success=await handler({app:{appId:"trusted-app"},
    data:{googleIdToken:signed()}});
  assert.equal(success.originalUid,uid);
  assert.equal(success.customToken,"signed-custom-token-for-original-uid");
  assert.equal(Object.hasOwn(success,"accountKey"),false);
  assert.equal(Object.hasOwn(success,"originalId"),false);
});

test("production deployment binding rejects wrong project, unapproved setup and QA OAuth",()=>{
  const {prepareExistingGoogleUidCallable}=require(
    "../deda_google_existing_uid_callable_wiring_PRIVATE_NOT_EXPORTED.js");
  const h=harness();
  class HttpsError extends Error {constructor(code,message){super(message);this.code=code;}}
  const opts={onCall:(p,f)=>f,HttpsError,auth:h.auth,db:h.db,
    getJwks:async()=>jwks,now:()=>nowMs};
  for(const extra of [
    {projectId:"deda-qa-uid-lab-20261108",ownerApproved:true,productionAudience:audience},
    {projectId:"deda-25b88",ownerApproved:false,productionAudience:audience},
    {projectId:"deda-25b88",ownerApproved:true,productionAudience:"qa.apps.googleusercontent.com"},
  ]) assert.throws(()=>prepareExistingGoogleUidCallable({...opts,...extra}),
    /deda-google-existing-uid-backend-not-approved/);
  const handler=prepareExistingGoogleUidCallable({...opts,
    projectId:"deda-25b88",ownerApproved:true,productionAudience:audience});
  assert.equal(typeof handler,"function");
});
