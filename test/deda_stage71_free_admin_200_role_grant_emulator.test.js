"use strict";
// Stage71 Spark Firestore Rules E2E: GM-only original 100+second 100, exactly
// once free use/gift; same-original-user recognition and no diamond writes.
// Authenticated test identities are synthetic on disposable localhost emulator.
const test=require("node:test");
const assert=require("node:assert/strict");
const {readFileSync}=require("node:fs");
const {resolve}=require("node:path");
const {createRequire}=require("node:module");
const req=createRequire(resolve(__dirname,"../functions/package.json"));
const {initializeTestEnvironment,assertFails,assertSucceeds}=
  req("@firebase/rules-unit-testing");
const {doc,setDoc,getDoc,getDocs,query,collection,where,limit,writeBatch,serverTimestamp}=
  req("firebase/firestore");
const projectId="demo-deda-stage71-free-admin200";
assert.equal(process.env.GCLOUD_PROJECT,projectId);
assert.match(process.env.FIRESTORE_EMULATOR_HOST||"",
  /^(127\.0\.0\.1|localhost):[0-9]{2,5}$/);
const rules=readFileSync("/tmp/deda-stage71-free200-candidate.rules","utf8");
assert.match(rules,/STAGE71_FREE_DUAL_200_ROLE_AND_UNIQUE_GRANT_NO_DEPLOY/);
const manager={uid:"stage71_general_manager",key:"account_manager",
 original:"@DEDA-AAA111"};
const recipient={uid:"stage71_recipient",key:"account_recipient",
 original:"@DEDA-BBB222"};
const other={uid:"stage71_other_user",key:"account_other",
 original:"@DEDA-CCC333"};
const groupOne="@DEDA-A00001",groupTwo="@DEDA-B00001";
const emailManager={uid:"gm_email_admin_only"};
let env;
const catalog=(db,id)=>doc(db,"deda_stage71_admin_catalog",id);
const owned=(db,id)=>doc(db,"deda_stage71_granted_registry",id);
const as=p=>env.authenticatedContext(p.uid).firestore();

async function seed(){
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async ctx=>{
    const db=ctx.firestore(),b=writeBatch(db);
    for(const p of [manager,recipient,other]){
      b.set(doc(db,"users",p.uid),{accountKey:p.key,
        sharePersonalId:p.original});
      b.set(doc(db,"deda_sessions",p.uid),{uid:p.uid,accountKey:p.key});
      b.set(doc(db,"deda_share_ids",p.original),{
        publicId:p.original,ownerUid:p.uid,kind:"personal",active:true});
    }
    b.set(doc(db,"admins",manager.uid),{
      active:true,status:"active",role:"general_manager"});
    b.set(doc(db,"admins",emailManager.uid),{
      active:true,status:"active",role:"general_manager"});
    b.set(doc(db,"admins",other.uid),{
      active:true,status:"active",role:"employee"});
    for(let i=1;i<=100;i++){
      for(const [group,prefix] of [["001","A"],["002","B"]]){
        const id="@DEDA-"+prefix+String(i).padStart(5,"0");
        b.set(catalog(db,id),{
          identifier:id,group,sequence:i,baseColor:"gold",
          status:"available",
        });
      }
    }
    b.set(doc(db,"deda_diamond_gift_balances",manager.original),{
      publicId:manager.original,balance:8743,lastClaimGiftId:"previous",
      createdAt:new Date(),updatedAt:new Date(),
    });
    await b.commit();
  });
}
function grant(db,id,to,kind="gifted",color="gold",issuer=manager.uid){
  const b=writeBatch(db);
  b.update(catalog(db,id),{
    status:kind,recipientOriginalId:to,
    grantedAt:serverTimestamp(),
  });
  b.set(owned(db,id),{
    identifier:id,recipientOriginalId:to,group:id===groupOne?"001":"002",
    baseColor:color,kind,grantedByUid:issuer,
    grantedAt:serverTimestamp(),
  });
  return b.commit();
}
test.before(async()=>{
  env=await initializeTestEnvironment({projectId,
    firestore:{host:"127.0.0.1",port:8080,rules}});
});
test.after(async()=>{if(env)await env.cleanup()});
test.beforeEach(seed);

