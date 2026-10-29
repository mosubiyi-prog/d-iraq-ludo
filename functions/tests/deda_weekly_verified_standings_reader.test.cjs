"use strict";
const test=require("node:test");
const assert=require("node:assert/strict");
const {readVerifiedWeeklyStandings,WeeklyNotReady,serverSeal,viewerParticipantId}
  =require("../deda_weekly_verified_standings_reader_core");
const SECRET="QA-only-weekly-standings-hmac-secret-not-for-production-20261030";
const ACCOUNT="07712345678",UID="verifiedUser1234",NOW=2000000000000;
const WEEK=7*86400000,CLOSE=WEEK-21600000;
class DB{
 constructor(){this.docs=new Map();this.writes=0;}
 doc(path){return {path};}
 seed(path,value){this.docs.set(path,structuredClone(value));}
 read(path){return structuredClone(this.docs.get(path));}
 async runTransaction(fn,opt){
  assert.equal(opt.readOnly,true);
  return fn({get:async r=>({exists:this.docs.has(r.path),data:()=>this.read(r.path)}),
    set:()=>{this.writes++;throw Error("writes-forbidden");}});
 }
}
const row=(i,uid,id,points)=>({
 place:i,participantId:uid,activePublicId:id,displayName:"User Sample "+i,
 weeklyPoints:points,verifiedTaskCompletions:points/20,
 diamondsIfFinalWinner:i===1?150:i===2?100:i===3?50:10});
function setup(){
 const db=new DB();
 const auth={getUser:async uid=>({uid,disabled:false,email:null,providerData:[]})};
 db.seed("deda_secure_account_bindings/"+UID,{uid:UID,accountKey:ACCOUNT,
  status:"PIN_VERIFIED_HOLD",canRestoreAssets:false,canMigrate:false});
 db.seed("deda_account_directory/"+ACCOUNT,
  {accountKey:ACCOUNT,active:true,createdUid:"originalUser999"});
 const currentStart=NOW-2*86400000;
 const pub={
  schema:1,issuer:"deda-weekly-reviewed-publisher-v1",issuedAtMs:NOW-1000,
  sourceVerified:true,oldApkWriterFenced:true,
  canonicalAccountProofsVerified:true,payoutsAllowed:false,
  current:{weekId:"week_id_2026",status:"live",
   openedAtMs:currentStart,closeAtMs:currentStart+CLOSE,
   nextOpenMs:currentStart+WEEK,rows:[
    row(1,"candidateAlphaUser123456","@DEDA-ABC123",160),
    row(2,viewerParticipantId(SECRET,ACCOUNT),"@DEDA-DEF123",100)]},
  previous:{weekId:"week_id_2025",status:"closed",
   openedAtMs:currentStart-WEEK,closeAtMs:currentStart-WEEK+CLOSE,
   nextOpenMs:currentStart,rows:[
    row(1,"oldWinnerUser123456789","@DEDA-GHI123",60)]}
 };
 pub.signature=serverSeal(SECRET,pub);
 db.seed("deda_weekly_approved_publication/active",pub);
 return {db,auth};
}
const request=(uid=UID,key=ACCOUNT)=>({
 auth:{uid,token:{firebase:{sign_in_provider:"anonymous"}}},
 app:{appId:"qa-app-check-context"},data:{accountKey:key}});
const run=(f,r=request(),time=NOW,secret=SECRET)=>
 readVerifiedWeeklyStandings({...f,request:r,nowMs:time,secret});
