"use strict";
/**
 * 100396 OBSERVATION MODE ONLY. The original app's claims are local; no server
 * can independently prove opening the map or reading a saved location from a
 * client claim. This records authenticated App Check *self-reported* task
 * rewards for QA, never production league points or diamonds.
 *
 * No writes to users/, deda_verified_progress, gifts, prize ledgers or
 * existing 100396 profile/XP. Independent 8-task proof issuers are required
 * before any ranked competition or real prizes.
 */
const {createHash} = require("node:crypto");
const {TASK_IDS} =
  require("./deda_weekly_original_eight_task_source_gate_NOT_EXPORTED.js");
const {windowFor,WEEK_MS} =
  require("./deda_weekly_stage31_frozen_league_winner_card_NOT_EXPORTED.js");

const ACCOUNT=/^[0-9]{10,16}$/;
const UID=/^[A-Za-z0-9_-]{6,128}$/;
class MonitorHold extends Error{
  constructor(code){super("DEDA_MONITOR_HOLD_"+code);this.name="MonitorHold";}
}
const hold=(code)=>{throw new MonitorHold(code);};
const get=s=>s.exists?s.data():null;
const publicSession=async(auth,uid)=>{
  const user=await auth.getUser(uid).catch(()=>null);
  if(!user||user.uid!==uid||user.disabled||user.email||
    (Array.isArray(user.providerData)&&user.providerData.length))
    hold("AUTH");
};

function dayInBaghdad(ms){
  const p=new Intl.DateTimeFormat("en-CA",{timeZone:"Asia/Baghdad",
    year:"numeric",month:"2-digit",day:"2-digit"})
    .formatToParts(new Date(ms));
  const d=Object.fromEntries(p.map(v=>[v.type,v.value]));
  return [d.year,d.month,d.day].join("-");
}
function validSession(request){
  const uid=request?.auth?.uid;
  const key=request?.data?.accountKey;
  const taskId=request?.data?.taskId;
  if(!UID.test(uid||"")||!ACCOUNT.test(key||"")||
     typeof request.app?.appId!=="string"||!request.app.appId||
     request.auth?.token?.firebase?.sign_in_provider!=="anonymous"||
     !request.data||Array.isArray(request.data)||
     Object.keys(request.data).length!==2||
     !TASK_IDS.includes(taskId))
    hold("AUTH_OR_TASK");
  return {uid,key,taskId};
}
async function recordMonitoredTask({db,auth,request,nowMs=Date.now()}){
  const {uid,key,taskId}=validSession(request);
  if(!Number.isSafeInteger(nowMs)||nowMs<=0)hold("TIME");
  await publicSession(auth,uid);
  const configRef=db.doc("deda_weekly_observation_config/active");
  const dirRef=db.doc("deda_account_directory/"+key);
  const bindRef=db.doc("deda_secure_account_bindings/"+uid);
  const digest=createHash("sha256").update(key).digest("hex");
  const day=dayInBaghdad(nowMs);
  return db.runTransaction(async tx=>{
    const [configS,dirS,bindS]=await Promise.all([
      tx.get(configRef),tx.get(dirRef),tx.get(bindRef)]);
    const cfg=get(configS),dir=get(dirS),binding=get(bindS);
    if(cfg?.qaEnabled!==true||cfg?.payoutsDisabled!==true||
       cfg?.productionRankEnabled!==false||
       !Array.isArray(cfg.allowlistedAccountHashes)||
       !cfg.allowlistedAccountHashes.includes(digest)||
       !Number.isSafeInteger(cfg.firstOpenMs)||
       cfg.firstOpenMs<=0)
      hold("OBSERVATION_DISABLED");
    if(dir?.active!==true||dir.accountKey!==key||
       !UID.test(dir.createdUid||"")||
       (dir.createdUid!==uid&&!(binding?.accountKey===key&&
        binding.uid===uid&&binding.status==="PIN_VERIFIED_HOLD"&&
        binding.canMigrate===false&&binding.canRestoreAssets===false)))
      hold("ACCOUNT");
    const n=Math.floor((nowMs-cfg.firstOpenMs)/WEEK_MS);
    if(n<0||n>5000)hold("NOT_OPEN");
    const week=windowFor(cfg.firstOpenMs,n);
    if(nowMs>=week.closeAtMs)
      return {status:"FROZEN_NO_POINTS",credited:false,unverified:true};
    const path="deda_weekly_observation_only/"+week.weekId;
    const dedupe=createHash("sha256")
      .update(digest+"|"+day+"|"+taskId).digest("hex");
    const claimRef=db.doc(path+"/claims/"+dedupe);
    const scoreRef=db.doc(path+"/scores/"+digest);
    const [oldS,scoreS]=await Promise.all([
      tx.get(claimRef),tx.get(scoreRef)]);
    if(oldS.exists)
      return {status:"OBSERVATION_ALREADY_RECORDED",credited:false,
        unverified:true};
    const old=get(scoreS);
    if(old&&(old.accountDigest!==digest||
      old.weekId!==week.weekId||
      !Number.isSafeInteger(old.observedXp)||
      !Number.isSafeInteger(old.observedTaskCount)||
      old.observedXp!==old.observedTaskCount*20||
      old.observedTaskCount<0||old.observedTaskCount>=56))
      hold("CORRUPT_OBSERVATION");
    tx.create(claimRef,{
      accountDigest:digest,taskId,dayId:day,
      observedAtMs:nowMs,source:"appcheck_client_task_claim_qa_only",
      independentlyVerified:false,canPayPrize:false,
    });
    tx.set(scoreRef,{
      accountDigest:digest,weekId:week.weekId,
      observedXp:(old?.observedXp||0)+20,
      observedTaskCount:(old?.observedTaskCount||0)+1,
      lastObservedAtMs:nowMs,independentlyVerified:false,
      payoutEligible:false,originalLevelXpChanged:false,
    });
    return {status:"OBSERVATION_RECORDED_QA",credited:false,unverified:true,
      observedWeeklyXp:(old?.observedXp||0)+20};
  },{maxAttempts:5});
}

