"use strict";

// OWNER DEVICE ONLY, READ-ONLY. Never upload a key, the original 100 names,
// or this local private file to GitHub, an APK, Firebase, logs or telemetry.
// This validates the owner's paired ciphertext without any network request.
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const {decryptOwnerPrivate100} = require(
  "./deda_stage19_private_admin100_decrypt_server_only_2026_10_19.js");

const MANIFEST = "server_private/catalogs/DEDA_GROUP001_ADMIN100_AES256GCM_2026-10-19.enc.json";

function fail() {
  throw new Error("owner-private100-offline-preflight-failed");
}
function secureLocalFile(file, isDirectory) {
  let stat;
  try {stat = fs.lstatSync(file);} catch (_) {fail();}
  if (stat.isSymbolicLink() || (stat.mode & 0o077) !== 0 ||
      (isDirectory ? !stat.isDirectory() : !stat.isFile())) fail();
  return stat;
}
function verifyOwnerPrivate100Offline({
  homeDir = os.homedir(),
  repoRoot = path.resolve(__dirname, ".."),
} = {}) {
  const privateDir = path.join(homeDir, ".deda-private");
  const keyFile = path.join(privateDir, "key.txt");
  secureLocalFile(privateDir, true);
  const keyStat = secureLocalFile(keyFile, false);
  if (keyStat.size < 44 || keyStat.size > 16384) fail();
  let source, manifest;
  try {
    source = fs.readFileSync(keyFile, "utf8");
    manifest = JSON.parse(fs.readFileSync(
      path.join(repoRoot, MANIFEST), "utf8"));
  } catch (_) {fail();}
  // The original owner key document may contain explanatory text.
  // Accept only 44-char AES-256 base64 candidates, and prove exactly one
  // candidate decrypts the authenticated original 100 in correct order.
  const candidates = [...new Set(source.match(/[A-Za-z0-9+/]{43}=/g) || [])];
  if (candidates.length < 1 || candidates.length > 25) fail();
  let matches = 0;
  for (const candidate of candidates) {
    try {
      const result = decryptOwnerPrivate100(manifest, candidate);
      if (result.length === 100) matches++;
    } catch (_) {
      // Never print failed candidates or cryptographic details.
    }
  }
  if (matches !== 1) fail();
  return Object.freeze({valid: true, count: 100});
}
if (require.main === module) {
  try {
    const outcome = verifyOwnerPrivate100Offline();
    process.stdout.write(
      "PASS: protected owner key matches encrypted catalog " +
      outcome.count + "/100; no secret exported, NO DEPLOY.\\n");
  } catch (_) {
    process.stderr.write("SAFE_STOP: offline key/catalog check failed.\\n");
    process.exitCode = 1;
  }
}
module.exports = {verifyOwnerPrivate100Offline};
