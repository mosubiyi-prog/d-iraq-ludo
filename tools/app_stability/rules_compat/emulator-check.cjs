'use strict';
// Actual production POLICY text, local demo DATA only. All console/SDK details
// are redirected to the private runner directory; public report has safe codes.
const fs=require('node:fs');const path=require('node:path');const assert=require('node:assert/strict');
const {createHash}=require('node:crypto');
const {initializeTestEnvironment}=require('@firebase/rules-unit-testing');
const {doc,setDoc,getDocFromServer,deleteDoc,collection,getDocs,updateDoc,serverTimestamp,Timestamp,runTransaction,arrayUnion}=require('firebase/firestore');
const project='demo-deda-live-progress-compat';
if(!/^(127\.0\.0\.1|localhost):[0-9]+$/.test(process.env.FIRESTORE_EMULATOR_HOST||'') ||
   process.env.GCLOUD_PROJECT!==project || process.env.GOOGLE_APPLICATION_CREDENTIALS ||
   process.env.DEDA_RULES_PRIMARY_SA || process.env.DEDA_RULES_SECONDARY_SA)throw Error('local-demo-without-production-credentials-required');
const privateDir=process.env.DEDA_RULES_PRIVATE,publicDir=process.env.DEDA_RULES_PUBLIC;
if(!privateDir||!publicDir)throw Error('private-and-public-directories-required');
const reportPath=path.join(publicDir,'rules-compat-report.json');
const report=JSON.parse(fs.readFileSync(reportPath,'utf8'));
const sha=text=>createHash('sha256').update(text).digest('hex');
const sources={before:fs.readFileSync(path.join(privateDir,'original.private.rules'),'utf8'),
  after:fs.readFileSync(path.join(privateDir,'candidate.private.rules'),'utf8')};
assert.equal(sha(sources.before),report.originalSHA256);assert.equal(sha(sources.after),report.candidateSHA256);
const A='07700000000',B='07700000001';
const actors={owner:'compat-owner-a',other:'compat-owner-b',manager:'compat-manager',anonymous:null};
const capture='compat_original_capture_00001';
const archive=`deda_progress_evidence/${A}/captures/${capture}`;
const receipt=`deda_progress_receipts/${A}/events/compat_receipt_fixture_00001`;
const migration=`deda_progress_migrations/${A}`;
const progress=`deda_verified_progress/${A}`;
const scopes={evidence:archive,receipt,migration,progress};
const records={taskPoints:' {"awards":{"spent":-5000}} ',socialCoinsAndXp:'{"coins":17,"xp":3020}',earnedDiamonds:'{"balance":9}'};
const payload=(id,uid=actors.owner,install='compat-install-a')=>({format:1,kind:'legacy-local-evidence',
  accountKey:A,sourceUid:uid,installId:install,captureId:id,records,createdAt:serverTimestamp()});
let env;
const cases=[];const observations={before:{},after:{}};
function database(actor){const uid=actors[actor];return uid?env.authenticatedContext(uid,
  {email:`${actor}@deda-qa.invalid`,email_verified:true,
    firebase:{sign_in_provider:actor==='manager'?'password':'anonymous'}}).firestore():env.unauthenticatedContext().firestore();}
