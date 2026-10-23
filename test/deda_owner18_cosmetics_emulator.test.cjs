const test = require('node:test');
const assert = require('node:assert/strict');
const {readFileSync, writeFileSync} = require('node:fs');
const {createHash} = require('node:crypto');
const {createRequire} = require('node:module');
const {resolve} = require('node:path');
const req = createRequire(resolve(__dirname, '../functions/package.json'));
const {initializeTestEnvironment, assertFails, assertSucceeds} = req('@firebase/rules-unit-testing');
const {doc, setDoc, getDoc, updateDoc, serverTimestamp, arrayUnion, arrayRemove, runTransaction, writeBatch} = req('firebase/firestore');
const project = 'demo-deda-owner18-cosmetics';
assert.equal(process.env.GCLOUD_PROJECT, project);
assert.match(process.env.FIRESTORE_EMULATOR_HOST || '', /^(localhost|127\.0\.0\.1):\d+$/);
const rules = readFileSync('/tmp/deda-owner18-cosmetics.rules', 'utf8');
const A = {uid:'owner18_A', key:'9647700001111', id:'@DEDA-AB3C5D'};
const B = {uid:'owner18_B', key:'9647800002222', id:'@DEDA-ZX4W6V'};
let env;
const account = (db, id=A.id) => doc(db, 'deda_native_account_cosmetics', id);
const data = (extras={}) => ({originalId:A.id, updatedAt:serverTimestamp(), ...extras});
test.before(async () => {
  env = await initializeTestEnvironment({projectId:project,
    firestore:{host:'127.0.0.1', port:8080, rules}});
});
test.beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async ctx => {
    const db=ctx.firestore();
    for(const u of [A,B]) {
      await setDoc(doc(db,'users',u.uid), {accountKey:u.key, sharePersonalId:u.id});
      await setDoc(doc(db,'deda_sessions',u.uid), {accountKey:u.key, uid:u.uid});
      await setDoc(doc(db,'deda_share_ids',u.id), {publicId:u.id,
        ownerUid:u.uid, kind:'personal', active:true});
    }
  });
});
test.after(async () => {
  if(env) await env.cleanup();
});
test('same account saves/restores native purchases and appearance', async () => {
  const db=env.authenticatedContext(A.uid).firestore();
  await assertSucceeds(setDoc(account(db),data({ownedStyles:['badge_member','badge_spark'],
    activeBadges:['badge_spark'], ownedFrames:['FRAME_03'], avatar:4,frame:6,background:7})));
  const secondDevice=env.authenticatedContext(A.uid).firestore();
  const saved=(await assertSucceeds(getDoc(account(secondDevice)))).data();
  assert.deepEqual(saved.ownedFrames,['FRAME_03']);
  assert.equal(saved.avatar,4);
  assert.deepEqual(saved.activeBadges,['badge_spark']);
});
test('another account and unauthenticated clients cannot read or overwrite inventory', async () => {
  const a=env.authenticatedContext(A.uid).firestore();
  await setDoc(account(a),data({ownedStyles:['badge_member']}));
  for(const db of [env.authenticatedContext(B.uid).firestore(),env.unauthenticatedContext().firestore()]) {
    await assertFails(getDoc(account(db)));
    await assertFails(setDoc(account(db),data({avatar:1})));
  }
});
test('union preserves previously purchased items and cannot remove them',async()=>{
  const db=env.authenticatedContext(A.uid).firestore();
  await setDoc(account(db),data({ownedStyles:['badge_member','badge_spark'],ownedFrames:['FRAME_03']}));
  await assertSucceeds(updateDoc(account(db),{ownedStyles:arrayUnion('badge_royal'),
    ownedFrames:arrayUnion('FRAME_05'),updatedAt:serverTimestamp()}));
  const saved=(await getDoc(account(db))).data();
  assert.equal(saved.ownedStyles.length,3);
  assert.equal(saved.ownedFrames.length,2);
  await assertFails(updateDoc(account(db),{ownedStyles:['badge_member'],updatedAt:serverTimestamp()}));
  await assertFails(updateDoc(account(db),{ownedFrames:[],updatedAt:serverTimestamp()}));
});
test('no balances, points, IDs or unknown style fields can be written in cosmetic backup',async()=>{
  const db=env.authenticatedContext(A.uid).firestore();
  for(const extra of [{balance:1000000},{xp:9000},{activeId:'@DEDA-IRAQI'},
    {ownedFrames:['FRAME_99']},{avatar:9},{frame:19},{background:9},
    {ownedStyles:['admin']}]) {
    await assertFails(setDoc(account(db),data(extra)));
  }
});
test('legacy account without sharePersonalId still requires matching route and session',async()=>{
  await env.withSecurityRulesDisabled(async ctx=>{
    await setDoc(doc(ctx.firestore(),'users',A.uid),{accountKey:A.key});
  });
  const db=env.authenticatedContext(A.uid).firestore();
  await assertSucceeds(setDoc(account(db),data({avatar:3})));
  await env.withSecurityRulesDisabled(async ctx=>{
    await setDoc(doc(ctx.firestore(),'deda_sessions',A.uid),{accountKey:B.key});
  });
  await assertFails(getDoc(account(db)));
});
test('public profile accepts the same avatar/frame/background range without affecting level',async()=>{
  const db=env.authenticatedContext(A.uid).firestore();
  await assertSucceeds(setDoc(doc(db,'deda_social_profiles',A.id),{
    publicId:A.id,ownerUid:A.uid,displayName:'DEDA owner18',
    avatarStyle:5,frameStyle:18,backgroundStyle:8,level:1,badges:['badge_member'],
    createdAt:serverTimestamp(),updatedAt:serverTimestamp(),
  }));
  assert.equal((await getDoc(doc(db,'deda_social_profiles',A.id))).data().level,1);
});
test('reused anonymous UID cannot access an older different account route',async()=>{
  await env.withSecurityRulesDisabled(async ctx=>{
    const db=ctx.firestore();
    await updateDoc(doc(db,'deda_share_ids',B.id),{ownerUid:A.uid});
    await setDoc(account(db,B.id),{originalId:B.id,avatar:4,updatedAt:new Date()});
  });
  const reused=env.authenticatedContext(A.uid).firestore();
  await assertFails(getDoc(account(reused,B.id)));
  await assertFails(setDoc(account(reused,B.id),{
    originalId:B.id,avatar:0,updatedAt:serverTimestamp()}));
});
test('two devices cannot begin charging the same native frame twice',async()=>{
  const db=env.authenticatedContext(A.uid).firestore();
  await setDoc(account(db),data());
  const begin=()=>runTransaction(db,async tx=>{
    const snap=await tx.get(account(db));
    if((snap.data().pendingFrames || []).includes('FRAME_03')) throw Error('pending');
    tx.update(account(db),{pendingFrames:arrayUnion('FRAME_03'),updatedAt:serverTimestamp()});
  });
  const results=await Promise.allSettled([begin(),begin()]);
  assert.equal(results.filter(x=>x.status==='fulfilled').length,1);
  await assertSucceeds(updateDoc(account(db),{ownedFrames:arrayUnion('FRAME_03'),
    pendingFrames:arrayRemove('FRAME_03'),updatedAt:serverTimestamp()}));
  assert.deepEqual((await getDoc(account(db))).data().ownedFrames,['FRAME_03']);
});
test('new signed-in UID for the same canonical account restores the backup',async()=>{
  const old=env.authenticatedContext(A.uid).firestore();
  await setDoc(account(old),data({ownedStyles:['badge_member','badge_spark'],avatar:5}));
  await env.withSecurityRulesDisabled(async ctx=>{
    const db=ctx.firestore();
    await setDoc(doc(db,'users','owner18_reinstalled'),{accountKey:A.key,sharePersonalId:A.id});
    await setDoc(doc(db,'deda_sessions','owner18_reinstalled'),{accountKey:A.key});
  });
  const restored=env.authenticatedContext('owner18_reinstalled').firestore();
  assert.equal((await assertSucceeds(getDoc(account(restored)))).data().avatar,5);
  // Both signed-in devices remain the SAME canonical account. A stale or
  // subsequently switched session loses access without changing the route.
  await assertSucceeds(getDoc(account(old)));
  await env.withSecurityRulesDisabled(async ctx=>{
    await updateDoc(doc(ctx.firestore(),'deda_sessions',A.uid),{accountKey:B.key});
  });
  await assertFails(getDoc(account(old)));
  await assertSucceeds(getDoc(account(restored)));
});
test('existing protected owner probe permits a missing receipt on a new legitimate UID only',async()=>{
  await env.withSecurityRulesDisabled(async ctx=>{
    const db=ctx.firestore();
    await setDoc(doc(db,'users','owner18_new_device'),{accountKey:A.key,sharePersonalId:A.id});
    await setDoc(doc(db,'deda_sessions','owner18_new_device'),{accountKey:A.key});
  });
  const db=env.authenticatedContext('owner18_new_device').firestore();
  const probe=doc(db,'deda_lab_frame_receipts',A.id,'frames','FRAME_03');
  assert.equal((await assertSucceeds(getDoc(probe))).exists(),false);
  await env.withSecurityRulesDisabled(async ctx=>{
    await updateDoc(doc(ctx.firestore(),'users',B.uid),{sharePersonalId:A.id});
  });
  const wrong=env.authenticatedContext(B.uid).firestore();
  await assertFails(getDoc(doc(wrong,'deda_lab_frame_receipts',A.id,'frames','FRAME_03')));
});
test('missing public alias projections can be rebuilt on a new UID from the immutable received grant',async()=>{
  const alias='@DEDA-TESTID';
  await env.withSecurityRulesDisabled(async ctx=>{
    const db=ctx.firestore();
    await setDoc(doc(db,'users','owner18_new_device'),{accountKey:A.key,sharePersonalId:A.id});
    await setDoc(doc(db,'deda_sessions','owner18_new_device'),{accountKey:A.key});
    await setDoc(doc(db,'deda_stage71_granted_registry',alias),{
      identifier:alias,recipientOriginalId:A.id,group:'001',baseColor:'gold',kind:'gifted',
      grantedByUid:'synthetic_gm',grantedAt:new Date()});
    await setDoc(doc(db,'deda_stage74_id_gift_receipts',alias),{
      identifier:alias,originalId:A.id,group:'001',receivedAt:new Date()});
    await setDoc(doc(db,'deda_stage71_active_identifier',A.id),{
      originalId:A.id,activeId:alias,updatedAt:new Date()});
  });
  const db=env.authenticatedContext('owner18_new_device').firestore();
  const batch=writeBatch(db);
  batch.set(doc(db,'deda_public_active_aliases',A.id),{originalId:A.id,
    activeId:alias,baseColor:'gold',updatedAt:serverTimestamp()});
  batch.set(doc(db,'deda_public_alias_routes',alias),{aliasId:alias,
    originalId:A.id,baseColor:'gold',updatedAt:serverTimestamp()});
  await assertSucceeds(batch.commit());
  const viewer=env.authenticatedContext(B.uid).firestore();
  assert.equal((await getDoc(doc(viewer,'deda_public_active_aliases',A.id))).data().activeId,alias);
  await assertFails(getDoc(doc(viewer,'deda_stage74_id_gift_receipts',alias)));
  await assertFails(setDoc(doc(viewer,'deda_public_active_aliases',A.id),{
    originalId:A.id,activeId:alias,baseColor:'gold',updatedAt:serverTimestamp()}));
});
// Receipt marks only a fully successful test run, never generated on failure.
process.on('exit', code => {
  if(code === 0) writeFileSync('/tmp/deda-owner18-cosmetics-tests-passed',
    createHash('sha256').update(rules).digest('hex'));
});
