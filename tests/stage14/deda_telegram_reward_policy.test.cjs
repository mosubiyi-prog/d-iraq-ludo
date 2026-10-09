const {test}=require("node:test");
const assert=require("node:assert/strict");
const crypto=require("node:crypto");
const {verifyTelegramLogin,memberConfirmed,claimEligible}=
  require("../../functions/deda_telegram_reward_policy.js");

const botToken="123456:ABCDEFGHIJKLMNOPQRSTUVabcdefghi";
const now=Date.UTC(2026,9,10,1,0,0);
function signed(payload) {
  const fields=Object.entries(payload).sort(([a],[b])=>a.localeCompare(b))
    .map(([k,v])=>`${k}=${v}`).join("\n");
  const key=crypto.createHash("sha256").update(botToken).digest();
  return {...payload,hash:crypto.createHmac("sha256",key)
    .update(fields).digest("hex")};
}
const valid=signed({id:"1012345678",first_name:"DEDA",
  auth_date:String(Math.floor(now/1000))});
const at={toMillis:()=>now-60000};
const task={activateAt:at,status:"scheduled",platform:"telegram",
  action:"follow",url:"https://t.me/DEDA_Iraq",
  rewardUnit:"diamonds",rewardAmount:10,rewardsEnabled:false,
  rewardClaimMode:"blocked-until-trusted-proof-and-ssv-ledger"};
const proof=verifyTelegramLogin(valid,botToken,now);
const member={status:"member",user:{id:1012345678}};
test("Telegram Login signature correctly authenticates signed Telegram identity",()=>{
  assert.deepEqual(proof,{valid:true,telegramUserId:"1012345678"});
  assert.equal(verifyTelegramLogin({...valid,id:"1"},botToken,now).valid,false);
  assert.equal(verifyTelegramLogin(valid,botToken,now+6*60000).valid,false);
  assert.equal(verifyTelegramLogin(valid,"",now).valid,false);
});
test("Telegram channel must return this EXACT user with real member role",()=>{
  assert.equal(memberConfirmed(member,proof.telegramUserId),true);
  for(const bad of [
    {status:"left",user:{id:1012345678}},
    {status:"kicked",user:{id:1012345678}},
    {status:"member",user:{id:987}},
    {status:"restricted",is_member:false,user:{id:1012345678}},
  ])assert.equal(memberConfirmed(bad,proof.telegramUserId),false);
});
test("existing 100327 published task NEVER grants diamonds even if member",()=>{
  const result=claimEligible({dayTask:task,now:new Date(now),
    loginProof:proof,botMember:member,userUid:"deda-user-1",
    claimAlreadyExists:false});
  assert.equal(result.eligible,false);
  assert.equal(result.reason,"trusted-wallet-ledger-not-live");
});
test("duplicate claim, bad member, future task are rejected",()=>{
  const configured={...task,rewardsEnabled:true,
    rewardClaimMode:"server-verified-telegram-membership"};
  for(const x of [
    {claimAlreadyExists:true},
    {botMember:{status:"left",user:{id:1012345678}}},
    {dayTask:{...configured,activateAt:{toMillis:()=>now+60000}}},
    {loginProof:{valid:false}},
  ])assert.equal(claimEligible({dayTask:configured,now:new Date(now),
    loginProof:proof,botMember:member,userUid:"deda-user-1",
    claimAlreadyExists:false,...x}).eligible,false);
});
