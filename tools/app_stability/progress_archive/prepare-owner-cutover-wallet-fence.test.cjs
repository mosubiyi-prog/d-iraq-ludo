"use strict";
const test=require("node:test");
const assert=require("node:assert/strict");
const fs=require("node:fs");
const path=require("node:path");
const {prepareCutoverWalletFenceRules:prepare}=
  require("./prepare-owner-cutover-wallet-fence.cjs");
const original=fs.readFileSync(
  path.join(__dirname,"../../../firestore.rules"),"utf8");
function block(s,marker) {
 const start=s.indexOf(marker);
 assert.ok(start>0,"path missing: "+marker);
 const end=s.indexOf("\n    match /",start+marker.length);
 assert.ok(end>start);
 return s.slice(start,end);
}
test("01 original DEDA 100342 rules untouched; candidate is generated in memory only",()=>{
 const after=prepare(original);
 assert.notEqual(after,original);
 assert.ok(after.includes("DEDA_NEW_PHONE_WALLET_WRITER_CUTOVER_CANDIDATE"));
 assert.equal(original.includes("DEDA_NEW_PHONE_WALLET_WRITER_CUTOVER_CANDIDATE"),false);
 assert.equal(fs.readFileSync(path.join(__dirname,"../../../firestore.rules"),"utf8"),original);
});
test("02 cutover records reject all client read/create/update/delete writes",()=>{
 const after=prepare(original);
 const gate=block(after,"match /deda_migration_spend_authority/{publicId}");
 assert.match(gate,/allow read, write: if false;/);
 assert.equal(gate.includes("allow create"),false);
});
test("03 wallet debit/credit and 13-frame receipt + owner writes always check holder",()=>{
 const after=prepare(original);
 for(const marker of [
   "match /deda_lab_frame_receipts/{publicId}/frames/{frameId}",
   "match /deda_lab_owned_frames/{publicId}/frames/{frameId}",
   "match /deda_diamond_gift_balances/{publicId}",
 ]){
   const rules=block(after,marker);
   assert.match(rules,/dedaCutoverWalletWriterAllowed\(publicId\)/);
   const expected=marker.includes("gift_balances")?2:1;
   assert.equal((rules.match(/dedaCutoverWalletWriterAllowed\(publicId\)/g)||[]).length,expected);
 }
 const gifts=block(after,"match /deda_diamond_gifts/{giftId}");
 assert.match(gifts,/dedaCutoverWalletWriterAllowed\(resource.data.targetPublicId\)/);
});
test("04 helper is keyed by original public ID and returns denied for mismatched active UID",()=>{
 const after=prepare(original);
 assert.match(after,/deda_migration_spend_authority\/\$\(publicId\)/);
 assert.match(after,/get\(path\)\.data\.activeUid == request\.auth\.uid/);
 assert.match(after,/get\(path\)\.data\.originalUid != request\.auth\.uid/);
 assert.match(after,/get\(path\)\.data\.status == 'new-device-exclusive'/);
 assert.match(after,/get\(path\)\.data\.protocol == 'deda-verified-progress-v1'/);
 assert.match(after,/return !exists\(path\) \|\| \(/);
});
test("06 stale old UID cannot mutate profile, session or manager personal wallet after cutover",()=>{
 const rules=prepare(original);
 const privateAccount=block(rules,"match /deda_migration_account_authority/{accountKey}");
 assert.match(privateAccount,/allow read, write: if false/);
 assert.match(rules,/deda_migration_account_authority\/\$\(accountKey\)/);
 assert.match(rules,/get\(path\)\.data\.activeUid == request\.auth\.uid/);
 const gm=block(rules,"match /deda_gm_personal_diamond_wallets/{accountKey}");
 assert.equal((gm.match(/dedaCutoverAccountWriterAllowed\(accountKey\)/g)||[]).length,2);
 const users=block(rules,"match /users/{uid}");
 assert.match(users,/dedaCutoverAccountWriterAllowed\(request.resource.data.accountKey\)/);
 assert.match(users,/dedaCutoverAccountWriterAllowed\(resource.data.accountKey\)/);
 const sessions=block(rules,"match /deda_sessions/{uid}");
 assert.match(sessions,/dedaCutoverAccountWriterAllowed\(request.resource.data.accountKey\)/);
});
test("05 force reevaluation when root permissions or source anchors change",()=>{
 const edited=original.replace(
   "allow update: if verifiedDiamondsPersonalOwner(publicId)",
   "allow update: if signedIn()");
 assert.throws(()=>prepare(edited),/ANCHOR_DRIFT/);
 assert.throws(()=>prepare("rules_version = '2';"),/BASELINE_REFUSED/);
 assert.throws(()=>prepare(prepare(original)),/BASELINE_REFUSED/);
});
test("07 old-phone original ID, account profile and session deletion paths are fenced",()=>{
 const candidate=prepare(original);
 const share=block(candidate,"match /deda_share_ids/{publicId}");
 assert.equal((share.match(/dedaCutoverWalletWriterAllowed\(publicId\)/g)||[]).length,1);
 const profile=block(candidate,"match /deda_account_profiles/{accountKey}");
 assert.equal((profile.match(/dedaCutoverAccountWriterAllowed\(accountKey\)/g)||[]).length,2);
 assert.match(profile,/allow update: if dedaCutoverAccountWriterAllowed\(accountKey\)/);
 const session=block(candidate,"match /deda_sessions/{uid}");
 assert.match(session,/allow delete: if signedIn\(\) && request\.auth\.uid == uid\s+&& dedaCutoverAccountWriterAllowed\(resource\.data\.accountKey\)/);
});
