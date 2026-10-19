"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {readAvailableApprovedIdentifiers, PRICE} = require(
  "../tools/deda_100359_stage41_verified_sale_list_private_2026_10_20.js");
const {createApprovedSaleCatalog} = require(
  "../tools/deda_stage18_private_atomic_identifier_checkout_2026_10_19.js");
const {createOwner19Gateway} = require(
  "../tools/deda_100359_owner19_combined_gateway_private_2026_10_19.js");

class Ref {
  constructor(db, path) {this.db=db;this.path=path;}
  doc(id) {return new Ref(this.db,this.path+"/"+id);}
  async get() {
    const x = this.db.docs.get(this.path);
    return {exists:x!==undefined,data:()=>structuredClone(x)};
  }
}
class Memory {
  constructor(){this.docs=new Map();}
  collection(name){return new Ref(this,name);}
  put(p,v){this.docs.set(p,v);}
  async runTransaction(){throw Error("no writes on catalog read");}
}
const reserved = Array.from({length:100},(_,i)=>"R"+String(i).padStart(3,"0"));
const sale = ["SALE01","SALE02"];
const config = () => createApprovedSaleCatalog({
  approvedSuffixes:sale,reservedSuffixes:reserved,
});
function stock(db,id,changes={}) {
  db.put("deda_verified_id_sale_catalog/"+id,{
    identifier:id,group:"002",status:"verified_available",
    priceDiamonds:10000,ownerApproved:true,...changes,
  });
}
const req = {auth:{uid:"validUid"},app:{appId:"verifiedApp"},data:{}};

test("only verified live sale stock is visible, no mock proposals", async () => {
  const db=new Memory();
  stock(db,"@DEDA-SALE01");
  const result=await readAvailableApprovedIdentifiers(db,{
    approvedCatalog:config(),approvedSuffixes:sale,
  });
  assert.deepEqual(result.identifiers, [{
    identifier:"@DEDA-SALE01",priceDiamonds:PRICE,
  }]);
  assert.equal(result.serverConfirmed,true);
  assert.equal(PRICE,10000);
  assert.equal(db.docs.size,1);
});
test("available candidate with existing public/alias/registry ID cannot appear", async () => {
  for(const collision of [
    "deda_share_ids/","deda_owned_identifier_aliases/",
    "deda_owned_identifier_registry/",
  ]) {
    const db=new Memory();
    stock(db,"@DEDA-SALE01");
    db.put(collision+"@DEDA-SALE01",{owner:"someone"});
    const x=await readAvailableApprovedIdentifiers(db,{
      approvedCatalog:config(),approvedSuffixes:sale,
    });
    assert.equal(x.identifiers.length,0,collision);
  }
});
test("unapproved stock, unpublished and forged sale pricing are ignored", async () => {
  for(const override of [{ownerApproved:false},{status:"proposal_only_not_for_sale"},
    {priceDiamonds:1},{group:"001"}]) {
    const db=new Memory();
    stock(db,"@DEDA-SALE01",override);
    const x=await readAvailableApprovedIdentifiers(db,{
      approvedCatalog:config(),approvedSuffixes:sale,
    });
    assert.deepEqual(x.identifiers,[]);
  }
});
test("reserved 100 cannot enter sale catalog; no catalog fails closed", async () => {
  const db=new Memory();
  await assert.rejects(readAvailableApprovedIdentifiers(db,{
    approvedSuffixes:sale,
  }),/failed-precondition/);
  assert.throws(()=>createApprovedSaleCatalog({
    approvedSuffixes:["R000"],reservedSuffixes:reserved,
  }),/reserved-identifier-cannot-be-listed|invalid-approved-sale/);
});
test("sale list callable defaults OFF, requires AppCheck, rejects client filters",async()=>{
  const db=new Memory();
  const gateway=createOwner19Gateway({
    db,exclusiveSuffixes:reserved,approvedSellableSuffixes:sale,
  });
  await assert.rejects(gateway.handle("listSale",req),/unavailable/);
  const live=createOwner19Gateway({
    db,exclusiveSuffixes:reserved,approvedSellableSuffixes:sale,
    flags:{listSale:true},
  });
  await assert.rejects(live.handle("listSale",{auth:req.auth,data:{}}),
    /permission-denied/);
  await assert.rejects(live.handle("listSale",{...req,data:{price:0}}),
    /invalid-argument/);
  stock(db,"@DEDA-SALE01");
  const x=await live.handle("listSale",req);
  assert.deepEqual(x.identifiers,[{identifier:"@DEDA-SALE01",priceDiamonds:10000}]);
});
