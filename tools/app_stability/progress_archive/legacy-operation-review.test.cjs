'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const {saveLegacyOperationReview,pointTierObservations,frames}=require('./legacy-operation-review.cjs');
const {assessLegacyEvidence}=require('./legacy-assessment.cjs');
const {saveMigrationAssessment}=require('./migration-assessment-store.cjs');
const A='07700000000',captureId='baseline_capture_00000001',migrationId='migration_review_00000001',originalId='@DEDA-ABC123';
const root=`deda_progress_migrations/${A}`,source=`deda_progress_evidence/${A}/captures/${captureId}`;
const nativePath=`deda_native_account_cosmetics/${originalId}`;
const rp=frame=>`deda_lab_frame_receipts/${originalId}/frames/${frame}`;
const op=frame=>`deda_lab_owned_frames/${originalId}/frames/${frame}`;
function evidence(awards={old:{points:100000}}){return {format:1,kind:'legacy-local-evidence',accountKey:A,captureId,
 sourceUid:'old-device',installId:'old-install',createdAt:{seconds:1,nanoseconds:0},records:{
 taskPoints:JSON.stringify({version:1,awards,completions:{},ledger:[]}),socialCoinsAndXp:'{"coins":30,"xp":20,"taskClaims":[]}',
 earnedDiamonds:'{"balance":9,"day":"2026-10-24","viewsToday":1}'}};}
