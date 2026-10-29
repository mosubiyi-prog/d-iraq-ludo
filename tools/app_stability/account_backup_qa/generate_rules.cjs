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
// Firestore grammar expects helper functions in the root function-declaration
// section BEFORE child match statements. The existing original rules keep
// their original order; only the QA helpers are inserted after signedIn().
const matchStart="    match /deda_progress_evidence/{accountKey}/captures/{captureId} {";
const signedIn="    function signedIn() { return request.auth != null; }";
if(block.split(matchStart).length!==2||source.split(signedIn).length!==2)
 throw Error("QA_RULES_HELPER_SCOPE_DRIFT");
const [helperDeclarations, archiveMatch]=block.split(matchStart);
// NEVER use string replacement values: Firestore regex ends with "
fs.writeFileSync(path.join(root,"deda_account_backup_qa.generated.rules"),
  generated,"utf8");
process.stdout.write("QA candidate generated; original Firestore rules untouched\n");
" which
// JavaScript String.replace() interprets as "append unmatched source suffix".
// In the prior candidate this silently TRIPLED the original rules.
const generated=source.replace(signedIn,()=>signedIn+"\n"+helperDeclarations)
  .replace(anchor,()=>matchStart+archiveMatch+"\n"+anchor);
const expectedLength=source.length+helperDeclarations.length+matchStart.length+archiveMatch.length+2;
if(generated.length!==expectedLength ||
   generated.split(anchor).length!==2 ||
   generated.split(matchStart).length!==2 ||
   generated.split('rules_version = ').length!==2 ||
   generated.split("    function signedIn() { return request.auth != null; }").length!==2 ||
   !generated.endsWith(source.slice(-48))) {
  throw Error("QA_ARCHIVE_RULES_DUPLICATION_OR_TRUNCATION_HOLD");
}
fs.writeFileSync(path.join(root,"deda_account_backup_qa.generated.rules"),
  generated,"utf8");
process.stdout.write("QA candidate generated; original Firestore rules untouched\n");
