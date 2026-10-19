"use strict";

// SERVER ONLY — Stage19 Group001 encrypted owner-private catalog loader.
// The encrypted JSON may be in PUBLIC GitHub: the AES key NEVER belongs
// in this repository, client APK, CI logs, or a public environment. For a
// future reviewed Cloud Function, inject the key via Firebase Secret Manager.
const {createDecipheriv} = require("node:crypto");
const {inflateSync} = require("node:zlib");
const {readFileSync} = require("node:fs");
const path = require("node:path");

const MANIFEST = "server_private/catalogs/DEDA_GROUP001_ADMIN100_AES256GCM_2026-10-19.enc.json";
const AAD = "DEDA|STAGE19|GROUP001|OWNER_ADMIN100|v1";
const SUFFIX = /^[A-Z0-9]{4,12}$/;

function stop() {
  throw new Error("private-admin100-unavailable-or-invalid");
}
function exactBase64(value, length) {
  if (typeof value !== "string" || !/^[A-Za-z0-9+/]+={0,2}$/.test(value) ||
      value.length % 4 !== 0) stop();
  const b = Buffer.from(value, "base64");
  if (b.toString("base64") !== value ||
      (length != null && b.length !== length)) stop();
  return b;
}

function decryptOwnerPrivate100(encryptedPayload, privateKeyB64) {
  try {
    if (!encryptedPayload || typeof encryptedPayload !== "object" ||
        encryptedPayload.kind !== "DEDA_ADMIN_EXCLUSIVE_CATALOG_ENCRYPTED" ||
        encryptedPayload.version !== 1 ||
        encryptedPayload.alg !== "AES-256-GCM" ||
        encryptedPayload.compression !== "zlib" ||
        encryptedPayload.aad !== AAD ||
        encryptedPayload.expected_count !== 100) stop();
    const key = exactBase64(privateKeyB64, 32);
    const iv = exactBase64(encryptedPayload.nonce_b64, 12);
    const cipherAndTag = exactBase64(encryptedPayload.ciphertext_b64);
    if (cipherAndTag.length < 32) stop();
    const tag = cipherAndTag.subarray(-16);
    const cipher = cipherAndTag.subarray(0, -16);
    const decipher = createDecipheriv("aes-256-gcm", key, iv);
    decipher.setAAD(Buffer.from(AAD, "utf8"));
    decipher.setAuthTag(tag);
    const compressed = Buffer.concat([
      decipher.update(cipher), decipher.final(),
    ]);
    const raw = inflateSync(compressed, {maxOutputLength: 16 * 1024});
    const decoded = JSON.parse(raw.toString("utf8"));
    if (decoded.schema !== "DEDA_ADMIN_EXCLUSIVE_GROUP001" ||
        decoded.version !== 1 || !Array.isArray(decoded.names) ||
        decoded.names.length !== 100 ||
        decoded.names.some(n => typeof n !== "string" || !SUFFIX.test(n)) ||
        new Set(decoded.names).size !== 100 ||
        decoded.names[0] !== "SALEM" ||
        decoded.names[99] !== "2020") stop();
    // Return one fresh array in precisely original numbered order.
    return Object.freeze([...decoded.names]);
  } catch (_) {
    // Never echo names, key, ciphertext, or cryptographic error details.
    stop();
  }
}

function readOwnerPrivate100FromSecret(privateKeyB64, repoRoot = path.join(__dirname, "..")) {
  if (typeof repoRoot !== "string" || !repoRoot) stop();
  try {
    const encrypted = JSON.parse(readFileSync(path.join(repoRoot, MANIFEST), "utf8"));
    return decryptOwnerPrivate100(encrypted, privateKeyB64);
  } catch (_) {
    stop();
  }
}

module.exports = {decryptOwnerPrivate100, readOwnerPrivate100FromSecret};
