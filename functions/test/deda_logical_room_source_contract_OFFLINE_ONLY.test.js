"use strict";
/**
 * DEDA A/B/C source contract: checks real repository code, not mock rights.
 * Only inspects source text. Passing DOES NOT verify server ownership,
 * deployed Firestore rules, login, Firebase Emulator or device functionality.
 * No production code or Firebase access.
 * Local execution: node --test functions/test/deda_logical_room_source_contract_OFFLINE_ONLY.test.js
 */
const test=require("node:test");
const assert=require("node:assert/strict");
const {readFileSync}=require("node:fs");
const {join}=require("node:path");
const get=p=>readFileSync(join(__dirname,"../..",p),"utf8");
const hasAll=(s,arr)=>arr.every(part=>s.includes(part));
const rule=(src,name)=>{
  const marker="match /"+name+" {";
  const start=src.indexOf(marker);
  if(start<0)return "";
  // Rules are nested. End at the next top-level sibling, not end of file.
  const next=src.indexOf("\n    match /",start+marker.length);
  return src.slice(start,next<0?undefined:next);
};
const ID="deda_share_ids/{publicId}";
const OWNER_GUARD="request.resource.data.ownerUid == resource.data.ownerUid";
const FRIEND_PAIR="final pairKey = _pairKey(sender.uid, target.ownerUid);";
test("immutable original route retains registered owner UID",()=>{
  const block=rule(get("firestore.rules"),ID);
  assert.equal(hasAll(block,["match /"+ID+" {",OWNER_GUARD,
    "resource.data.ownerUid == request.auth.uid",
    "allow delete: if false;"]),true);
});
test("PIN directory and credentials are separately keyed to account",()=>{
  const src=get("firestore.rules");
  assert.equal(hasAll(src,["match /deda_credentials/{accountKey} {",
    "match /deda_account_directory/{accountKey} {"]),true);
});
test("friendship queries and pair IDs use immutable UIDs",()=>{
  const src=get("lib/deda_social_service.dart");
  assert.equal(hasAll(src,[".where('members', arrayContains: uid)",
    FRIEND_PAIR,
    "final values = <String>[firstUid, secondUid]..sort();"]),true);
});
test("gift claim still binds recipient and atomic balance change",()=>{
  const src=get("firestore.rules");
  assert.equal(hasAll(src,["function verifiedDiamondsPersonalOwner(publicId) {",
    "match /deda_diamond_gifts/{giftId} {",
    "request.resource.data.giftId == giftId",
    "getAfter(userGiftBalancePath(resource.data.targetPublicId))"]),true);
});
test("weekly league preserves account / week / public ID records",()=>{
  const src=get("firestore.rules");
  assert.equal(hasAll(src,["match /deda_weekly_direct_accounts/{publicId} {",
    "match /deda_weekly_direct_weeks/{weekId}/scores/{publicId} {",
    "deda_weekly_direct_control/active"]),true);
});
test("admin gating remains a separate backend authorization",()=>{
  const src=get("lib/deda_backend.dart");
  assert.equal(hasAll(src,[".collection('admins')",
    "currentDedaAccountCanSeeAdminEntry",
    "currentDedaAccountIsGeneralManager"]),true);
});
test("legacy session-change risk remains; owner pilot is default OFF",()=>{
  const pin=get("lib/deda_pin_auth.dart");
  const flag=get("lib/deda_100431_linked_owner_session_policy.dart");
  assert.equal(hasAll(pin,["await auth.signOut();",
    "auth.signInAnonymously()","dedaLinkedOwnerCompatEnabled"]),true);
  assert.equal(flag.includes("'DEDA_STEP2_LINKED_OWNER_COMPAT', defaultValue: false"),true);
});
test("domain readback paths match original DEDA collections",()=>{
  const src=get("lib/deda_step2_account_domains_recovery_readback.dart");
  assert.equal(hasAll(src,["deda_stage71_active_identifier/$id",
    "deda_weekly_direct_weeks/$week/scores/$id",
    "deda_social_profiles/$id"]),true);
});
test("room modules remain private and never exported from index.js",()=>{
  const index=get("functions/index.js");
  assert.equal(index.includes("deda_logical_room_offline_preflight_PRIVATE_NOT_EXPORTED"),false);
  assert.equal(index.includes("deda_logical_room_domain_readback_OFFLINE_ONLY"),false);
  const core=get("functions/deda_logical_room_offline_preflight_PRIVATE_NOT_EXPORTED.js");
  assert.equal(hasAll(core,["crossUidReadPermitted: false",
    "createTokenPermitted: false","adminEntryPermitted: false"]),true);
  const domains=get("functions/deda_logical_room_domain_readback_OFFLINE_ONLY.js");
  assert.equal(hasAll(domains,["financialGrantPermitted:false",
    "HOLD_FOR_INDEPENDENT_OWNER_PROOF"]),true);
});
test("regression detector fails when real original ID guard is deleted",()=>{
  const original=rule(get("firestore.rules"),ID);
  const corrupted=original.replace(OWNER_GUARD,
    "request.resource.data.ownerUid == request.auth.uid");
  assert.equal(original.includes(OWNER_GUARD),true);
  assert.equal(corrupted.includes(OWNER_GUARD),false);
});
test("regression detector fails when UID friend pair is replaced with alias",()=>{
  const social=get("lib/deda_social_service.dart");
  const mutated=social.replace(FRIEND_PAIR,
    "final pairKey = sender.publicId;");
  assert.equal(social.includes(FRIEND_PAIR),true);
  assert.equal(mutated.includes(FRIEND_PAIR),false);
});
test("repository rule text is not proof of what is deployed in Firebase",()=>{
  const rules=get("firestore.rules");
  assert.equal(rules.includes(
    "This rule set is DEVELOPMENT ONLY until reconciled with LIVE Firebase."),true);
});