class Store{
 constructor(){this.docs=new Map();this.writes=[];this.retry=null;this.fail=false;}
 serverTimestamp(){return {seconds:2,nanoseconds:0};}
 async runTransaction(action){
  const run=async()=>{const writes=new Map();const result=await action({get:async path=>{
   assert.equal(writes.size,0,'read after write');return structuredClone(this.docs.get(path)??null);
  },set:(path,data)=>writes.set(path,structuredClone(data))});return {writes,result};};
  let out=await run();if(this.retry){const retry=this.retry;this.retry=null;retry(this.docs);out=await run();}
  if(this.fail)throw Error('commit-failure');for(const [path,data]of out.writes){this.docs.set(path,data);this.writes.push(path);}return out.result;
 }
}
async function fixture(){
 const store=new Store();store.docs.set(source,evidence());
 await saveMigrationAssessment({store,accountKey:A,captureId,migrationId});store.writes=[];
 store.docs.set('users/old-device',{accountKey:A,sharePersonalId:originalId});
 store.docs.set(`deda_share_ids/${originalId}`,{publicId:originalId,kind:'personal',active:true,ownerUid:'old-device'});
 store.docs.set(nativePath,{originalId,pendingFrames:['FRAME_03'],ownedFrames:['FRAME_05'],ownedStyles:['badge_gold'],avatar:2,custom:'preserve'});
 return {store,request:{store,accountKey:A,migrationId,originalId}};
}
const save=f=>saveLegacyOperationReview(f.request);
async function rejected(f,code){const before=structuredClone([...f.store.docs]);await assert.rejects(save(f),e=>e.code===code);assert.deepEqual([...f.store.docs],before);assert.deepEqual(f.store.writes,[]);}
function pair(store,frame='FRAME_03'){
 store.docs.set(rp(frame),{kind:'lab_frame',publicId:originalId,frameId:frame,cost:1000,createdAt:{seconds:1,nanoseconds:0}});
 store.docs.set(op(frame),{publicId:originalId,frameId:frame,receiptId:`${originalId}_${frame}`,createdAt:{seconds:1,nanoseconds:0}});
}
const points=awards=>{const raw=evidence(awards);return pointTierObservations(raw,assessLegacyEvidence(raw,A,captureId));};
test('writes one private review and preserves every source, pending payment, item, wallet and migration phase',async()=>{
 const f=await fixture();f.store.docs.set('deda_gm_personal_diamond_wallets/test',{balance:1000000});const before=structuredClone([...f.store.docs]);
 const result=await save(f);assert.deepEqual(f.store.writes,[result.path]);
 for(const [path,value]of before)assert.deepEqual(f.store.docs.get(path),value);
 assert.equal(result.report.pendingPurchases,'unknown');assert.equal(result.report.canAutoSettle,false);
 assert.deepEqual(result.report.nativePendingFrames,['FRAME_03']);assert.equal(result.report.frames.length,13);
 assert.equal(result.report.canReleaseBalance,false);assert.equal(f.store.docs.get(root).phase,'evidence-saved');
});
test('receipt-confirmed ownership does not prove pending native charge or authorize refund/clearing',async()=>{
 const f=await fixture();pair(f.store);const r=await save(f),frame=r.report.frames[0];
 assert.equal(frame.receiptConfirmed,true);assert.equal(frame.nativePending,true);assert.equal(frame.canAutoRefund,false);assert.equal(frame.canAutoCharge,false);
 assert.equal(frame.disposition,'ownership-confirmed-payment-review-still-required');assert.deepEqual(f.store.docs.get(nativePath).pendingFrames,['FRAME_03']);
});
test('same inputs replay with original timestamp and reordered Firestore maps do not conflict',async()=>{
 const f=await fixture();const first=await save(f);const before=structuredClone(f.store.docs.get(first.path));f.store.writes=[];
 const native=f.store.docs.get(nativePath);f.store.docs.set(nativePath,Object.fromEntries(Object.entries(native).reverse()));
 assert.equal((await save(f)).replayed,true);assert.deepEqual(f.store.docs.get(first.path),before);assert.deepEqual(f.store.writes,[]);
});
test('changed pending state creates a second immutable report and retains the first unresolved report',async()=>{
 const f=await fixture(),first=await save(f);f.store.docs.get(nativePath).pendingFrames.push('FRAME_06');
 const second=await save(f);assert.notEqual(first.path,second.path);assert.deepEqual(f.store.docs.get(first.path).nativePendingFrames,['FRAME_03']);
 assert.deepEqual(second.report.nativePendingFrames,['FRAME_03','FRAME_06']);
});
for(const kind of ['missing-native','missing-pending','invalid-pending','duplicate-pending','unknown-frame'])test(`${kind} never becomes zero pending purchases`,async()=>{
 const f=await fixture();const native=f.store.docs.get(nativePath);
 if(kind==='missing-native')f.store.docs.delete(nativePath);if(kind==='missing-pending')delete native.pendingFrames;
 if(kind==='invalid-pending')native.pendingFrames='paid';if(kind==='duplicate-pending')native.pendingFrames=['FRAME_03','FRAME_03'];
 if(kind==='unknown-frame')native.pendingFrames=['FRAME_FUTURE'];const r=await save(f);
 assert.equal(r.report.pendingPurchases,'unknown');assert.equal(r.report.canAutoSettle,false);
 if(kind==='unknown-frame')assert.deepEqual(r.report.nativePendingFrames,['FRAME_FUTURE']);else assert.equal(r.report.nativePendingFrames,null);
});
for(const kind of ['receipt-only','ownership-only','wrong-cost','wrong-frame','wrong-owner','wrong-receipt-id'])test(`${kind} does not grant receipt-confirmed ownership`,async()=>{
 const f=await fixture();pair(f.store);
 if(kind==='receipt-only')f.store.docs.delete(op('FRAME_03'));if(kind==='ownership-only')f.store.docs.delete(rp('FRAME_03'));
 if(kind==='wrong-cost')f.store.docs.get(rp('FRAME_03')).cost=1;
 if(kind==='wrong-frame')f.store.docs.get(rp('FRAME_03')).frameId='FRAME_05';
 if(kind==='wrong-owner')f.store.docs.get(op('FRAME_03')).publicId='@DEDA-OTHER1';
 if(kind==='wrong-receipt-id')f.store.docs.get(op('FRAME_03')).receiptId='forged';
 const r=await save(f);assert.equal(r.report.frames[0].receiptConfirmed,false);assert.ok(r.report.issues.some(v=>v.includes('partial-or-invalid')));
});
for(const kind of ['alias','different-account','inactive-route','foreign-route-owner','wrong-native-owner'])test(`${kind} cannot inspect or attach another account inventory`,async()=>{
 const f=await fixture();
 if(kind==='alias')f.request.originalId='@DEDA-PREMIUM';
 if(kind==='different-account')f.store.docs.get('users/old-device').accountKey='07700000001';
 if(kind==='inactive-route')f.store.docs.get(`deda_share_ids/${originalId}`).active=false;
 if(kind==='foreign-route-owner'){f.store.docs.get(`deda_share_ids/${originalId}`).ownerUid='other-device';f.store.docs.set('users/other-device',{accountKey:'07700000001'});}
 if(kind==='wrong-native-owner')f.store.docs.get(nativePath).originalId='@DEDA-OTHER1';
 await rejected(f,kind==='alias'?'canonical-original-required':kind==='wrong-native-owner'?'operation-review-cosmetic-owner-conflict':'operation-review-owner-not-proven');
});
test('changed archived bytes invalidate operation review rather than reviewing a new balance silently',async()=>{
 const f=await fixture();f.store.docs.get(source).records.taskPoints+=' ';await rejected(f,'migration-reviewed-evidence-conflict');
});
test('retry rechecks canonical owner before committing any private inventory snapshot',async()=>{
 const f=await fixture();f.store.retry=docs=>docs.get('users/old-device').accountKey='07700000001';
 await assert.rejects(save(f),e=>e.code==='operation-review-owner-not-proven');assert.deepEqual(f.store.writes,[]);
});
test('failed commit leaves all pending frames and ownership intact',async()=>{
 const f=await fixture();f.store.fail=true;const before=structuredClone([...f.store.docs]);await assert.rejects(save(f),/commit-failure/);assert.deepEqual([...f.store.docs],before);
});
test('no point-tier entries are observed separately from missing point evidence',()=>{
 assert.equal(points({}).observedUnclaimedReturns,0);
 const raw=evidence();raw.records.taskPoints=null;assert.equal(pointTierObservations(raw,assessLegacyEvidence(raw,A,captureId)).observedUnclaimedReturns,null);
});
test('open first reserve keeps its future return entitlement without refunding raw points',()=>{
 const r=points({'point_tier_reserve|5000':{points:-5000}});assert.equal(r.observedUnclaimedReturns,1);
 assert.equal(r.tiers[0].status,'unclaimed-return');assert.equal(r.tiers[0].recordedReservePoints,-5000);assert.equal(r.tiers[0].canAutoRefund,false);
});
test('already returned reserve/claim pair is never proposed for a second return',()=>{
 const r=points({'point_tier_reserve|5000':{points:-5000},'point_tier_claim|5000':{points:5050}});
 assert.equal(r.observedUnclaimedReturns,0);assert.equal(r.tiers[0].status,'returned-in-raw-balance');
});
test('terminal 25000 reserve is a spent prize stage and never a refundable reservation',()=>{
 const awards={};for(const threshold of [5000,10000,15000,20000,25000]){
 awards[`point_tier_reserve|${threshold}`]={points:-threshold};if(threshold!==25000)awards[`point_tier_claim|${threshold}`]={points:threshold+threshold/100};}
 const r=points(awards);assert.equal(r.observedUnclaimedReturns,0);assert.equal(r.tiers[4].status,'terminal-prize-reserve');assert.equal(r.tiers[4].bonus,0);
});
for(const awards of [
 {'point_tier_claim|5000':{points:5050}},
 {'point_tier_reserve|5000':{points:-1}},
 {'point_tier_reserve|10000':{points:-10000}},
 {'point_tier|5000':{points:50}},
 {'point_tier_reserve|30000':{points:-30000}},
 {'point_tier_reserve|25000':{points:-25000},'point_tier_claim|25000':{points:25250}},
])test(`inconsistent/obsolete point-tier history held without deletion: ${Object.keys(awards).join(',')}`,()=>{
 const original=structuredClone(awards),r=points(awards);assert.equal(r.observedUnclaimedReturns,null);assert.ok(r.issues.length>0);assert.deepEqual(awards,original);
});
test('duplicate raw JSON keys cannot hide a claimed reservation from review',()=>{
 const raw=evidence();raw.records.taskPoints='{"version":1,"awards":{},"awards":{"point_tier_reserve|5000":{"points":-5000}},"completions":{},"ledger":[]}';
 assert.equal(pointTierObservations(raw,assessLegacyEvidence(raw,A,captureId)).observedUnclaimedReturns,null);
});
function sidecar(f){
 const id='purchase_capture_origin_00001';
 const journals=Object.fromEntries(frames.map(frame=>[frame,null]));journals.FRAME_03='paid';journals.FRAME_05='charging';
 const raw={format:1,kind:'legacy-purchase-evidence',accountKey:A,captureId:id,sourceUid:'old-device',installId:'old-install',
 createdAt:{seconds:3,nanoseconds:0},records:{originalId,progressCaptureId:captureId,localSnapshot:JSON.stringify({format:1,accountKey:A,originalId,
 inventory:' {"owned":["frame_3"]} ',frameJournals:journals})}};
 f.request.purchaseCaptureId=id;f.store.docs.set(`deda_purchase_evidence/${A}/captures/${id}`,raw);return raw;
}
test('linked original phone paid journal is preserved in review but never authorizes charge/refund/ownership',async()=>{
 const f=await fixture();sidecar(f);pair(f.store);const r=await save(f);
 assert.equal(r.report.frames[0].localJournal.state,'paid-recorded');assert.equal(r.report.frames[1].localJournal.state,'charging-recorded');
 assert.equal(r.report.purchaseJournalEvidence.canProvePayment,false);assert.equal(r.report.pendingPurchases,'unknown');
 assert.equal(r.report.canAutoSettle,false);assert.deepEqual(f.store.docs.get(nativePath).pendingFrames,['FRAME_03']);
 assert.equal(f.store.writes.length,1);
});
for(const field of ['sourceUid','installId'])test(`journal with changed ${field} cannot be attributed to parent progress source`,async()=>{
 const f=await fixture(),raw=sidecar(f);raw[field]='new-device';await rejected(f,'purchase-evidence-origin-conflict');
});
test('different progress capture cannot silently supply a more convenient payment journal',async()=>{
 const f=await fixture(),raw=sidecar(f);raw.records.progressCaptureId='different_capture_000001';await rejected(f,'purchase-evidence-parent-conflict');
});
test('requested missing payment journal blocks review without creating an empty/settled report',async()=>{
 const f=await fixture();f.request.purchaseCaptureId='purchase_capture_origin_00001';await rejected(f,'purchase-evidence-missing');
});
test('changed journal bytes cause a new immutable review and keep the earlier paid observation',async()=>{
 const f=await fixture(),raw=sidecar(f);const first=await save(f);raw.records.localSnapshot+=' ';
 const second=await save(f);assert.notEqual(first.path,second.path);assert.equal(f.store.docs.get(first.path).frames[0].localJournal.state,'paid-recorded');
});