/**
 * Fetch own QA observation only. No claimed scores are presented as approved
 * competitors, and no public ranking/prize payment is possible here.
 */
async function readMonitoredXp({db,auth,request,nowMs=Date.now()}){
  const uid=request?.auth?.uid,key=request?.data?.accountKey;
  if(!UID.test(uid||"")||!ACCOUNT.test(key||"")||
     request.auth?.token?.firebase?.sign_in_provider!=="anonymous"||
     typeof request.app?.appId!=="string"||!request.app.appId||
     !request.data||Array.isArray(request.data)||
     Object.keys(request.data).length!==1)
    hold("AUTH_OR_INPUT");
  await publicSession(auth,uid);
  const hash=createHash("sha256").update(key).digest("hex");
  const [configS,dirS,bindingS]=await Promise.all([
    db.doc("deda_weekly_observation_config/active").get(),
    db.doc("deda_account_directory/"+key).get(),
    db.doc("deda_secure_account_bindings/"+uid).get(),
  ]);
  const cfg=get(configS),dir=get(dirS),binding=get(bindingS);
  if(cfg?.qaEnabled!==true||cfg?.payoutsDisabled!==true||
     cfg?.productionRankEnabled!==false||
     !Array.isArray(cfg.allowlistedAccountHashes)||
     !cfg.allowlistedAccountHashes.includes(hash)||
     !Number.isSafeInteger(cfg.firstOpenMs)||
     dir?.active!==true||dir.accountKey!==key||
     !UID.test(dir.createdUid||"")||
     (dir.createdUid!==uid&&!(binding?.accountKey===key&&
       binding.uid===uid&&binding.status==="PIN_VERIFIED_HOLD"&&
       binding.canMigrate===false&&binding.canRestoreAssets===false)))
    hold("OBSERVATION_NOT_READY");
  const index=Math.floor((nowMs-cfg.firstOpenMs)/WEEK_MS);
  if(index<0||index>5000)hold("WEEK_NOT_OPEN");
  const week=windowFor(cfg.firstOpenMs,index);
  const score=await db.doc("deda_weekly_observation_only/"+
    week.weekId+"/scores/"+hash).get();
  const data=get(score);
  if(data&&(data.weekId!==week.weekId||
    data.accountDigest!==hash||
    !Number.isSafeInteger(data.observedXp)||
    data.observedXp<0||data.observedXp>1120||
    data.observedXp%20!==0||
    data.observedXp!==data.observedTaskCount*20||
    data.independentlyVerified!==false||
    data.payoutEligible!==false))
    hold("CORRUPT_OBSERVATION");
  return Object.freeze({
    status:"QA_OBSERVATION_ONLY_NOT_APPROVED",
    weekId:week.weekId,
    observedXp:data?.observedXp||0,
    taskCount:data?.observedTaskCount||0,
    readOnly:true,independentlyVerified:false,
    publicRankingAllowed:false,payoutEligible:false,
  });
}

module.exports={recordMonitoredTask,readMonitoredXp,MonitorHold,dayInBaghdad};
