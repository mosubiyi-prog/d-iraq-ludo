"use strict";
const test=require("node:test"),assert=require("node:assert/strict");
const {displayOnlyEngagementArchive:read}=
  require("../deda_100429_daily_quiz_continuity_NOT_EXPORTED.js");
const A="07712345678",B="07799999999",ID="@DEDA-ABC123",DAY="2026-11-01";
const questions=[
 "sign_stop","sign_yield_v2","sign_school_v3",
 "sign_speed_60_v4","sign_no_entry_v5",
];
const capture=()=>({
 format:1,kind:"untrusted-local-ui-evidence",
 accountKey:A,originalId:ID,captureId:"source_phone_backup_2026_11_01",
 days:[{day:DAY,completedSlots:["open_map","traffic_skills"],
 loginCompleted:true,quiz:{selected:[...questions],seen:[...questions],
 answered:Object.fromEntries(questions.map((q,i)=>[q,i%3])),
 correct:[questions[0],questions[2]],index:4,completed:true}}],
});
const args=record=>({record,accountKey:A,originalId:ID,day:DAY});
test("normal old-device daily quiz and 8-task slot history parses for viewing only",()=>{
 const a=read(args(capture()));
 assert.equal(a.status,"UNTRUSTED_UI_PREVIEW_ONLY");
 assert.deepEqual(a.snapshot.completedSlots,["open_map","traffic_skills"]);
 assert.equal(a.snapshot.quiz.correct.length,2);
 assert.equal(a.snapshot.quiz.completed,true);
 for(const k of ["canGrantRewards","canCreditPoints","canCreditDiamonds",
                   "canReissueQuizPoints","canWriteExistingTaskClaims","canRestoreUi"]){
   assert.equal(a[k],false,k);
 }
 assert.equal(Object.isFrozen(a.snapshot.quiz),true);
});
test("same archive on different phone is deterministic and never reissues XP or 25 question points",()=>{
 const a=read(args(capture())),b=read(args(capture()));
 assert.deepEqual(a,b);
 assert.equal(a.captureDigest,b.captureDigest);
 assert.equal(a.canCreditPoints,false);
});
test("wrong phone account or wrong original DEDA ID cannot ingest previous user's quiz",()=>{
 assert.throws(()=>read({...args(capture()),accountKey:B}),/untrusted/);
 assert.throws(()=>read({...args(capture()),originalId:"@DEDA-FFF999"}),/untrusted/);
});
test("missing archive or missing day is not interpreted as a fresh zero-completed day",()=>{
 const missing=read(args(null));
 assert.equal(missing.status,"NO_VERIFIED_UI_BACKUP");
 assert.equal(missing.canRestoreUi,false);
 const other=read({...args(capture()),day:"2026-11-02"});
 assert.equal(other.status,"UI_DAY_NOT_IN_ARCHIVE");
 assert.equal(other.snapshot,null);
});
test("same capture ID with changed answers is tampering, not newer trusted state",()=>{
 const first=read(args(capture())),changed=capture();
 changed.days[0].quiz.answered[questions[0]]=2;
 assert.throws(()=>read({...args(changed),priorDigest:first.captureDigest}),/untrusted/);
 assert.equal(read({...args(capture()),priorDigest:first.captureDigest}).captureDigest,
  first.captureDigest);
});
test("client attempts to add XP, points, diamonds, or a reward receipt are rejected",()=>{
 for(const field of ["xp","diamonds","taskPoints","credited","rewardReceipt"]){
   const bad=capture();bad.days[0][field]=9999;
   assert.throws(()=>read(args(bad)),/untrusted/);
 }
});
test("quiz answers must only use five actual bank questions and options 0..3",()=>{
 for(const invalid of [
  {answered:{unknown_question:1}},
  {answered:{[questions[0]]:4}},
  {correct:["sign_other_v4"]},
  {selected:["sign_fake_v2",...questions.slice(1)]},
  {selected:["sign_stop_v1",...questions.slice(1)]},
  {selected:[questions[0],questions[0],...questions.slice(2)]},
  {index:9},
 ]){
   const bad=capture();Object.assign(bad.days[0].quiz,invalid);
   assert.throws(()=>read(args(bad)),/untrusted/);
 }
});
test("daily tasks cannot be duplicated, invented, or claim traffic completion without quiz",()=>{
 for(const ids of [
  ["open_map","open_map"],["fake_task"],["traffic_skills","open_map","open_map"]]){
  const bad=capture();bad.days[0].completedSlots=ids;
  assert.throws(()=>read(args(bad)),/untrusted/);
 }
 const noQuiz=capture();noQuiz.days[0].quiz.completed=false;
 assert.throws(()=>read(args(noQuiz)),/untrusted/);
});
test("question bank seen IDs, unfinished progress and selected correct subset remain intact",()=>{
 const partial=capture();partial.days[0].completedSlots=["open_map"];
 partial.days[0].quiz.completed=false;
 partial.days[0].quiz.answered={[questions[0]]:1};
 partial.days[0].quiz.correct=[questions[0]];
 partial.days[0].quiz.index=0;
 const r=read(args(partial));
 assert.equal(r.snapshot.quiz.completed,false);
 assert.deepEqual(r.snapshot.quiz.correct,[questions[0]]);
 assert.equal(r.canRestoreUi,false);
});
test("fourth answer choice is valid as recorded by the real existing app",()=>{
 const old=capture();old.days[0].quiz.answered[questions[0]]=3;
 const r=read(args(old));
 assert.equal(r.snapshot.quiz.answered[questions[0]],3);
 assert.equal(r.canReissueQuizPoints,false);
});
test("a completed five-question quiz must have five answered IDs; no points inferred",()=>{
 const bad=capture();delete bad.days[0].quiz.answered[questions[4]];
 assert.throws(()=>read(args(bad)),/untrusted/);
});
test("invalid Iraq calendar days, duplicate day captures and oversized journal fail closed",()=>{
 const invalid=capture();invalid.days[0].day="2026-02-30";
 assert.throws(()=>read(args(invalid)),/untrusted/);
 const duplicate=capture();duplicate.days.push(JSON.parse(JSON.stringify(duplicate.days[0])));
 assert.throws(()=>read(args(duplicate)),/untrusted/);
 const large=capture();large.captureId="X".repeat(81);
 assert.throws(()=>read(args(large)),/untrusted/);
});
test("new-day phone UI data cannot override previous same-day answers or claim existing rewards",()=>{
 const old=capture();
 old.days.push({...JSON.parse(JSON.stringify(old.days[0])),
  day:"2026-11-02",completedSlots:[],loginCompleted:false,
  quiz:{selected:[...questions],seen:[...questions],answered:{},
   correct:[],index:0,completed:false}});
 const a=read(args(old));
 const b=read({...args(old),day:"2026-11-02"});
 assert.equal(a.snapshot.quiz.completed,true);
 assert.equal(b.snapshot.quiz.completed,false);
 assert.equal(b.canReissueQuizPoints,false);
 assert.equal(b.canGrantRewards,false);
});

test("mirror exactly existing Dart 20-base × 5-variant 100-question bank",()=>{
 const fs=require("node:fs"),path=require("node:path");
 const dart=fs.readFileSync(path.join(__dirname,"../../lib/traffic_quiz_page.dart"),"utf8");
 const segment=dart.split("const List<_TrafficQuestion> _trafficQuestionBase = [")[1]
   ?.split("const int _trafficVariantsPerBase")[0];
 assert.ok(segment,"Flutter traffic bank source missing");
 const base=[...segment.matchAll(/\bid:\s*'([^']+)'/g)].map(m=>m[1]);
 const registry=require("../deda_100429_daily_quiz_continuity_NOT_EXPORTED").TRAFFIC_BASE;
 assert.equal(base.length,20);
 assert.deepEqual(new Set(registry),new Set(base));
 assert.match(dart,/const int _trafficVariantsPerBase = 5;/);
 assert.match(dart,/base.answersAr.length != 4/);
 for(const id of base)assert.ok(!id.includes("_v1"));
});