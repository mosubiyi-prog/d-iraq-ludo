"use strict";
/**
 * DEDA 100399 - 20-user community standings, OWNER-REVIEW CANDIDATE.
 * Only receives the existing task-success notification AFTER original +20
 * level XP. It never awards XP or diamonds and never edits DEDA profiles.
 * Auth/App Check and canonical account binding are mandatory.
 * The existing phone task check is not independent server proof of physical
 * completion; do not authorize real prize credit from these receipts.
 *
 * Default OFF until an owner-controlled server document is enabled.
 */
const {createHash, randomUUID}=require("node:crypto");
const ACCOUNT=/^[0-9]{10,16}$/;
const UID=/^[A-Za-z0-9_-]{6,128}$/;
const PUB=/^@DEDA-[A-Z0-9]{4,12}$/;
const NAME=/^[^\x00-\x1f\x7f@]{2,60}$/;
const TASKS=new Set([
  "share_personal_location","open_map","share_registered_place",
  "open_saved_place","open_received_place","review_added_place",
  "traffic_skills","long_trip",
]);
const WEEK_MS=7*86400000,FREEZE_MS=6*3600000;
const DIGEST=v=>createHash("sha256").update(v).digest("hex");
const fail=x=>{const e=new Error("COMMUNITY_WEEKLY_"+x);e.publicCode=x;throw e;};
const data=s=>s?.exists===true?s.data():null;
const IRAQ=new Intl.DateTimeFormat("en-CA",{timeZone:"Asia/Baghdad",
  year:"numeric",month:"2-digit",day:"2-digit"});
