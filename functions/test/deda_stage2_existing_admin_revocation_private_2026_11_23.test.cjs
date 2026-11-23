"use strict";
// Tests the ORIGINAL onCall handler under a synthetic local harness.
// No Firebase project, deployment, user account, SDK, or request token.
const {test} = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const source = fs.readFileSync(path.join(__dirname,"..","index.js"),"utf8");
const start = source.indexOf("exports.revokeAdminMemberSessions = onCall(");
const end = source.indexOf("exports.resetAdminTemporaryPassword = onCall(",start);
assert.ok(start > 0 && end > start);
const handlerSource = source.slice(start,end);

function fixture(overrides = {}) {
  const changes = {revokes: [], audits: [], reads: []};
  const actor = {
    uid:"synthetic-manager",
    role:"general_manager",
    data:{role:"general_manager",status:"active",active:true},
  };
  const entry = {
    accountKey:"9647712345690",accessType:"general_manager_gateway",
    allowedRole:"general_manager",status:"active",active:true,
    adminUid:"synthetic-manager",
  };
  const subordinate = {
    role:"employee",active:false,status:"temporarily_stopped",
    displayName:"Synthetic employee",adminId:"DEDA-ADM-QA",
  };
  Object.assign(actor.data,overrides.actor || {});
  Object.assign(entry,overrides.gateway || {});
  Object.assign(subordinate,overrides.target || {});
  const getFirestore = () => ({
    collection: (name) => ({
      doc: (id) => ({
        get: async () => {
          changes.reads.push(name + "/" + id);
          if (name === "admin_entry_access") {
            return {exists:overrides.gatewayMissing !== true,data:()=>entry};
          }
          if (name === "admins") {
            return {exists:overrides.targetMissing !== true,data:()=>subordinate};
          }
          throw Error("unexpected path");
        },
      }),
    }),
  });
  function HttpsError(code,message) {
    const error = new Error(message);error.code = code;return error;
  }
  const sandbox = {
    exports:{},onCall:fn=>fn,
    requireGeneralManager:async()=>actor,
    cleanText:(s,max)=>String(s||"").trim().replace(/\s+/g," ").slice(0,max),
    HttpsError,
    getFirestore,
    getAuth:()=>({
      revokeRefreshTokens:async (uid) => {
        changes.revokes.push(uid);
        if (overrides.failRevoke) throw Error("mock-auth-outage");
      },
    }),
    writeAdminAudit:async(...args)=>{changes.audits.push(args);},
  };
  vm.runInNewContext(handlerSource,sandbox);
  const data={uid:"synthetic-employee",reason:"Synthetic suspension review",
    dedaPhone:"9647712345690",stage2Isolated:true};
  return {handler:sandbox.exports.revokeAdminMemberSessions,
    changes,data,actor,entry,subordinate};
}
test("existing callable revokes exactly target refresh tokens after explicit role, gateway and suspension",async()=>{
  const f=fixture();
  assert.equal((await f.handler({data:f.data})).success,true);
  assert.deepEqual(f.changes.revokes,["synthetic-employee"]);
  assert.equal(f.changes.audits.length,1);
  assert.equal(f.changes.audits[0][1],"admin_sessions_revoked");
});
test("roleless legacy GM record cannot revoke staff sessions",async()=>{
  const f=fixture({actor:{role:"",status:"active",active:true}});
  await assert.rejects(()=>f.handler({data:f.data}),/explicit-active-gm-required/);
  assert.equal(f.changes.revokes.length,0);
});
test("inactive GM cannot trigger existing server callable",async()=>{
  const f=fixture({actor:{status:"temporarily_stopped",active:false}});
  await assert.rejects(()=>f.handler({data:f.data}),/explicit-active-gm-required/);
  assert.equal(f.changes.revokes.length,0);
});
test("wrong, missing and foreign GM phone gateway all fail closed",async()=>{
  for (const options of [
    {gatewayMissing:true},
    {gateway:{adminUid:"other-manager"}},
    {gateway:{allowedRole:"employee"}},
    {gateway:{accessType:"member"}},
    {gateway:{active:false}},
  ]) {
    const f=fixture(options);
    await assert.rejects(()=>f.handler({data:f.data}),/manager-gateway-unverified/);
    assert.equal(f.changes.revokes.length,0);
  }
});
test("stage2 refuses active staff, GM, or already disabled/non-suspended identities",async()=>{
  for (const target of [
    {active:true,status:"active"},
    {role:"general_manager"},
    {role:""},
  ]) {
    const f=fixture({target});
    await assert.rejects(()=>f.handler({data:f.data}),/suspend-bound-subordinate/);
    assert.equal(f.changes.revokes.length,0);
  }
});
test("disabled subordinate also has refresh tokens revoked before removal",async()=>{
  const f=fixture({target:{active:false,status:"disabled"}});
  assert.equal((await f.handler({data:f.data})).success,true);
  assert.deepEqual(f.changes.revokes,["synthetic-employee"]);
});
test("actor cannot revoke self or unknown target; failures never forge audit",async()=>{
  const f=fixture();f.data.uid=f.actor.uid;
  await assert.rejects(()=>f.handler({data:f.data}),/valid-subordinate-required/);
  const m=fixture({targetMissing:true});
  await assert.rejects(()=>m.handler({data:m.data}),/admin-member-not-found/);
  const fail=fixture({failRevoke:true});
  await assert.rejects(()=>fail.handler({data:fail.data}),/mock-auth-outage/);
  assert.equal(fail.changes.audits.length,0);
});
test("legacy GM uid+reason call remains compatible, but with explicit active role",async()=>{
  const f=fixture({target:{active:true,status:"active"}});
  const result=await f.handler({data:{uid:f.data.uid,reason:f.data.reason}});
  assert.equal(result.success,true);
  assert.equal(f.changes.revokes.length,1);
});
test("no second revocation handler, no public auth, no production deployment",()=>{
  assert.equal(source.split("exports.revokeAdminMemberSessions = onCall(").length-1,1);
  assert.ok(handlerSource.includes("await getAuth().revokeRefreshTokens(targetUid)"));
  assert.ok(handlerSource.includes('return {success: true}'));
  assert.doesNotMatch(handlerSource,/deleteUser\(|createUser\(/);
});
