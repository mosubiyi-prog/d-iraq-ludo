"use strict";
/*
 * DEDA Stage2 TASKS-only Firestore emulator regression test.
 * Synthetic identities and documents, no users' tasks, wallet, credentials,
 * production Firebase, Play, or device build. Original rules are read-only.
 */
const fs = require("node:fs");
const assert = require("node:assert/strict");
const {test} = require("node:test");
const firebase = require("firebase/compat/app");
require("firebase/compat/firestore");
const {
  initializeTestEnvironment, assertSucceeds, assertFails,
} = require("@firebase/rules-unit-testing");

const project = "demo-deda-stage2-isolated-admin-private-qa";
const managerUid = "qa_tasks_manager_20261123";
const staffUid = "qa_tasks_staff_20261123";
const publicUid = "qa_tasks_public_20261123";
const outsiderUid = "qa_tasks_outsider_20261123";
const sent = () => firebase.firestore.FieldValue.serverTimestamp();
const stamp = date => firebase.firestore.Timestamp.fromDate(date);
const clock = () => new Date();
const draft = () => ({
  cycle:"daily",action:"open_map",titleAr:"افتح الخارطة",
  titleEn:"Open the map",targetCount:1,rewardUnit:"points",
  rewardAmount:5,url:"",status:"draft",revision:1,
  createdByUid:managerUid,updatedByUid:managerUid,
  createdAt:sent(),updatedAt:sent(),
});

