"use strict";

// Owner19 Stage55: manager personal 1,000,000 was historically CLIENT-minted.
// It is not eligible for a REAL card/ID purchase until every old wallet has
// a backend-verified provenance receipt AND the owner approves the policy.
// Never infer entitlement from GM role or an account's numeric balance.
// Emulator-only allowance maintains strictly disposable purchase QA tests.
const DEMO_PROJECT=/^demo-deda-[a-z0-9_-]+$/;
const LOCAL_EMULATOR=/^(127\.0\.0\.1|localhost):[0-9]{2,5}$/;

function rejectIfUnprovenManagerPersonalSpending(amount) {
  if(!Number.isSafeInteger(amount)||amount<0||amount>1073741824){
    const error=new Error("invalid-gm-personal-wallet-debit");
    error.code="failed-precondition";
    throw error;
  }
  if(amount===0)return;
  const project=process.env.GCLOUD_PROJECT||"";
  const emulator=process.env.FIRESTORE_EMULATOR_HOST||"";
  if(DEMO_PROJECT.test(project)&&LOCAL_EMULATOR.test(emulator)){
    // The Firebase Admin SDK is pointed at a LOCAL DISPOSABLE EMULATOR.
    // This is NOT evidence that the GM balance can be spent in production.
    return;
  }
  const error=new Error("gm-test-million-needs-independent-server-provenance");
  error.code="failed-precondition";
  throw error;
}
module.exports={rejectIfUnprovenManagerPersonalSpending};
