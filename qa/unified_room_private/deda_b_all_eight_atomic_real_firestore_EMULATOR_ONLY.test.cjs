"use strict";
/*
 * DEDA / point 01: actual Firebase Auth + Firestore EMULATORS ONLY.
 * The independent owner/review documents in this test are SYNTHETIC QA,
 * not a real-world ownership attestation or permission to deploy.
 * Reuses the existing private B all-eight issuer and existing Rules
 * candidate. No real Firebase endpoints or Google Play.
 */
const {test}=require("node:test");
const assert=require("node:assert/strict");
const fs=require("node:fs");
const {initializeApp,deleteApp}=require("firebase-admin/app");
const {getAuth}=require("firebase-admin/auth");
const {getFirestore,Timestamp}=require("firebase-admin/firestore");
const {initializeTestEnvironment}=require("@firebase/rules-unit-testing");
const {makeRoomGrantIssuer}=require("../../functions/deda_unified_room_grant_issuer_private_v1.js");
const {createRoomReadonlyGuard,DOMAINS}=require("../../functions/deda_unified_room_readonly_guard_v1.js");

const project="demo-deda-room-live-additive-compare";
const B="QA_CREATION_UID_B",A="QA_ORIGINAL_UID_A",C="QA_SOCIAL_UID_C";
const account="9647712345678",originalId="@DEDA-ABC123";
const canonicalAccountId="DEDA_QA_ATOMIC_B_CID_12345";
const evidenceDigest="e".repeat(64);
const domains=Object.keys(DOMAINS);
const payloads={
 profile:{displayName:"DEDA QA",level:13},
 original_id:{publicId:originalId},
 premium_id:{displayId:"@DEDA-1234",color:"royal"},
 friends:{friendCount:2},league:{weeklyPoints:50},gifts:{giftCount:3},
 wallet:{balanceDisplay:80,giftWalletBalance:20},
 places:{publishedPlaceCount:4}
};
const grantPath=d=>"deda_unified_room_read_grants/"+B+"/domains/"+d;
const viewPath=d=>"deda_unified_room_private_views/"+B+"/domains/"+d;
const auditPath=d=>"deda_unified_room_grant_audit/"+B+"/domains/"+d;
const exists=async(db,path)=>(await db.doc(path).get()).exists;
async function can(fn){try{await fn();return true;}catch(_){return false;}}
function assertOnlyEmulators(){
 assert.equal(process.env.GCLOUD_PROJECT,project);
 assert.equal(process.env.FIRESTORE_EMULATOR_HOST,"127.0.0.1:8088");
 assert.equal(process.env.FIREBASE_AUTH_EMULATOR_HOST,"127.0.0.1:9099");
 assert.ok(fs.existsSync("/tmp/deda-room-candidate-rules.rules"));
 const index=fs.readFileSync("functions/index.js","utf8");
 assert.equal(index.includes('require("./deda_unified_room_grant_issuer_private_v1.js")'),false);
 assert.match(index,/enabled:false/);
}
async function seed(db,now){
 const records=[
 ["deda_unified_room_owner_authorizations/"+B,{
   uid:B,readerUid:B,status:"independently_verified",
   independentEvidenceSource:"verified_offline_authority",
   evidenceDigest,reviewers:["QA_REVIEWER_ONE","QA_REVIEWER_TWO"],
   accountKey:account,originalId,canonicalAccountId,
   historicalUids:[A,B,C],approvedAtMs:now-2000,expiresAtMs:now+3600000
 }],
 ["deda_unified_room_owner_directory/"+B,{
   uid:B,accountKey:account,originalId,canonicalAccountId,historicalUids:[A,B,C]
 }],
 ["deda_unified_room_sessions/"+B,{
   uid:B,accountKey:account,canonicalAccountId,active:true,
   revision:7,sessionNonce:"QA_CURRENT_B_CANONICAL_SESSION_07"
 }],
 ["deda_account_directory/"+account,{accountKey:account,active:true,createdUid:B}],
 ["deda_credentials/"+account,{accountKey:account,active:true,createdUid:B}],
 ["deda_share_ids/"+originalId,{publicId:originalId,kind:"personal",active:true,
   ownerUid:A,accountKey:account}],
 ["deda_social_profiles/"+originalId,{publicId:originalId,ownerUid:C}],
 ["users/"+A,{accountKey:account,sharePersonalId:originalId,privatePin:"DO_NOT_PROJECT"}],
 ["users/"+B,{accountKey:account,level:13,privateToken:"DO_NOT_PROJECT"}],
 ["users/"+C,{accountKey:account,privatePhone:"DO_NOT_PROJECT"}],
 ];
 await Promise.all(records.map(([path,data])=>db.doc(path).set(data)));
 return records;
}
function makeIssuer(db,auth,now,{missingDomain=null}={}){
 const independentReview=async({uid,domain})=>({
   status:domain===missingDomain?"PENDING":"INDEPENDENTLY_ATTESTED",
   independentEvidenceSource:"verified_offline_authority",
   // A deliberately synthetic server-only TEST adapter. No user documents.
   readerUid:uid,domain,accountKey:account,originalId,canonicalAccountId,
   evidenceDigest,uidA:A,uidB:B,uidC:C,
   reviewers:["QA_REVIEWER_ONE","QA_REVIEWER_TWO"],verifiedAtMs:now-500
 });
 const projectDomain=async({domain})=>payloads[domain];
 return makeRoomGrantIssuer({db,auth,independentReview,projectDomain,
   toTimestamp:ms=>Timestamp.fromMillis(ms),clock:()=>now,enabled:true});
}
async function signIn(){
 const reply=await fetch("http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=qa-only",{
   method:"POST",headers:{"content-type":"application/json"},
   body:JSON.stringify({email:"qa-b-atomic@example.test",
     password:"QA_EMULATOR_ONLY_STRONG_TEST_PASSWORD_1!",returnSecureToken:true})
 });
 const data=await reply.json();
 assert.equal(reply.ok,true,JSON.stringify(data));
 return data.idToken;
}
test("POINT01: B eight-domain real Firestore atomic issue/denials on isolated emulators",async()=>{
 assertOnlyEmulators();
 const app=initializeApp({projectId:project},"DEDA_B_ATOMIC_EMULATOR_QA");
 const db=getFirestore(app),auth=getAuth(app);
 const rules=fs.readFileSync("/tmp/deda-room-candidate-rules.rules","utf8");
 const env=await initializeTestEnvironment({projectId:project,firestore:{
   rules,host:"127.0.0.1",port:8088
 }});
 try{
   await env.clearFirestore();
   const beforeUser=await auth.getUser(B).catch(()=>null);
   if(!beforeUser)await auth.createUser({uid:B,email:"qa-b-atomic@example.test",
     password:"QA_EMULATOR_ONLY_STRONG_TEST_PASSWORD_1!",emailVerified:true});
   const token=await signIn();
   assert.equal((await auth.verifyIdToken(token,true)).uid,B);
   const authCount=(await auth.listUsers()).users.length;
   const now=Date.now();
   const seeded=await seed(db,now);
   const original=await Promise.all(seeded.map(([p])=>db.doc(p).get().then(d=>d.data())));
   const client=env.authenticatedContext(B,{firebase:{sign_in_provider:"password"}}).firestore();
   const other=env.authenticatedContext(C,{firebase:{sign_in_provider:"password"}}).firestore();
   for(const domain of domains){
     assert.equal(await can(()=>client.doc(viewPath(domain)).get()),false,
       "no pre-authorization access: "+domain);
   }
   const issuer=makeIssuer(db,auth,now);
   const issued=await issuer.issueAllForB({uid:B});
   assert.equal(issued.status,"ISSUED_ALL_EIGHT_READ_ONLY",issued.reason);
   assert.equal(issued.domains.length,8);
   for(const domain of domains){
     assert.equal(await exists(db,grantPath(domain)),true);
     assert.equal(await exists(db,viewPath(domain)),true);
     assert.equal(await exists(db,auditPath(domain)),true);
     const source=domain==="friends"?C:
       ["profile","league"].includes(domain)?B:A;
     assert.equal((await db.doc(grantPath(domain)).get()).data().sourceUid,source);
     assert.equal(await can(()=>client.doc(viewPath(domain)).get()),true,
       "B should read only its reviewed scope: "+domain);
     assert.equal(await can(()=>other.doc(viewPath(domain)).get()),false,
       "C cannot use B grant: "+domain);
     assert.equal(await can(()=>client.doc(grantPath(domain)).get()),false,
       "B cannot read private grant: "+domain);
     assert.equal(await can(()=>client.doc(viewPath(domain)).update(
       {sourceUid:C})),false,"client write forbidden: "+domain);
     const reader=createRoomReadonlyGuard({db,auth,clock:()=>now,enabled:true});
     const result=await reader({auth:{uid:B,token:{firebase:{sign_in_provider:"password"}}},
       app:{appId:"QA_ONLY_FIREBASE_APP_ID"},input:{domain}});
     assert.equal(result.status,"VERIFIED_READ_ONLY",domain+":"+result.reason);
     assert.deepEqual(result.payload,payloads[domain]);
   }
   const after=await Promise.all(seeded.map(([p])=>db.doc(p).get().then(d=>d.data())));
   assert.deepEqual(after,original,"historical A/B/C documents unchanged");
   assert.equal((await auth.listUsers()).users.length,authCount);
   const home=["profile","original_id","premium_id","friends","league"];
   const batchReader=createRoomReadonlyGuard({db,auth,clock:()=>now,enabled:true});
   const homeBatch=await batchReader({
      auth:{uid:B,token:{firebase:{sign_in_provider:"password"}}},
      app:{appId:"QA_ONLY_FIREBASE_APP_ID"},input:{domains:home}
   });
   assert.equal(homeBatch.status,"SCOPED_HOME_READ_ONLY");
   assert.deepEqual(Object.keys(homeBatch.results),home);
   for(const domain of home){
      assert.equal(homeBatch.results[domain].status,"VERIFIED_READ_ONLY",domain);
      assert.deepEqual(homeBatch.results[domain].payload,payloads[domain]);
   }
   console.log("PASS_ONE_CALL_SAME_SNAPSHOT_FIVE_HOME_SCOPES_B");
   assert.equal((await issuer.issueAllForB({uid:B})).status,"HOLD");
   console.log("PASS_B_ALL_EIGHT_FIRESTORE_EMULATOR_ATOMIC_VIEWS_AND_RULES");

   // Missing just ONE historic-domain attestation produces no partial grant.
   for(const fault of ["one-domain","changed-social","previous-grant","revoked","session-rotated"]){
     await env.clearFirestore();
     await seed(db,Date.now());
     const base=Date.now();
     if(fault==="changed-social"){
       await db.doc("deda_social_profiles/"+originalId).update({ownerUid:A});
     }
     if(fault==="previous-grant"){
       await db.doc(grantPath("friends")).set({status:"active"});
     }
     if(fault==="revoked"){
       await db.doc("deda_unified_room_revocations/"+B+"/domains/places")
         .set({status:"revoked"});
     }
     if(fault==="session-rotated"){
       await db.doc("deda_unified_room_sessions/"+B).update({active:false});
     }
     const fresh=makeIssuer(db,auth,base,{
       missingDomain:fault==="one-domain"?"friends":null
     });
     const denied=await fresh.issueAllForB({uid:B});
     assert.equal(denied.status,"HOLD",fault);
     for(const d of domains){
       assert.equal(await exists(db,viewPath(d)),false,fault+":"+d);
       assert.equal(await exists(db,auditPath(d)),false,fault+":"+d);
       if(fault!=="previous-grant"||d!=="friends")
         assert.equal(await exists(db,grantPath(d)),false,fault+":"+d);
     }
   }
   console.log("PASS_ONE_SCOPE_FAILURE_ZERO_PARTIAL_WRITES_ON_FIRESTORE_EMULATOR");

   // Source B is allowed to stay a historic, unlinked Auth principal.
   // A separate EXISTING authenticated reader can consume independently
   // authorized B/A/C views without ever signing into historical B.
   const current="QA_EXISTING_SIGNED_READER_R1";
   const existsCurrent=await auth.getUser(current).catch(()=>null);
   if(!existsCurrent)await auth.createUser({
     uid:current,email:"qa-reader-r@example.test",
     password:"QA_EMULATOR_ONLY_STRONG_TEST_PASSWORD_2!",emailVerified:true});
   await env.clearFirestore();
   const newNow=Date.now();
   await seed(db,newNow);
   const legacyDocs=[
     "deda_account_directory/"+account,
     "deda_credentials/"+account,
     "deda_share_ids/"+originalId,
     "deda_social_profiles/"+originalId,
     "users/"+A,"users/"+B,"users/"+C
   ];
   const legacyBefore=await Promise.all(legacyDocs.map(p=>db.doc(p).get().then(s=>s.data())));
   for(const group of ["deda_unified_room_owner_authorizations",
      "deda_unified_room_owner_directory","deda_unified_room_sessions"]){
     const old=(await db.doc(group+"/"+B).get()).data();
     const row={...old,uid:current};
     if("readerUid" in row)row.readerUid=current;
     await db.doc(group+"/"+current).set(row);
   }
   const currentIssuer=makeIssuer(db,auth,newNow);
   const done=await currentIssuer.issueAllForCurrentReader({uid:current});
   assert.equal(done.status,"ISSUED_ALL_EIGHT_READ_ONLY",done.reason);
   const reader=createRoomReadonlyGuard({db,auth,clock:()=>newNow,enabled:true});
   const currentClient=env.authenticatedContext(current,{
     firebase:{sign_in_provider:"password"}}).firestore();
   const oldClient=env.authenticatedContext(B,{
     firebase:{sign_in_provider:"password"}}).firestore();
   for(const domain of domains){
     assert.equal(await can(()=>currentClient.doc(
       "deda_unified_room_private_views/"+current+"/domains/"+domain).get()),true);
     assert.equal(await can(()=>oldClient.doc(
       "deda_unified_room_private_views/"+current+"/domains/"+domain).get()),false);
     const grant=(await db.doc("deda_unified_room_read_grants/"+current+
       "/domains/"+domain).get()).data();
     const expected=domain==="friends"?C:
       ["profile","league"].includes(domain)?B:A;
     assert.equal(grant.sourceUid,expected);
     const response=await reader({
       auth:{uid:current,token:{firebase:{sign_in_provider:"password"}}},
       app:{appId:"QA_ONLY_FIREBASE_APP_ID"},input:{domain}});
     assert.equal(response.status,"VERIFIED_READ_ONLY",domain+":"+response.reason);
   }
   const legacyAfter=await Promise.all(legacyDocs.map(p=>db.doc(p).get().then(s=>s.data())));
   assert.deepEqual(legacyAfter,legacyBefore,"historical source A/B/C must not change");
   assert.equal((await currentIssuer.issueAllForB({uid:current})).status,"HOLD");
   console.log("PASS_EXISTING_READER_CAN_ACCESS_B_A_C_WITHOUT_B_AUTH_SIGN_IN");
 }finally{
   await env.cleanup();
   await deleteApp(app);
 }
});
