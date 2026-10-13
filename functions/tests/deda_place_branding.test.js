"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {setPlaceTheme, requirePaletteIndex} = require("../deda_place_branding.js");

class FakeDoc {
  constructor(map, id) {this.map = map; this.id = id;}
  async get() {const row=this.map.get(this.id);return {exists:row!==undefined,data:()=>row};}
}
class FakeDB {
  constructor() {this.rows = new Map();}
  collection(name) {return {doc:(id)=>new FakeDoc(this.rows,name+"/"+id)};}
  async runTransaction(callback) {
    const edits=[];
    const result=await callback({
      get:(ref)=>ref.get(),
      update:(ref, fields)=>edits.push({ref,fields}),
    });
    for(const edit of edits) this.rows.set(edit.ref.id, {...this.rows.get(edit.ref.id), ...edit.fields});
    return result;
  }
}
function seeded() {
  const db=new FakeDB();
  db.rows.set("users/uid1",{accountKey:"9647700000001"});
  db.rows.set("deda_sessions/uid1",{accountKey:"9647700000001"});
  db.rows.set("users/uid2",{accountKey:"9647700000002"});
  db.rows.set("deda_sessions/uid2",{accountKey:"9647700000002"});
  db.rows.set("published_places/approved_place_01",{
    published:true,status:"approved", ownerUid:"uid1", accountKey:"9647700000001",
    name:"حلاقة الأخوين",themeIndex:4, latitude:32.4,longitude:44.3,
    approvalNumber:"DEDA-2026-0000017",
  });
  return db;
}
test("accepted indices are exactly 0..13 integers",()=>{
  for(let i=0;i<=13;i++)assert.equal(requirePaletteIndex(i),i);
  for(const bad of [-1,14,1.5,"2",null,false])assert.throws(()=>requirePaletteIndex(bad));
});
test("verified owner changes only the published colour without other changes", async()=>{
  const db=seeded(), key="published_places/approved_place_01";
  const before={...db.rows.get(key)};
  const result=await setPlaceTheme(db,{uid:"uid1",placeId:"approved_place_01",themeIndex:1});
  assert.deepEqual(result,{placeId:"approved_place_01",themeIndex:1});
  assert.deepEqual(db.rows.get(key),{...before,themeIndex:1});
  await setPlaceTheme(db,{uid:"uid1",placeId:"approved_place_01",themeIndex:1});
  assert.deepEqual(db.rows.get(key),{...before,themeIndex:1});
});
test("other accounts and missing verification cannot recolour places",async()=>{
  const db=seeded(), key="published_places/approved_place_01";
  const before={...db.rows.get(key)};
  await assert.rejects(()=>setPlaceTheme(db,{uid:"uid2",placeId:"approved_place_01",themeIndex:10}),/published-owner-place-required/);
  db.rows.delete("deda_sessions/uid1");
  await assert.rejects(()=>setPlaceTheme(db,{uid:"uid1",placeId:"approved_place_01",themeIndex:10}),/verified-owner-session-required/);
  assert.deepEqual(db.rows.get(key),before);
});
test("hidden, deleted or unpublished places are immutable",async()=>{
  for(const state of [{hiddenByManager:true},{published:false},{deleted:true},{status:"deleted"}]){
    const db=seeded(),key="published_places/approved_place_01";
    db.rows.set(key,{...db.rows.get(key),...state});
    const original={...db.rows.get(key)};
    await assert.rejects(()=>setPlaceTheme(db,{uid:"uid1",placeId:"approved_place_01",themeIndex:12}),/published-owner-place-required/);
    assert.deepEqual(db.rows.get(key),original);
  }
});
