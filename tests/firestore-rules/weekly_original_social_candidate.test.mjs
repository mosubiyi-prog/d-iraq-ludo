import {before,after,test} from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import {initializeTestEnvironment,assertSucceeds,assertFails} from "@firebase/rules-unit-testing";
import {doc,setDoc,getDoc,updateDoc,deleteDoc,query,where,collection,getDocs,serverTimestamp} from "firebase/firestore";

const PROJECT="demo-deda-weekly-xp-stage9";
if(process.env.GCLOUD_PROJECT!==PROJECT || process.env.FIRESTORE_EMULATOR_HOST!=="127.0.0.1:8080")
  throw Error("WEEKLY_SOCIAL_PRIVATE_RULES_EMULATOR_ONLY");
const candidate=fs.readFileSync("firebase.weekly-social.candidate.rules","utf8");
const original=fs.readFileSync("firestore.rules","utf8");
if(original.includes("match /deda_friendships/{relationId}") ||
   !candidate.includes("weeklySocialPair") ||
   !candidate.endsWith(original.slice(-1000)))
  throw Error("ORIGINAL_PRODUCTION_RULES_MUST_STAY_UNCHANGED");
let env;
const A="social_original_a",B="social_original_b",C="social_original_attacker",SAME="social_same_account";
const profiles=Object.freeze({
 [A]:{id:"@DEDA-AA1111",name:"الأول",account:"07701234567"},
 [B]:{id:"@DEDA-BB2222",name:"الثاني",account:"07707654321"},
 [C]:{id:"@DEDA-CC3333",name:"آخر",account:"07705555555"},
 [SAME]:{id:"@DEDA-DD4444",name:"نفس الحساب",account:"07701234567"},
});
const auth=(uid)=>env.authenticatedContext(uid).firestore();
const pair=[A,B].sort().join("__");
const prof=(uid)=>({
  publicId:profiles[uid].id,ownerUid:uid,displayName:profiles[uid].name,
  avatarStyle:1,frameStyle:2,backgroundStyle:0,level:9,badges:[],
  createdAt:serverTimestamp(),updatedAt:serverTimestamp()
});
const relation=(from,to)=>({
  pairKey:[from,to].sort().join("__"),
  members:[from,to],requesterUid:from,recipientUid:to,
  requesterPublicId:profiles[from].id,recipientPublicId:profiles[to].id,
  requesterName:profiles[from].name,recipientName:profiles[to].name,
  status:"pending",createdAt:serverTimestamp(),updatedAt:serverTimestamp()
});
before(async()=>{
 env=await initializeTestEnvironment({projectId:PROJECT,
  firestore:{host:"127.0.0.1",port:8080,rules:candidate}});
 await env.withSecurityRulesDisabled(async context=>{
  const db=context.firestore();
  for(const [uid,user] of Object.entries(profiles)){
   await setDoc(doc(db,"users",uid),{
     uid,accountKey:user.account,sharePersonalId:user.id,name:user.name,
   });
   await setDoc(doc(db,"deda_share_ids",user.id),{
     publicId:user.id,ownerUid:uid,kind:"personal",active:true,displayName:user.name,
   });
   await setDoc(doc(db,"deda_sessions",uid),{
     uid,accountKey:user.account,installId:uid+"_install",
   });
  }
 });
});
after(async()=>env?.cleanup());
test("both original DEDA clients can CREATE their own profile; cannot take another UID",async()=>{
 for(const uid of [A,B,C,SAME])
  await assertSucceeds(setDoc(doc(auth(uid),"deda_social_profiles",profiles[uid].id),prof(uid)));
 await assertFails(setDoc(doc(auth(C),"deda_social_profiles",profiles[A].id),prof(C)));
 await assertFails(updateDoc(doc(auth(C),"deda_social_profiles",profiles[A].id),
   {ownerUid:C,displayName:"HACK",updatedAt:serverTimestamp()}));
 await assertSucceeds(getDoc(doc(auth(B),"deda_social_profiles",profiles[A].id)));
});
test("real existing original sendFriendRequest writes PENDING only for verified two distinct accounts",async()=>{
 await assertSucceeds(setDoc(doc(auth(A),"deda_friendships",pair),relation(A,B)));
 assert.equal((await getDoc(doc(auth(B),"deda_friendships",pair))).data().status,"pending");
 await assertFails(setDoc(doc(auth(C),"deda_friendships",[A,C].sort().join("__")),
   relation(A,C)));
 await assertFails(setDoc(doc(auth(A),"deda_friendships",[A,SAME].sort().join("__")),
   relation(A,SAME)));
 await assertFails(setDoc(doc(auth(A),"deda_friendships",[A,C].sort().join("__")),
   {...relation(A,C),status:"accepted",respondedAt:serverTimestamp()}));
 await assertFails(setDoc(doc(auth(A),"deda_friendships",[A,C].sort().join("__")),
   {...relation(A,C),members:[A,A]}));
});
test("only recipient can ACCEPT original request, not sender or third user",async()=>{
 const ref=uid=>doc(auth(uid),"deda_friendships",pair);
 await assertFails(updateDoc(ref(A),{
   status:"accepted",respondedAt:serverTimestamp(),updatedAt:serverTimestamp()
 }));
 await assertFails(updateDoc(ref(C),{
   status:"accepted",respondedAt:serverTimestamp(),updatedAt:serverTimestamp()
 }));
 await assertFails(updateDoc(ref(B),{
   status:"accepted",recipientUid:C,respondedAt:serverTimestamp(),
   updatedAt:serverTimestamp()
 }));
 await assertSucceeds(updateDoc(ref(B),{
   status:"accepted",respondedAt:serverTimestamp(),updatedAt:serverTimestamp()
 }));
 const confirmed=await getDoc(ref(A));
 assert.equal(confirmed.data().status,"accepted");
 assert.equal(confirmed.data().recipientUid,B);
 await assertFails(updateDoc(ref(B),{
   status:"rejected",respondedAt:serverTimestamp(),updatedAt:serverTimestamp()
 }));
});
test("accepted relation query visible only to its members",async()=>{
 for(const uid of [A,B]){
  await assertSucceeds(getDoc(doc(auth(uid),"deda_friendships",pair)));
  const result=await assertSucceeds(getDocs(query(
   collection(auth(uid),"deda_friendships"),where("members","array-contains",uid))));
  assert.equal(result.docs.filter(d=>d.id===pair).length,1);
 }
 await assertFails(getDoc(doc(auth(C),"deda_friendships",pair)));
 await assertFails(deleteDoc(doc(auth(C),"deda_friendships",pair)));
});
test("do not permit any XP/weekly leaderboard or diamond writes by original client",async()=>{
 for(const collectionId of [
  "deda_weekly_stage63_private_immutable_frozen_xp_snapshots",
  "deda_weekly_private_published_place_share_action_proofs",
  "deda_verified_progress","deda_progress_receipts"
 ]){
  await assertFails(setDoc(doc(auth(A),collectionId,"unauthorized"),{
    xp:999999,weeklyPoints:999999,diamonds:999999,issuer:"client",
  }));
 }
});
