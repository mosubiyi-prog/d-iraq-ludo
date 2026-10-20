"use strict";

// Stage63 PRIVATE Firestore Emulator E2E: exactly the SAME callable names
// consumed by original Flutter shop/manager/friends, not direct unit APIs.
// Synthetic Group001 suffixes ONLY; no real 100, real wallet or credentials.
// No Google Play, production deployment, owner account or phone alteration.
const test=require("node:test"),assert=require("node:assert/strict");
const {createHash}=require("node:crypto");
const {resolve}=require("node:path");
const {createRequire}=require("node:module");
const host=process.env.FIRESTORE_EMULATOR_HOST||"";
assert.match(host,/^(127\.0\.0\.1|localhost):[0-9]{2,5}$/);
const PROJECT="demo-deda-stage63-owner-e2e";
assert.equal(process.env.GCLOUD_PROJECT,PROJECT);
const req=createRequire(resolve(__dirname,"../functions/package.json"));
const {initializeApp,deleteApp}=req("firebase-admin/app");
const {getFirestore}=req("firebase-admin/firestore");
const {createOwner19Stage59PrivateRoutes,OWNER19,STAGE16,ROUTES}=require(
  "../tools/deda_owner19_stage59_all_server_routes_PRIVATE_NOT_EXPORTED_2026_10_20.js");
const hash=s=>createHash("sha256").update(s).digest("hex");
const privateSuffixes=Array.from({length:100},(_,i)=>
  "Q"+String(i+100).padStart(3,"0"));
const manager={uid:"gm_stage63",key:"gm_account_stage63",id:"@DEDA-A9B8C7"};
const buyer={uid:"buyer_stage63",key:"buyer_account_stage63",id:"@DEDA-B9C8D7"};
const sale="@DEDA-AAAAAA";
class HttpsError extends Error{constructor(code,reason){super(reason);this.code=code;}}
let app,db,routes,secretTouches=0;
function request(uid,data={}){
  return {auth:{uid},app:{appId:"local.emulator.test"},data};
}
function guest(data={}) {
  return {auth:null,app:{appId:"local.emulator.test"},data};
}
function noApp(uid,data={}){return {auth:{uid},data};}
async function call(name,uid,data={}){
  return routes[name](request(uid,data));
}
async function setupUser(batch,person){
  batch.set(db.collection("users").doc(person.uid),{
    accountKey:person.key,sharePersonalId:person.id,
  });
  batch.set(db.collection("deda_sessions").doc(person.uid),{
    uid:person.uid,accountKey:person.key,
  });
  batch.set(db.collection("deda_share_ids").doc(person.id),{
    publicId:person.id,ownerUid:person.uid,kind:"personal",active:true,
  });
}
test.before(async()=>{
  app=initializeApp({projectId:PROJECT},"stage63-owner-flow-no-production");
  db=getFirestore(app);
  const batch=db.batch();
  await setupUser(batch,manager);
  await setupUser(batch,buyer);
  batch.set(db.collection("deda_diamond_gift_balances").doc(buyer.id),{
    publicId:buyer.id,balance:30000,
  });
  batch.set(db.collection("admins").doc(manager.uid),{
    role:"general_manager",status:"active",active:true,
  });
  batch.set(db.collection("admin_entry_access").doc(manager.key),{
    accountKey:manager.key,active:true,status:"active",
    allowedRole:"general_manager",accessType:"general_manager_gateway",
  });
  batch.set(db.collection("deda_verified_id_sale_catalog").doc(sale),{
    identifier:sale,group:"002",status:"verified_available",
    ownerApproved:true,priceDiamonds:10000,
  });
  await batch.commit();
  routes=createOwner19Stage59PrivateRoutes({
    db,onCall:(_,handler)=>handler,HttpsError,
    secret:{value:()=>{secretTouches++;return "test-only-key";}},
    readEncryptedManifest:()=>({testOnly:true}),
    decryptPrivate100:(manifest,key)=>{
      assert.equal(key,"test-only-key");
      assert.equal(manifest.testOnly,true);
      return [...privateSuffixes];
    },
    approvedGroup002:()=>["AAAAAA"],
    flags:{
      purchase:{readExclusive:true,gmSelfUse:true,gmGift:true,
        buyIdentifier:true,listSale:true,
        point16:{read:true,cardPurchase:true,cardUse:true,
          identifierUse:true,alias:true}},
      read:{activeInk:true,publicInk:true,friendAlias:true},
    },
  });
});
test.after(async()=>{if(app)await deleteApp(app);});

