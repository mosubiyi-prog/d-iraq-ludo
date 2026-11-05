"use strict";

// DEDA 100436 STAGE 2 — server-controlled candidate. No deployment here.
// A linked original UID may reserve a journal step, but only the Admin SDK
// verifier re-reads canonical server evidence and issues its attestation.
// No client-provided receipt is trusted, and NO wallet/XP/prize is awarded.
// Missing/ambiguous evidence, stale UID or unverified source fails CLOSED.
// Four domain readbacks are NOT proof of complete account restoration.

const {createHash} = require("node:crypto");
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const {stage2LiveGateEnabled} = require("./deda_stage2_live_gate.js");

const enabled = (
  process.env.FUNCTIONS_EMULATOR === "true" &&
  process.env.DEDA_RECOVERY_JOURNAL_SERVER_ENABLED === "true"
) || stage2LiveGateEnabled("journal");
const eligible = new Set([
  "originalBackupReadback",
  "purchaseBackupReadback",
  "levelPointsRestore",
  "publishedPlaceRecovery",
]);

const validAccount = (x) => typeof x === "string" && /^[0-9]{10,16}$/.test(x);
const validOriginal = (x) => typeof x === "string" && /^@DEDA-[A-Z0-9]{6}$/.test(x);
const validIntent = (x) => typeof x === "string" && /^[A-Za-z0-9_-]{20,100}$/.test(x);
const validReceipt = (x) => typeof x === "string" && /^[A-Za-z0-9_-]{12,128}$/.test(x);
const deny = (code, message) => {throw new HttpsError(code, message);};

function validatePayload(data, uid, token) {
  if (!data || typeof data !== "object" || Array.isArray(data)) {
    deny("invalid-argument", "invalid-journal-completion-request");
  }
  const keys = [
    "accountKey", "originalUid", "originalId", "intentId", "code",
    "operationKey", "receiptId",
  ];
  if (Object.keys(data).length !== keys.length ||
      Object.keys(data).some((x) => !keys.includes(x))) {
    deny("invalid-argument", "invalid-journal-completion-fields");
  }
  const {accountKey, originalUid, originalId, intentId, code, operationKey, receiptId} = data;
  if (!validAccount(accountKey) || !validOriginal(originalId) ||
      !validIntent(intentId) || !eligible.has(code) || !validReceipt(receiptId) ||
      originalUid !== uid ||
      token?.firebase?.sign_in_provider !== "password" ||
      token?.email !== accountKey + "@deda-login.invalid" ||
      operationKey !== `deda_guardian_v1/${uid}/${intentId}/${code}`) {
    deny("permission-denied", "original-owner-completion-proof-required");
  }
}

async function verifyImmutableServerOwner(db, uid, data) {
  // The linked Firebase credential is not enough: verify the server's
  // immutable directory, original user UID, original ID, and live account
  // session. Never use a locally typed name, premium ID, or guessed phone.
  const {accountKey, originalId} = data;
  const [directory, user, route, session] = await Promise.all([
    db.doc(`deda_account_directory/${accountKey}`).get(),
    db.doc(`users/${uid}`).get(),
    db.doc(`deda_share_ids/${originalId}`).get(),
    db.doc(`deda_sessions/${uid}`).get(),
  ]);
  if (!directory.exists || !user.exists || !route.exists || !session.exists ||
      directory.data()?.accountKey !== accountKey ||
      directory.data()?.active !== true ||
      directory.data()?.createdUid !== uid ||
      user.data()?.accountKey !== accountKey ||
      user.data()?.sharePersonalId !== originalId ||
      route.data()?.publicId !== originalId ||
      route.data()?.ownerUid !== uid ||
      route.data()?.kind !== "personal" ||
      route.data()?.active !== true ||
      session.data()?.uid !== uid ||
      session.data()?.accountKey !== accountKey) {
    deny("permission-denied", "original-owner-server-provenance-missing");
  }
}