async function permitted(action){
  try{await action();return true;}catch(error){
    if(['permission-denied','unauthenticated'].includes(error.code))return false;
    throw error;
  }
}
async function check(name,action){
  try{await action();cases.push({name,passed:true});}
  catch(error){
    const code=typeof error.code==='string'&&/^[a-z0-9_/-]{1,60}$/i.test(error.code)?error.code:'check-failed';
    cases.push({name,passed:false,code});throw Error('compat-check-failed');
  }
}
async function seed(){
  await env.clearFirestore();await env.withSecurityRulesDisabled(async context=>{
    const db=context.firestore(),now=Timestamp.now();
    for(const [uid,key,id,install] of [[actors.owner,A,'@DEDA-AB3C5D','compat-install-a'],
                                     [actors.other,B,'@DEDA-ZX4W6V','compat-install-b']]){
      await setDoc(doc(db,'users',uid),{accountKey:key,phone:key,name:'Synthetic QA User',accountType:'user',
        sharePersonalId:id,authMethod:'deda_pin_firestore_v1',createdAt:now,updatedAt:now});
      await setDoc(doc(db,'deda_sessions',uid),{uid,accountKey:key,installId:install,signedInAt:now,lastSeenAt:now});
      await setDoc(doc(db,'deda_share_ids',id),{publicId:id,kind:'personal',active:true,ownerUid:uid,accountKey:key});
    }
    await setDoc(doc(db,'admins',actors.manager),{active:true,status:'active',role:'general_manager',
      email:'manager@deda-qa.invalid',displayName:'Synthetic QA Manager',firstLoginCompletedAt:now});
    await setDoc(doc(db,'admin_entry_access',A),{accountKey:A,active:false,role:'employee',adminUid:actors.owner});
    await setDoc(doc(db,'admin_audit','compat-audit'),{adminUid:actors.manager,createdAt:now,action:'fixture'});
    await setDoc(doc(db,'published_places','compat-public-place'),{name:'Synthetic place',active:true,
      status:'approved',ownerUid:actors.owner,ownerAccountKey:A,ownerPhone:A,createdAt:now});
    await setDoc(doc(db,'place_requests','compat-owner-request'),{name:'Synthetic request',ownerUid:actors.owner,
      ownerAccountKey:A,ownerPhone:A,uid:actors.owner,status:'pending',createdAt:now});
    await setDoc(doc(db,'support_requests','compat-owner-support'),{uid:actors.owner,ownerUid:actors.owner,
      accountKey:A,phone:A,status:'open',message:'Synthetic support',createdAt:now});
    await setDoc(doc(db,'deda_diamond_gift_balances','@DEDA-AB3C5D'),{balance:1234,publicId:'@DEDA-AB3C5D',
      originalId:'@DEDA-AB3C5D',ownerUid:actors.owner,updatedAt:now});
    await setDoc(doc(db,archive),{...payload(capture),createdAt:now});
    await setDoc(doc(db,receipt),{format:1,accountKey:A,fixture:true});
    await setDoc(doc(db,migration),{format:1,accountKey:A,fixture:true});
    await setDoc(doc(db,progress),{format:1,accountKey:A,version:1,balances:{points:5,coins:17,xp:3020,earnedDiamonds:9},initializedBy:'a'.repeat(64)});
  });
}
const legacy=[
  ['own-user-get','owner',db=>getDocFromServer(doc(db,'users',actors.owner)),true],
  ['other-user-get','owner',db=>getDocFromServer(doc(db,'users',actors.other))],
  ['own-profile-update','owner',db=>updateDoc(doc(db,'users',actors.owner),{name:'Synthetic changed name',updatedAt:serverTimestamp()}),true],
  ['own-session-get','owner',db=>getDocFromServer(doc(db,'deda_sessions',actors.owner)),true],
  ['other-session-get','owner',db=>getDocFromServer(doc(db,'deda_sessions',actors.other)),false],
  ['public-place-authed','owner',db=>getDocFromServer(doc(db,'published_places','compat-public-place'))],
  ['public-place-anonymous','anonymous',db=>getDocFromServer(doc(db,'published_places','compat-public-place'))],
  ['gift-wallet-read','owner',db=>getDocFromServer(doc(db,'deda_diamond_gift_balances','@DEDA-AB3C5D'))],
  ['own-place-request','owner',db=>getDocFromServer(doc(db,'place_requests','compat-owner-request'))],
  ['other-place-request','other',db=>getDocFromServer(doc(db,'place_requests','compat-owner-request'))],
  ['own-support-request','owner',db=>getDocFromServer(doc(db,'support_requests','compat-owner-support'))],
  ['own-admin-entry-get','owner',db=>getDocFromServer(doc(db,'admin_entry_access',A))],
  ['other-admin-entry-get','other',db=>getDocFromServer(doc(db,'admin_entry_access',A))],
  ['normal-user-admin-list','owner',db=>getDocs(collection(db,'admins')),false],
  ['recognized-manager-admin-list','manager',db=>getDocs(collection(db,'admins')),true],
  ['normal-user-self-admin-grant','owner',db=>setDoc(doc(db,'admins',actors.owner),{active:true,status:'active',role:'general_manager'}),false],
  ['normal-user-entry-grant','owner',db=>setDoc(doc(db,'admin_entry_access',A),{accountKey:A,active:true,role:'general_manager',adminUid:actors.owner}),false],
  ['manager-audit-list','manager',db=>getDocs(collection(db,'admin_audit')),true],
];
async function legacyChecks(mode){
  for(const [name,actor,operation,expected] of legacy){
    await check(`${mode}/legacy/${name}`,async()=>{
      const allowed=await permitted(()=>operation(database(actor)));observations[mode][name]=allowed;
      if(expected!==undefined)assert.equal(allowed,expected);
      if(mode==='after')assert.equal(allowed,observations.before[name]);
    });
  }
}
async function beforeNamespaceChecks(){
  for(const [scope,route] of Object.entries(scopes))for(const actor of Object.keys(actors)){
    await check(`before/new-private-scope-denied/${scope}/${actor}`,async()=>{
      const db=database(actor);
      assert.equal(await permitted(()=>getDocFromServer(doc(db,route))),false);
      const id=`compat_probe_${scope}_${actor}_00001`;
      const target=scope==='evidence'?`deda_progress_evidence/${A}/captures/${id}`:
        scope==='receipt'?`deda_progress_receipts/${A}/events/${id}`:route;
      assert.equal(await permitted(()=>setDoc(doc(db,target),scope==='evidence'?payload(id,actors[actor]||'no-auth'):
        {format:1,accountKey:A,ownerUid:actors[actor],fixture:true})),false);
    });
  }
}
async function afterArchiveChecks(){
  await check('after/owner-evidence-read-and-create',async()=>{
    const db=database('owner');const snap=await getDocFromServer(doc(db,archive));assert.deepEqual(snap.data().records,records);
    const id='compat_new_owned_capture_00001';await setDoc(doc(db,`deda_progress_evidence/${A}/captures/${id}`),payload(id));
    const saved=await getDocFromServer(doc(db,`deda_progress_evidence/${A}/captures/${id}`));assert(saved.data().createdAt instanceof Timestamp);
  });
  await check('after/owner-evidence-update-and-delete-denied',async()=>{
    const ref=doc(database('owner'),archive);
    assert.equal(await permitted(()=>updateDoc(ref,{records:{...records,earnedDiamonds:'forged'}})),false);
    assert.equal(await permitted(()=>deleteDoc(ref)),false);
  });
  await check('after/new-uid-same-account-can-read-old-evidence',async()=>{
    const uid='compat-replacement-uid';
    await env.withSecurityRulesDisabled(async c=>{
      await setDoc(doc(c.firestore(),'users',uid),{accountKey:A});
      await setDoc(doc(c.firestore(),'deda_sessions',uid),{uid,accountKey:A,installId:'compat-new-install'});
    });
    const db=env.authenticatedContext(uid).firestore();const old=await getDocFromServer(doc(db,archive));
    assert.equal(old.data().sourceUid,actors.owner);assert.equal(old.data().installId,'compat-install-a');
    const id='compat_replacement_capture_00001';await setDoc(doc(db,`deda_progress_evidence/${A}/captures/${id}`),payload(id,uid,'compat-new-install'));
  });
  for(const actor of ['other','manager','anonymous'])await check(`after/private-account-access-denied/${actor}`,async()=>{
    const db=database(actor);
    assert.equal(await permitted(()=>getDocFromServer(doc(db,archive))),false);
    assert.equal(await permitted(()=>getDocs(collection(db,`deda_progress_evidence/${A}/captures`))),false);
    assert.equal(await permitted(()=>getDocFromServer(doc(db,progress))),false);
  });
  for(const scope of ['receipt','migration','progress'])for(const actor of Object.keys(actors)){
    await check(`after/client-server-state-write-denied/${scope}/${actor}`,async()=>{
      const db=database(actor),route=scopes[scope];
      assert.equal(await permitted(()=>setDoc(doc(db,route),{format:1,accountKey:A,fixture:true})),false);
      assert.equal(await permitted(()=>deleteDoc(doc(db,route))),false);
      if(scope!=='progress')assert.equal(await permitted(()=>getDocFromServer(doc(db,route))),false);
    });
  }
  await check('after/owner-verified-projection-read-only',async()=>{
    const snap=await getDocFromServer(doc(database('owner'),progress));assert.equal(snap.data().balances.coins,17);
  });
  await check('after/old-wallet-balance-and-profile-still-present',async()=>{
    await env.withSecurityRulesDisabled(async c=>{
      assert.equal((await getDocFromServer(doc(c.firestore(),'deda_diamond_gift_balances','@DEDA-AB3C5D'))).data().balance,1234);
      assert.equal((await getDocFromServer(doc(c.firestore(),'users',actors.owner))).data().name,'Synthetic changed name');
    });
  });
}