test("Auth, AppCheck and nonmanager locks preserve real buyer/GM separation",async()=>{
  await assert.rejects(routes[STAGE16.buyCard](guest({
    color:"gold",requestId:"stage63_card_bad"})),e=>e.code==="unauthenticated");
  await assert.rejects(routes[STAGE16.buyCard](noApp(buyer.uid,{
    color:"gold",requestId:"stage63_card_noapp"})),e=>e.code==="permission-denied");
  await assert.rejects(call(OWNER19.adminRead,buyer.uid,{}),
    e=>e.code==="permission-denied");
  await assert.rejects(call(OWNER19.adminSelfUse,buyer.uid,{
    identifier:"@DEDA-Q100",color:"royal"}),
    e=>e.code==="permission-denied");
  const gift=(await db.collection("deda_diamond_gift_balances")
    .doc(buyer.id).get()).data().balance;
  assert.equal(gift,30000);
});

test("5k bought full-card style -> 1 debit, persisted Use, retry no charge",async()=>{
  const pending=await call(STAGE16.readCards,buyer.uid,{});
  assert.deepEqual(pending.ownedColors,[]);
  const payload={color:"gold",requestId:"stage63_card_purchase_0001"};
  const paid=await call(STAGE16.buyCard,buyer.uid,payload);
  assert.equal(paid.serverConfirmed,true);
  assert.equal(paid.diamondsCharged,5000);
  const replay=await call(STAGE16.buyCard,buyer.uid,payload);
  assert.equal(replay.transactionId,paid.transactionId);
  assert.equal(replay.diamondsCharged,5000); // historical receipt, NOT a new debit
  assert.equal((await db.collection("deda_diamond_gift_balances")
    .doc(buyer.id).get()).data().balance,25000);
  const activated=await call(STAGE16.activateCard,buyer.uid,{color:"gold"});
  assert.equal(activated.activeColor,"gold");
  assert.deepEqual(activated.ownedColors,["gold"]);
  const persistent=await call(STAGE16.readCards,buyer.uid,{});
  assert.equal(persistent.activeColor,"gold");
  const bad=await call(STAGE16.activateCard,buyer.uid,{color:"pink"})
    .then(()=>null,e=>e);
  assert.equal(bad.code,"permission-denied");
  assert.equal((await db.collection("deda_diamond_gift_balances")
    .doc(buyer.id).get()).data().balance,25000);
});

test("10k approved Group002 ID -> global exclusive ownership and durable switch",async()=>{
  const stock=await call(OWNER19.listSale,buyer.uid,{});
  assert.equal(stock.priceDiamonds,10000);
  assert.equal(stock.identifiers.length,1);
  assert.equal(stock.identifiers[0].identifier,sale);
  const data={identifier:sale,requestId:"stage63_identifier_buy_001"};
  const purchased=await call(OWNER19.idPurchase,buyer.uid,data);
  assert.equal(purchased.serverConfirmed,true);
  assert.equal(purchased.diamondsCharged,10000);
  const retry=await call(OWNER19.idPurchase,buyer.uid,data);
  assert.equal(retry.transactionId,purchased.transactionId);
  assert.equal((await db.collection("deda_diamond_gift_balances")
    .doc(buyer.id).get()).data().balance,15000);
  const noStock=await call(OWNER19.listSale,buyer.uid,{});
  assert.equal(noStock.identifiers.length,0);
  const owned=await call(STAGE16.readIdentifiers,buyer.uid,{});
  assert.equal(owned.originalId,buyer.id);
  assert.deepEqual(owned.ownedIds,[buyer.id,sale]);
  const activated=await call(STAGE16.activateIdentifier,buyer.uid,{
    identifier:sale,
  });
  assert.equal(activated.activeId,sale);
  const old=(await db.collection("users").doc(buyer.uid).get()).data();
  assert.equal(old.sharePersonalId,buyer.id);
  assert.equal((await call(STAGE16.readIdentifiers,buyer.uid,{})).activeId,sale);
  await assert.rejects(call(OWNER19.idPurchase,manager.uid,{
    identifier:sale,requestId:"stage63_second_user_buy"}),
    e=>["already-exists","failed-precondition"].includes(e.code));
});

