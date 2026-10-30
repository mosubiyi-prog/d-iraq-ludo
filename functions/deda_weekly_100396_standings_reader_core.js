"use strict";
/*
 * Read-only ORIGINAL DEDA 100396 weekly ranks. Resolves private canonical
 * account keys to public profiles on the SERVER; never returns phone/UID.
 * This reader is inert without an owner-approved calendar and verified,
 * already-applied XP events; no local task booleans, payout or XP writes.
 */
const {createHash,createHmac}=require("node:crypto");
const {readVerifiedLeagueTopTen}=
 require("./deda_weekly_xp_top10_from_mirror_NOT_EXPORTED.js");
const {windowFor}=require("./deda_weekly_stage31_frozen_league_winner_card_NOT_EXPORTED.js");
const ACCOUNT=/^[0-9]{10,16}$/;
const UID=/^[A-Za-z0-9_-]{6,128}$/;
const PUB=/^@DEDA-[A-Z0-9]{4,12}$/;
const TEXT=/^[^\u0000-\u001f\u007f@]{2,60}$/;
const HMAC_DOMAIN="DEDA_WEEKLY_PUBLIC_PARTICIPANT_V1\n";
class WeeklyHold extends Error{
 constructor(code){super("DEDA_WEEKLY_READER_HOLD_"+code);this.name="WeeklyHold";}
}
const hold=code=>{throw new WeeklyHold(code);};
const d=s=>s.exists?s.data():null;
function participant(key,secret){
 if(!Buffer.isBuffer(secret)||secret.length<32)hold("SIGNING_KEY");
 return "deda-public-"+createHmac("sha256",secret)
   .update(HMAC_DOMAIN).update(key).digest("base64url").slice(0,36);
}
async function identity(db,key){
 if(!ACCOUNT.test(key||""))hold("INVALID_CANONICAL_KEY");
 const hash=createHash("sha256").update(key).digest("hex");
 const [directory,profile,owned]=await Promise.all([
  db.doc("deda_account_directory/"+key).get(),
  db.doc("deda_account_profiles/"+key).get(),
  db.doc("deda_owned_identifier_accounts/"+hash).get(),
 ]);
 const dir=d(directory),p=d(profile),o=d(owned);
 if(!dir||dir.accountKey!==key||dir.active!==true||
    !UID.test(dir.createdUid||"")||!p||p.accountKey!==key||
    !TEXT.test(p.name||""))
  hold("UNVERIFIED_PROFILE");
 const original=d(await db.doc("users/"+dir.createdUid).get());
 const originalId=original?.sharePersonalId;
 if(original?.accountKey!==key||!PUB.test(originalId||""))
  hold("UNKNOWN_ORIGINAL_ID");
 const active=o?.activeId||originalId;
 if(!PUB.test(active||"")||(o && (o.accountKey!==key||
    o.originalId!==originalId||!Array.isArray(o.ownedIds)||
    !o.ownedIds.includes(active))))
   hold("UNVERIFIED_ACTIVE_ID");
 const route=d(await db.doc("deda_share_ids/"+originalId).get());
 if(!route||route.kind!=="personal"||route.active!==true||
    route.publicId!==originalId||!UID.test(route.ownerUid||""))
   hold("BROKEN_PUBLIC_ID_ROUTE");
 if(route.ownerUid!==dir.createdUid){
  // Do not trust unreviewed handovers: need exclusive server authority.
  const [authority,link]=await Promise.all([
   db.doc("deda_migration_account_authority/"+key).get(),
   db.doc("deda_private_second_phone_links/"+route.ownerUid).get(),
  ]);
  const a=d(authority),l=d(link);
  if(a?.status!=="new-device-exclusive"||a.accountKey!==key||
     a.originalUid!==dir.createdUid||a.activeUid!==route.ownerUid||
     l?.accountKey!==key||l.oldUid!==dir.createdUid||
     l.newUid!==route.ownerUid)hold("UNVERIFIED_PHONE_HANDOVER");
 }
 return {accountKey:key,displayName:p.name,activePublicId:active,
   originalUid:dir.createdUid};
}
async function readWeek(db,firstOpenMs,index,nowMs,secret){
 const win=windowFor(firstOpenMs,index);
 const raw=await readVerifiedLeagueTopTen({
  db,firstOpenMs,nowMs:Math.max(win.openedAtMs,
   Math.min(nowMs,win.nextOpenMs-1)),
 });
 if(raw.weekId!==win.weekId||raw.rewardsCredited!==false||
    raw.productionReady!==false)hold("UNREVIEWED_WEEK");
 const rows=[];
 for(const item of raw.privateRows){
  const snap=await db.doc("deda_weekly_verified_xp_mirror_private/"+
    win.weekId+"/scores/"+item.accountDigest).get();
  const score=d(snap);
  const key=score?.accountKey;
  if(!ACCOUNT.test(key||"")||
     createHash("sha256").update(key).digest("hex")!==item.accountDigest)
    hold("ACCOUNT_POINTER_INVALID");
  const ident=await identity(db,key);
  rows.push({
   place:item.place,participantId:participant(key,secret),
   activePublicId:ident.activePublicId,displayName:ident.displayName,
   weeklyPoints:item.weeklyPoints,
   verifiedTaskCompletions:item.verifiedTaskCompletions,
   diamondsIfFinalWinner:item.place===1?150:item.place===2?100:
    item.place===3?50:10,
  });
 }
 return {weekId:win.weekId,rows};
}
async function readWeeklyStandings({
 db,auth,request,secret,nowMs=Date.now(),
}){
 const uid=request?.auth?.uid,key=request?.data?.accountKey;
 if(!db||!auth||!UID.test(uid||"")||!ACCOUNT.test(key||"")||
    request.auth.token?.firebase?.sign_in_provider!=="anonymous"||
    !request.app?.appId||!request.data||
    Object.keys(request.data).length!==1||
    !Number.isSafeInteger(nowMs))hold("BAD_SESSION");
 let user;
 try{user=await auth.getUser(uid);}catch(_){hold("BAD_AUTH");}
 if(!user||user.uid!==uid||user.disabled||user.email||
    (Array.isArray(user.providerData)&&user.providerData.length))
  hold("BAD_AUTH");
 const [configSnap,dirSnap,bindingSnap]=await Promise.all([
  db.doc("deda_weekly_verified_calendar/active").get(),
  db.doc("deda_account_directory/"+key).get(),
  db.doc("deda_secure_account_bindings/"+uid).get(),
 ]);
 const config=d(configSnap),dir=d(dirSnap),bind=d(bindingSnap);
 if(config?.enabled!==true||config?.publisherApproved!==true||
    config?.allowClientMintedXp!==false||
    config?.allowLocalTaskBooleanProofs!==false||
    !Number.isSafeInteger(config.firstOpenMs)||
    dir?.accountKey!==key||dir.active!==true||
    (dir.createdUid!==uid&&!(bind?.accountKey===key&&
      bind.uid===uid&&bind.status==="PIN_VERIFIED_HOLD"&&
      bind.canMigrate===false&&bind.canRestoreAssets===false)))
  hold("ACCOUNT_OR_CALENDAR_UNVERIFIED");
 const index=Math.floor((nowMs-config.firstOpenMs)/(7*86400000));
 if(index<1||index>5000)hold("WEEK_NOT_READY");
 const currentWin=windowFor(config.firstOpenMs,index);
 const [cur,prev]=await Promise.all([
  readWeek(db,config.firstOpenMs,index,nowMs,secret),
  readWeek(db,config.firstOpenMs,index-1,nowMs,secret),
 ]);
 const viewer=participant(key,secret);
 const decorate=(week,status,remainingMs)=>{
  const mine=week.rows.find(r=>r.participantId===viewer);
  return {verified:true,status,weekId:week.weekId,
   remainingMs,rewardsCredited:false,rows:week.rows,
   viewerParticipantId:mine?viewer:null,viewerPlace:mine?mine.place:null};
 };
 return {
  source:"future_server_issued_only",readOnly:true,
  current:decorate(cur,"live",
   Math.max(0,currentWin.closeAtMs-nowMs)),
  previous:decorate(prev,"closed",0),
 };
}
module.exports={readWeeklyStandings,WeeklyHold,participant,identity};