test("STAGE2 TASKS: original rules, isolated admin, nonpaying paths", {
  timeout:180000,
}, async t => {
  assert.equal(process.env.DEDA_EMULATOR_ONLY,"true");
  assert.equal(process.env.FIRESTORE_EMULATOR_HOST,"127.0.0.1:8097");
  const env=await initializeTestEnvironment({
    projectId:project,
    firestore:{rules:fs.readFileSync("firestore.rules","utf8"),
      host:"127.0.0.1",port:8097},
  });
  const manager=env.authenticatedContext(managerUid).firestore();
  const staff=env.authenticatedContext(staffUid).firestore();
  const publicDb=env.authenticatedContext(publicUid).firestore();
  const outsider=env.authenticatedContext(outsiderUid).firestore();
  const draftRef=manager.doc("admin_task_drafts/daily_open_map");
  const previewRef=manager.doc("admin_daily_schedule_previews/preview_open_map");
  const socialRef=manager.doc("deda_social_direct_drafts/featured");

  try {
    await env.withSecurityRulesDisabled(async ctx => {
      const db=ctx.firestore();
      await Promise.all([
        db.doc("admins/"+managerUid).set({
          active:true,status:"active",role:"general_manager",
        }),
        db.doc("admins/"+staffUid).set({
          active:true,status:"active",role:"employee",
          permissions:{viewTeam:true},
        }),
        db.doc("users/"+publicUid).set({
          accountKey:"9647712345788",name:"QA public user",
        }),
      ]);
    });

    await t.test("only manager may see or write private task drafts", async () => {
      await assertSucceeds(manager.collection("admin_task_drafts").get());
      await assertFails(staff.collection("admin_task_drafts").get());
      await assertFails(publicDb.doc(draftRef.path).get());
      await assertFails(outsider.doc(draftRef.path).set(draft()));
      await assertFails(staff.doc(draftRef.path).set(draft()));
      await assertSucceeds(draftRef.set(draft()));
      await assertFails(draftRef.update({
        rewardAmount:6000,revision:2,
        updatedByUid:managerUid,updatedAt:sent(),
      }));
      await assertFails(draftRef.update({
        rewardAmount:5,revision:3,
        updatedByUid:managerUid,updatedAt:sent(),
      }));
      await assertSucceeds(draftRef.update({
        titleAr:"افتح الخارطة يومياً",revision:2,
        updatedByUid:managerUid,updatedAt:sent(),
      }));
      await assertFails(draftRef.delete());
    });

    await t.test("private schedule preview can be prepared and cancelled without publishing", async () => {
      const future=stamp(new Date(Date.now()+8*3600000));
      const preview={
        slotId:"open_map",action:"open_map",titleAr:"افتح الخارطة",
        titleEn:"افتح الخارطة",targetCount:1,rewardUnit:"points",
        rewardAmount:5,url:"",status:"pending",revision:1,
        effectiveAt:future,createdByUid:managerUid,updatedByUid:managerUid,
        createdAt:sent(),updatedAt:sent(),
      };
      await assertFails(staff.doc(previewRef.path).set(preview));
      await assertSucceeds(previewRef.set(preview));
      await assertFails(publicDb.doc(previewRef.path).get());
      await assertFails(staff.doc(previewRef.path).get());
      await assertFails(manager.doc("deda_daily_published_task_slots/open_map")
        .set({action:"open_map",rewardAmount:9999}));
      await assertSucceeds(previewRef.update({
        status:"cancelled",revision:2,
        updatedByUid:managerUid,updatedAt:sent(),
      }));
      await assertFails(previewRef.delete());
      assert.equal((await previewRef.get()).data().status,"cancelled");
    });

    await t.test("Telegram-only draft: no claim, no rewards, no non-admin writes", async () => {
      const data={
        platform:"telegram",action:"follow",title:"متابعة قناة اختبار",
        url:"https://t.me/DEDA_QA_TEST_2026",
        rewardUnit:"diamonds",rewardAmount:10,
        doubleWithRewardedAd:false,
        otherPlatform:"",otherAction:"",rewardsEnabled:false,
        status:"draft",revision:1,scheduledDay:"",activateAt:null,
        createdByUid:managerUid,createdAt:sent(),
        updatedByUid:managerUid,updatedAt:sent(),
      };
      await assertFails(publicDb.doc(socialRef.path).get());
      await assertFails(staff.doc(socialRef.path).set(data));
      await assertFails(socialRef.set({...data,rewardsEnabled:true}));
      await assertFails(socialRef.set({...data,platform:"instagram"}));
      await assertSucceeds(socialRef.set(data));

      const date=new Date(Date.UTC(clock().getUTCFullYear(),
        clock().getUTCMonth(),clock().getUTCDate()+5));
      const dayId=date.toISOString().slice(0,10);
      const at=stamp(new Date(date.getTime()-3*3600000));
      const dayRef=manager.doc("deda_social_direct_days/"+dayId);
      await assertFails(publicDb.doc(dayRef.path).get());
      await assertSucceeds(manager.runTransaction(async tx=>{
        const snap=await tx.get(socialRef);
        assert.equal(snap.data().revision,1);
        tx.update(socialRef,{
          status:"scheduled",revision:2,scheduledDay:dayId,activateAt:at,
          updatedByUid:managerUid,updatedAt:sent(),
        });
        tx.set(dayRef,{
          dayId,year:date.getUTCFullYear(),month:date.getUTCMonth()+1,
          day:date.getUTCDate(),activateAt:at,status:"scheduled",
          revision:1,platform:"telegram",action:"follow",
          title:data.title,url:data.url,rewardUnit:data.rewardUnit,
          rewardAmount:10,doubleWithRewardedAd:false,
          rewardsEnabled:false,
          rewardClaimMode:"blocked-until-trusted-proof-and-ssv-ledger",
          createdByUid:managerUid,updatedByUid:managerUid,
          createdAt:sent(),updatedAt:sent(),
        });
      }));
      assert.equal((await dayRef.get()).data().rewardsEnabled,false);
      await assertFails(dayRef.update({
        rewardsEnabled:true,revision:2,updatedByUid:managerUid,
        updatedAt:sent(),
      }));
      await assertSucceeds(manager.runTransaction(async tx=>{
        const a=await tx.get(socialRef);
        const d=await tx.get(dayRef);
        assert.equal(a.data().revision,2);
        assert.equal(d.data().status,"scheduled");
        tx.update(socialRef,{
          status:"cancelled",revision:3,
          updatedByUid:managerUid,updatedAt:sent(),
        });
        tx.update(dayRef,{
          status:"cancelled",revision:2,
          updatedByUid:managerUid,updatedAt:sent(),
        });
      }));
      await env.withSecurityRulesDisabled(async ctx=>{
        const db=ctx.firestore();
        assert.equal((await db.doc(dayRef.path).get()).data().status,"cancelled");
        assert.equal((await db.collection("deda_diamond_gifts").get()).empty,true);
        assert.equal((await db.collection("deda_weekly_direct_admin_events").get()).empty,true);
      });
    });
  } finally {
    await env.cleanup();
  }
});