// A compact deterministic receipt label shared with the Dart worker adapters.
// It is NOT a security hash: canonical source + original UID are independently
// rechecked by the server before any journal transition is authorized.
function receiptLabel(kind, source) {
  let a=0x811c9dc5, b=0x9e3779b9;
  for (const v of Buffer.from(source,"utf8")) {
    a=Math.imul(a ^ v, 16777619) >>> 0;
    b=Math.imul(b ^ v, 2246822519) >>> 0;
  }
  return kind + "_" + a.toString(16).padStart(8,"0") +
    b.toString(16).padStart(8,"0");
}
function revision(value) {
  return createHash("sha256").update(JSON.stringify(value)).digest("hex");
}
function validKeys(obj, keys) {
  return obj && typeof obj==="object" && !Array.isArray(obj) &&
    Object.keys(obj).length===keys.length &&
    keys.every(k=>Object.prototype.hasOwnProperty.call(obj,k));
}
function validTimestamp(value) {
  return value && typeof value.toMillis==="function" &&
    Number.isSafeInteger(value.toMillis());
}
const progressParts=["taskPoints","socialCoinsAndXp","earnedDiamonds"];
async function readOriginalProgress(db, accountKey, uid) {
  const snapshots=await db.collection("deda_progress_evidence")
    .doc(accountKey).collection("captures")
    .orderBy("createdAt","desc").limit(26).get();
  if (snapshots.empty || snapshots.size>25) {
    deny("failed-precondition","original-backup-absent-or-ambiguous");
  }
  let first=null;
  const keys=["format","kind","accountKey","sourceUid",
    "installId","captureId","records","createdAt"];
  for (const doc of snapshots.docs) {
    const d=doc.data();
    if (!validKeys(d,keys) || d.format!==1 ||
        d.kind!=="legacy-local-evidence" ||
        d.accountKey!==accountKey || d.sourceUid!==uid ||
        typeof d.installId!=="string" || d.installId.length<1 ||
        d.installId.length>128 ||
        typeof d.captureId!=="string" ||
        !/^[A-Za-z0-9_-]{20,80}$/.test(d.captureId) ||
        doc.id!==d.captureId || !validTimestamp(d.createdAt) ||
        !validKeys(d.records,progressParts) ||
        progressParts.some(p=>d.records[p]!==null &&
            typeof d.records[p]!=="string") ||
        progressParts.every(p=>d.records[p]===null) ||
        JSON.stringify(d.records).length>1000000) {
      deny("failed-precondition","original-backup-provenance-missing");
    }
    const item={captureId:d.captureId,installId:d.installId,
      records:{
        taskPoints:d.records.taskPoints,
        socialCoinsAndXp:d.records.socialCoinsAndXp,
        earnedDiamonds:d.records.earnedDiamonds,
      }};
    if(first===null) first=item;
    else if (first.installId!==item.installId ||
        JSON.stringify(first.records)!==JSON.stringify(item.records)) {
      deny("failed-precondition","original-phone-backups-disagree");
    }
  }
  return first;
}
const tasks=new Set(["share_personal_location","open_map",
  "share_registered_place","open_saved_place","open_received_place",
  "review_added_place","traffic_skills","long_trip"]);
function realDay(s) {
  if(typeof s!=="string" || !/^20\d\d-\d\d-\d\d$/.test(s))return false;
  const ms=Date.parse(s+"T00:00:00Z");
  return Number.isFinite(ms) && new Date(ms).toISOString().slice(0,10)===s;
}
function canonicalLevelPoints(raw) {
  if(typeof raw!=="string" || raw.length>800000) {
    deny("failed-precondition","original-level-ledger-unavailable");
  }
  let d;
  try{d=JSON.parse(raw);}catch(_){
    deny("failed-precondition","original-level-ledger-invalid");
  }
  if(!validKeys(d,["version","completions","awards","ledger"]) ||
      d.version!==1 || !d.completions || !d.awards ||
      Array.isArray(d.completions) || Array.isArray(d.awards) ||
      !Array.isArray(d.ledger) ||
      Object.keys(d.completions).length>200000 ||
      Object.keys(d.awards).length>200000 || d.ledger.length>600) {
    deny("failed-precondition","original-level-schema-conflict");
  }
  for(const [key,item] of Object.entries(d.completions)) {
    const parts=key.split("|");
    if(parts.length!==2 || !realDay(parts[0]) ||
        !tasks.has(parts[1]) || item?.taskId!==parts[1] ||
        item?.cycleId!==parts[0]) {
      deny("failed-precondition","original-level-completion-conflict");
    }
  }
  const bonus={5000:50,10000:100,15000:150,20000:200,25000:250};
  let sum=0;
  for(const [id,row] of Object.entries(d.awards)) {
    if(!row || typeof row!=="object" || row.id!==id ||
        !Number.isSafeInteger(row.points)) {
      deny("failed-precondition","original-level-award-invalid");
    }
    const x=id.split("|");
    const day=x[1];
    if (["task","traffic_answer","daily_login"].includes(x[0]) &&
        !realDay(day)) deny("failed-precondition","invalid-level-award-day");
    if(x[0]==="task") {
      if(x.length!==3 || !tasks.has(x[2]) ||
          row.points!==5 || row.type!=="task" ||
          row.taskId!==x[2] || row.cycleId!==day ||
          !Object.prototype.hasOwnProperty.call(d.completions,day+"|"+x[2])) {
        deny("failed-precondition","invalid-task-award");
      }
    } else if(x[0]==="traffic_answer") {
      if(x.length!==3 || !x[2] || row.points!==5 ||
          row.type!=="traffic_answer" ||
          row.cycleId!==day || row.dedupeId!==x[2]) {
        deny("failed-precondition","invalid-traffic-award");
      }
    } else if(x[0]==="daily_login") {
      if(x.length!==2 || row.points!==10 ||
          row.type!=="daily_login" || row.dayId!==day ||
          row.cycleId!==day)deny("failed-precondition","invalid-daily-login");
    } else if(x[0]==="point_tier_reserve" ||
              x[0]==="point_tier_claim") {
      const threshold=Number(day);
      if(x.length!==2 || !(threshold in bonus) ||
          row.threshold!==threshold ||
          row.reservedPoints!==threshold ||
          row.bonusPoints!==bonus[threshold]) {
        deny("failed-precondition","invalid-point-tier");
      }
      if(x[0]==="point_tier_reserve") {
        if(row.points!==-threshold || row.type!=="point_tier_reserve") {
          deny("failed-precondition","invalid-tier-reservation");
        }
      } else if(row.points!==threshold+bonus[threshold] ||
          row.type!=="point_tier_claim" ||
          !Object.prototype.hasOwnProperty.call(d.awards,
            "point_tier_reserve|"+day)) {
        deny("failed-precondition","invalid-tier-claim");
      }
    } else if(id==="point_tier|5000") {
      if(row.points!==50) deny("failed-precondition","invalid-legacy-tier");
    } else {
      deny("failed-precondition","unknown-level-award");
    }
    sum+=row.points;
    if(!Number.isSafeInteger(sum))deny("failed-precondition","invalid-points-total");
  }
  if(sum<0)deny("failed-precondition","negative-points-total");
  for(const row of d.ledger) {
    if(!row || typeof row.id!=="string" ||
        !Object.prototype.hasOwnProperty.call(d.awards,row.id) ||
        JSON.stringify(row)!==JSON.stringify(d.awards[row.id])) {
      deny("failed-precondition","original-level-ledger-disagrees");
    }
  }
  return sum;
}
const nativeFrames=["FRAME_03","FRAME_05","FRAME_06","FRAME_07",
 "FRAME_08","FRAME_09","FRAME_10","FRAME_11","FRAME_12",
 "FRAME_13","FRAME_14","FRAME_15","FRAME_16"];
