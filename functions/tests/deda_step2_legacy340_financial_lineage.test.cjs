'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const {createHash}=require('node:crypto');
const {inspectLegacy340FinancialLineage,previewLegacy340FinancialLineage}=
 require('../deda_step2_legacy340_financial_lineage_NOT_EXPORTED.js');
const accountKey='07712345678',uid='uid_original_1',id='@DEDA-ABC123';
const migrationId='M'.repeat(20),captureId='C'.repeat(20),settlementId='S'.repeat(20),purchaseId='P'.repeat(20);
const root='deda_progress_migrations/'+accountKey,timestamp={seconds:1793600000,nanoseconds:0};
const frames=['FRAME_03','FRAME_05','FRAME_06','FRAME_07','FRAME_08','FRAME_09',
 'FRAME_10','FRAME_11','FRAME_12','FRAME_13','FRAME_14','FRAME_15','FRAME_16'];
const parts={taskPoints:'{"version":1,"awards":{},"completions":{},"ledger":[]}',
 socialCoinsAndXp:'{"coins":35,"xp":45,"taskClaims":[]}',
 earnedDiamonds:'{"balance":120,"viewsToday":0,"day":"2026-11-02"}'};
function digest(raw){return createHash('sha256').update(JSON.stringify([
 'untrusted-legacy-evidence-v1',accountKey,captureId,raw.sourceUid,raw.installId,
 [timestamp.seconds,timestamp.nanoseconds],...['taskPoints','socialCoinsAndXp','earnedDiamonds'].map(k=>raw.records[k])
 ])).digest('hex');}
