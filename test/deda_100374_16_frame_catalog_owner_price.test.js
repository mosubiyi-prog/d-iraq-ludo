"use strict";
const test=require("node:test");
const assert=require("node:assert/strict");
const fs=require("node:fs");
const crypto=require("node:crypto");

const catalog=require("../docs/DEDA_LAB_16_VERIFIED_FRAME_CATALOG_STAGED_ONLY_2026-10-21.json");
const sha=p=>crypto.createHash("sha256").update(fs.readFileSync(p)).digest("hex");

test("exactly 16 original uniquely numbered LAB artworks; 3 free 13 locked",()=>{
  assert.equal(catalog.total,16);
  assert.equal(catalog.frames.length,16);
  const names=new Set(),digests=new Set();
  for(const [index,item] of catalog.frames.entries()){
    assert.equal(item.id,"FRAME_"+String(index+1).padStart(2,"0"));
    assert.match(item.name_ar,/\S/);
    assert.match(item.sha256,/^[0-9a-f]{64}$/);
    assert.ok(item.bytes>100000 && item.bytes<900000);
    assert.equal(names.has(item.name_ar),false);
    assert.equal(digests.has(item.sha256),false);
    names.add(item.name_ar);digests.add(item.sha256);
  }
  assert.equal(names.size,16);
  assert.equal(digests.size,16);
});

test("the three genuine existing royal assets match LAB originals byte for byte",()=>{
  const expected={"FRAME_01":"royal_frame_1.webp",
    "FRAME_02":"royal_frame_2.webp","FRAME_04":"royal_frame_0.webp"};
  for(const [id,basename] of Object.entries(expected)){
    const row=catalog.frames.find(f=>f.id===id);
    assert.equal(row.initial_price_diamonds,0);
    const p="assets/deda_royal_frames/"+basename;
    assert.ok(fs.existsSync(p));
    assert.equal(fs.statSync(p).size,row.bytes);
    assert.equal(sha(p),row.sha256);
    assert.equal(row.base_asset_at_100373,p);
  }
});

test("every additional frame is locked at exactly 1000, three remain free",()=>{
  const free=catalog.frames.filter(f=>f.initial_access==="free");
  const locked=catalog.frames.filter(f=>f.initial_access==="locked");
  assert.deepEqual(free.map(x=>x.id),["FRAME_01","FRAME_02","FRAME_04"]);
  assert.equal(locked.length,13);
  assert.ok(free.every(f=>f.initial_price_diamonds===0));
  assert.ok(locked.every(f=>f.initial_price_diamonds===1000 && !f.base_asset_at_100373));
  assert.equal(catalog.additionalLockedUnitPriceDiamonds,1000);
  assert.equal(catalog.internalAvatarSize,"111x111");
  assert.equal(catalog.referenceAssetCanvas,"850x850");
});

test("frame catalog is staging only; no fake wallet or product entitlement",()=>{
  assert.match(catalog.status,/NOT a deployed purchasing ledger/);
  assert.ok(catalog.frames.every(f=>Object.keys(f).every(k=>
    !/balance|wallet|ownerUid|receipt|purchaseRecord/i.test(k))));
});