async function readPurchasePair(db, data, progress) {
  const snap=await db.doc("deda_purchase_evidence/"+data.accountKey+
    "/captures/"+progress.captureId).get();
  const d=snap.exists?snap.data():null;
  if(!validKeys(d,["format","kind","accountKey","sourceUid",
      "installId","captureId","records","createdAt"]) ||
      d.format!==1 || d.kind!=="legacy-purchase-evidence" ||
      d.accountKey!==data.accountKey || d.sourceUid!==data.originalUid ||
      d.captureId!==progress.captureId ||
      d.installId!==progress.installId ||
      !validTimestamp(d.createdAt) ||
      !validKeys(d.records,["originalId","progressCaptureId",
        "localSnapshot"]) ||
      d.records.originalId!==data.originalId ||
      d.records.progressCaptureId!==progress.captureId ||
      typeof d.records.localSnapshot!=="string" ||
      Buffer.byteLength(d.records.localSnapshot,"utf8")>200000) {
    deny("failed-precondition","paired-purchase-source-missing");
  }
  let payload;
  try{payload=JSON.parse(d.records.localSnapshot);}catch(_){
    deny("failed-precondition","original-purchase-snapshot-invalid");
  }
  if(!validKeys(payload,["format","accountKey","originalId",
      "inventory","frameJournals"]) ||
      payload.format!==1 || payload.accountKey!==data.accountKey ||
      payload.originalId!==data.originalId ||
      !validKeys(payload.frameJournals,nativeFrames) ||
      JSON.stringify(payload)!==d.records.localSnapshot) {
    deny("failed-precondition","original-purchase-capture-conflict");
  }
  return {purchaseCaptureId:progress.captureId,installId:progress.installId,
    snapshot:d.records.localSnapshot};
}
async function serverReadbackAttestation(db, data) {
  const account=data.accountKey, uid=data.originalUid;
  let label,source;
  if(data.code==="publishedPlaceRecovery") {
    const query=await db.collection("published_places")
      .where("accountKey","==",account).where("published","==",true)
      .limit(2).get();
    if(query.size!==1)deny("failed-precondition","published-place-not-unique");
    const doc=query.docs[0],d=doc.data();
    if(d.ownerUid!==uid || d.accountKey!==account ||
        d.published!==true ||
        typeof d.approvalNumber!=="string" ||
        !d.approvalNumber.trim() || !doc.id ||
        doc.id.includes("/")) {
      deny("failed-precondition","original-published-place-mismatch");
    }
    label="published_place";
    source={id:doc.id,approvalNumber:d.approvalNumber};
  } else {
    const progress=await readOriginalProgress(db,account,uid);
    if(data.code==="originalBackupReadback") {
      label="progress";
      source=progress;
    } else if(data.code==="purchaseBackupReadback") {
      label="purchases";
      source=await readPurchasePair(db,data,progress);
    } else if(data.code==="levelPointsRestore") {
      label="level";
      const earnedPoints=canonicalLevelPoints(progress.records.taskPoints);
      source={captureId:progress.captureId,earnedPoints,
        originalTaskLedger:progress.records.taskPoints};
    } else {
      deny("failed-precondition","unreviewed-source-domain");
    }
  }
  const provenance=data.code==="publishedPlaceRecovery" ? source.id :
    data.code==="levelPointsRestore" ?
      source.captureId+"|"+source.earnedPoints :
    data.code==="purchaseBackupReadback" ?
      source.purchaseCaptureId+"|"+source.installId :
      source.captureId+"|"+source.installId;
  const receiptId=receiptLabel(label,provenance);
  return {receiptId,sourceRevision:revision({
    uid,account,dataCode:data.code,source,
  })};
}

