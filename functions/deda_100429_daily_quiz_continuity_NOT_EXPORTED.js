"use strict";
// DEDA 100429 — traffic quiz / daily tasks UI continuity, staging only.
// NO data is read from a device or sent to a server here. Archive records
// are untrusted LOCAL UI evidence; they cannot grant level XP, points, a task
// completion receipt, weekly league score, any diamonds or rewards.
// The real restore caller must first prove the account's canonical original
// and save/retrieve this evidence through a separately reviewed backend.
const {createHash}=require("node:crypto");
const SLOTS=new Set(["share_personal_location","open_map",
  "share_registered_place","open_saved_place","open_received_place",
  "review_added_place","traffic_skills","long_trip"]);
const DAY=/^\d{4}-\d{2}-\d{2}$/;
// Literal source list from lib/traffic_quiz_page.dart, which uses 20 bases
// and exactly five variants (base + _v2/_v3/_v4/_v5). Do NOT accept guessed
// question IDs: that would silently corrupt an account's quiz progress.
const TRAFFIC_BASE=Object.freeze(["sign_pedestrian_crossing","sign_no_entry","sign_stop","sign_speed_60","sign_yield","sign_traffic_light","sign_no_parking","sign_no_stopping","sign_roundabout","sign_turn_right","sign_school","sign_road_works","sign_slippery","sign_bend_right","sign_crossroad","sign_one_way","sign_priority_road","sign_horn_prohibited","sign_bicycle_path","sign_parking"]);
const QUESTION_IDS=new Set(TRAFFIC_BASE.flatMap(id=>
  [id,...[2,3,4,5].map(v=>id+"_v"+v)]));
if(QUESTION_IDS.size!==100)throw Error("traffic-question-bank-registry-conflict");
const ACCOUNT=/^[0-9]{8,15}$/;
const ORIGINAL=/^@DEDA-[A-Z0-9]{6}$/;
const CAPTURE=/^[A-Za-z0-9_-]{20,80}$/;
function stop(){throw Error("untrusted-engagement-ui-archive");}
function exact(obj,keys){
 if(!obj||typeof obj!=="object"||Array.isArray(obj) ||
    Object.keys(obj).length!==keys.length ||
    keys.some(k=>!Object.prototype.hasOwnProperty.call(obj,k)))stop();
}
function validDay(s){
 if(typeof s!=="string"||!DAY.test(s))return false;
 const t=new Date(s+"T00:00:00Z");
 return !Number.isNaN(t.valueOf())&&t.toISOString().startsWith(s);
}
function arr(v,limit,pred){
 if(!Array.isArray(v)||v.length>limit||v.some(x=>!pred(x))||
    new Set(v).size!==v.length)stop();
 return v;
}
function quiz(record){
 exact(record,["selected","seen","answered","correct","index","completed"]);
 const selected=arr(record.selected,5,v=>typeof v==="string"&&QUESTION_IDS.has(v));
 const seen=arr(record.seen,100,v=>typeof v==="string"&&QUESTION_IDS.has(v));
 if(selected.length!==5||!Number.isInteger(record.index)||record.index<0||
    record.index>=5||typeof record.completed!=="boolean")stop();
 const set=new Set(selected),all=new Set(seen);
 if(selected.some(q=>!all.has(q)))stop();
 const answered=record.answered;
 if(!answered||typeof answered!=="object"||Array.isArray(answered)||
    Object.keys(answered).length>5)stop();
 for(const [q,option]of Object.entries(answered)){
  if(!set.has(q)||!Number.isInteger(option)||option<0||option>3)stop();
 }
 const correct=arr(record.correct,5,q=>typeof q==="string"&&set.has(q));
 if(correct.some(q=>!Object.prototype.hasOwnProperty.call(answered,q)))stop();
 if(record.completed&&Object.keys(answered).length!==5)stop();
 return Object.freeze({selected:Object.freeze([...selected]),
  seen:Object.freeze([...seen]),answered:Object.freeze({...answered}),
  correct:Object.freeze([...correct]),index:record.index,completed:record.completed});
}
function daily(day){
 exact(day,["day","completedSlots","loginCompleted","quiz"]);
 if(!validDay(day.day)||typeof day.loginCompleted!=="boolean")stop();
 const completed=arr(day.completedSlots,8,v=>typeof v==="string"&&SLOTS.has(v));
 const q=quiz(day.quiz);
 if(completed.includes("traffic_skills")&&!q.completed)stop();
 return Object.freeze({day:day.day,completedSlots:Object.freeze([...completed]),
   loginCompleted:day.loginCompleted,quiz:q});
}
function displayOnlyEngagementArchive({record,accountKey,originalId,day,priorDigest}){
 if(!ACCOUNT.test(accountKey)||!ORIGINAL.test(originalId)||!validDay(day))stop();
 if(record==null)return Object.freeze({
   status:"NO_VERIFIED_UI_BACKUP",canRestoreUi:false,canGrantRewards:false,
   canCreditPoints:false,canCreditDiamonds:false,
 });
 exact(record,["format","kind","accountKey","originalId","captureId","days"]);
 if(record.format!==1||record.kind!=="untrusted-local-ui-evidence"||
    record.accountKey!==accountKey||record.originalId!==originalId||
    typeof record.captureId!=="string"||!CAPTURE.test(record.captureId)||
    !Array.isArray(record.days)||record.days.length>31)stop();
 const days=record.days.map(daily);
 if(new Set(days.map(d=>d.day)).size!==days.length)stop();
 const serialized=JSON.stringify(record);
 if(Buffer.byteLength(serialized,"utf8")>65000)stop();
 const digest=createHash("sha256").update(serialized).digest("hex");
 // A stored archive claim with the same immutable capture ID but changed
 // bytes must NEVER be silently reconciled.
 if(priorDigest!==undefined && priorDigest!==digest)stop();
 const today=days.find(d=>d.day===day);
 return Object.freeze({
   status:today?"UNTRUSTED_UI_PREVIEW_ONLY":"UI_DAY_NOT_IN_ARCHIVE",
   captureDigest:digest,
   canRestoreUi:false, // no real server-backed delivery is wired
   canGrantRewards:false,canCreditPoints:false,canCreditDiamonds:false,
   canWriteExistingTaskClaims:false,canReissueQuizPoints:false,
   snapshot:today??null,
 });
}
module.exports={displayOnlyEngagementArchive,TRAFFIC_BASE};
