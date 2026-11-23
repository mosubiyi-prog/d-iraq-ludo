"use strict";

const {test} = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const {verifyOriginalOwnerSessionBeforePinApproval: preflight} =
  require("../deda_stage2_original_owner_session_pin_preflight_private_2026_11_23.js");

const key = "07712345678";
const uid = "original-owner-uid";
const requestId = "recovery-review-2026";
const email = `${key}@deda-login.invalid`;
const nowMs = 1795450000000;
const stamp = {toMillis: () => nowMs};
function fixture() {
  const docs = new Map([
    [`recovery_requests/${requestId}`, {
      status: "review", accountKey: key, requesterUid: uid,
    }],
    [`deda_account_directory/${key}`, {
      active: true, accountKey: key, createdUid: uid, authEmail: email,
    }],
    [`deda_credentials/${key}`, {
      active: true, accountKey: key, createdUid: uid, pin: "123456",
      pinSyncVersion: 1, updatedAt: stamp, pinSyncedAt: stamp,
    }],
    [`users/${uid}`, {accountKey: key, sharePersonalId: "@DEDA-ABC123"}],
  ]);
  const db = {collection: (collection) => ({doc: (id) => ({
    get: async () => {
      const d = docs.get(`${collection}/${id}`);
      return {exists: d !== undefined, data: () => d};
    },
  })})};
  const auth = {
    async verifyIdToken() {
      return {
        uid, email, auth_time: Math.floor(nowMs / 1000) - 60,
        firebase: {sign_in_provider: "password"},
      };
    },
    async getUser(u) {return {uid: u, email, disabled: false};},
  };
  return {docs,db,auth,params:{db,auth,requestId,idToken:"mock-token-not-real",nowMs}};
}
test("existing original UID, recently reauthenticated nonanonymous session and synced sources pass preflight ONLY",async()=>{
  const f = fixture();
  assert.deepEqual(await preflight(f.params), {
    eligible:true,requestId,originalUid:uid,accountKey:key,
  });
  assert.equal(f.docs.get(`deda_credentials/${key}`).pin,"123456");
});
test("replacement-device anonymous/different requester UID cannot be approved from phone and name",async()=>{
  const f=fixture();
  f.docs.get(`recovery_requests/${requestId}`).requesterUid="new-anonymous-device";
  assert.deepEqual(await preflight(f.params),{eligible:false,reason:"owner-proof-unavailable"});
});
test("revoked token and wrong UID are denied identically",async()=>{
  const f=fixture();
  f.auth.verifyIdToken=async()=>{throw Error("revoked");};
  assert.equal((await preflight(f.params)).eligible,false);
  f.auth.verifyIdToken=async()=>({
    uid:"impostor",email,auth_time:Math.floor(nowMs/1000),
    firebase:{sign_in_provider:"password"},
  });
  assert.equal((await preflight(f.params)).eligible,false);
});
test("anonymous auth and stale or future authentication cannot prove original owner",async()=>{
  const f=fixture();
  const base={uid,email,firebase:{sign_in_provider:"password"}};
  for(const decoded of [
    {...base,auth_time:Math.floor(nowMs/1000)-301},
    {...base,auth_time:Math.floor(nowMs/1000)+1},
    {...base,auth_time:Math.floor(nowMs/1000),firebase:{sign_in_provider:"anonymous"}},
  ]) {
    f.auth.verifyIdToken=async()=>decoded;
    assert.equal((await preflight(f.params)).eligible,false);
  }
});
test("unsynchronized legacy PIN, mixed UIDs, or a pending recovery lock block approval",async()=>{
  for (const kind of ["sync","uid","lock"]) {
    const f=fixture();
    if (kind==="sync") f.docs.get(`deda_credentials/${key}`).pinSyncedAt={toMillis:()=>nowMs-1};
    if (kind==="uid") f.docs.get(`deda_credentials/${key}`).createdUid="other-uid";
    if (kind==="lock") f.docs.set(`deda_pin_recovery_locks/${key}`,{requestId});
    assert.equal((await preflight(f.params)).eligible,false,kind);
  }
});
test("role-bearing admin account, missing original profile, unapproved request state are denied",async()=>{
  for(const kind of ["admin","profile","approved","ready"]) {
    const f=fixture();
    if(kind==="admin") f.docs.set(`admins/${uid}`,{role:"general_manager"});
    if(kind==="profile") f.docs.delete(`users/${uid}`);
    if(kind==="approved" || kind==="ready")
      f.docs.get(`recovery_requests/${requestId}`).status=kind;
    assert.equal((await preflight(f.params)).eligible,false,kind);
  }
});
test("private preflight is NOT routed into production; existing worker remains OFF and no new PIN writer introduced",()=>{
  const root=path.join(__dirname,"..");
  const index=fs.readFileSync(path.join(root,"index.js"),"utf8");
  const gate=fs.readFileSync(path.join(root,
    "deda_stage2_original_owner_session_pin_preflight_private_2026_11_23.js"),"utf8");
  assert.match(index,/const dedaPinCompatPilotEnabled = false;/);
  assert.doesNotMatch(index,/require\(["']\.\/deda_stage2_original_owner_session_pin_preflight_private_2026_11_23/);
  assert.doesNotMatch(gate,/updateUser\s*\(|createCustomToken\s*\(|tx\.update\s*\(|\.set\s*\(/);
});