// Match immutable 100380 DedaPinAuth's Firestore payloads/order. Only credential
// and profile creation use normal client rules; no privileged session/user seeds
// for this account. Auth token issuance is still a rules-unit fixture, not PIN UI.
const pinAccount='07700000002',syntheticPin='381649';
const pinUids={first:'compat-pin-register',second:'compat-pin-new-device',
  trusted:'compat-pin-trusted-uid',wrong:'compat-pin-wrong',untrusted:'compat-pin-untrusted'};
const pinDb=uid=>env.authenticatedContext(uid,{firebase:{sign_in_provider:'anonymous'}}).firestore();
const prove=(db,uid,pin=syntheticPin,key=pinAccount)=>setDoc(doc(db,'deda_auth_attempts',uid),
  {uid,accountKey:key,pin,createdAt:serverTimestamp()});
const open=(db,uid,installId,key=pinAccount)=>setDoc(doc(db,'deda_sessions',uid),
  {uid,accountKey:key,installId,signedInAt:serverTimestamp(),lastSeenAt:serverTimestamp()});
const userPayload=install=>({name:'Synthetic PIN Owner',phone:pinAccount,accountKey:pinAccount,
  accountType:'user',authMethod:'deda_pin_firestore_v1',trustedInstallIds:arrayUnion(install),
  updatedAt:serverTimestamp(),lastSeenAt:serverTimestamp()});