function iraqDay(ms){
  const parts=Object.fromEntries(IRAQ.formatToParts(new Date(ms))
    .map(p=>[p.type,p.value]));
  return parts.year+"-"+parts.month+"-"+parts.day;
}
function validateStart(ms){
  // Start at 06:00 Baghdad, so the last six hours freeze at 00:00-06:00.
  if(!Number.isSafeInteger(ms)||ms<Date.UTC(2026,9,1)||
     ms>Date.UTC(2040,0,1)||
     !new Date(ms).toISOString().endsWith("T03:00:00.000Z"))
    fail("INVALID_START");
  return ms;
}
function weekAt(startAtMs,nowMs){
  validateStart(startAtMs);
  if(!Number.isSafeInteger(nowMs)||nowMs<startAtMs)fail("NOT_STARTED");
  const index=Math.floor((nowMs-startAtMs)/WEEK_MS);
  const openedAtMs=startAtMs+index*WEEK_MS;
  return {id:"community-"+String(index).padStart(5,"0"),
    openedAtMs,closeAtMs:openedAtMs+WEEK_MS-FREEZE_MS,
    nextOpenMs:openedAtMs+WEEK_MS};
}
async function identify({db,auth,request,readOnly=false}){
  const uid=request?.auth?.uid,accountKey=request?.data?.accountKey;
  const input=request?.data;
  if(!UID.test(uid||"")||!ACCOUNT.test(accountKey||"")||
    request.auth?.token?.firebase?.sign_in_provider!=="anonymous"||
    typeof request.app?.appId!=="string"||!request.app.appId||
    !input||typeof input!=="object"||Array.isArray(input)||
    Object.keys(input).length!==(readOnly?1:2))
    fail("AUTH_REQUIRED");
  const user=await auth.getUser(uid).catch(()=>null);
  if(!user||user.disabled||user.uid!==uid||user.email||
     (Array.isArray(user.providerData)&&user.providerData.length))
    fail("AUTH_REQUIRED");
  const [directory,binding]=await Promise.all([
    db.doc("deda_account_directory/"+accountKey).get(),
    db.doc("deda_secure_account_bindings/"+uid).get(),
  ]);
  const d=data(directory),b=data(binding);
  if(!d||d.active!==true||d.accountKey!==accountKey||
     !UID.test(d.createdUid||"")||
     (d.createdUid!==uid&&!(b&&b.uid===uid&&
       b.accountKey===accountKey&&b.status==="PIN_VERIFIED_HOLD"&&
       b.canMigrate===false&&b.canRestoreAssets===false)))
    fail("ACCOUNT_UNVERIFIED");
  return {uid,accountKey,accountDigest:DIGEST(accountKey),directory:d};
}
async function activeConfig(db){
  const cfg=data(await db.doc("deda_weekly_community_config/active").get());
  // 20-user community launch must be explicitly enabled server-side.
  // Never enable diamonds or accept caller-supplied amounts.
  if(!cfg||cfg.communityEnabled!==true||
     cfg.grantDiamonds!==false||cfg.allowClientTaskReports!==true)
    fail("LEAGUE_DISABLED");
  validateStart(cfg.startAtMs);
  return cfg;
}
async function claim({db,auth,request,nowMs=Date.now(),newId=randomUUID}){
  const who=await identify({db,auth,request});
  const cfg=await activeConfig(db);
  const taskId=request.data.taskId;
  if(!TASKS.has(taskId))fail("BAD_TASK");
  const w=weekAt(cfg.startAtMs,nowMs);
  if(nowMs>=w.closeAtMs)return {
    status:"WEEK_FROZEN",counted:false,weeklyXp:0,weekId:w.id};
  const day=iraqDay(nowMs);
  const weekPath="deda_weekly_community/"+w.id;
  const claimRef=db.doc(weekPath+"/claims/"+DIGEST(who.accountDigest+"|"+day+"|"+taskId));
  const scoreRef=db.doc(weekPath+"/scores/"+who.accountDigest);
  return db.runTransaction(async tx=>{
    const [prior,previous]=await Promise.all([tx.get(claimRef),tx.get(scoreRef)]);
    const s=data(previous);
    if(prior.exists)return {status:"ALREADY_RECORDED",counted:false,
      weeklyXp:s?.weeklyXp??0,weekId:w.id};
    if(s&&(!UID.test(s.participantId?.replace(/^weekly-user-/,"")||"")||
      s.accountDigest!==who.accountDigest||s.accountKey!==who.accountKey||
      s.weekId!==w.id||!Number.isSafeInteger(s.weeklyXp)||
      s.weeklyXp!==20*s.tasks||s.tasks>=56||s.prizesPaid!==false))
      fail("CORRUPT_SCORE");
    const participantId=s?.participantId||"weekly-user-"+newId().replace(/-/g,"");
    if(!/^weekly-user-[A-Za-z0-9_-]{20,64}$/.test(participantId))
      fail("INVALID_PARTICIPANT");
    const next={accountKey:who.accountKey,accountDigest:who.accountDigest,
      participantId,weekId:w.id,weeklyXp:(s?.weeklyXp||0)+20,
      tasks:(s?.tasks||0)+1,lastEarnedAtMs:nowMs,
      prizesPaid:false,taskProofIndependent:false};
    tx.create(claimRef,{accountDigest:who.accountDigest,day,taskId,
      recordedAtMs:nowMs,independentlyVerified:false});
    tx.set(scoreRef,next);
    return {status:"COUNTED_COMMUNITY",counted:true,
      weeklyXp:next.weeklyXp,weekId:w.id};
  },{maxAttempts:5});
}
async function rowsFor({db,week,viewerDigest}){
  const snapshot=await db.collection("deda_weekly_community/"+week.id+"/scores").get();
  if(snapshot.size>500)fail("TOO_MANY_USERS");
  const scores=[];
  for(const doc of snapshot.docs){
    const s=doc.data();
    if(!s||doc.id!==s.accountDigest||!ACCOUNT.test(s.accountKey||"")||
      DIGEST(s.accountKey)!==s.accountDigest||s.weekId!==week.id||
      !/^weekly-user-[A-Za-z0-9_-]{20,64}$/.test(s.participantId||"")||
      !Number.isSafeInteger(s.tasks)||s.tasks<1||s.tasks>56||
      s.weeklyXp!==20*s.tasks||s.prizesPaid!==false)fail("INVALID_SCORE");
    scores.push(s);
  }
  scores.sort((a,b)=>b.weeklyXp-a.weeklyXp||
    a.lastEarnedAtMs-b.lastEarnedAtMs||
    a.accountDigest.localeCompare(b.accountDigest));
  const viewerRank=scores.findIndex(s=>s.accountDigest===viewerDigest);
  const selected=scores.slice(0,10);
  if(viewerRank>=10)selected.push(scores[viewerRank]);
  const rows=[];
  for(const s of selected){
    const [d,p]=await Promise.all([
      db.doc("deda_account_directory/"+s.accountKey).get(),
      db.doc("deda_account_profiles/"+s.accountKey).get(),
    ]);
    const dir=data(d),profile=data(p);
    if(dir?.active!==true||dir.accountKey!==s.accountKey||
       !UID.test(dir.createdUid||"")||profile?.accountKey!==s.accountKey||
       !NAME.test(profile.name||""))fail("PUBLIC_PROFILE_INCOMPLETE");
    const owner=data(await db.doc("users/"+dir.createdUid).get());
    const publicId=owner?.sharePersonalId;
    if(!PUB.test(publicId||""))fail("PUBLIC_ID_INCOMPLETE");
    const place=scores.findIndex(x=>x.accountDigest===s.accountDigest)+1;
    rows.push({place,participantId:s.participantId,
      displayName:profile.name,activePublicId:publicId,
      weeklyPoints:s.weeklyXp,verifiedTaskCompletions:s.tasks,
      diamondsIfFinalWinner:place===1?150:place===2?100:place===3?50:
        place<=10?10:0});
  }
  const me=rows.find(r=>r.participantId===
    scores[viewerRank]?.participantId);
  return {rows,viewerParticipantId:me?.participantId??null,
    viewerPlace:me?.place??null};
}
async function standings({db,auth,request,nowMs=Date.now()}){
  const who=await identify({db,auth,request,readOnly:true});
  const cfg=await activeConfig(db);
  const week=weekAt(cfg.startAtMs,nowMs);
  const previous=week.openedAtMs===cfg.startAtMs?
    {id:"community-before-start"}:
    weekAt(cfg.startAtMs,week.openedAtMs-1);
  const [now,prior]=await Promise.all([
    rowsFor({db,week,viewerDigest:who.accountDigest}),
    week.openedAtMs===cfg.startAtMs?
      Promise.resolve({rows:[],viewerParticipantId:null,viewerPlace:null}):
      rowsFor({db,week:previous,viewerDigest:who.accountDigest}),
  ]);
  const serialize=(period,info,status,remainingMs)=>({
    verified:true,status,weekId:period.id,rows:info.rows,
    viewerParticipantId:info.viewerParticipantId,
    viewerPlace:info.viewerPlace,rewardsCredited:false,remainingMs,
  });
  return {source:"future_server_issued_only",readOnly:true,
    current:serialize(week,now,"live",
      Math.max(0,week.closeAtMs-nowMs)),
    previous:serialize(previous,prior,"closed",0)};
}
module.exports={claim,standings,identify,activeConfig,weekAt,iraqDay};
