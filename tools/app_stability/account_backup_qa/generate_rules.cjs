"use strict";
const fs=require("node:fs"), path=require("node:path");
const root=path.resolve(__dirname,"../../..");
const source=fs.readFileSync(path.join(root,"firestore.rules"),"utf8");
const block=fs.readFileSync(path.join(__dirname,"qa_archive_rule_block.txt"),"utf8");
const anchor="    match /deda_account_profiles/{accountKey} {";
if(source.split(anchor).length!==2 ||
   source.includes("match /deda_progress_evidence/{accountKey}/captures/{captureId}") ||
   !source.includes("match /deda_auth_attempts/{uid} {") ||
   !source.includes("match /deda_sessions/{uid} {") ||
   !block.includes("allow update, delete: if false;"))
  throw Error("DEDA_QA_ARCHIVE_BASELINE_DRIFT_HOLD");
fs.writeFileSync(path.join(root,"deda_account_backup_qa.generated.rules"),
  source.replace(anchor,block+"\n"+anchor),"utf8");
process.stdout.write("QA candidate generated; original Firestore rules untouched\n");
