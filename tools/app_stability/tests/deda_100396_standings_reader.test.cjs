"use strict";
const test=require("node:test"),assert=require("node:assert/strict");
const {createHash}=require("node:crypto");
const {windowFor}=require("../../../functions/deda_weekly_stage31_frozen_league_winner_card_NOT_EXPORTED.js");
const {readWeeklyStandings,WeeklyHold}=
 require("../../../functions/deda_weekly_100396_standings_reader_core.js");
const KEY="07701234567",UID="originalUser123",SECRET=Buffer.alloc(32,71);
const FIRST=Date.UTC(2026,9,19,3),WEEK=7*86400000;
const NOW=FIRST+WEEK+2*86400000;
const ORIGINAL="@DEDA-100123",CURRENT=windowFor(FIRST,1),PREV=windowFor(FIRST,0);
class DB{
 constructor(){this.docs=new Map();this.writes=[];}
 doc(path){return {get:async()=>({exists:this.docs.has(path),
  data:()=>this.docs.get(path)})};}
 collection(path){const self=this;return {get:async()=>{
  const docs=[...self.docs.entries()].filter(([p])=>
   p.startsWith(path+"/")&&!p.slice(path.length+1).includes("/"))
   .map(([p,v])=>({id:p.slice(path.length+1),data:()=>v}));
  return {size:docs.length,docs};
 }};}
 seed(p,v){this.docs.set(p,v);}
}
function fixture(){
 const db=new DB(),digest=createHash("sha256").update(KEY).digest("hex");
 db.seed("deda_weekly_verified_calendar/active",{
  enabled:true,publisherApproved:true,firstOpenMs:FIRST,
  allowClientMintedXp:false,allowLocalTaskBooleanProofs:false,
 });
 db.seed("deda_account_directory/"+KEY,{
  accountKey:KEY,active:true,createdUid:UID});
 db.seed("deda_account_profiles/"+KEY,{
  accountKey:KEY,name:"لاعب ديدا"});
 db.seed("users/"+UID,{
  accountKey:KEY,sharePersonalId:ORIGINAL});
 db.seed("deda_share_ids/"+ORIGINAL,{
  publicId:ORIGINAL,kind:"personal",active:true,ownerUid:UID});
 for(const [window,points] of [[CURRENT,40],[PREV,20]]){
  const s={accountDigest:digest,accountKey:KEY,
   weekId:window.weekId,weeklyPoints:points,
   verifiedTaskCompletions:points/20,
   lastEarnedAtMs:window.openedAtMs+86400000,
   rewardsCredited:false,levelXpChanged:false};
  db.seed("deda_weekly_verified_xp_mirror_private/"+
    window.weekId+"/scores/"+digest,s);
 }
 const auth={getUser:async uid=>({
  uid,disabled:false,email:null,providerData:[],
 })};
 return {db,auth};
}
function request(uid=UID,accountKey=KEY){
 return {auth:{uid,token:{firebase:{sign_in_provider:"anonymous"}}},
  app:{appId:"1:qa:android:test"},data:{accountKey}};
}
const read=(f,req=request(),nowMs=NOW)=>readWeeklyStandings({
 ...f,request:req,secret:SECRET,nowMs});
const deny=promise=>assert.rejects(promise,e=>e instanceof WeeklyHold);
test("01 exact existing screen-compatible current and previous leaderboard",async()=>{
 const f=fixture(),view=await read(f);
 assert.equal(view.source,"future_server_issued_only");
 assert.equal(view.readOnly,true);
 assert.equal(view.current.verified,true);
 assert.equal(view.current.status,"live");
 assert.equal(view.previous.status,"closed");
 assert.deepEqual(view.current.rows.map(x=>x.weeklyPoints),[40]);
 assert.deepEqual(view.previous.rows.map(x=>x.weeklyPoints),[20]);
 assert.equal(view.current.viewerPlace,1);
 assert.equal(view.current.rows[0].diamondsIfFinalWinner,150);
 assert.equal(view.current.rows[0].activePublicId,ORIGINAL);
 assert.equal(view.current.rows[0].displayName,"لاعب ديدا");
 assert.equal(view.current.rewardsCredited,false);
 assert.equal(JSON.stringify(view).includes(KEY),false);
 assert.equal(JSON.stringify(view).includes(UID),false);
 assert.equal(f.db.writes.length,0);
});
test("02 unrelated signed-in user cannot view verified league",async()=>{
 await deny(read(fixture(),request("attackerUser999")));
});
test("03 forged local client XP and wallet input not accepted",async()=>{
 const req=request();req.data.diamonds=1000000;
 await deny(read(fixture(),req));
});
test("04 owner disabled calendar blocks a valid prior week",async()=>{
 const f=fixture();f.db.seed("deda_weekly_verified_calendar/active",{
  enabled:false,publisherApproved:true,firstOpenMs:FIRST,
  allowClientMintedXp:false,allowLocalTaskBooleanProofs:false,
 });
 await deny(read(f));
});
test("05 tampered canonical account score refuses rank and protects wallet",async()=>{
 const f=fixture(),digest=createHash("sha256").update(KEY).digest("hex");
 const path="deda_weekly_verified_xp_mirror_private/"+
  CURRENT.weekId+"/scores/"+digest;
 f.db.seed(path,{...f.db.docs.get(path),accountKey:"07709999999"});
 await deny(read(f));
 assert.equal(f.db.writes.length,0);
});
test("06 no old week shows an empty predecessor, never invented winner",async()=>{
 const f=fixture(),weekOne=FIRST+86400000;
 const view=await read(f,request(),weekOne);
 assert.equal(view.current.status,"live");
 assert.equal(view.previous.rows.length,0);
 assert.equal(view.previous.rewardsCredited,false);
});
test("07 score frozen at midnight until six without modifying level",async()=>{
 const f=fixture(),freeze=CURRENT.closeAtMs+1200;
 const view=await read(f,request(),freeze);
 assert.equal(view.current.remainingMs,0);
 assert.equal(view.current.rows[0].weeklyPoints,40);
 assert.equal(f.db.writes.length,0);
});
test("08 valid delegated server binding can read same canonical account",async()=>{
 const f=fixture(),fresh="newPhoneUid987";
 f.db.seed("deda_secure_account_bindings/"+fresh,{
  accountKey:KEY,uid:fresh,status:"PIN_VERIFIED_HOLD",
  canMigrate:false,canRestoreAssets:false});
 const view=await read(f,request(fresh));
 assert.equal(view.current.rows[0].weeklyPoints,40);
 assert.equal(view.current.viewerPlace,1);
});
test("09 reject re-registered alias, owner mismatch and missing profile",async()=>{
 const f=fixture();
 f.db.seed("deda_share_ids/"+ORIGINAL,{
  publicId:ORIGINAL,kind:"personal",active:true,ownerUid:"foreignOwnerUid99"});
 await deny(read(f));
 f.db.docs.delete("deda_share_ids/"+ORIGINAL);
 await deny(read(f));
});
