"use strict";
const test=require("node:test");
const assert=require("node:assert/strict");
const {canonicalMatches}=require("../../../functions/deda_canonical_account_proof_core");

const KEY="07700000000";
const ORIGINAL="@DEDA-AB3C5D";
const OWNER="synthetic_original_uid";
function fixture() {
  return {
    accountKey:KEY,originalId:ORIGINAL,
    directory:{accountKey:KEY,active:true,createdUid:OWNER},
    credential:{accountKey:KEY,active:true,createdUid:OWNER},
    profile:{accountKey:KEY},
    owner:{accountKey:KEY,sharePersonalId:ORIGINAL},
    route:{publicId:ORIGINAL,kind:"personal",active:true,ownerUid:OWNER},
  };
}
test("original public ID from verified creator route matches",()=>{
  assert.equal(canonicalMatches(fixture()),true);
});
const invalid=[
  ["missing immutable original",v=>{delete v.owner.sharePersonalId;}],
  ["premium alias substituted for original",v=>{v.owner.sharePersonalId="@DEDA-ZZ9999";}],
  ["route owner does not match creator",v=>{v.route.ownerUid="different_creator";}],
  ["route inactive/revoked",v=>{v.route.active=false;}],
  ["route kind not personal",v=>{v.route.kind="place";}],
  ["route ID conflicting",v=>{v.route.publicId="@DEDA-ZZ9999";}],
  ["record creator UID inconsistent",v=>{v.credential.createdUid="different_creator";}],
  ["original owner tied to another account",v=>{v.owner.accountKey="07800000000";}],
  ["directory account key differs",v=>{v.directory.accountKey="07800000000";}],
  ["profile account key differs",v=>{v.profile.accountKey="07800000000";}],
  ["credential inactive",v=>{v.credential.active=false;}],
  ["directory inactive",v=>{v.directory.active=false;}],
  ["route originalId conflicts",v=>{v.route.originalId="@DEDA-ZZ9999";}],
  ["non-original format",v=>{v.originalId="@DEDA-TOO-LONG";}],
  ["format aliases remain distinct",v=>{v.accountKey="9647700000000";}],
];
for(const [name,change] of invalid) {
  test("deny "+name,()=>{
    const v=fixture();change(v);
    assert.equal(canonicalMatches(v),false);
  });
}
