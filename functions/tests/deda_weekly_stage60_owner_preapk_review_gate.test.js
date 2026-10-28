"use strict";
const test=require("node:test"),assert=require("node:assert/strict");
const fs=require("node:fs"),path=require("node:path");
const {verify,ids,blocked,statuses}=require(
 "../../tools/app_stability/stage60/owner_preapk_review_gate.cjs");
const root=path.resolve(__dirname,"../..");
const original=JSON.parse(fs.readFileSync(path.join(
 root,"tools/app_stability/stage60/owner_preapk_review_manifest.json"),"utf8"));
const change=fn=>{const x=structuredClone(original);fn(x);return x;};
const byId=(m,id)=>m.items.find(x=>x.id===id);
const fail=(m,expected)=>assert.throws(()=>verify(m,{base:root}),expected);
test("01: comprehensive Stage60 owner inventory validates against ORIGINAL 33 requirement groups",()=>{
 const x=verify(original,{base:root});
 assert.equal(x.manifestValidated,true);assert.equal(x.featuresReviewed,33);
});
test("02: every approved requirement id has exactly one item",()=>{
 assert.equal(ids.length,33);
 assert.deepEqual(new Set(ids),new Set(original.items.map(x=>x.id)));
});
test("03: status totals distinguish SOURCE ONLY, QA, PHONE PARTIAL, UNVERIFIED and HOLD",()=>{
 const x=verify(original,{base:root});
 assert.deepEqual(x.sourceEvidenceCategories,{
  NOT_YET_VERIFIED_LIVE:18,
  IMPLEMENTED_IN_SOURCE_ONLY:6,
  QA_MODEL_ONLY:6,
  PARTIAL_PHONE_EVIDENCE:2,
  SAFETY_HOLD:1
 });
});
test("04: no owner approval or APK/AAB authorization inferred from passing report audit",()=>{
 const x=verify(original,{base:root});
 assert.equal(x.ownerApproved,false);assert.equal(x.apkBuildAuthorized,false);
 assert.equal(x.releaseReady,false);assert.equal(x.ownerReviewRequired,true);
});
test("05: original phone-tested baseline 100342 must remain protected",()=>{
 const x=verify(original,{base:root});assert.equal(x.referenceBuild,100342);
});
test("06: drop one requirement fails rather than treating incomplete report as complete",()=>{
 fail(change(x=>x.items.pop()),/INCOMPLETE_OWNER_SCOPE/);
});
test("07: same requirement listed twice cannot hide an omitted one",()=>{
 fail(change(x=>x.items[0]=x.items[1]),/DUPLICATE_OR_MISSING_OWNER_REQUIREMENT/);
});
test("08: invalid false COMPLETED state of unreleased weekly gifts must stop",()=>{
 fail(change(x=>byId(x,"L08").status="IMPLEMENTED_IN_SOURCE_ONLY"),
  /BLOCKER_INCORRECTLY_DECLARED_COMPLETE/);
});
test("09: invalid claim that 100 distinct questions are complete stops",()=>{
 fail(change(x=>byId(x,"T02").status="IMPLEMENTED_IN_SOURCE_ONLY"),
  /BLOCKER_INCORRECTLY_DECLARED_COMPLETE/);
});
test("10: invalid claim that existing quiz has exactly 3 choices stops",()=>{
 fail(change(x=>byId(x,"T03").status="IMPLEMENTED_IN_SOURCE_ONLY"),
  /BLOCKER_INCORRECTLY_DECLARED_COMPLETE/);
});
test("11: misplaced nonexistent source evidence cannot verify owner requirement",()=>{
 fail(change(x=>byId(x,"F01").evidence="lib/fictional_16_frames_sale.dart"),
  /MISSING_SOURCE/);
});
test("12: traversal path or absolute location cannot enter owner manifest",()=>{
 fail(change(x=>byId(x,"I01").evidence="../private_wallets"),
  /BAD_OR_INCOMPLETE_REQUIREMENT/);
});
test("13: project has no real phone/tablet acceptance at this Stage60 branch",()=>{
 const x=verify(original,{base:root});
 assert.equal(x.phonesTabletsNotRetested,true);
 assert.equal(original.installedApkCompared,false);
 assert.equal(original.deviceQAAccepted,false);
});
test("14: no real cross-phone wallet transfer/ID recovery/roll back claimed",()=>{
 const x=verify(original,{base:root});
 assert.equal(x.historicalWalletNotMigrated,true);
 assert.equal(original.crossDeviceTransferReady,false);
 assert.equal(byId(original,"A01").status,"QA_MODEL_ONLY");
});
test("15: reward numbers are presentation only and weekly gifts are not spendable",()=>{
 const x=verify(original,{base:root});
 assert.equal(x.weeklyGiftsNotSpendable,true);
 assert.equal(original.weeklyProductionPayoutReady,false);
 assert.equal(byId(original,"L07").status,"IMPLEMENTED_IN_SOURCE_ONLY");
 assert.equal(byId(original,"L08").status,"QA_MODEL_ONLY");
});
test("16: daily traffic quiz in original source remains 20 base × 5 variants, with 4 choices",()=>{
 const x=verify(original,{base:root});
 assert.equal(x.quizRequiresDistinct100ThreeAnswers,true);
 assert.equal(byId(original,"T01").status,"IMPLEMENTED_IN_SOURCE_ONLY");
 assert.equal(byId(original,"T02").status,"NOT_YET_VERIFIED_LIVE");
 assert.equal(byId(original,"T03").status,"NOT_YET_VERIFIED_LIVE");
});
test("17: original Stage59 confirms absent real weekly user route/verified reader",()=>{
 const x=verify(original,{base:root});
 assert.equal(x.stage59OriginalFilesChecked,18);
 assert.equal(x.stage59FeatureGapsReviewed,19);
 assert.equal(byId(original,"L01").status,"NOT_YET_VERIFIED_LIVE");
});
test("18: admin league may have SOURCE tile while control remains disabled",()=>{
 assert.equal(byId(original,"L10").status,"IMPLEMENTED_IN_SOURCE_ONLY");
 assert.equal(byId(original,"L11").status,"NOT_YET_VERIFIED_LIVE");
});
test("19: all four ID/foil stock + shop + original ID projection problems remain separated",()=>{
 for(const id of ["I01","I02","I03","I04","I05","I06","P01"])
  assert.ok(byId(original,id).limitation.length>15);
 assert.equal(byId(original,"I03").status,"NOT_YET_VERIFIED_LIVE");
});
test("20: GM 1M personal/admin refill cannot silently be marked verified spendable",()=>{
 assert.equal(byId(original,"G01").status,"NOT_YET_VERIFIED_LIVE");
 assert.equal(original.realWalletWritesAuthorized,false);
});
test("21: protect original phone source and production Firebase/Play deployment",()=>{
 assert.equal(byId(original,"R02").status,"SAFETY_HOLD");
 assert.equal(original.playPublishAuthorized,false);
 assert.equal(original.productionFirebaseDeployAuthorized,false);
});
test("22: removing any required description is rejected by report completeness check",()=>{
 fail(change(x=>byId(x,"L01").requirement="short"),/BAD_OR_INCOMPLETE_REQUIREMENT/);
});
test("23: creating invented release-ready status is rejected",()=>{
 fail(change(x=>byId(x,"L11").status="LIVE_READY"),/BAD_OR_INCOMPLETE_REQUIREMENT/);
});
test("24: changing source commit without actual re-audit cannot inherit old approval",()=>{
 fail(change(x=>x.sourceCommit="fake-commit"),/WRONG_GITHUB_SOURCE_BASELINE/);
});
test("25: illegal owner/build authorization cannot be injected by changing only manifest flags",()=>{
 for(const key of [
  "apkBuildAuthorized","playPublishAuthorized","productionFirebaseDeployAuthorized",
  "realWalletWritesAuthorized","deviceQAAccepted",
  "weeklyProductionPayoutReady","crossDeviceTransferReady"
 ]){
  fail(change(x=>x[key]=true),/UNAUTHORIZED_RELEASE_OR_CREDIT/);
 }
});
test("26: explicit user approval gate cannot be accidentally removed",()=>{
 fail(change(x=>x.ownerReviewRequired=false),/MISSING_OWNER_APPROVAL_GATE/);
});
test("27: QA-only Stage58 no-transfers and Stage57 private Auth cannot be called live",()=>{
 assert.equal(byId(original,"A01").status,"QA_MODEL_ONLY");
 assert.equal(byId(original,"A02").status,"QA_MODEL_ONLY");
});
test("28: weekly 06:00 approved artwork and 00:00 freeze remain QA until integrated",()=>{
 assert.equal(byId(original,"L04").status,"QA_MODEL_ONLY");
 assert.equal(byId(original,"L05").status,"QA_MODEL_ONLY");
});
test("29: UI audit includes a standalone approved leaderboard but no live standings",()=>{
 assert.equal(byId(original,"L02").status,"IMPLEMENTED_IN_SOURCE_ONLY");
 assert.equal(byId(original,"L06").status,"NOT_YET_VERIFIED_LIVE");
});
test("30: all 20 hard release blockers are explicitly represented",()=>{
 assert.equal(blocked.length,20);
 assert.equal(new Set(blocked).size,20);
 for(const id of blocked)assert.ok(ids.includes(id));
});
