"use strict";
const assert=require("node:assert/strict");
const {test}=require("node:test");
const {inspectEightSectionRestoration,domains,history}=
 require("./deda_eight_domains_restore_coverage_PRIVATE_QA.cjs");
const verified=()=>({
 ownerIndependentlyVerified:true,sameOriginalUid:true,createdNewUid:false,
 singleAuthSession:true,financialSourceComplete:true,
 scopes:Object.fromEntries(domains.map(x=>[x,"verified-server"])),
 legacy:Object.fromEntries(history.map(x=>[x,"verified-server-readback-new-phone"]))
});
test("POINT4 eight domain list exactly matches approved work",()=>{
 assert.deepEqual(domains,["profile","original_id","premium_id","friends",
  "league","gifts","wallet","places"]);
});
test("AHMED REGRESSION: old ID, 440 gems and Hadaya but no level 13 or coins 2000+ is NOT restored",()=>{
 const s=verified();
 s.scopes.wallet="partial-gift-wallet-only";
 s.legacy.taskPoints="unknown-no-old-phone";
 s.legacy.socialXp="missing-local-1200-to-1299";
 s.legacy.coins="missing-local-2000-plus";
 s.financialSourceComplete=false;
 const result=inspectEightSectionRestoration(s);
 assert.equal(result.fullyRestored,false);
 assert.equal(result.financialRestoreAuthorized,false);
 assert.equal(result.creditsAnything,false);
 assert.ok(result.blockers.some(x=>x.startsWith("history:socialXp")));
 assert.ok(result.blockers.some(x=>x.startsWith("history:coins")));
 assert.ok(result.blockers.some(x=>x.startsWith("domain:wallet")));
});
test("POINT4 one-UID proof does not override a missing section",()=>{
 const s=verified();s.scopes.places="unknown";
 const r=inspectEightSectionRestoration(s);
 assert.equal(r.allEightDomainsVerified,false);
 assert.equal(r.fullyRestored,false);
});
test("POINT4 a new UID always HOLDs even with eight displayed sections",()=>{
 const s=verified();s.sameOriginalUid=false;s.createdNewUid=true;
 const r=inspectEightSectionRestoration(s);
 assert.equal(r.fullyRestored,false);
 assert.ok(r.blockers.includes("same-original-uid"));
});
test("POINT4 no independent proof or single-session: HOLD",()=>{
 const s=verified();s.ownerIndependentlyVerified=false;
 s.singleAuthSession=false;
 const r=inspectEightSectionRestoration(s);
 assert.equal(r.fullyRestored,false);
 assert.ok(r.blockers.includes("independent-owner-proof"));
 assert.ok(r.blockers.includes("one-auth-session"));
});
test("POINT4 complete hypothetical synthetic evidence has no credit authority",()=>{
 const r=inspectEightSectionRestoration(verified());
 assert.equal(r.allEightDomainsVerified,true);
 assert.equal(r.fullyRestored,true);
 assert.equal(r.financialRestoreAuthorized,false);
 assert.equal(r.modifiesUid,false);
 assert.equal(r.creditsAnything,false);
});
test("POINT4 unknown empty snapshot cannot accidentally pass",()=>{
 const r=inspectEightSectionRestoration({});
 assert.equal(r.fullyRestored,false);
 assert.ok(r.blockers.length>=16);
});
