"use strict";
const fs=require("node:fs"), path=require("node:path");
const root=path.resolve(__dirname,"../../..");
const source=fs.readFileSync(path.join(root,"firestore.rules"),"utf8");
const block=fs.readFileSync(path.join(__dirname,"qa_archive_rule_block.txt"),"utf8");
const anchor="    match /deda_account_profiles/{accountKey} {";
const matchStart="    match /deda_progress_evidence/{accountKey}/captures/{captureId} {";
const signedIn="    function signedIn() { return request.auth != null; }";
if(source.split(anchor).length!==2 ||
   source.includes(matchStart) ||
   !source.includes("match /deda_auth_attempts/{uid} {") ||
   !source.includes("match /deda_sessions/{uid} {") ||
   !block.includes("allow update, delete: if false;") ||
   block.split(matchStart).length!==2 ||
   source.split(signedIn).length!==2) {
  throw Error("QA_ARCHIVE_RULES_BASELINE_DRIFT_HOLD");
}
const [helperDeclarations,archiveMatch]=block.split(matchStart);
// The replacement values contain Firestore regex literals, which may be
// interpreted as replacement patterns by JS. Functions prevent substitution.
const generated=source.replace(signedIn,()=>signedIn+"\n"+helperDeclarations)
  .replace(anchor,()=>matchStart+archiveMatch+"\n"+anchor);
const expectedLength=source.length+helperDeclarations.length+
  matchStart.length+archiveMatch.length+2;
if(generated.length!==expectedLength ||
   generated.split(anchor).length!==2 ||
   generated.split(matchStart).length!==2 ||
   generated.split("rules_version = ").length!==2 ||
   generated.split(signedIn).length!==2 ||
   !generated.endsWith(source.slice(-48))) {
  throw Error("QA_ARCHIVE_RULES_DUPLICATED_OR_TRUNCATED_HOLD");
}
fs.writeFileSync(path.join(root,"deda_account_backup_qa.generated.rules"),
  generated,"utf8");
process.stdout.write("QA only generated rules; source preserved\n");
