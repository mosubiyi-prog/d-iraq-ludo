"use strict";
const {timingSafeEqual} = require("node:crypto");
const PATHS = new Set(["/telegram/webhook", "/v1/telegram/start",
  "/v1/telegram/claim", "/v1/telegram/readiness",
  "/v1/telegram/manage", "/v1/automation/readiness"]);
const secretEqual = (a,b) => {
  if (!a || !b || typeof a !== "string" || typeof b !== "string") return false;
  const x=Buffer.from(a), y=Buffer.from(b);
  return x.length === y.length && timingSafeEqual(x,y);
};
const send = (res,status,data) => {
  res.writeHead(status, {"Content-Type":"application/json; charset=utf-8",
    "Cache-Control":"no-store","X-Content-Type-Options":"nosniff"});
  res.end(JSON.stringify(data));
};
async function bodyJson(req) {
  if (String(req.headers["content-type"]||"").split(";")[0].trim() !==
      "application/json") throw Error("invalid-body");
  let size=0; const chunks=[];
  for await (const chunk of req) {
    size += chunk.length;
    if (size > 32768) throw Error("invalid-body");
    chunks.push(chunk);
  }
  const result=JSON.parse(Buffer.concat(chunks).toString("utf8"));
  if (!result || typeof result!=="object" || Array.isArray(result)) {
    throw Error("invalid-body");
  }
  return result;
}
function bearer(req) {
  const text=String(req.headers.authorization||"");
  const match=/^Bearer ([A-Za-z0-9_.-]{30,8192})$/.exec(text);
  return match?match[1]:"";
}
/**
 * Never accepts user UID, account key, Telegram ID, wallet amount or PIN
 * authority from untrusted body. All privileges injected by trusted server.
 * No CORS, no personal data in errors; backed by existing atomic Firestore.
 */
function createDedaExternalApi(d) {
  for(const name of ["verifyUser","requireManager","begin","claim","botStart",
    "onBotLinked","telegramReady","manage"]) {
    if(typeof d?.[name]!=="function") throw Error("missing-"+name);
  }
  if(!d.webhookSecret) throw Error("missing-telegram-webhook-secret");
  return async (req,res) => {
    const url=String(req.url||"");
    if(req.method==="GET" && url==="/health") {
      return send(res,200,{status:"running"});
    }
    if(!PATHS.has(url.split("?")[0]))return send(res,404,{error:"not-found"});
    if(req.method!=="POST")return send(res,405,{error:"post-only"});
    if(url.includes("?"))return send(res,400,{error:"query-not-allowed"});
    if(url==="/telegram/webhook" &&
        !secretEqual(req.headers["x-telegram-bot-api-secret-token"],d.webhookSecret)) {
      return send(res,403,{error:"forbidden"});
    }
    try {
      const body=await bodyJson(req);
      if(url==="/telegram/webhook") {
        const outcome=await d.botStart(body);
        if(outcome?.outcome==="linked")await d.onBotLinked(outcome);
        return send(res,200,{ok:true});
      }
      const token=bearer(req);
      if(!token)return send(res,401,{error:"sign-in-required"});
      const uid=await d.verifyUser(token);
      if(!uid)return send(res,401,{error:"sign-in-required"});
      if(url==="/v1/telegram/start"){
        return send(res,200,{result:await d.begin(uid)});
      }
      if(url==="/v1/telegram/claim"){
        return send(res,200,{result:await d.claim(uid)});
      }
      const actor=await d.requireManager(uid);
      if(!actor)return send(res,403,{error:"general-manager-required"});
      if(url==="/v1/automation/readiness"){
        // NEVER claim old 10/30-second Cloud Functions are deployed here.
        return send(res,200,{result:{ready:false,
          reason:"background-worker-not-deployed"}});
      }
      if(url==="/v1/telegram/readiness"){
        return send(res,200,{result:{ready:await d.telegramReady()===true}});
      }
      if(url==="/v1/telegram/manage"){
        if(!["enable","disable"].includes(body.op) ||
            Object.keys(body).some(k=>k!=="op")){
          return send(res,400,{error:"invalid-operation"});
        }
        if(body.op==="enable" && await d.telegramReady()!==true){
          return send(res,409,{result:{outcome:"bot-or-webhook-not-ready"}});
        }
        return send(res,200,{result:await d.manage(actor,body.op)});
      }
      return send(res,404,{error:"not-found"});
    }catch(error){
      const invalid=error instanceof SyntaxError || error?.message==="invalid-body";
      return send(res,invalid?400:503,
        {error:invalid?"invalid-request":"service-unavailable"});
    }
  };
}
module.exports={createDedaExternalApi,secretEqual};
