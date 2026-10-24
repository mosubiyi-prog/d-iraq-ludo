'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const {approveLegacyBaseline,policyPath}=require('./baseline-review.cjs');
const {saveMigrationAssessment}=require('./migration-assessment-store.cjs');
const {parseMigration,reconcileMigratedReceipt}=require('./migration-gate.cjs');
const A='07700000000',captureId='baseline_capture_00000001',migrationId='migration_review_00000001';
const root=`deda_progress_migrations/${A}`,source=`deda_progress_evidence/${A}/captures/${captureId}`;
const reviewPath=`${root}/reviews/${migrationId}`,approvalPath=`${root}/approvals/${migrationId}`;
const revision='owner_review_policy_00001';
const token=()=>({uid:'fixture-manager',email:'manager@example.test',firebase:{sign_in_provider:'password'}});
const admin=()=>({active:true,status:'active',role:'general_manager',email:'manager@example.test',mustChangePassword:false});
const policy=()=>({format:1,enabled:true,revision,decisionBasis:'owner-reviewed-grandfathering',acceptedIssues:[
 'local-values-not-server-attested','legacy-writer-fence-not-established','pending-operations-not-reviewed']});
class Store{
 constructor(){this.docs=new Map();this.writes=[];this.retry=null;this.fail=false;}
 serverTimestamp(){return {seconds:1,nanoseconds:0};}
 async runTransaction(action){
  const run=async()=>{const writes=new Map();const result=await action({get:async path=>{
   assert.equal(writes.size,0,'all reads must precede writes');return structuredClone(this.docs.get(path)??null);
  },set:(path,data)=>writes.set(path,structuredClone(data))});return {writes,result};};
  let out=await run();if(this.retry){const retry=this.retry;this.retry=null;retry(this.docs);out=await run();}
  if(this.fail)throw Error('fixture-commit-failure');
  for(const [path,data]of out.writes){this.docs.set(path,data);this.writes.push(path);}return out.result;
 }
}
async function fixture(){
 const store=new Store();store.docs.set(source,{format:1,kind:'legacy-local-evidence',accountKey:A,captureId,
 sourceUid:'old-device',installId:'old-install',createdAt:{seconds:1,nanoseconds:0},records:{
 taskPoints:'{"version":1,"completions":{},"awards":{"old":{"points":100}},"ledger":[]}',
 socialCoinsAndXp:'{"coins":30,"xp":20,"taskClaims":[]}',earnedDiamonds:'{"balance":9,"day":"2026-10-24","viewsToday":1}'}});
 await saveMigrationAssessment({store,accountKey:A,captureId,migrationId});store.writes=[];
 store.docs.set(policyPath,policy());store.docs.set('admins/fixture-manager',admin());
 let calls=0;const auth={verifyIdToken:async(value,revoked)=>{assert.equal(value,'signed-fixture-token');assert.equal(revoked,true);calls++;return token();}};
 const request={store,auth,idToken:'signed-fixture-token',accountKey:A,migrationId,
 expectedEvidenceDigest:store.docs.get(root).evidenceDigest,policyRevision:revision};
 return {store,request,calls:()=>calls};
}
const approve=f=>approveLegacyBaseline(f.request);
async function reject(f,code){const before=structuredClone([...f.store.docs]);await assert.rejects(approve(f),e=>e.code===code);
 assert.deepEqual([...f.store.docs],before);assert.deepEqual(f.store.writes,[]);}
