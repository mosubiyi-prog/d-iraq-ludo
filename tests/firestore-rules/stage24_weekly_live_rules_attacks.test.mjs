import {readFileSync} from 'node:fs';
import {before,after,test} from 'node:test';
import {
  assertFails,initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  doc,deleteDoc,getDoc,setDoc,updateDoc,
} from 'firebase/firestore';

const PROJECT='demo-deda-stage24-live-rules-client-attack';
const FILE=process.env.DEDA_STAGE24_LIVE_RULES_TMPFILE;
if(!FILE||!FILE.endsWith('.rules')) {
  throw Error('STAGE24_MUST_TEST_ACTUAL_DOWNLOADED_LIVE_RULES');
}
const source=readFileSync(FILE,'utf8');
if(!source.includes('rules_version'))throw Error('STAGE24_INVALID_RULESET');
let env,viewer,manager,unauthenticated;
const paths=Object.freeze([
  'deda_weekly_xp_receipts/real-week/events/claim',
  'deda_weekly_standings/real-week',
  'deda_weekly_identity_attestations/real-user',
  'deda_weekly_competition_config/current',
  'deda_weekly_verified_equipped_public/some-owner-hash',
  'deda_weekly_public_profiles/some-owner-hash',
  'deda_weekly_prize_receipts/week-winner',
  'deda_weekly_earned_wallets/some-owner-hash',
]);

before(async()=>{
  env=await initializeTestEnvironment({
    projectId:PROJECT,firestore:{rules:source},
  });
  viewer=env.authenticatedContext('real-user').firestore();
  manager=env.authenticatedContext('manager-user',{
    admin:true,role:'general_manager',
  }).firestore();
  unauthenticated=env.unauthenticatedContext().firestore();
  await env.withSecurityRulesDisabled(async(context)=>{
    const db=context.firestore();
    await setDoc(doc(db,'admins','manager-user'),{
      role:'general_manager',active:true,status:'active',
    });
    for(const path of paths)await setDoc(doc(db,path),{
      issuer:'privileged_server_only_task_xp_issuer_v1',
      isVerified:true,levelXpAmount:20,
      diamonds:150,socialProfile:'not-a-real-user',
    });
  });
});

after(async()=>{if(env)await env.cleanup();});

for(const [role,select] of [
  ['normal',()=>viewer],['general_manager',()=>manager],
  ['anonymous',()=>unauthenticated],
]) {
  for(const path of paths) {
    test(\`\${role} cannot read, forge, edit or delete backend-only \${path}\`,async()=>{
      const ref=doc(select(),path);
      await assertFails(getDoc(ref));
      await assertFails(setDoc(ref,{
        issuer:'privileged_server_only_task_xp_issuer_v1',
        accountKey:'07712345678',
        levelXpAmount:500000,
        diamonds:99999999,
        rank:1,
      }));
      await assertFails(updateDoc(ref,{levelXpAmount:400000}));
      await assertFails(deleteDoc(ref));
    });
  }
}
