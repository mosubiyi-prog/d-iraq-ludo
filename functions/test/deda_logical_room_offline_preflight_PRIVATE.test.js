"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {inspectRoomCandidate, DOMAIN_SOURCES} =
  require("../deda_logical_room_offline_preflight_PRIVATE_NOT_EXPORTED.js");
const accountKey = "07700000000", originalId = "@DEDA-ABC123";
const A = "fixture-original-owner-A";
const B = "fixture-registration-B";
const C = "fixture-social-C";
const D = "fixture-untrusted-D";
const all = Object.keys(DOMAIN_SOURCES);
function snapshot() {
  return {
    accountKey,originalId,
    directory:{accountKey,createdUid:B,active:true},
    credentials:{accountKey,createdUid:B,active:true},
    route:{publicId:originalId,ownerUid:A,kind:"personal",active:true},
    social:{publicId:originalId,ownerUid:C},
    originalUser:{accountKey,sharePersonalId:originalId},
    registeredUser:{accountKey},
    socialUser:{accountKey,sharePersonalId:originalId},
  };
}
const check = (overrides={}) => inspectRoomCandidate({
  snapshot:snapshot(),sessionUid:B,domains:all,...overrides,
});
const forbidden = (result) => {
  for (const key of ["crossUidReadPermitted","crossUidWritePermitted",
    "loginPermitted","createUidPermitted","createTokenPermitted",
    "adminEntryPermitted","financialGrantPermitted"]) {
    assert.equal(result[key],false);
  }
  for (const d of result.domainPlans) {
    assert.equal(d.authorization,"NOT_GRANTED");
    assert.equal(d.sourceWrite,false);
    assert.equal(d.sourceUidReassignment,false);
    assert.equal(d.duplicateReceiptIssuance,false);
  }
};
test("room models full DEDA domains but never authorizes cross-UID reads",()=>{
  const out=check();assert.equal(out.domainPlans.length,all.length);
  assert.equal(out.decision,"HOLD_FOR_INDEPENDENT_PROOF_AND_SERVER_RULES");
  forbidden(out);
});
test("A B C and unexpected D are all denied authorization",()=>{
  for (const uid of [A,B,C,D,null]) forbidden(check({sessionUid:uid}));
  assert.equal(check({sessionUid:D}).sessionKind,"untrusted_current_uid");
});
test("admin access stays entirely separate and false",()=>{
  const x=check({domains:["administration"]});forbidden(x);
  assert.equal(x.domainPlans[0].separateAdminVerification,true);
});
test("wallet, gifts and diamonds never aggregate nor reissue",()=>{
  const x=check({domains:["diamonds","gifts","frames"]});
  forbidden(x);
  assert.equal(x.domainPlans.length,3);
});
test("uid pair friendships cannot become accountKey-only authorization",()=>{
  const x=check({domains:["friends","social_profile"]});
  assert.equal(x.domainPlans[0].historicalSource,
    "uid_pair_memberships_reconcile_individually");forbidden(x);
});
test("caller supplied authorization and custom claims ignored",()=>{
  const s=snapshot();s.superuser=true;s.customClaims={admin:true};
  forbidden(check({snapshot:s,approved:true,independentProof:{verified:true}}));
});
test("no request domains does not confer default read-all",()=>{
  for(const domains of [null,[],["unknown"],["friends","friends"]]) {
    const x=check({domains});assert.equal(x.decision,"HOLD");forbidden(x);
  }
});
test("mismatched registration vs credentials refuses room",()=>{
  const s=snapshot();s.credentials.createdUid=A;
  const x=check({snapshot:s});assert.equal(x.reason,"HISTORICAL_RECORD_CONFLICT");
  forbidden(x);
});
test("foreign account key in social user refuses room",()=>{
  const s=snapshot();s.socialUser.accountKey="07799999999";
  const x=check({snapshot:s});assert.equal(x.decision,"HOLD");forbidden(x);
});
test("foreign account key in each source refuses room",()=>{
  for(const field of ["directory","credentials","originalUser","registeredUser"]) {
    const s=snapshot();s[field].accountKey="07799999999";
    const x=check({snapshot:s});assert.equal(x.decision,"HOLD");forbidden(x);
  }
});
test("original ID mismatch or inactive route refuses room",()=>{
  const s=snapshot();s.route.publicId="@DEDA-BBBBBB";
  forbidden(check({snapshot:s}));
  const q=snapshot();q.route.active=false;forbidden(check({snapshot:q}));
});
test("social profile original ID mismatch refuses room",()=>{
  const s=snapshot();s.social.publicId="@DEDA-BBBBBB";
  const x=check({snapshot:s});assert.equal(x.decision,"HOLD");forbidden(x);
});
test("aligned historical UIDs still do not prove Auth owner",()=>{
  const s=snapshot();s.directory.createdUid=A;s.credentials.createdUid=A;
  s.social.ownerUid=A;
  const x=check({snapshot:s});assert.equal(x.reason,"AUTH_STILL_UNPROVEN");
  forbidden(x);
});
test("no UID names, tokens, PINs or account key leak from room plan",()=>{
  const asJson=JSON.stringify(check());
  for(const secret of [A,B,C,D,accountKey,originalId]) {
    assert.equal(asJson.includes(secret),false);
  }
});
test("invalid snapshot never creates a room mapping",()=>{
  for (const s of [null,{},[],{accountKey:"bad",originalId}]) {
    const x=check({snapshot:s});assert.equal(x.decision,"HOLD");
    forbidden(x);
  }
});
test("dry-run does not modify original source records",()=>{
  const s=snapshot(),before=JSON.stringify(s);
  const x=check({snapshot:s});assert.equal(JSON.stringify(s),before);
  assert.equal(Object.isFrozen(x),true);
  assert.equal(Object.isFrozen(x.domainPlans),true);
  forbidden(x);
});
test("a matching old session alone never enables administration",()=>{
  const x=check({sessionUid:A,domains:["original_id","administration"]});
  assert.equal(x.sessionKind,"historical_uid_seen");forbidden(x);
});
test("PIN and local trusted install claims never change denial",()=>{
  const s=snapshot();s.pin="123456";s.trustedInstallIds=["fake"];
  const x=check({snapshot:s,phone:"07700000000",pin:"123456"});
  assert.equal(x.decision,"HOLD_FOR_INDEPENDENT_PROOF_AND_SERVER_RULES");
  forbidden(x);
});