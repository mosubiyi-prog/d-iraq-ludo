"use strict";
const test=require("node:test");
const assert=require("node:assert/strict");
const {createHash}=require("node:crypto");
const {MAX,baghdadDay,refillGMPersonalToMillion:refill,
  refillApprovedAtMidnight:sweep,buildStage56MidnightSchedule:scheduled}=
  require("../tools/deda_owner19_stage56_gm_personal_midnight_refill_PRIVATE_NO_DEPLOY_2026_10_20.js");
const sha=x=>createHash("sha256").update(x).digest("hex");
const uid="valid_UID56",key="gm_personal_acct_56",orig="@DEDA-Z1Y2X3";
const D1=new Date("2026-10-20T20:59:59.999Z"); // Oct 20, 23:59:59 Baghdad
const D2=new Date("2026-10-20T21:00:00.000Z"); // Oct 21, 00:00 Baghdad
const D3=new Date("2026-10-21T21:00:00.000Z"); // Oct 22, 00:00 Baghdad
class Ref{
  constructor(db,p){this.db=db;this.path=p;}
  doc(id){return new Ref(this.db,this.path+"/"+id);}
}
class Db{
  constructor(){this.docs=new Map();this.writes=0;this.queryCount=0;}
  collection(c){
    const db=this;
    return {
      doc(id){return new Ref(db,c+"/"+id);},
      where(field,op,val){
        assert.equal(op,"==");
        const conditions=[[field,val]];
        const q={
          where(other,op2,v2){assert.equal(op2,"==");conditions.push([other,v2]);return q;},
          limit(num){
            return {async get(){
              const docs=[...db.docs.entries()]
                .filter(([path,data])=>path.startsWith(c+"/")&&
                  path.split("/").length===2&&
                  conditions.every(([key,value])=>data[key]===value))
                .slice(0,num).map(([path,data])=>({
                  id:path.split("/")[1],data:()=>structuredClone(data),
                }));
              return {size:docs.length,docs};
            }};
          },
        };
        return q;
      },
    };
  }
  put(path,obj){this.docs.set(path,structuredClone(obj));}
  patch(path,changes){Object.assign(this.docs.get(path),changes);}
  async runTransaction(fn){
    const tx={
      get:async ref=>{
        const value=this.docs.get(ref.path);
        return {exists:value!==undefined,
          data:()=>structuredClone(value)};
      },
      update:(ref,change)=>{
        const before=this.docs.get(ref.path);
        if(!before)throw Error("missing-doc");
        this.docs.set(ref.path,{...before,...structuredClone(change)});
        this.writes++;
      },
      create:()=>{throw Error("refill-cannot-create-any-wallet");},
      set:()=>{throw Error("refill-cannot-create-any-wallet");},
    };
    return fn(tx);
  }
}
const wallet="deda_gm_personal_diamond_wallets/"+key;
const approval="deda_gm_personal_refill_approvals/"+sha(key);
const donation="deda_admin_diamond_wallets/"+key;
function setup({balance=950000,anchor="2026-10-20",last=null}={}){
  const db=new Db();
  db.put("users/"+uid,{accountKey:key,sharePersonalId:orig});
  db.put("deda_sessions/"+uid,{uid,accountKey:key});
  db.put("deda_share_ids/"+orig,{publicId:orig,kind:"personal",
    active:true,ownerUid:uid});
  db.put("admin_entry_access/"+key,{
    accountKey:key,active:true,status:"active",
    allowedRole:"general_manager",
    accessType:"general_manager_gateway"});
  db.put("admins/"+uid,{role:"general_manager",active:true,status:"active"});
  db.put(wallet,{
    accountKey:key,balance,initialBalance:MAX,
    ...(last?{lastDailyRefillBaghdadDay:last}:{}),
  });
  db.put(approval,{accountKey:key,originalId:orig,approved:true,
    ownerApprovedMidnightRefill:true,
    serverAuditedMintProvenance:true,capDiamonds:MAX,
    walletType:"gm_personal_test",status:"active",
    refillAnchorBaghdadDay:anchor,lastVerifiedGmUid:uid});
  db.put(donation,{balance:MAX});
  return db;
}
const run=(db,now=D2)=>refill(db,{uid,now});
test("Baghdad midnight uses Iraq day, not rolling 24h or UTC midnight",()=>{
  assert.equal(baghdadDay(D1),"2026-10-20");
  assert.equal(baghdadDay(D2),"2026-10-21");
  assert.equal(baghdadDay(D3),"2026-10-22");
  assert.equal(baghdadDay(new Date("2026-12-31T21:00:00Z")),"2027-01-01");
  assert.throws(()=>baghdadDay("fake"),e=>e.code==="invalid-argument");
});
test("spend 50,000: 950,000 remains tonight; at 00 Baghdad +50,000",async()=>{
  const db=setup();
  const tonight=await run(db,D1);
  assert.equal(tonight.balance,950000);
  assert.equal(tonight.diamondsRestored,0);
  assert.equal(db.writes,0);
  const after=await run(db,D2);
  assert.equal(after.balance,1000000);
  assert.equal(after.diamondsRestored,50000);
  assert.equal(after.alreadyRefilledToday,false);
  assert.equal(db.docs.get(wallet).lastDailyRefillBaghdadDay,"2026-10-21");
  assert.equal(db.docs.get(donation).balance,1000000);
  assert.equal(db.writes,1);
});
test("multiple logins/retries on same day never refill twice",async()=>{
  const db=setup();
  const first=await run(db,D2);
  assert.equal(first.diamondsRestored,50000);
  db.patch(wallet,{balance:990000}); // a legitimate second spend this day
  const second=await run(db,new Date("2026-10-21T10:00:00Z"));
  assert.equal(second.alreadyRefilledToday,true);
  assert.equal(second.diamondsRestored,0);
  assert.equal(second.balance,990000);
  assert.equal(db.writes,1);
  const next=await run(db,D3);
  assert.equal(next.diamondsRestored,10000);
  assert.equal(next.balance,MAX);
  assert.equal(db.writes,2);
});
test("full million does not mint a diamond, but records this day's marker",async()=>{
  const db=setup({balance:MAX});
  const result=await run(db,D2);
  assert.equal(result.diamondsRestored,0);
  assert.equal(result.balance,MAX);
  assert.equal(db.docs.get(wallet).lastDailyRefillAmount,0);
});
test("late app open refills only once, NOT 1 million for each missed date",async()=>{
  const db=setup({balance:800000});
  const later=await run(db,new Date("2026-10-27T12:00:00Z"));
  assert.equal(later.balance,MAX);
  assert.equal(later.diamondsRestored,200000);
  assert.equal(db.writes,1);
});
test("cannot exceed million, use missing wallet or mint test money",async()=>{
  for(const balance of [-1,1000001,NaN,0.25]){
    const db=setup({balance});
    await assert.rejects(run(db),e=>e.code==="failed-precondition");
    assert.equal(db.writes,0);
  }
  const missing=setup();
  missing.docs.delete(wallet);
  await assert.rejects(run(missing),e=>e.code==="failed-precondition");
  assert.equal(missing.writes,0);
});
test("requires explicit server-only signed source approval and GM role",async()=>{
  const edits=[
    db=>db.docs.delete(approval),
    db=>db.patch(approval,{approved:false}),
    db=>db.patch(approval,{serverAuditedMintProvenance:false}),
    db=>db.patch(approval,{ownerApprovedMidnightRefill:false}),
    db=>db.patch(approval,{capDiamonds:2000000}),
    db=>db.patch(approval,{originalId:"@DEDA-FAKE00"}),
    db=>db.patch(approval,{walletType:"admin_donation_pool"}),
    db=>db.patch("admins/"+uid,{role:"employee"}),
    db=>db.patch("deda_sessions/"+uid,{accountKey:"another"}),
    db=>db.patch("deda_share_ids/"+orig,{ownerUid:"intruder"}),
    db=>db.patch(wallet,{accountKey:"another"}),
    db=>db.patch(wallet,{initialBalance:2000000}),
  ];
  for(const change of edits){
    const db=setup();
    change(db);
    await assert.rejects(run(db),e=>["permission-denied","failed-precondition"].includes(e.code));
    assert.equal(db.writes,0);
  }
});
test("refill cannot happen before approval's anchor day",async()=>{
  const db=setup({anchor:"2026-10-21"});
  await assert.rejects(run(db,D1),e=>e.code==="failed-precondition");
  const atAnchor=await run(db,D2);
  assert.equal(atAnchor.diamondsRestored,0);
  const next=await run(db,D3);
  assert.equal(next.diamondsRestored,50000);
});
test("trusted scheduler is precisely midnight Baghdad but default OFF",async()=>{
  let capturedConfig,handler;
  const wrapper=scheduled({
    db:setup(),onSchedule:(config,cb)=>{capturedConfig=config;handler=cb;return cb;},
  });
  assert.equal(wrapper,handler);
  assert.equal(capturedConfig.schedule,"0 0 * * *");
  assert.equal(capturedConfig.timeZone,"Asia/Baghdad");
  const before=setup();
  assert.deepEqual(await handler(),{
    skipped:true,reason:"owner-release-not-approved",
  });
  assert.equal(before.writes,0);
});
test("staged scheduler touches only separate approved GM wallets",async()=>{
  const db=setup();
  assert.equal((await sweep(db,{now:D2})).length,1);
  assert.equal(db.docs.get(wallet).balance,MAX);
  assert.equal(db.docs.get(donation).balance,MAX);
  assert.equal((await sweep(db,{now:D2}))[0].diamondsRestored,0);
  db.patch(approval,{lastVerifiedGmUid:"other"});
  await assert.rejects(sweep(db,{now:D3}),
    e=>["permission-denied","failed-precondition"].includes(e.code));
});
