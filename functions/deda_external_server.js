"use strict";
// External managed Node alternative; NEVER active by merely committing code.
const http=require("node:http");
const {initializeApp,getApps,applicationDefault}=require("firebase-admin/app");
const {getAuth}=require("firebase-admin/auth");
const {getFirestore}=require("firebase-admin/firestore");
const {createDedaExternalApi}=require("./deda_external_api.js");
const binding=require("./deda_telegram_bot_binding.js");
const {claimVerifiedTelegramFollow}=require("./deda_telegram_verified_claim.js");
const reward=require("./deda_telegram_reward_activation.js");
const getEnv = n => {
  const v=String(process.env[n]||"").trim();
  if(!v)throw Error("missing-runtime-secret-or-setting-"+n);
  return v;
};
function trustedPublicWebhook() {
  const u=new URL(getEnv("DEDA_EXTERNAL_PUBLIC_ORIGIN"));
  if(u.protocol!=="https:" || u.username || u.password ||
      u.search || u.hash || u.pathname!=="/" ||
      ["localhost","127.0.0.1"].includes(u.hostname)){
    throw Error("trusted-https-origin-required");
  }
  return u.origin+"/telegram/webhook";
}
function createServer() {
  if(process.env.DEDA_EXTERNAL_ENABLE!=="owner-approved") {
    throw Error("service-not-authorized-by-owner");
  }
  const project=getEnv("GOOGLE_CLOUD_PROJECT");
  if(project!=="deda-25b88")throw Error("wrong-firebase-project");
  const expectedWebhook=trustedPublicWebhook();
  const botToken=getEnv("DEDA_TELEGRAM_BOT_TOKEN");
  const webhookSecret=getEnv("DEDA_TELEGRAM_WEBHOOK_SECRET");
  if(!/^[A-Za-z0-9_-]{32,256}$/.test(webhookSecret)){
    throw Error("bad-telegram-webhook-secret");
  }
  // ADC must be provisioned ONLY in host runtime as a least-privilege secret.
  if(getApps().length===0)initializeApp({
    credential:applicationDefault(),projectId:project,
  });
  const db=getFirestore();
  async function authUser(token) {
    const user=await getAuth().verifyIdToken(token,true);
    return user?.uid||"";
  }
  async function activeGM(uid) {
    const snap=await db.collection("admins").doc(uid).get();
    const d=snap.data()||{};
    if(!snap.exists || d.active!==true ||
        d.role!=="general_manager" || String(d.status||"active")!=="active") {
      return null;
    }
    return {uid,role:"general_manager",active:true};
  }
  async function telegramReady() {
    try{
      const [admin,webhook]=await Promise.all([
        reward.checkBotIsChannelAdmin(botToken),
        fetch("https://api.telegram.org/bot"+botToken+"/getWebhookInfo",{
          signal:AbortSignal.timeout(7000),
        }),
      ]);
      if(admin!==true || !webhook.ok)return false;
      const result=await webhook.json();
      return result.ok===true && result.result?.url===expectedWebhook;
    }catch(_){return false;}
  }
  const handlers={
    webhookSecret,
    verifyUser:authUser,
    requireManager:activeGM,
    telegramReady,
    begin: uid=>binding.startVerification(db,{uid,botToken}),
    claim: uid=>claimVerifiedTelegramFollow(db,{
      uid,botToken,telegramLogin:null,
    }),
    botStart: body=>binding.acceptBotStart(db,{
      update:body,receivedSecret:webhookSecret,expectedSecret:webhookSecret,
    }),
    onBotLinked: async x=>{
      try {
        await fetch("https://api.telegram.org/bot"+botToken+"/sendMessage",{
          method:"POST",
          headers:{"Content-Type":"application/json"},
          body:JSON.stringify({chat_id:x.chatId,
            text:"✅ تم ربط حساب تليجرام مع DEDA. ارجع للتطبيق للتحقق."}),
          signal:AbortSignal.timeout(7000),
        });
      }catch(_){/* Binding is already saved; no tokens in logs. */}
    },
    manage:(actor,op)=>reward.manageVerifiedTelegramReward(db,{
      actor,op,botToken,botAdminCheck:telegramReady,
    }),
  };
  const handler=createDedaExternalApi(handlers);
  return http.createServer((req,res)=>{
    handler(req,res).catch(()=>{
      if(!res.headersSent){
        res.writeHead(503,{"Content-Type":"application/json",
          "Cache-Control":"no-store"});
        res.end('{"error":"service-unavailable"}');
      }
    });
  });
}
if(require.main===module){
  const port=Number(process.env.PORT||"8080");
  if(!Number.isInteger(port)||port<1024||port>65535){
    throw Error("invalid-port");
  }
  createServer().listen(port,"0.0.0.0",()=>{
    console.log("DEDA isolated Node Telegram service listening; rewards OFF by default.");
  });
}
module.exports={createServer,trustedPublicWebhook};
