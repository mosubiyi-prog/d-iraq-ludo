'use strict';
// MANUAL dedicated lab WIF only; never uses production secrets or client tokens.
const fs=require('node:fs');
const {initializeApp,applicationDefault,deleteApp}=require('firebase-admin/app');
const {getFirestore,FieldValue}=require('firebase-admin/firestore');
const {DedaTrustedProgressTransactionStore}=require('./reconcile-store.cjs');
const {apply,build,checkStored,project}=require('./uid-trusted-fixture.cjs');
const email='deda-stage03-lab-writer@deda-qa-uid-lab-20261108.iam.gserviceaccount.com';
const audience='//iam.googleapis.com/projects/180856267046/locations/global/workloadIdentityPools/deda-stage03-lab/providers/github';
function requireThat(ok){if(!ok)throw Error('lab-credential-or-project-rejected')}
async function main(){
  requireThat(process.env.GITHUB_EVENT_NAME==='workflow_dispatch'&&
    process.env.GITHUB_REF==='refs/heads/deda-100451-owner-admin-session-safe-repair-2026-11-20'&&
    process.env.GITHUB_REPOSITORY==='mosubiyi-prog/d-iraq-ludo'&&
    !process.env.FIRESTORE_EMULATOR_HOST&&!process.env.FIREBASE_AUTH_EMULATOR_HOST&&
    process.env.GCLOUD_PROJECT===project);
  const cfg=JSON.parse(fs.readFileSync(process.env.GOOGLE_APPLICATION_CREDENTIALS,'utf8'));
  requireThat(cfg.type==='external_account'&&cfg.audience===audience&&
    cfg.service_account_impersonation_url==='https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/'+email+':generateAccessToken');
  const app=initializeApp({projectId:project,credential:applicationDefault()},'stage03-lab-fixture');
  const db=getFirestore(app);
  try{
    requireThat(db.projectId===project);
    const store=new DedaTrustedProgressTransactionStore({db,serverTimestamp:()=>FieldValue.serverTimestamp()});
    const result=await apply({store,projectId:project});
    const expected=build();
    for(const [path,value] of Object.entries(expected)){
      const snap=await db.doc(path).get();
      requireThat(snap.exists&&checkStored(path,snap.data(),value));
    }
    console.log(result.replayed?'PASS_EXACT_LAB_FIXTURE_REPLAY_NO_WRITE':'PASS_TRUSTED_LAB_SYNTHETIC_ATOMIC_WRITE',result.count);
    console.log('PASS_TRUSTED_SERVER_READBACK_NO_REAL_AWARD_OR_PURCHASE');
  }finally{await db.terminate();await deleteApp(app)}
}
main().catch(e=>{console.log('BLOCK_TRUSTED_FIXTURE',e.code&&/^[a-z0-9/-]+$/.test(String(e.code))?e.code:'guard-or-operation');process.exitCode=1});
