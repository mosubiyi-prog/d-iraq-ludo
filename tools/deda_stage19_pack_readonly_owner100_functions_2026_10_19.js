"use strict";

// Create an ISOLATED, reproducible server-only runtime for owner's review.
// Neither this file nor GitHub Actions deploys Functions or sets any secret.
// GitHub repository is public: only existing AES-GCM ciphertext is included;
// absolutely NEVER copy owner private decryption key or original JSON/TXT.
const fs=require("node:fs");
const path=require("node:path");
const {createHash}=require("node:crypto");

const SOURCES=Object.freeze([
  ["tools/deda_intakadha_point15_identifier_ownership_admin_gifts_2026_10_19.js",
   "deda_intakadha_point15_identifier_ownership_admin_gifts_2026_10_19.js"],
  ["tools/deda_stage19_private_exclusive_catalog_reader_2026_10_19.js",
   "deda_stage19_private_exclusive_catalog_reader_2026_10_19.js"],
  ["tools/deda_stage19_private_admin100_decrypt_server_only_2026_10_19.js",
   "deda_stage19_private_admin100_decrypt_server_only_2026_10_19.js"],
  ["server_private/catalogs/DEDA_GROUP001_ADMIN100_AES256GCM_2026-10-19.enc.json",
   "catalogs/DEDA_GROUP001_ADMIN100_AES256GCM_2026-10-19.enc.json"],
]);
const SECRETS=["DEDA_STAGE19_ADMIN100_AES_KEY_B64",
 "DEDA_100_IDENTIFIERS_BACKUP.json",
 "DEDA_100_IDENTIFIERS_NUMBERED.txt"];

function packStage19ReadOnly(repoRoot, outDir) {
  const root=path.resolve(repoRoot);
  const dest=path.resolve(outDir);
  const allowed=path.resolve(root,"functions","stage19_private","runtime");
  if(dest!==allowed)throw Error("SAFE_STOP: runtime directory must be stage19 only");
  if (fs.existsSync(dest)) {
    const current=fs.readdirSync(dest);
    if(current.length)throw Error("SAFE_STOP: existing runtime must not be overwritten");
  }
  const live=fs.readFileSync(path.join(root,"functions","index.js"),"utf8");
  if (live.includes("stage19_owner100_readonly_NOT_EXPORTED") ||
      live.includes("dedaStage19Exclusive100Read") ||
      live.includes("deda_stage19_private_exclusive_catalog_reader")) {
    throw Error("SAFE_STOP: production Functions must remain untouched");
  }
  const hashes=[];
  for(const [source, target] of SOURCES) {
    const bytes=fs.readFileSync(path.join(root,source));
    const content=bytes.toString("utf8");
    if(SECRETS.some(x=>source.includes(x) || target.includes(x))) {
      throw Error("SAFE_STOP: no plaintext or secrets may be bundled");
    }
    if(target.endsWith(".json")) {
      const body=JSON.parse(content);
      if(body.kind!=="DEDA_ADMIN_EXCLUSIVE_CATALOG_ENCRYPTED" ||
          body.version!==1 ||
          body.alg!=="AES-256-GCM" ||
          body.expected_count!==100 ||
          typeof body.ciphertext_b64!=="string" ||
          typeof body.nonce_b64!=="string" ||
          content.includes('"names"')) {
        throw Error("SAFE_STOP: only validated ciphertext is permitted");
      }
    }
    const targetPath=path.join(dest,target);
    fs.mkdirSync(path.dirname(targetPath),{recursive:true});
    fs.writeFileSync(targetPath,bytes,{flag:"wx"});
    const reread=fs.readFileSync(targetPath);
    if(!reread.equals(bytes))throw Error("SAFE_STOP: bundled bytes mismatch");
    hashes.push({relative:target,sha256:createHash("sha256")
      .update(bytes).digest("hex")});
  }
  return Object.freeze(hashes);
}

if(require.main===module) {
  try{
    const root=path.resolve(__dirname,"..");
    const manifest=packStage19ReadOnly(
      root,path.join(root,"functions","stage19_private","runtime"));
    // Only file count and digests, never decrypted names or secret.
    process.stdout.write("PASS: staged read-only ciphertext runtime source "+
      manifest.length+" files SHA256 verified. NO deploy.\n");
  }catch(e) {
    process.stderr.write("SAFE_STOP: "+e.message+"\n");
    process.exitCode=1;
  }
}
module.exports={packStage19ReadOnly,SOURCES};