async function pinOwnershipChecks(mode){
  const first=pinDb(pinUids.first),second=pinDb(pinUids.second),trusted=pinDb(pinUids.trusted);
  await check(`${mode}/pin/client-registration-and-first-session`,async()=>{
    const directory=doc(first,'deda_account_directory',pinAccount);
    await runTransaction(first,async transaction=>{
      assert.equal((await transaction.get(directory)).exists(),false);
      transaction.set(doc(first,'deda_credentials',pinAccount),{accountKey:pinAccount,pin:syntheticPin,
        active:true,createdUid:pinUids.first,createdAt:serverTimestamp(),updatedAt:serverTimestamp()});
      transaction.set(directory,{accountKey:pinAccount,active:true,createdUid:pinUids.first,
        createdAt:serverTimestamp(),updatedAt:serverTimestamp()});
    });
    await prove(first,pinUids.first);await open(first,pinUids.first,'compat-pin-install-first');
    await setDoc(doc(first,'deda_account_profiles',pinAccount),{accountKey:pinAccount,
      name:'Synthetic PIN Owner',phone:pinAccount,accountType:'user',
      trustedInstallIds:['compat-pin-install-first'],createdAt:serverTimestamp(),
      updatedAt:serverTimestamp(),lastSeenAt:serverTimestamp()});
    await setDoc(doc(first,'users',pinUids.first),{...userPayload('compat-pin-install-first'),createdAt:serverTimestamp()},{merge:true});
    assert.equal((await getDocFromServer(doc(first,'users',pinUids.first))).data().accountKey,pinAccount);
  });
  await check(`${mode}/pin/credential-and-attempt-remain-unreadable`,async()=>{
    for(const route of [['deda_credentials',pinAccount],['deda_auth_attempts',pinUids.first]]){
      assert.equal(await permitted(()=>getDocFromServer(doc(first,...route))),false);
    }
  });
  await check(`${mode}/pin/wrong-pin-cannot-open-session-or-profile`,async()=>{
    const uid=pinUids.wrong,db=pinDb(uid);
    assert.equal(await permitted(()=>prove(db,uid,'000000')),false);
    assert.equal(await permitted(()=>open(db,uid,'compat-wrong-install')),false);
    assert.equal(await permitted(()=>getDocFromServer(doc(db,'deda_account_profiles',pinAccount))),false);
    assert.equal(await permitted(()=>setDoc(doc(db,'users',uid),userPayload('compat-wrong-install'))),false);
  });
  await check(`${mode}/pin/new-device-correct-pin-session-readback`,async()=>{
    await prove(second,pinUids.second);await open(second,pinUids.second,'compat-pin-install-second');
    const session=await getDocFromServer(doc(second,'deda_sessions',pinUids.second));
    assert.equal(session.data().accountKey,pinAccount);assert.equal(session.data().installId,'compat-pin-install-second');
    assert.equal(session.metadata.fromCache,false);assert.equal(session.metadata.hasPendingWrites,false);
    assert.equal((await getDocFromServer(doc(second,'deda_account_profiles',pinAccount))).data().name,'Synthetic PIN Owner');
  });
  await check(`${mode}/pin/new-device-profile-trust-and-users-binding`,async()=>{
    await setDoc(doc(second,'deda_account_profiles',pinAccount),{
      trustedInstallIds:arrayUnion('compat-pin-install-second'),lastSeenAt:serverTimestamp(),updatedAt:serverTimestamp()},{merge:true});
    await setDoc(doc(second,'users',pinUids.second),userPayload('compat-pin-install-second'),{merge:true});
    assert.equal((await getDocFromServer(doc(second,'users',pinUids.second))).data().accountKey,pinAccount);
  });
  await check(`${mode}/pin/trusted-install-new-uid-without-pin`,async()=>{
    await open(trusted,pinUids.trusted,'compat-pin-install-second');
    assert.equal((await getDocFromServer(doc(trusted,'deda_account_profiles',pinAccount))).data().accountKey,pinAccount);
    await setDoc(doc(trusted,'users',pinUids.trusted),userPayload('compat-pin-install-second'),{merge:true});
    assert.equal((await getDocFromServer(doc(trusted,'deda_sessions',pinUids.trusted))).data().uid,pinUids.trusted);
  });
  await check(`${mode}/pin/untrusted-install-without-pin-denied`,async()=>{
    const uid=pinUids.untrusted,db=pinDb(uid);
    assert.equal(await permitted(()=>open(db,uid,'compat-pin-install-unknown')),false);
    assert.equal(await permitted(()=>getDocFromServer(doc(db,'deda_account_profiles',pinAccount))),false);
  });
  await check(`${mode}/pin/valid-proof-cannot-switch-to-other-account`,async()=>{
    assert.equal(await permitted(()=>open(second,pinUids.second,'compat-pin-install-second',A)),false);
    assert.equal((await getDocFromServer(doc(second,'deda_sessions',pinUids.second))).data().accountKey,pinAccount);
  });
  await check(`${mode}/pin/cannot-write-another-uid-proof-session-or-user`,async()=>{
    assert.equal(await permitted(()=>prove(second,pinUids.first)),false);
    assert.equal(await permitted(()=>open(second,pinUids.first,'compat-pin-install-second')),false);
    assert.equal(await permitted(()=>setDoc(doc(second,'users',pinUids.first),userPayload('compat-pin-install-second'),{merge:true})),false);
  });
  await check(`${mode}/pin/original-profile-and-both-trust-entries-preserved`,async()=>{
    const profile=(await getDocFromServer(doc(first,'deda_account_profiles',pinAccount))).data();
    assert.equal(profile.name,'Synthetic PIN Owner');assert.equal(profile.accountKey,pinAccount);
    assert.deepEqual(profile.trustedInstallIds,['compat-pin-install-first','compat-pin-install-second']);
    assert.equal((await getDocFromServer(doc(first,'users',pinUids.first))).data().name,'Synthetic PIN Owner');
  });
  if(mode==='after')await check('after/pin/client-proven-new-uid-reads-original-evidence',async()=>{
    const id='compat_pin_owned_capture_00001';
    const route=`deda_progress_evidence/${pinAccount}/captures/${id}`;
    await setDoc(doc(first,route),{...payload(id,pinUids.first,'compat-pin-install-first'),accountKey:pinAccount});
    for(const db of [second,trusted]){
      const evidence=(await getDocFromServer(doc(db,route))).data();
      assert.equal(evidence.sourceUid,pinUids.first);assert.equal(evidence.installId,'compat-pin-install-first');
      assert.deepEqual(evidence.records,records);
    }
    for(const uid of [pinUids.wrong,pinUids.untrusted]){
      assert.equal(await permitted(()=>getDocFromServer(doc(pinDb(uid),route))),false);
    }
  });
}

