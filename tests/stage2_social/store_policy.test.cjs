"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const service = require("../../functions/deda_social_task_stage2_store.js");

class FakeFirestore {
  constructor() { this.values=new Map(); this.counter=0; }
  collection(name) {
    const self=this;
    return {
      doc(id) {
        const key=name+"/"+(id||("auto-"+(++self.counter)));
        return {id:key.split("/").at(-1),key,
          get:async()=>self._snap(key)};
      },
      where(field,operator,value) {
        if (operator!=="==") throw Error("unsupported-test-query");
        return {limit(max) {return {get:async()=>({
          docs:[...self.values.entries()].filter(([k,v])=>
            k.startsWith(name+"/")&&v[field]===value)
            .slice(0,max).map(([k,v])=>({
              id:k.split("/").at(-1),data:()=>structuredClone(v),
            })),
        })};}};
      },
    };
  }
  _snap(key) {
    const v=this.values.get(key);
    return {exists:!!v,data:()=>v&&structuredClone(v)};
  }
  async runTransaction(task) {
    const pending=[];
    const tx={
      get:async ref=>this._snap(ref.key),
      set:(ref,value)=>pending.push(["set",ref.key,value]),
      update:(ref,value)=>pending.push(["update",ref.key,value]),
      create:(ref,value)=>pending.push(["create",ref.key,value]),
    };
    const result=await task(tx);
    for(const [action,key,value] of pending) {
      if(action==="create" && this.values.has(key)) {
        throw Error("already-exists");
      }
      if(action==="update" && !this.values.has(key)) {
        throw Error("not-found");
      }
      this.values.set(key,structuredClone({
        ...(action==="update"?this.values.get(key):{}),...value,
      }));
    }
    return result;
  }
}
const manager = {uid:"gm"};
const now = new Date("2026-10-09T14:00:00Z");
const template = {
  platform:"telegram", action:"follow",
  title:"تابع قناة الدليل الدقيق",url:"https://t.me/DEDA_Iraq",
  rewardUnit:"coins",rewardAmount:25,doubleWithRewardedAd:true,
};
function database() {
  const db=new FakeFirestore();
  db.values.set("admins/gm",{role:"general_manager",active:true,status:"active"});
  db.values.set("admins/employee",{role:"employee",active:true,status:"active"});
  return db;
}
function useDemo() {
  process.env.FIRESTORE_EMULATOR_HOST="127.0.0.1:8080";
  process.env.GCLOUD_PROJECT=service.DEMO_PROJECT;
}
test("all persistent functions are HARD BLOCKED on production", async()=>{
  const oldHost=process.env.FIRESTORE_EMULATOR_HOST;
  const oldProject=process.env.GCLOUD_PROJECT;
  delete process.env.FIRESTORE_EMULATOR_HOST;
  process.env.GCLOUD_PROJECT="deda-real-project";
  await assert.rejects(service.save(database(),{
    ...manager,taskId:"s1",draft:template,expectedRevision:0,now,
  }),/SOCIAL_STAGE2_EMULATOR_ONLY_NO_PRODUCTION/);
  process.env.FIRESTORE_EMULATOR_HOST=oldHost||"";
  process.env.GCLOUD_PROJECT=oldProject||"";
});
test("only authenticated current GM can create drafts", async()=>{
  useDemo();
  const db=database();
  await assert.rejects(service.save(db,{
    authUid:"employee",taskId:"s1",draft:template,
    expectedRevision:0,now,
  }),/general-manager-server-verification-required/);
  await assert.rejects(service.save(db,{
    authUid:"spoofed",taskId:"s1",draft:template,
    expectedRevision:0,now,
  }),/general-manager-server-verification-required/);
  const saved=await service.save(db,{
    authUid:"gm",taskId:"s1",draft:template,expectedRevision:0,now,
  });
  assert.equal(saved.revision,1);
  assert.equal(saved.rewardUnit,"coins");
  assert.equal(saved.doubleWithRewardedAd,true);
  assert.equal(saved.rewardsEnabled,false);
  await assert.rejects(service.save(db,{
    authUid:"gm",taskId:"s1",draft:template,expectedRevision:0,now,
  }),/revision-conflict/);
});
test("schedule cancel and publisher maintain no-pay staging boundary",async()=>{
  useDemo();const db=database();
  const draft=await service.save(db,{
    authUid:"gm",taskId:"s2",draft:template,expectedRevision:0,now,
  });
  const scheduled=await service.schedule(db,{
    authUid:"gm",taskId:"s2",expectedRevision:draft.revision,
    day:"2026-10-10",now,
  });
  assert.equal(scheduled.effectiveAtUtc,"2026-10-09T21:00:00.000Z");
  assert.deepEqual(await service.publishDue(db,{
    now:new Date("2026-10-09T20:59:59Z"),
  }),[{taskId:"s2",outcome:"not-due"}]);
  const cancelled=await service.cancel(db,{
    authUid:"gm",taskId:"s2",expectedRevision:scheduled.revision,
    now:new Date("2026-10-09T20:59:59Z"),
  });
  assert.equal(cancelled.status,"cancelled");
  assert.deepEqual(await service.publishDue(db,{
    now:new Date("2026-10-09T21:00:01Z"),
  }),[]);
  assert.equal(db.values.has(service.PUBLISHED+"/s2"),false);
});
test("midnight publishes configuration once, not rewards or balances",async()=>{
  useDemo();const db=database();
  const saved=await service.save(db,{
    authUid:"gm",taskId:"s3",draft:template,expectedRevision:0,now,
  });
  await service.schedule(db,{
    authUid:"gm",taskId:"s3",expectedRevision:saved.revision,
    day:"2026-10-10",now,
  });
  const at=new Date("2026-10-09T21:00:01Z");
  assert.deepEqual(await service.publishDue(db,{now:at}),
      [{taskId:"s3",outcome:"published-config-only"}]);
  assert.deepEqual(await service.publishDue(db,{now:at}),[]);
  const row=db.values.get(service.PUBLISHED+"/s3");
  assert.equal(row.shadowOnly,true);
  assert.equal(row.rewardsEnabled,false);
  assert.equal(row.rewardClaimMode,"disabled");
  assert.equal([...db.values.keys()].some(k=>
    /wallet|balance|ledger|credential/i.test(k)),false);
  const count=[...db.values.keys()].filter(k=>
    k.startsWith(service.AUDIT+"/")).length;
  assert.equal(count,3);
  await assert.rejects(service.cancel(db,{
    authUid:"gm",taskId:"s3",expectedRevision:row.revision,now:at,
  }),/not-scheduled/);
});