async function verifiedCompletion(request, db = getFirestore()) {
  if (!enabled) deny("unavailable", "journal-verification-not-activated");
  if (!request.auth?.uid) deny("unauthenticated", "linked-owner-required");
  const uid = request.auth.uid, data = request.data;
  validatePayload(data, uid, request.auth.token);
  await verifyImmutableServerOwner(db, uid, data);
  // Re-read the REAL authoritative source using Admin SDK, then derive the
  // expected receipt independently of any client-supplied data.
  const audited = await serverReadbackAttestation(db, data);
  if (audited.receiptId !== data.receiptId) {
    deny("failed-precondition", "trusted-server-readback-missing");
  }

  const id = `${data.intentId}_${data.code}`;
  const rowRef = db.doc(`deda_recovery_journals/${uid}/steps/${id}`);
  const proofRef = db.doc(
      `deda_recovery_server_attestations/${uid}/receipts/${id}`);

  // Firestore transaction retries on conflicts. ALL reads precede writes.
  // No worker side effect runs here: no grants, purchases, rewards or PIN.
  return db.runTransaction(async (tx) => {
    const [row, proof] = await Promise.all([tx.get(rowRef), tx.get(proofRef)]);
    const r = row.data(), p = proof.data();
    const identical = r &&
      r.ownerUid === uid &&
      r.accountKey === data.accountKey &&
      r.originalId === data.originalId &&
      r.intentId === data.intentId &&
      r.code === data.code &&
      r.operationKey === data.operationKey;
    if (!row.exists || !identical) {
      deny("failed-precondition", "journal-reservation-not-proven");
    }

    // A client can NEVER create an attestation. This Admin SDK transaction
    // writes it only after the independent canonical server readback above.
    if (proof.exists) {
      if (p.ownerUid !== uid ||
          p.accountKey !== data.accountKey ||
          p.originalId !== data.originalId ||
          p.intentId !== data.intentId ||
          p.code !== data.code ||
          p.operationKey !== data.operationKey ||
          p.receiptId !== data.receiptId ||
          p.serverVerified !== true ||
          p.issuedBy !== "deda-approved-domain-verifier-v1" ||
          p.sourceRevision !== audited.sourceRevision) {
        deny("failed-precondition", "trusted-server-readback-missing");
      }
    } else {
      tx.create(proofRef, {
        ownerUid:uid, accountKey:data.accountKey,
        originalId:data.originalId, intentId:data.intentId,
        code:data.code, operationKey:data.operationKey,
        receiptId:data.receiptId, serverVerified:true,
        issuedBy:"deda-approved-domain-verifier-v1",
        sourceRevision:audited.sourceRevision,
        createdAt:FieldValue.serverTimestamp(),
      });
    }
    if (r.state === "verified") {
      if (r.receiptId !== data.receiptId) {
        deny("failed-precondition", "journal-receipt-conflict");
      }
      return {verified: true, receiptId: data.receiptId};
    }
    if (r.state !== "reserved" || "receiptId" in r) {
      deny("failed-precondition", "journal-state-conflict");
    }

    tx.update(rowRef, {
      state: "verified",
      receiptId: data.receiptId,
      verifiedAt: FieldValue.serverTimestamp(),
    });
    return {verified: true, receiptId: data.receiptId};
  });
}

// Export is local to this FILE. It will NOT become a deployed Cloud Function
// unless someone explicitly wires it into functions/index.js and deploys.
exports.dedaRecoveryJournalComplete = onCall(
    {enforceAppCheck: true, timeoutSeconds: 30},
    (request) => verifiedCompletion(request));
exports.__privateVerifiedCompletionForQaOnly = verifiedCompletion;