const deny=p=>assert.rejects(p,e=>e instanceof WeeklyNotReady);
test("verified current and previous top10 is reader only",async()=>{
 const f=setup(),view=await run(f);
 assert.equal(view.source,"future_server_issued_only");
 assert.equal(view.current.rows[0].weeklyPoints,160);
 assert.equal(view.current.viewerPlace,2);
 assert.equal(view.previous.status,"closed");
 assert.equal(view.current.rows[1].diamondsIfFinalWinner,100);
 assert.equal(view.current.rewardsCredited,false);
 assert.equal(view.readOnly,true);
 assert.equal(f.db.writes,0);
 assert.equal(JSON.stringify(view).includes(ACCOUNT),false);
});
test("repeated reads cannot change owner wallets or XP",async()=>{
 const f=setup();
 f.db.seed("users/"+UID+"/wallet/original",{diamonds:91,frames:["paid"]});
 assert.deepEqual(await run(f),await run(f));
 assert.deepEqual(f.db.read("users/"+UID+"/wallet/original"),{diamonds:91,frames:["paid"]});
 assert.equal(f.db.writes,0);
});
test("no publication means no fabricated standings",async()=>{
 const f=setup();
 f.db.docs.delete("deda_weekly_approved_publication/active");
 await deny(run(f));
});
test("no original account binding or different UID denied",async()=>{
 const f=setup();
 await deny(run(f,request("otherUser123456")));
 await deny(run(f,request(UID,"07777777777")));
});
test("forged source flag, tampered signature, wrong points denied",async()=>{
 const f=setup(),path="deda_weekly_approved_publication/active";
 let p=f.db.read(path);p.sourceVerified=false;f.db.seed(path,p);await deny(run(f));
 p=setup().db.read(path);p.current.rows[0].weeklyPoints=999;
 f.db.seed(path,p);await deny(run(f));
 p=setup().db.read(path);p.signature="f".repeat(64);
 f.db.seed(path,p);await deny(run(f));
});
test("reordering duplicate participants/IDs denied even when server-signed",async()=>{
 const f=setup(),path="deda_weekly_approved_publication/active";
 for(const key of ["participantId","activePublicId"]){
  const p=setup().db.read(path);
  p.current.rows[1][key]=p.current.rows[0][key];
  p.signature=serverSeal(SECRET,p);
  f.db.seed(path,p);
  await deny(run(f));
 }
});
test("signed million points and wrong prize cannot enter weekly ranking",async()=>{
 const f=setup(),path="deda_weekly_approved_publication/active";
 for(const edit of [p=>{p.current.rows[0].weeklyPoints=1000000;
    p.current.rows[0].verifiedTaskCompletions=50000;},
   p=>{p.current.rows[1].diamondsIfFinalWinner=5000;}]){
  const p=setup().db.read(path);edit(p);p.signature=serverSeal(SECRET,p);
  f.db.seed(path,p);await deny(run(f));
 }
});
test("unauthenticated and extra client XP fields are never accepted",async()=>{
 const f=setup();
 const a=request();delete a.auth;await deny(run(f,a));
 const b=request();delete b.app;await deny(run(f,b));
 const c=request();c.data.xp=999;await deny(run(f,c));
});
test("stale publication and post-week change rejected",async()=>{
 const f=setup();
 await deny(run(f,request(),NOW+11*60000));
 await deny(run(f,request(),NOW-2000));
 const p=f.db.read("deda_weekly_approved_publication/active");
 p.issuedAtMs=p.current.nextOpenMs-1000;p.signature=serverSeal(SECRET,p);
 f.db.seed("deda_weekly_approved_publication/active",p);
 await deny(run(f,request(),p.current.nextOpenMs+1));
});
test("00-06 freeze returns immutable same-week ranking with zero remaining",async()=>{
 const f=setup(),path="deda_weekly_approved_publication/active";
 const p=f.db.read(path),at=p.current.closeAtMs+1000;
 p.issuedAtMs=at-1000;p.signature=serverSeal(SECRET,p);f.db.seed(path,p);
 const view=await run(f,request(),at);
 assert.equal(view.current.remainingMs,0);
 assert.equal(view.current.rows[0].place,1);
 assert.equal(view.previous.rows[0].place,1);
});
test("malformed private identities and wallet-bearing rows denied",async()=>{
 const f=setup(),path="deda_weekly_approved_publication/active";
 const p=f.db.read(path);p.current.rows[0].authUid="victim";
 p.signature=serverSeal(SECRET,p);f.db.seed(path,p);await deny(run(f));
});
test("backend failures and missing secret are explicit, not success",async()=>{
 const f=setup();f.db.runTransaction=async()=>{throw Error("db-down");};
 await assert.rejects(run(f),/DEDA_WEEKLY_READ_BACKEND_UNAVAILABLE/);
 await assert.rejects(run(setup(),request(),NOW,"bad"),/DEDA_WEEKLY_READER_SECRET_UNAVAILABLE/);
});
