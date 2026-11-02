'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const {ORIGIN,WEEK_MS}=require('../deda_weekly_direct_prize_plan.js');
const {completedWeeks,candidateIds,inspectHistoricalWeeklyGiftReceipts,
 previewHistoricalWeeklyGifts}=
 require('../deda_step2_historical_weekly_gifts_audit_NOT_EXPORTED.js');
const original='@DEDA-ABC123',alias='@DEDA-VIP123';
const p=(states=[])=>({status:'STAGE71_74_PREMIUM_HISTORY_READONLY_HOLD',
 stage71And74ServerSourcesScanned:true,states});
const m=n=>ORIGIN+n*WEEK_MS;
const key=(id,week='2026-10-31')=>
 'deda-weekly-'+week+'-'+id.slice(1);
const data=(id,week='2026-10-31',status='pending',amount=150)=>({
 giftId:key(id,week),sourceType:'weekly_league',targetPublicId:id,
 amount,status,createdAt:{toMillis:()=>m(1)}
});
const fixture=(rows=new Map(),premium=p(),nowMs=m(1)+1000)=>{
 const calls=[],reader={async get(path){calls.push(path);return rows.get(path)??null;}};
 return {calls,reader,run:()=>inspectHistoricalWeeklyGiftReceipts({
  reader,originalId:original,premium,nowMs})};
};
test('before league first close no prizes fabricated',async()=>{
 const f=fixture(new Map(),p(),m(0)+10);
 const r=await f.run();assert.equal(r.checkedClosedWeeks,0);
 assert.equal(r.notFoundUnknownDocumentSlots,0);
 assert.equal(r.allHistoricalPrizesRecovered,false);
});
test('one completed week absent gift is UNKNOWN not no winnings',async()=>{
 const f=fixture(),r=await f.run();
 assert.equal(r.checkedClosedWeeks,1);
 assert.equal(r.notFoundUnknownDocumentSlots,1);
 assert.equal(r.knownPendingGiftDocuments,0);
 assert.equal(r.canCreditDiamonds,false);
});
test('legitimate pending gift is not another wallet deposit',async()=>{
 const f=fixture(new Map([['deda_diamond_gifts/'+key(original),
  data(original)]]));
 const r=await f.run();
 assert.equal(r.knownPendingGiftDocuments,1);
 assert.equal(r.historicalSourceRows[0].status,'pending-do-not-credit-on-restore');
 assert.equal(r.canClaimGift,false);
});
test('previously claimed gift cannot be recreated or reissued',async()=>{
 const f=fixture(new Map([['deda_diamond_gifts/'+key(original),
  data(original,'2026-10-31','claimed')]]));
 const r=await f.run();
 assert.equal(r.knownClaimedGiftDocuments,1);
 assert.equal(r.canReissueWeeklyPrize,false);
});
test('verified premium alias is also scanned; original absence unknown',async()=>{
 const premium=p([{identifier:alias,state:'gift-received-once'}]);
 const f=fixture(new Map([['deda_diamond_gifts/'+key(alias),
  data(alias)]]),premium);
 const r=await f.run();
 assert.equal(r.ownerIdentifierCandidates,2);
 assert.equal(r.knownPendingGiftDocuments,1);
 assert.equal(r.notFoundUnknownDocumentSlots,1);
 assert.equal(r.legacyPremiumAliasesUnverified,true);
});
test('pending premium transfer does not become an automatic award',async()=>{
 const f=fixture(new Map(),p([{identifier:alias,state:'gift-awaits-receipt'}]));
 const r=await f.run();
 assert.equal(r.ownerIdentifierCandidates,2);
 assert.equal(r.canCreditDiamonds,false);
 assert.equal(r.allHistoricalPrizesRecovered,false);
});
test('two gifts for aliases of same original in one week stop, never double credit',async()=>{
 const premium=p([{identifier:alias,state:'self-used-server-grant'}]);
 const f=fixture(new Map([
  ['deda_diamond_gifts/'+key(original),data(original)],
  ['deda_diamond_gifts/'+key(alias),data(alias)],
 ]),premium);
 await assert.rejects(f.run(),
  e=>e.code==='step2-historical-duplicate-weekly-owner-prize');
});
test('foreign owner target and mismatched gift ID reject',async()=>{
 for(const alter of [{targetPublicId:'@DEDA-OTHER1'},
  {giftId:'forged'}, {sourceType:'manual'}]){
  const f=fixture(new Map([['deda_diamond_gifts/'+key(original),
   {...data(original),...alter}]]));
  await assert.rejects(f.run(),
   e=>e.code==='step2-historical-weekly-receipt-conflict');
 }
});
test('invalid amounts and claimed state reject',async()=>{
 for(const alter of [{amount:0},{amount:-1},{amount:1.5},
  {status:'reissued'}]){
  const f=fixture(new Map([['deda_diamond_gifts/'+key(original),
   {...data(original),...alter}]]));
  await assert.rejects(f.run(),
   e=>e.code==='step2-historical-weekly-receipt-conflict');
 }
});
test('prize created before league week closes is not trusted',async()=>{
 const f=fixture(new Map([['deda_diamond_gifts/'+key(original),
  {...data(original),createdAt:{toMillis:()=>m(1)-1}}]]));
 await assert.rejects(f.run(),
  e=>e.code==='step2-historical-weekly-receipt-conflict');
});
test('unknown clock or impossible future time blocks before any reads',async()=>{
 for(const now of [-1,NaN,1.5,5000000000000]){
  const f=fixture(new Map(),p(),now);
  await assert.rejects(f.run(),e=>e.code==='step2-historical-week-clock-untrusted');
  assert.equal(f.calls.length,0);
 }
});
test('exact Baghdad 06:00 boundary and completed week IDs',()=>{
 assert.deepEqual(completedWeeks(m(1)-1).weeks.map(x=>x.id),[]);
 assert.deepEqual(completedWeeks(m(1)).weeks.map(x=>x.id),['2026-10-31']);
 assert.deepEqual(completedWeeks(m(2)).weeks.map(x=>x.id),['2026-10-31','2026-11-07']);
});
test('recent 12 weeks bounded; older weeks remain explicitly unverified',()=>{
 const r=completedWeeks(m(14));
 assert.equal(r.totalCompletedWeeks,14);
 assert.equal(r.weeks.length,12);
 assert.equal(r.weeks[0].id,'2026-11-14');
 assert.equal(r.olderWeeksNotScanned,true);
});
test('unproven premium query cannot authorize history scan',async()=>{
 const f=fixture(new Map(),{...p(),stage71And74ServerSourcesScanned:false});
 await assert.rejects(f.run(),
  e=>e.code==='step2-historical-owner-proof-incomplete');
});
test('too many alias records block expensive partial scans',async()=>{
 const states=Array.from({length:13},(_,i)=>({
  identifier:'@DEDA-AB'+String(i).padStart(4,'0'),state:'gift-received-once'
 }));
 assert.throws(()=>candidateIds(original,p(states)),
  e=>e.code==='step2-historical-alias-scan-over-limit');
});
test('malformed and duplicate premium alias entries rejected',()=>{
 assert.throws(()=>candidateIds(original,p([
  {identifier:alias,state:'gift-received-once'},
  {identifier:alias,state:'gift-received-once'},
 ])),e=>e.code==='step2-historical-premium-candidates-conflict');
 assert.throws(()=>candidateIds(original,p([
  {identifier:'@DEDA-VIP123',state:'unknown'},
 ])),e=>e.code==='step2-historical-premium-candidates-conflict');
});
test('historical preview requires trusted server clock and linked UID',async()=>{
 await assert.rejects(previewHistoricalWeeklyGifts({
  store:{},auth:{},idToken:'fake'
 }),e=>e.code==='step2-historical-server-clock-required');
 await assert.rejects(previewHistoricalWeeklyGifts({
  store:{serverNowMs:()=>m(1)},auth:{},idToken:'fake'
 }),e=>e.code==='step2-linked-session-dependencies-missing');
});