(async()=>{
  let success=false;
  try{
    for(const mode of ['before','after']){
      env=await initializeTestEnvironment({projectId:project,firestore:{rules:sources[mode]}});
      await seed();await legacyChecks(mode);await pinOwnershipChecks(mode);
      if(mode==='before')await beforeNamespaceChecks();else await afterArchiveChecks();
      await env.cleanup();env=null;
    }
    // 18 old-policy observations per mode +16 baseline namespace probes +20
    // added-policy cases, plus 10 PIN cases per policy and one archive bridge.
    // Both old policy and merged policy were loaded.
    assert.equal(cases.length,93);assert(cases.every(value=>value.passed));success=true;
  }catch(error){
    if(!cases.some(value=>!value.passed))cases.push({name:'emulator-setup-or-completion',passed:false,code:'setup-or-count-failed'});
  }finally{
    if(env){try{await env.cleanup();}catch(_){success=false;}}
    report.status=success?'emulator-passed-awaiting-release-verify':'emulator-failed';
    report.emulator={project,expectedCases:93,completedCases:cases.length,passed:cases.filter(c=>c.passed).length,
      failed:cases.filter(c=>!c.passed).length,cases,legacyObservations:observations,
      data:'synthetic only, no production documents read or written'};
    fs.writeFileSync(reportPath,JSON.stringify(report,null,2)+'\n');
    process.exitCode=success?0:1;
  }
})().catch(()=>{process.exitCode=1;});
