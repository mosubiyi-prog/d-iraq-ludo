"use strict";
/**
 * Owner-only live data test — uses actual task claim button reports, Firebase
 * Auth and App Check. Counters are real shared server state, not local preview.
 * The server enforces one account+task+Baghdad-day claim, fixed +20 weekly XP.
 * But physical activity is not independently proven. NEVER grant diamonds or
 * label this eligible for production prizes until server task proofs exist.
 */
const {createHash,createHmac}=require("node:crypto");
const ACCOUNT=/^[0-9]{10,16}$/;
const UID=/^[A-Za-z0-9_-]{6,128}$/;
const PUB=/^@DEDA-[A-Z0-9]{4,12}$/;
const NAME=/^[^\x00-\x1f\x7f@]{2,60}$/;
const TASK_IDS=new Set([
 "share_personal_location","open_map","share_registered_place",
 "open_saved_place","open_received_place","review_added_place",
 "traffic_skills","long_trip",
]);
const FIRST_OPEN=Date.UTC(2026,9,30,3); // Baghdad Oct 30 06:00
const WEEK=7*86400000,FREEZE=6*3600000;
const DAY=new Intl.DateTimeFormat("en-CA",{
 timeZone:"Asia/Baghdad",year:"numeric",month:"2-digit",day:"2-digit",
});
const fail=code=>{const e=new Error("DEDA_WEEKLY_"+code);e.publicCode=code;throw e;};
const val=s=>s.exists?s.data():null;
const hash=s=>createHash("sha256").update(s).digest("hex");
function weekAt(ms){
 const n=Math.floor((ms-FIRST_OPEN)/WEEK);
 if(!Number.isSafeInteger(n)||n<0||n>5000)fail("NOT_STARTED");
 const openedAtMs=FIRST_OPEN+n*WEEK;
 return {id:"weekly-"+String(n).padStart(5,"0"),
  openedAtMs,closeAtMs:openedAtMs+WEEK-FREEZE,
  nextOpenMs:openedAtMs+WEEK};
}
function baghdadDay(ms){
 const v=Object.fromEntries(DAY.formatToParts(new Date(ms))
   .map(p=>[p.type,p.value]));
 return v.year+"-"+v.month+"-"+v.day;
}
async function authorize({request,db,auth,readOnly=false}){
 const uid=request?.auth?.uid,accountKey=request?.data?.accountKey;
 if(!UID.test(uid||"")||!ACCOUNT.test(accountKey||"")||
    request.auth?.token?.firebase?.sign_in_provider!=="anonymous"||
    typeof request.app?.appId!=="string"||!request.app.appId||
    !request.data||Array.isArray(request.data)||
    Object.keys(request.data).length!==(readOnly?1:2))
    fail("AUTH_REQUIRED");
 const u=await auth.getUser(uid).catch(()=>null);
 if(!u||u.uid!==uid||u.disabled||u.email||
    (Array.isArray(u.providerData)&&u.providerData.length))
    fail("AUTH_REQUIRED");
 const [directorySnap,bindingSnap,configSnap]=await Promise.all([
  db.doc("deda_account_directory/"+accountKey).get(),
  db.doc("deda_secure_account_bindings/"+uid).get(),
  db.doc("deda_weekly_owner_pilot_config/active").get(),
 ]);
 const d=val(directorySnap),b=val(bindingSnap),config=val(configSnap);
 if(!d||d.active!==true||d.accountKey!==accountKey||
    !UID.test(d.createdUid||"")||
    (d.createdUid!==uid&&!(b&&b.uid===uid&&
      b.accountKey===accountKey&&b.status==="PIN_VERIFIED_HOLD"&&
      b.canMigrate===false&&b.canRestoreAssets===false)))
  fail("ACCOUNT_UNVERIFIED");
 const accountDigest=hash(accountKey);
 // No test account can access this endpoint without explicit server-side
 // allowlisting. It cannot be activated from inside an APK.
 if(config?.ownerQaEnabled!==true||
    config?.grantDiamonds!==false||
    config?.allowClientTaskReports!==true||
    !Array.isArray(config.allowedAccounts)||
    !config.allowedAccounts.includes(accountDigest))
  fail("OWNER_QA_DISABLED");
 return {uid,accountKey,accountDigest,config,directory:d};
}
async function claim({db,auth,request,nowMs=Date.now()}){
 const subject=await authorize({request,db,auth});
 const taskId=request.data.taskId;
 if(!TASK_IDS.has(taskId)||!Number.isSafeInteger(nowMs))fail("BAD_TASK");
 const w=weekAt(nowMs);
 if(nowMs>=w.closeAtMs)return {
  status:"WEEK_FROZEN",counted:false,weeklyXp:0};
 const day=baghdadDay(nowMs);
 const base="deda_weekly_owner_pilot/"+w.id;
 const claimRef=db.doc(base+"/claims/"+
   hash(subject.accountDigest+"|"+day+"|"+taskId));
 const scoreRef=db.doc(base+"/scores/"+subject.accountDigest);
 return db.runTransaction(async tx=>{
   const [prior,scored]=await Promise.all([
     tx.get(claimRef),tx.get(scoreRef)]);
   const s=val(scored);
   if(prior.exists)return {status:"ALREADY_RECORDED",
     counted:false,weeklyXp:s?.weeklyXp??0};
   if(s&&(s.accountDigest!==subject.accountDigest||
      s.accountKey!==subject.accountKey||
      s.weekId!==w.id||
      !Number.isSafeInteger(s.weeklyXp)||
      !Number.isSafeInteger(s.tasks)||
      s.weeklyXp!==s.tasks*20||s.tasks>=56))
     fail("CORRUPT_SCORE");
   const next={weekId:w.id,accountDigest:subject.accountDigest,
     accountKey:subject.accountKey,weeklyXp:(s?.weeklyXp||0)+20,
     tasks:(s?.tasks||0)+1,lastEarnedAtMs:nowMs,
     prizesPaid:false,taskProofIndependent:false};
   // One unique task for this Baghdad calendar day, even when the user
   // changes phone or retries an earlier successful request.
   tx.create(claimRef,{accountDigest:subject.accountDigest,
     taskId,day,recordedAtMs:nowMs,independentlyVerified:false});
   tx.set(scoreRef,next);
   return {status:"COUNTED_OWNER_QA",counted:true,
     weeklyXp:next.weeklyXp,weekId:w.id};
 },{maxAttempts:5});
}
async function readRows({db,w,secret}){
 const query=await db.collection("deda_weekly_owner_pilot/"+
   w.id+"/scores").get();
 if(query.size>10000)fail("TOO_MANY_USERS");
 const scored=[];
 for(const item of query.docs){
  const s=item.data();
  if(!s||item.id!==s.accountDigest||!ACCOUNT.test(s.accountKey||"")||
     hash(s.accountKey)!==s.accountDigest||s.weekId!==w.id||
     !Number.isSafeInteger(s.weeklyXp)||s.weeklyXp<20||
     s.weeklyXp%20!==0||s.tasks!==s.weeklyXp/20||
     s.tasks>56||s.prizesPaid!==false||
     s.taskProofIndependent!==false)fail("INVALID_SCORE");
  scored.push(s);
 }
 scored.sort((a,b)=>b.weeklyXp-a.weeklyXp||
   a.lastEarnedAtMs-b.lastEarnedAtMs||
   a.accountDigest.localeCompare(b.accountDigest));
 const rows=[];
 for(const [i,s] of scored.slice(0,10).entries()){
  const [d,p]=await Promise.all([
   db.doc("deda_account_directory/"+s.accountKey).get(),
   db.doc("deda_account_profiles/"+s.accountKey).get(),
  ]);
  const dir=val(d),profile=val(p);
  if(dir?.active!==true||dir.accountKey!==s.accountKey||
     !UID.test(dir.createdUid||"")||profile?.accountKey!==s.accountKey||
     !NAME.test(profile.name||""))continue;
  const owner=val(await db.doc("users/"+dir.createdUid).get());
  const publicId=owner?.sharePersonalId;
  if(!PUB.test(publicId||""))continue;
  const participantId="weekly-user-"+createHmac("sha256",secret)
   .update(s.accountKey).digest("base64url").slice(0,35);
  const place=rows.length+1;
  rows.push({place,participantId,displayName:profile.name,
   activePublicId:publicId,weeklyPoints:s.weeklyXp,
   verifiedTaskCompletions:s.tasks,
   diamondsIfFinalWinner:place===1?150:place===2?100:
     place===3?50:10});
 }
 return rows;
}
async function standings({db,auth,request,nowMs=Date.now(),secret}){
 const subject=await authorize({request,db,auth,readOnly:true});
 if(typeof secret!=="string"||secret.length<32)fail("CONFIG");
 const w=weekAt(nowMs);
 const p=weekAt(Math.max(FIRST_OPEN, w.openedAtMs-1));
 const currentRows=await readRows({db,w,secret});
 const previousRows=w.id===p.id?[]:
   await readRows({db,w:p,secret});
 const viewer="weekly-user-"+createHmac("sha256",secret)
   .update(subject.accountKey).digest("base64url").slice(0,35);
 const make=(period,rows,status,remainingMs)=>{
   const me=rows.find(r=>r.participantId===viewer);
   return {verified:true,status,weekId:period.id,rows,remainingMs,
     rewardsCredited:false,viewerParticipantId:me?viewer:null,
     viewerPlace:me?.place??null};
 };
 return {
  // Official screen decoder recognizes server-issued snapshots.
  // Only the SERVER-RECORDED CLAIM is verified here; underlying user action
  // is not independently proven and MUST NOT trigger prize payouts.
  source:"future_server_issued_only",readOnly:true,
  current:make(w,currentRows,"live",Math.max(0,w.closeAtMs-nowMs)),
  previous:make(w.id===p.id?{id:"weekly-before-competition"}:p,
   previousRows,"closed",0),
 };
}
module.exports={claim,standings,authorize,weekAt,baghdadDay};
