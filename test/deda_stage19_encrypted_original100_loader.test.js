"use strict";
const {test} = require("node:test");
const assert = require("node:assert/strict");
const {randomBytes, createCipheriv} = require("node:crypto");
const {deflateSync} = require("node:zlib");
const fs = require("node:fs");
const path = require("node:path");
const {decryptOwnerPrivate100, readOwnerPrivate100FromSecret} =
  require("../tools/deda_stage19_private_admin100_decrypt_server_only_2026_10_19.js");

const AAD = "DEDA|STAGE19|GROUP001|OWNER_ADMIN100|v1";
const secret = randomBytes(32);
const names = ["SALEM", ...Array.from({length: 98}, (_, i) =>
  "T" + String(i).padStart(3, "0")), "2020"];

function encrypt(plainNames, key=secret) {
  const nonce = randomBytes(12);
  const data = deflateSync(Buffer.from(JSON.stringify({
    schema:"DEDA_ADMIN_EXCLUSIVE_GROUP001", version:1, names:plainNames,
  })), {level: 9});
  const c = createCipheriv("aes-256-gcm", key, nonce);
  c.setAAD(Buffer.from(AAD));
  const wire = Buffer.concat([c.update(data), c.final(), c.getAuthTag()]);
  return {
    kind: "DEDA_ADMIN_EXCLUSIVE_CATALOG_ENCRYPTED",
    version:1, alg:"AES-256-GCM", compression:"zlib", aad:AAD,
    nonce_b64:nonce.toString("base64"), ciphertext_b64:wire.toString("base64"),
    expected_count:100,
  };
}
function privateKey() {return secret.toString("base64");}

test("encrypted server-only 100 manifest decrypts and preserves all 100 in precise order", ()=>{
  const result=decryptOwnerPrivate100(encrypt(names),privateKey());
  assert.equal(result.length,100);
  assert.deepEqual(result,names);
  assert.equal(Object.isFrozen(result),true);
});

test("wrong key cannot decrypt owner-only catalog", ()=>{
  assert.throws(()=>decryptOwnerPrivate100(encrypt(names),randomBytes(32).toString("base64")),
    /private-admin100-unavailable-or-invalid/);
});

test("tampered ciphertext or AAD rejected without partial member list", ()=>{
  const msg=encrypt(names);
  const wire=Buffer.from(msg.ciphertext_b64,"base64");
  wire[10] ^= 0xFF;
  assert.throws(()=>decryptOwnerPrivate100({
    ...msg,ciphertext_b64:wire.toString("base64"),
  },privateKey()), /private-admin100-unavailable-or-invalid/);
  assert.throws(()=>decryptOwnerPrivate100({...msg,aad:"public"},privateKey()),
    /private-admin100-unavailable-or-invalid/);
});

test("truncated, duplicate, reordered or malformed member lists rejected", ()=>{
  for(const other of [
    names.slice(1),
    [...names.slice(0,99),names[0]],
    [...names.slice(0,99),"2021"],
    ["2020",...names.slice(1,99),"SALEM"],
    [...names.slice(0,99),"a space"],
  ]) {
    assert.throws(()=>decryptOwnerPrivate100(encrypt(other),privateKey()),
      /private-admin100-unavailable-or-invalid/);
  }
});

test("public GitHub ciphertext is authentic schema, but not decryptable without private key", ()=>{
  const payload = JSON.parse(fs.readFileSync(path.join(__dirname,
    "../server_private/catalogs/DEDA_GROUP001_ADMIN100_AES256GCM_2026-10-19.enc.json"),"utf8"));
  assert.equal(payload.expected_count,100);
  assert.equal(payload.aad,AAD);
  assert.equal(payload.alg,"AES-256-GCM");
  assert.equal(payload.kind,"DEDA_ADMIN_EXCLUSIVE_CATALOG_ENCRYPTED");
  assert.throws(()=>decryptOwnerPrivate100(payload,privateKey()),
    /private-admin100-unavailable-or-invalid/);
});

test("production Firebase and Android source never contain ciphertext key or staged decoder", ()=>{
  for(const filename of ["functions/index.js","lib/main.dart"]) {
    const text=fs.readFileSync(path.join(__dirname,"..",filename),"utf8");
    assert.equal(text.includes("DEDA_STAGE19_ADMIN100_AES_KEY_B64"),false);
    assert.equal(text.includes("deda_stage19_private_admin100_decrypt_server_only"),false);
  }
});