function fixture(){
 const docs=new Map(),reads=[],reader={async get(p){reads.push(p);return docs.get(p)??null;}};
 const run=()=>inspectLegacy340FinancialLineage({reader,accountKey,originalUid:uid,originalId:id});
 const capture=()=>{
  const raw={format:1,kind:'legacy-local-evidence',accountKey,sourceUid:uid,
   installId:'install_1',captureId,records:{...parts},createdAt:timestamp};
  const evidenceDigest=digest(raw);
  docs.set(root,{format:1,accountKey,migrationId,phase:'evidence-saved',
   evidenceDigest,baselineEventKey:null,settlementId:null});
  docs.set(root+'/reviews/'+migrationId,{accountKey,migrationId,captureId,evidenceDigest});
  docs.set('deda_progress_evidence/'+accountKey+'/captures/'+captureId,raw);
  return raw;
 };
 const settlement=()=>{
  const raw=capture();
  docs.set(root,{...docs.get(root),phase:'baseline-approved',settlementId});
  docs.set(root+'/settlementReviews/'+settlementId,{accountKey,migrationId,
   originalId:id,evidenceDigest:digest(raw),purchaseCaptureId:purchaseId});
  const snapshot={format:1,accountKey,originalId:id,inventory:null,
   frameJournals:Object.fromEntries(frames.map(f=>[f,null]))};
  const purchase={format:1,kind:'legacy-purchase-evidence',accountKey,
   sourceUid:uid,installId:raw.installId,captureId:purchaseId,createdAt:timestamp,
   records:{originalId:id,progressCaptureId:captureId,localSnapshot:JSON.stringify(snapshot)}};
  docs.set('deda_purchase_evidence/'+accountKey+'/captures/'+purchaseId,purchase);
  return {raw,snapshot,purchase};
 };
 return {docs,reads,reader,run,capture,settlement};
}
const reject=(p,code)=>assert.rejects(p,e=>e.code===code);
test('old account without migration is UNKNOWN, not zero balance',async()=>{
 const f=fixture(),r=await f.run();
 assert.equal(r.progressSource.status,'migration-not-started-unknown');
 assert.equal(r.giftWalletSource,'not-found-unknown-not-zero');
 assert.equal(r.canCreditDiamonds,false);assert.equal(r.allowPhoneCutover,false);
 assert.equal(f.reads.length,3);
});
test('gift wallet is independent and never added to local earnings',async()=>{
 const f=fixture();f.docs.set('deda_diamond_gift_balances/'+id,{publicId:id,balance:250});
 const r=await f.run();assert.match(r.giftWalletSource,/no-double-credit/);
 assert.equal(r.canMergeOldDeviceWallet,false);
 assert.equal(JSON.stringify(r).includes('250'),false);
});
test('foreign/negative/unsafe gift wallet blocks rather than repair',async()=>{
 for(const value of [{publicId:'@DEDA-OTHER1',balance:5},{publicId:id,balance:-1},
  {publicId:id,balance:2**54},{publicId:id,balance:'0'}]){
  const f=fixture();f.docs.set('deda_diamond_gift_balances/'+id,value);
  await reject(f.run(),'step2-legacy-gift-wallet-owner-or-amount-conflict');
 }
});
test('verified balance before reviewed cutover is conflict',async()=>{
 const f=fixture();f.docs.set('deda_verified_progress/'+accountKey,{balances:{coins:5}});
 await reject(f.run(),'step2-legacy-premature-verified-state-conflict');
});
test('pending does not claim a saved original-phone archive',async()=>{
 const f=fixture();f.docs.set(root,{format:1,accountKey,migrationId,phase:'pending'});
 const r=await f.run();assert.equal(r.migrationPhase,'pending');
 assert.equal(f.reads.some(p=>p.includes('/captures/')),false);
});
test('same UID progress/XP/diamonds source is still UNTRUSTED',async()=>{
 const f=fixture();f.capture();const r=await f.run();
 assert.equal(r.progressSource.allThreePresent,true);
 assert.equal(r.progressSource.parts.earnedDiamonds,'captured-local-untrusted');
 assert.equal(r.canRestoreXpOrPoints,false);assert.equal(r.sourceReviewAndLegacyWriterFenceProven,false);
});
test('reviewed archive vanished: stop rather than guess',async()=>{
 const f=fixture();f.capture();f.docs.delete('deda_progress_evidence/'+accountKey+'/captures/'+captureId);
 await reject(f.run(),'step2-legacy-reviewed-capture-vanished');
});
test('source UID belongs to someone else: reject even with same account key',async()=>{
 const f=fixture(),r=f.capture();r.sourceUid='foreign_uid';
 await reject(f.run(),'step2-legacy-progress-owner-or-capture-conflict');
});
test('captured balance changed after digest is not baseline',async()=>{
 const f=fixture(),r=f.capture();r.records.earnedDiamonds='{"balance":999}';
 await reject(f.run(),'step2-legacy-capture-review-digest-conflict');
});
test('invalid, duplicate JSON or negative old diamonds rejected',async()=>{
 for(const str of ['{bad','{"balance":1,"bal\\u0061nce":2}','{"balance":-1}']){
  const f=fixture(),r=f.capture();r.records.earnedDiamonds=str;
  await assert.rejects(f.run());
 }
});
test('wrong review capture or account cannot be trusted',async()=>{
 for(const change of [{accountKey:'00000000000'},{captureId:'Z'.repeat(20)},
  {evidenceDigest:'f'.repeat(64)}]){
  const f=fixture();f.capture();f.docs.set(root+'/reviews/'+migrationId,
   {...f.docs.get(root+'/reviews/'+migrationId),...change});
  await assert.rejects(f.run());
 }
});
test('no outstanding journal does not itself permit activation',async()=>{
 const f=fixture();f.settlement();const r=await f.run();
 assert.equal(r.purchaseSource.pending,0);assert.equal(r.purchaseSource.paid,0);
 assert.equal(r.canChargeOrRefundFrame,false);assert.equal(r.allowPhoneCutover,false);
});
test('pending and paid frames detected but not charged twice',async()=>{
 const f=fixture(),p=f.settlement();
 p.snapshot.frameJournals.FRAME_03='charging';p.snapshot.frameJournals.FRAME_05='paid';
 p.purchase.records.localSnapshot=JSON.stringify(p.snapshot);
 const r=await f.run();assert.equal(r.purchaseSource.pending,1);assert.equal(r.purchaseSource.paid,1);
 assert.equal(r.canChargeOrRefundFrame,false);
});
test('bad or incomplete 13-frame journal is not silently cleared',async()=>{
 for(const edit of [s=>{s.frameJournals.FRAME_03=2;},
  s=>{delete s.frameJournals.FRAME_16;},s=>{s.originalId='@DEDA-FOREIG';}]){
  const f=fixture(),p=f.settlement();edit(p.snapshot);
  p.purchase.records.localSnapshot=JSON.stringify(p.snapshot);
  await assert.rejects(f.run());
 }
});
test('sidecar copied from other UID/phone or different parent rejected',async()=>{
 for(const change of [{installId:'new_phone'},{sourceUid:'foreign_uid'},
  {records:{originalId:id,progressCaptureId:'X'.repeat(20),localSnapshot:'{}'}}]){
  const f=fixture(),p=f.settlement();Object.assign(p.purchase,change);
  await reject(f.run(),'step2-legacy-purchase-owner-or-parent-conflict');
 }
});
test('settlement referencing missing purchase source must HOLD',async()=>{
 const f=fixture();f.settlement();
 f.docs.delete('deda_purchase_evidence/'+accountKey+'/captures/'+purchaseId);
 await reject(f.run(),'step2-legacy-settlement-purchase-capture-vanished');
});
test('false cutover-complete with no verified state must stop',async()=>{
 const f=fixture();f.settlement();f.docs.set(root,{...f.docs.get(root),phase:'cutover-complete'});
 await reject(f.run(),'step2-legacy-completed-verified-state-missing');
});
test('completed-looking state still does not prove 100340 writer fencing',async()=>{
 const f=fixture();f.settlement();f.docs.set(root,{...f.docs.get(root),phase:'cutover-complete'});
 f.docs.set('deda_verified_progress/'+accountKey,{format:1,balances:{earnedDiamonds:1000}});
 const r=await f.run();assert.equal(r.verifiedProgressDocumentObserved,true);
 assert.equal(r.sourceReviewAndLegacyWriterFenceProven,false);
 assert.equal(r.allTwentyThreeDomainsRestored,false);
});
test('unverified UID rejected before any financial read',async()=>{
 const f=fixture();
 await reject(inspectLegacy340FinancialLineage({reader:f.reader,
  accountKey,originalUid:'../admin',originalId:id}),'step2-legacy-owner-scope-unproven');
 assert.equal(f.reads.length,0);
});
test('preview requires actual linked UID session, never just token text',async()=>{
 await reject(previewLegacy340FinancialLineage({store:{},auth:{},idToken:'fake'}),
  'step2-linked-session-dependencies-missing');
});
test('financial scanner never writes or changes old account documents',async()=>{
 const f=fixture();f.settlement();await f.run();
 assert.equal(f.reads.some(p=>p.includes('deda_purchase_evidence/')),true);
 assert.equal(typeof f.reader.set,'undefined');
});
