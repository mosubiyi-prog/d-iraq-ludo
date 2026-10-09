import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {before,after,test} from "node:test";
import {initializeTestEnvironment,assertSucceeds,assertFails}
  from "@firebase/rules-unit-testing";
import {doc,getDoc,setDoc,updateDoc,serverTimestamp}
  from "firebase/firestore";

const PROJECT="demo-deda-next-manager-automations";
let env,gm,member,other;
const setting=(db,id)=>doc(db,"deda_automation_settings",id);
const status=(db,id)=>doc(db,"deda_automation_status",id);
const initial=(enabled=false)=>({
  enabled,enabledAt:enabled?serverTimestamp():null,
  revision:1,updatedAt:serverTimestamp(),changedByUid:"gm",
});
before(async()=>{
  assert.equal(process.env.FIRESTORE_EMULATOR_HOST ? PROJECT : "",
    PROJECT,"test must use emulator only");
  assert.equal(process.env.GCLOUD_PROJECT,PROJECT);
  env=await initializeTestEnvironment({
    projectId:PROJECT,firestore:{rules:readFileSync("firestore.rules","utf8")},
  });
  await env.withSecurityRulesDisabled(async ctx=>{
    await setDoc(doc(ctx.firestore(),"admins","gm"),{
      role:"general_manager",active:true,status:"active",
    });
    await setDoc(doc(ctx.firestore(),"admins","staff"),{
      role:"employee",active:true,status:"active",
    });
  });
  gm=env.authenticatedContext("gm").firestore();
  member=env.authenticatedContext("member").firestore();
  other=env.authenticatedContext("staff").firestore();
});
after(async()=>{if(env)await env.cleanup();});

test("manager can create OFF switches, no non-manager can read or edit",async()=>{
  for(const id of ["place_auto_approval","pin_auto_recovery"]) {
    await assertSucceeds(setDoc(setting(gm,id),initial()));
    await assertSucceeds(getDoc(setting(gm,id)));
    for(const db of [member,other]) {
      await assertFails(getDoc(setting(db,id)));
      await assertFails(setDoc(setting(db,id),initial()));
    }
  }
});
test("even manager CANNOT switch ON before trusted backend readiness",async()=>{
  await assertFails(updateDoc(setting(gm,"place_auto_approval"),{
    enabled:true,enabledAt:serverTimestamp(),revision:2,
    updatedAt:serverTimestamp(),changedByUid:"gm",
  }));
  await assertFails(setDoc(status(gm,"place_auto_approval"),{ready:true}));
  await assertFails(setDoc(setting(gm,"unexpected"),initial()));
});
test("Admin SDK sets readiness, manager can switch ON and back OFF",async()=>{
  await env.withSecurityRulesDisabled(async ctx=>{
    await setDoc(status(ctx.firestore(),"place_auto_approval"),{ready:true});
  });
  await assertSucceeds(updateDoc(setting(gm,"place_auto_approval"),{
    enabled:true,enabledAt:serverTimestamp(),revision:2,
    updatedAt:serverTimestamp(),changedByUid:"gm",
  }));
  await assertSucceeds(updateDoc(setting(gm,"place_auto_approval"),{
    enabled:false,enabledAt:null,revision:3,
    updatedAt:serverTimestamp(),changedByUid:"gm",
  }));
  assert.equal((await getDoc(setting(gm,"place_auto_approval"))).data().enabled,false);
});
test("clients cannot inject payout fields, bypass revision or impersonate actor",async()=>{
  for(const change of [
    {enabled:true,revision:4,changedByUid:"staff",enabledAt:serverTimestamp(),
      updatedAt:serverTimestamp()},
    {enabled:true,revision:99,changedByUid:"gm",enabledAt:serverTimestamp(),
      updatedAt:serverTimestamp()},
    {enabled:true,revision:4,changedByUid:"gm",enabledAt:serverTimestamp(),
      updatedAt:serverTimestamp(),unsafeReward:1000000},
  ]) await assertFails(updateDoc(setting(gm,"place_auto_approval"),change));
});
