"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const {randomBytes, createCipheriv} = require("node:crypto");
const {deflateSync} = require("node:zlib");
const {verifyOwnerPrivate100Offline} = require(
  "../tools/deda_owner19_private100_key_preflight_OFFLINE_ONLY.js");

// Fully synthetic 100-name fixture; NEVER access the real owner's private key.
const aad = "DEDA|STAGE19|GROUP001|OWNER_ADMIN100|v1";
function fixture() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "deda-qa-private-"));
  const homeDir = path.join(root, "owner");
  const privateDir = path.join(homeDir, ".deda-private");
  const catalogDir = path.join(root, "server_private", "catalogs");
  fs.mkdirSync(privateDir, {recursive:true, mode:0o700});
  fs.mkdirSync(catalogDir, {recursive:true});
  fs.chmodSync(privateDir, 0o700);
  const key = randomBytes(32);
  const nonce = randomBytes(12);
  const cipher = createCipheriv("aes-256-gcm", key, nonce);
  cipher.setAAD(Buffer.from(aad));
  const names = ["SALEM", ...Array.from({length:98}, (_, i) =>
    "Z" + String(i + 1).padStart(3,"0")), "2020"];
  const body = deflateSync(Buffer.from(JSON.stringify({
    schema:"DEDA_ADMIN_EXCLUSIVE_GROUP001",version:1,names,
  })));
  const encrypted = Buffer.concat([cipher.update(body),
    cipher.final(),cipher.getAuthTag()]);
  fs.writeFileSync(path.join(catalogDir,
    "DEDA_GROUP001_ADMIN100_AES256GCM_2026-10-19.enc.json"),
    JSON.stringify({
      kind:"DEDA_ADMIN_EXCLUSIVE_CATALOG_ENCRYPTED",
      version:1,alg:"AES-256-GCM",compression:"zlib",aad,
      expected_count:100,nonce_b64:nonce.toString("base64"),
      ciphertext_b64:encrypted.toString("base64"),
    }));
  const keyFile = path.join(privateDir,"key.txt");
  fs.writeFileSync(keyFile,
    "Owner document header\\n"+key.toString("base64")+
    "\\nProtected note\\n", {mode:0o600});
  fs.chmodSync(keyFile,0o600);
  return {root,homeDir,privateDir,keyFile,clean:()=>fs.rmSync(root,{
    recursive:true,force:true})};
}

test("synthetic owner document decrypts exactly 100 offline with no output", () => {
  const f=fixture();
  try {
    assert.deepEqual(verifyOwnerPrivate100Offline({
      homeDir:f.homeDir,repoRoot:f.root}),{valid:true,count:100});
  } finally {f.clean();}
});

test("wrong, unreadable, or world-readable local key fails closed", () => {
  const f=fixture();
  try {
    fs.chmodSync(f.keyFile,0o644);
    assert.throws(()=>verifyOwnerPrivate100Offline({
      homeDir:f.homeDir,repoRoot:f.root}),/offline-preflight-failed/);
    fs.chmodSync(f.keyFile,0o600);
    fs.writeFileSync(f.keyFile,randomBytes(32).toString("base64"));
    assert.throws(()=>verifyOwnerPrivate100Offline({
      homeDir:f.homeDir,repoRoot:f.root}),/offline-preflight-failed/);
  } finally {f.clean();}
});

test("symlinked private key is refused", () => {
  const f=fixture();
  try {
    const orig=path.join(f.privateDir,"original.txt");
    fs.renameSync(f.keyFile,orig);
    fs.symlinkSync(orig,f.keyFile);
    assert.throws(()=>verifyOwnerPrivate100Offline({
      homeDir:f.homeDir,repoRoot:f.root}),/offline-preflight-failed/);
  } finally {f.clean();}
});