test("manager sees EXACT 100 synthetic IDs, assigns four distinct permanent colors",async()=>{
  const first=await call(OWNER19.adminRead,manager.uid,{});
  assert.equal(first.total,100);
  assert.deepEqual(first.identifiers.map(x=>x.identifier),
    privateSuffixes.map(x=>"@DEDA-"+x));
  assert.deepEqual(first.history,[]);
  for(const [index,color] of ["gold","diamond","royal","pink"].entries()){
    const id="@DEDA-"+privateSuffixes[index];
    const granted=await call(OWNER19.adminSelfUse,manager.uid,{
      identifier:id,color,
    });
    assert.equal(granted.serverConfirmed,true);
    assert.equal(granted.permanentColor,color);
    assert.equal(granted.activeId,id);
    const row=(await db.collection("deda_owned_identifier_registry")
      .doc(id).get()).data();
    assert.equal(row.assignedColor,color);
    await assert.rejects(call(OWNER19.adminSelfUse,manager.uid,{
      identifier:id,color:color==="gold"?"pink":"gold",
    }),e=>e.code==="already-exists");
  }
  const after=await call(OWNER19.adminRead,manager.uid,{});
  assert.equal(after.total,100);
  assert.equal(after.history.length,4);
  assert.ok(after.identifiers.slice(0,4)
    .every((x,i)=>x.status==="self_used"&&
      x.permanentColor===["gold","diamond","royal","pink"][i]));
  assert.ok(after.history.every((x,i,a)=>i===0 ||
    a[i-1].grantedAt>=x.grantedAt));
  const ledger=await call(STAGE16.readIdentifiers,manager.uid,{});
  assert.equal(ledger.originalId,manager.id);
  assert.equal(ledger.ownedIds.length,5);
  assert.equal((await db.collection("users").doc(manager.uid).get()).data()
    .sharePersonalId,manager.id);
});

test("manager grants 5th reserved ID with fixed color, true history and recipient ownership",async()=>{
  const gifted="@DEDA-"+privateSuffixes[4];
  const grant=await call(OWNER19.adminGrant,manager.uid,{
    identifier:gifted,color:"pink",recipientOriginalId:buyer.id,
  });
  assert.equal(grant.serverConfirmed,true);
  assert.equal(grant.permanentColor,"pink");
  assert.equal(grant.recipientOriginalId,buyer.id);
  const read=await call(OWNER19.adminRead,manager.uid,{});
  assert.equal(read.history.length,5);
  assert.equal(read.identifiers[4].status,"gifted");
  assert.equal(read.identifiers[4].ownerOriginalId,buyer.id);
  assert.equal(read.identifiers[4].permanentColor,"pink");
  assert.ok(read.history.some(x=>x.identifier===gifted &&
    x.recipientOriginalId===buyer.id&&x.color==="pink"&&x.kind==="gifted"));
  const before=await call(STAGE16.readIdentifiers,buyer.uid,{});
  assert.ok(before.ownedIds.includes(gifted));
  const activated=await call(STAGE16.activateIdentifier,buyer.uid,{
    identifier:gifted,
  });
  assert.equal(activated.activeId,gifted);
  const switched=await call(STAGE16.readIdentifiers,buyer.uid,{});
  assert.equal(switched.activeId,gifted);
  assert.equal(switched.originalId,buyer.id);
  assert.ok(switched.ownedIds.includes(sale));
  assert.equal((await db.collection("deda_diamond_gift_balances")
    .doc(buyer.id).get()).data().balance,15000);
  await assert.rejects(call(OWNER19.adminGrant,manager.uid,{
    identifier:gifted,color:"gold",recipientOriginalId:buyer.id,
  }),e=>["already-exists","failed-precondition"].includes(e.code));
  const verified=await call(OWNER19.adminRead,manager.uid,{});
  assert.equal(verified.history.length,5);
  assert.ok(secretTouches>0); // server-only synthetic catalog; no real key.
});


test("public/friend/profile verified ink survives gift and resolves the ORIGINAL account",async()=>{
  const gifted="@DEDA-"+privateSuffixes[4];
  const active=await call(ROUTES.activeInk,buyer.uid,{});
  assert.equal(active.serverConfirmed,true);
  assert.equal(active.originalId,buyer.id);
  assert.equal(active.activeId,gifted);
  assert.equal(active.permanentColor,"pink");

  for(const wanted of [buyer.id,gifted]){
    const visible=await call(ROUTES.publicInk,manager.uid,{
      identifier:wanted,
    });
    assert.deepEqual({
      confirmed:visible.serverConfirmed,
      requested:visible.requestedId,
      displayed:visible.displayId,
      fixedInk:visible.permanentColor,
    },{
      confirmed:true,requested:wanted,displayed:gifted,fixedInk:"pink",
    });
  }

  const friend=await call(ROUTES.friendAlias,manager.uid,{
    identifier:gifted,
  });
  assert.equal(friend.serverConfirmed,true);
  assert.equal(friend.requestedId,gifted);
  assert.equal(friend.originalId,buyer.id);
  const lookup=await call(ROUTES.friendAlias,manager.uid,{
    identifier:buyer.id,
  });
  assert.equal(lookup.originalId,buyer.id);
  for(const payload of [active,friend,lookup]){
    assert.ok(!Object.hasOwn(payload,"accountKey"));
    assert.ok(!Object.hasOwn(payload,"phone"));
    assert.ok(!Object.hasOwn(payload,"balance"));
    assert.ok(!Object.hasOwn(payload,"location"));
  }
  const finalWallet=(await db.collection("deda_diamond_gift_balances")
    .doc(buyer.id).get()).data().balance;
  assert.equal(finalWallet,15000);
});