test('manager review creates ONLY private approval and pending-settlement phase; never receipt or money',async()=>{
 const f=await fixture(),original=structuredClone(f.store.docs.get(source));const r=await approve(f);
 assert.equal(r.phase,'baseline-approved');assert.equal(r.canReleaseBalance,false);assert.equal(f.calls(),1);
 assert.deepEqual(f.store.writes,[approvalPath,root]);assert.equal(f.store.docs.get(root).settlementId,null);
 assert.equal(f.store.docs.get(approvalPath).receipt.delta.coins,30);assert.equal(f.store.docs.get(reviewPath).canAutoApprove,false);
 assert.deepEqual(f.store.docs.get(source),original);assert.equal(f.store.docs.get(`deda_verified_progress/${A}`),undefined);
 await assert.rejects(reconcileMigratedReceipt({store:f.store,accountKey:A,receiptId:'award_receipt_0000000001'}),e=>e.code==='migration-pending');
});
test('repeat approval preserves timestamp and does not downgrade cutover or mint a receipt',async()=>{
 const f=await fixture();await approve(f);const before=structuredClone(f.store.docs.get(approvalPath));f.store.writes=[];
 assert.equal((await approve(f)).replayed,true);assert.deepEqual(f.store.docs.get(approvalPath),before);assert.deepEqual(f.store.writes,[]);
 f.store.docs.set(root,{...f.store.docs.get(root),phase:'cutover-complete',settlementId:'settlement_review_0000001'});
 assert.equal((await approve(f)).phase,'cutover-complete');assert.deepEqual(f.store.writes,[]);
});
for(const change of ['missing','disabled'])test(`${change} policy defaults to no approval`,async()=>{
 const f=await fixture();if(change==='missing')f.store.docs.delete(policyPath);else f.store.docs.get(policyPath).enabled=false;
 await reject(f,'baseline-review-policy-disabled');
});
for(const change of ['revision','decisionBasis','acceptedIssues','extra'])test(`invalid policy ${change} denies approval`,async()=>{
 const f=await fixture(),p=f.store.docs.get(policyPath);
 if(change==='revision')p.revision='different_policy_0000001';if(change==='decisionBasis')p.decisionBasis='provider-verified';
 if(change==='acceptedIssues')p.acceptedIssues=[];if(change==='extra')p.verified=true;
 await reject(f,'invalid-baseline-review-policy');
});
for(const [field,value]of [['active',false],['status','paused'],['role','admin'],['email','different@example.test'],['mustChangePassword',true]])test(`manager ${field} rechecked on server`,async()=>{
 const f=await fixture();f.store.docs.get('admins/fixture-manager')[field]=value;await reject(f,'baseline-review-general-manager-required');
});
for(const provider of ['anonymous','custom','google.com'])test(`${provider} sign-in cannot approve old funds`,async()=>{
 const f=await fixture();f.request.auth={verifyIdToken:async()=>({...token(),firebase:{sign_in_provider:provider}})};
 await reject(f,'baseline-review-admin-sign-in-required');
});
test('Firebase revoked/invalid token error leaves every document unchanged',async()=>{
 const f=await fixture();f.request.auth={verifyIdToken:async()=>{throw Object.assign(Error('revoked'),{code:'auth/id-token-revoked'});}};
 await reject(f,'auth/id-token-revoked');
});
for(const field of ['reviewerUid','verified','amount'])test(`client ${field} is not an approval input`,async()=>{
 const f=await fixture();f.request[field]=field==='amount'?1000000:true;await reject(f,'invalid-baseline-review-request');assert.equal(f.calls(),0);
});
for(const change of ['digest','migrationId'])test(`stale selected ${change} cannot approve another snapshot`,async()=>{
 const f=await fixture();if(change==='digest')f.request.expectedEvidenceDigest='f'.repeat(64);else f.request.migrationId='other_migration_00000001';
 await reject(f,'baseline-review-migration-conflict');
});
test('changed archived bytes cannot retain a valid approval just by keeping raw totals',async()=>{
 const f=await fixture();f.store.docs.get(source).records.socialCoinsAndXp+=' ';await reject(f,'migration-reviewed-evidence-conflict');
});
test('extra reported issue requires explicit policy acknowledgement and is never silently ignored',async()=>{
 const f=await fixture();f.store.docs.get(source).records.taskPoints='{"version":1,"completions":{},"awards":{"old":{"points":100}},"ledger":"bad"}';
 f.store.docs.delete(root);f.store.docs.delete(reviewPath);await saveMigrationAssessment({store:f.store,accountKey:A,captureId,migrationId});
 f.store.writes=[];f.request.expectedEvidenceDigest=f.store.docs.get(root).evidenceDigest;
 await reject(f,'baseline-review-unaccepted-issues');
});
for(const kind of ['missing','negative'])test(`${kind} legacy amount is not grandfathered as zero`,async()=>{
 const f=await fixture();const raw=f.store.docs.get(source);
 if(kind==='missing')raw.records.socialCoinsAndXp=null;
 else raw.records.taskPoints='{"version":1,"completions":{},"awards":{"spent":{"points":-5}},"ledger":[]}';
 f.store.docs.delete(root);f.store.docs.delete(reviewPath);await saveMigrationAssessment({store:f.store,accountKey:A,captureId,migrationId});
 f.store.writes=[];f.request.expectedEvidenceDigest=f.store.docs.get(root).evidenceDigest;
 await reject(f,kind==='missing'?'invalid-amount':'invalid-baseline');
});
test('transaction retry reverifies token and refuses a removed manager role',async()=>{
 const f=await fixture();f.store.retry=docs=>docs.get('admins/fixture-manager').role='admin';
 await assert.rejects(approve(f),e=>e.code==='baseline-review-general-manager-required');assert.equal(f.calls(),2);assert.deepEqual(f.store.writes,[]);
});
test('transaction retry refuses disabled policy before persisting first-attempt approval',async()=>{
 const f=await fixture();f.store.retry=docs=>docs.get(policyPath).enabled=false;
 await assert.rejects(approve(f),e=>e.code==='baseline-review-policy-disabled');assert.equal(f.calls(),2);assert.deepEqual(f.store.writes,[]);
});
test('failed atomic commit writes neither approval nor migration phase',async()=>{
 const f=await fixture();f.store.fail=true;const before=structuredClone([...f.store.docs]);
 await assert.rejects(approve(f),/fixture-commit-failure/);assert.deepEqual([...f.store.docs],before);
});
test('preexisting financial state requires reconciliation instead of approving a replacement baseline',async()=>{
 const f=await fixture();f.store.docs.set(`deda_verified_progress/${A}`,{existing:'preserve'});await reject(f,'baseline-review-existing-state-conflict');
});
test('altered private approval cannot replay with a different amount',async()=>{
 const f=await fixture();await approve(f);f.store.docs.get(approvalPath).receipt.delta.coins++;f.store.writes=[];
 await reject(f,'baseline-review-approval-conflict');
});
test('baseline approval may await settlement but cutover still requires a settlement ID',()=>{
 const root={format:1,accountKey:A,migrationId,phase:'baseline-approved',evidenceDigest:'a'.repeat(64),baselineEventKey:'b'.repeat(64),settlementId:null};
 assert.equal(parseMigration(root,A).settlementId,null);
 assert.throws(()=>parseMigration({...root,phase:'cutover-complete'},A),e=>e.code==='invalid-migration');
});