test("only verified active general manager reads exactly two catalog groups of 100",async()=>{
  const snap=await assertSucceeds(getDocs(query(
    collection(as(manager),"deda_stage71_admin_catalog"),limit(250))));
  assert.equal(snap.docs.length,200);
  assert.equal(snap.docs.filter(d=>d.data().group==="001").length,100);
  assert.equal(snap.docs.filter(d=>d.data().group==="002").length,100);
  await assertFails(getDoc(catalog(as(other),groupOne)));
  await assertFails(getDocs(query(
    collection(as(recipient),"deda_stage71_admin_catalog"),limit(250))));
});
test("GM gifted Group001 identifier is immutable and recipient alone reads ownership",async()=>{
  const db=as(manager);
  await assertSucceeds(grant(db,groupOne,recipient.original));
  const row=(await getDoc(catalog(db,groupOne))).data();
  assert.equal(row.status,"gifted");
  assert.equal(row.baseColor,"gold");
  assert.equal(row.recipientOriginalId,recipient.original);
  assert.equal((await getDoc(owned(as(recipient),groupOne))).data().kind,"gifted");
  await assertFails(getDoc(owned(as(other),groupOne)));
  await assertFails(grant(db,groupOne,other.original));
  assert.equal((await getDoc(catalog(db,groupOne))).data().recipientOriginalId,
    recipient.original);
  assert.equal((await getDoc(doc(db,"deda_diamond_gift_balances",manager.original)))
    .data().balance,8743);
});
test("Group002 free manager self-use only with authenticated own original ID",async()=>{
  await assertSucceeds(grant(as(manager),groupTwo,manager.original,"self_used"));
  assert.equal((await getDoc(owned(as(manager),groupTwo))).data().kind,
    "self_used");
});
test("employee cannot grant, seed catalog or change original fixed color",async()=>{
  const db=as(other),gm=as(manager);
  await assertFails(grant(db,groupTwo,recipient.original));
  await assertFails(setDoc(catalog(db,"@DEDA-FAKE01"),{
    identifier:"@DEDA-FAKE01",group:"002",sequence:100,
    baseColor:"gold",status:"available",
  }));
  await assertFails(grant(gm,groupOne,recipient.original,"gifted","pink"));
});
test("no manager impersonation, duplicate grant or unknown recipient",async()=>{
  const db=as(manager);
  await assertFails(grant(db,groupOne,recipient.original,"self_used"));
  await assertFails(grant(db,groupOne,"@DEDA-QQQQQQ"));
  await assertSucceeds(grant(db,groupOne,recipient.original));
  await assertFails(grant(db,groupOne,recipient.original));
});

test("recipient can activate a granted alias and go back to original, strangers cannot",async()=>{
  await assertSucceeds(grant(as(manager),groupOne,recipient.original));
  const db=as(recipient);
  const path=doc(db,"deda_stage71_active_identifier",recipient.original);
  await assertSucceeds(setDoc(path,{originalId:recipient.original,
    activeId:groupOne,updatedAt:serverTimestamp()}));
  assert.equal((await getDoc(path)).data().activeId,groupOne);
  await assertFails(setDoc(path,{originalId:recipient.original,
    activeId:groupTwo,updatedAt:serverTimestamp()}));
  await assertFails(setDoc(doc(as(other),"deda_stage71_active_identifier",
    recipient.original),{originalId:recipient.original,
    activeId:groupOne,updatedAt:serverTimestamp()}));
  await assertSucceeds(setDoc(path,{originalId:recipient.original,
    activeId:recipient.original,updatedAt:serverTimestamp()}));
  assert.equal((await getDoc(path)).data().activeId,recipient.original);
});


test("GM-only initial import creates a real immutable inventory row; outsiders cannot seed extras",async()=>{
  const gm=as(manager),visitor=as(other);
  const imported="@DEDA-NEW100";
  const payload={identifier:imported,group:"002",sequence:100,
    baseColor:"gold",status:"available"};
  await assertFails(setDoc(catalog(visitor,imported),payload));
  await assertFails(setDoc(catalog(gm,imported),{
    ...payload,baseColor:"pink",
  }));
  await assertSucceeds(setDoc(catalog(gm,imported),payload));
  assert.equal((await getDoc(catalog(gm,imported))).data().status,"available");
  await assertFails(setDoc(catalog(gm,imported),payload));
  await assertFails(setDoc(catalog(gm,manager.original),{
    identifier:manager.original,group:"002",sequence:100,
    baseColor:"gold",status:"available",
  }));
});

test("gifted recipient can query ONLY own 200-ID registry by original ID",async()=>{
  await assertSucceeds(grant(as(manager),groupOne,recipient.original));
  await assertSucceeds(grant(as(manager),groupTwo,other.original));
  const inbox=await assertSucceeds(getDocs(query(
    collection(as(recipient),"deda_stage71_granted_registry"),
    where("recipientOriginalId","==",recipient.original),limit(200)
  )));
  assert.equal(inbox.docs.length,1);
  assert.equal(inbox.docs[0].id,groupOne);
  await assertFails(getDocs(query(
    collection(as(recipient),"deda_stage71_granted_registry"),
    where("recipientOriginalId","==",other.original),limit(200)
  )));
});

test("REAL administration email-only GM can read and give WITHOUT personal phone session",async()=>{
  const gm=as(emailManager);
  const records=await assertSucceeds(getDocs(query(
    collection(gm,"deda_stage71_admin_catalog"),limit(250))));
  assert.equal(records.docs.length,200);
  await assertSucceeds(grant(gm,groupOne,recipient.original,"gifted","gold",emailManager.uid));
  assert.equal((await getDoc(owned(as(recipient),groupOne))).data().grantedByUid,
    emailManager.uid);
  await assertFails(grant(as(other),groupTwo,recipient.original));
});
