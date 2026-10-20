"use strict";
const test=require("node:test"),assert=require("node:assert/strict");
const {createHash}=require("node:crypto");
const {auditRecordedPurchaseReceipt:audit}=
 require("../tools/deda_owner19_stage54_purchase_receipt_audit_private_2026_10_20.js");
const sha=s=>createHash("sha256").update(s,"utf8").digest("hex");
const uid="person_stage54",oldUid="historic_person_stage54";
const key="account_stage54",original="@DEDA-Z1X2C3";
const special="@DEDA-ABCD",purchased="@DEDA-AAAAAA";
const cardReq="stage54_card_purchase_001",idReq="stage54_id_purchase_001";
const account=sha(key);
class Ref {
  constructor(db,path){this.db=db;this.path=path;}
  doc(id){return new Ref(this.db,this.path+"/"+id);}
  collection(id){return new Ref(this.db,this.path+"/"+id);}
}
class Db {
  constructor(){this.docs=new Map();this.writes=0;}
  collection(name){return new Ref(this,name);}
  put(path,data){this.docs.set(path,structuredClone(data));}
  del(path){this.docs.delete(path);}
  patch(path,fields){Object.assign(this.docs.get(path),fields);}
  async runTransaction(fn) {
    const tx={get:async ref=>{
      const stored=this.docs.get(ref.path);
      return {exists:stored!==undefined,data:()=>structuredClone(stored)};
    },set:()=>{this.writes++;throw Error("read-only-audit-wrote");},
      update:()=>{this.writes++;throw Error("read-only-audit-wrote");},
      create:()=>{this.writes++;throw Error("read-only-audit-wrote");},
    };
    return fn(tx);
  }
}
const cardPath="deda_id_card_purchase_requests/"+account+"/requests/"+cardReq;
const idPath="deda_id_purchase_requests/"+account+"/requests/"+idReq;
const entPath="deda_id_card_entitlements/"+account;
const ledgerPath="deda_owned_identifier_accounts/"+account;
function fixture(){
  const db=new Db();
  db.put("users/"+uid,{accountKey:key,sharePersonalId:original,phone:"private"});
  db.put("deda_sessions/"+uid,{uid,accountKey:key});
  db.put("users/"+oldUid,{accountKey:key});
  db.put("deda_share_ids/"+original,{
    publicId:original,active:true,kind:"personal",ownerUid:oldUid,
  });
  db.put(entPath,{accountKey:key,colors:{gold:true,diamond:true},
    activeColor:"diamond"});
  db.put(cardPath,{
    accountKey:key,publicId:original,color:"gold",
    requestId:cardReq,transactionId:sha(key+":"+cardReq+":gold"),
    diamondsCharged:5000,giftCharged:3000,gmPersonalCharged:2000,
    alreadyOwned:false,serverConfirmed:true,
  });
  db.put(ledgerPath,{
    accountKey:key,originalId:original,activeId:special,
    ownedIds:[original,special,purchased],
  });
  db.put("deda_owned_identifier_registry/"+purchased,{
    identifier:purchased,accountKey:key,originalId:original,
    status:"owned",acquisition:"diamond_purchase",
  });
  db.put("deda_owned_identifier_aliases/"+purchased,{
    identifier:purchased,accountKey:key,originalId:original,
    kind:"permanent_alias",
  });
  db.put("deda_verified_id_sale_catalog/"+purchased,{
    identifier:purchased,group:"002",status:"sold",ownerAccountHash:account,
  });
  db.put(idPath,{
    accountKey:key,originalId:original,identifier:purchased,
    requestId:idReq,transactionId:sha(key+":"+idReq+":"+purchased),
    diamondsCharged:10000,giftCharged:6000,gmPersonalCharged:4000,
    serverConfirmed:true,
  });
  return db;
}
const read=(db,kind,requestId)=>audit(db,{uid,kind,requestId});
test("recorded card charge 5k verifies owner color entitlement and exact split",async()=>{
  const db=fixture();
  const v=await read(db,"card",cardReq);
  assert.deepEqual(v,{
    serverConfirmed:true,kind:"card",requestId:cardReq,
    verifiedType:"owned_card_color",diamondsCharged:5000,
    receiptMatchesOwnership:true,
    historicWalletProvenanceEstablished:false,purchaseReleaseApproved:false,
  });
  assert.equal(db.writes,0);
  assert.equal(JSON.stringify(v).includes(key),false);
  assert.equal(JSON.stringify(v).includes("phone"),false);
});
test("already-owned card receipt must be zero and preserve its entitlement",async()=>{
  const db=fixture();db.patch(cardPath,{
    alreadyOwned:true,diamondsCharged:0,giftCharged:0,gmPersonalCharged:0,
  });
  const v=await read(db,"card",cardReq);
  assert.equal(v.diamondsCharged,0);
  db.patch(cardPath,{giftCharged:5000});
  await assert.rejects(read(db,"card",cardReq),e=>e.code==="failed-precondition");
});
test("old 4-char GM ID plus newly purchased six-char Group002 reconcile together",async()=>{
  const db=fixture();
  const v=await read(db,"identifier",idReq);
  assert.equal(v.diamondsCharged,10000);
  assert.equal(v.verifiedType,"owned_group002_identifier");
  assert.equal(v.receiptMatchesOwnership,true);
  assert.equal(v.historicWalletProvenanceEstablished,false);
  assert.equal(db.writes,0);
});
test("read-only audit is idempotent; replay cannot debit",async()=>{
  const db=fixture();
  assert.deepEqual(await read(db,"card",cardReq),await read(db,"card",cardReq));
  assert.deepEqual(await read(db,"identifier",idReq),await read(db,"identifier",idReq));
  assert.equal(db.writes,0);
});
test("forged 5k receipt splits, IDs, account, color and entitlement are rejected",async()=>{
  const edits=[
    db=>db.patch(cardPath,{giftCharged:5001}),
    db=>db.patch(cardPath,{gmPersonalCharged:-1}),
    db=>db.patch(cardPath,{diamondsCharged:10000}),
    db=>db.patch(cardPath,{transactionId:"fake_receipt"}),
    db=>db.patch(cardPath,{accountKey:"other-account"}),
    db=>db.patch(cardPath,{color:"pink"}),
    db=>db.patch(cardPath,{alreadyOwned:true}),
    db=>db.patch(entPath,{colors:{diamond:true}}),
    db=>db.patch("deda_sessions/"+uid,{accountKey:"other"}),
    db=>db.patch("users/"+oldUid,{accountKey:"other"}),
  ];
  for(const edit of edits){
    const db=fixture();edit(db);
    const error=await read(db,"card",cardReq).then(()=>null,e=>e);
    assert.ok(error && ["failed-precondition","permission-denied"].includes(error.code));
    assert.equal(db.writes,0);
  }
});
test("forged Group002 receipt, ledger, alias or stock are rejected",async()=>{
  const edits=[
    db=>db.patch(idPath,{diamondsCharged:5000}),
    db=>db.patch(idPath,{giftCharged:9000}),
    db=>db.patch(idPath,{gmPersonalCharged:0}),
    db=>db.patch(idPath,{originalId:"@DEDA-X0X0X0"}),
    db=>db.patch(idPath,{transactionId:"client_record"}),
    db=>db.patch(idPath,{identifier:special}),
    db=>db.patch(ledgerPath,{ownedIds:[original,special]}),
    db=>db.patch(ledgerPath,{activeId:"@DEDA-FAKE"}),
    db=>db.patch("deda_owned_identifier_registry/"+purchased,{accountKey:"other"}),
    db=>db.patch("deda_owned_identifier_registry/"+purchased,{acquisition:"general_manager_gift"}),
    db=>db.patch("deda_owned_identifier_aliases/"+purchased,{originalId:"@DEDA-FAKE00"}),
    db=>db.patch("deda_verified_id_sale_catalog/"+purchased,{ownerAccountHash:"other"}),
    db=>db.patch("deda_verified_id_sale_catalog/"+purchased,{status:"verified_available"}),
    db=>db.put("deda_share_ids/"+purchased,{
      publicId:purchased,kind:"personal",active:true,ownerUid:"other",
    }),
  ];
  for(const edit of edits){
    const db=fixture();edit(db);
    await assert.rejects(read(db,"identifier",idReq),
      e=>e.code==="failed-precondition");
    assert.equal(db.writes,0);
  }
});
test("missing receipt, wrong UID, invalid request type fail closed",async()=>{
  const db=fixture();
  await assert.rejects(read(db,"card","missing_request_1234"),e=>e.code==="not-found");
  await assert.rejects(audit(db,{uid:"unauthenticated!",kind:"card",
    requestId:cardReq}),e=>e.code==="unauthenticated");
  await assert.rejects(read(db,"rewards",cardReq),e=>e.code==="invalid-argument");
  await assert.rejects(read(db,"identifier","!"),e=>e.code==="invalid-argument");
  assert.equal(db.writes,0);
});
