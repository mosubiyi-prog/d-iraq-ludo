'use strict';
// Unpublished lab-only candidate: derive exact synthetic data from the existing fixture.
// No general client balance writer. Authorization is a protected, console-owner seed.
// Do not deploy these generated rules to production or use for real entitlements.
const {readFileSync,writeFileSync}=require('node:fs');
const {build,base,uid,buildAccount}=require('./uid-trusted-fixture.cjs');
const marker={uid,purpose:'DEDA_STAGE03_SYNTHETIC_ONLY',format:1};
const markerPath='deda_lab_fixture_authorization/'+uid;
function literal(v){
  if(v===null||typeof v==='boolean'||typeof v==='string')return JSON.stringify(v);
  if(typeof v==='number'&&Number.isSafeInteger(v))return String(v);
  if(Array.isArray(v))return '['+v.map(literal).join(',')+']';
  if(v&&typeof v==='object')return '{'+Object.entries(v).map(([k,x])=>JSON.stringify(k)+':'+literal(x)).join(',')+'}';
  throw Error('unsupported fixture value');
}
function generate(original){
  const docs=build(),paths=Object.keys(docs),view=base+'/inventory/current';
  if(paths.length!==12||!docs[base]||!docs[view]||paths.some(p=>p!==base&&!p.startsWith(base+'/')))throw Error('unexpected fixture shape');
  const direct=paths.filter(p=>p.startsWith(base+'/receipts/')||p.startsWith(base+'/events/'));
  const inv=[base+'/inventorySources/current',base+'/inventoryHistory/1'];
  if(direct.length!==8||inv.some(p=>!docs[p])||paths.length!==direct.length+inv.length+2)throw Error('unexpected fixture layout');
  const firestorePath=p=>'/databases/$(database)/documents/'+p;
  const value=p=>{
    const v=literal(docs[p]);
    return p.startsWith(base+'/events/')?v.slice(0,-1)+',"createdAt":request.time}':v;
  };
  const after=p=>'getAfter('+firestorePath(p)+').data == '+value(p);
  const rootCreation='!exists('+firestorePath(base)+') && '+after(base);
  const create=p=>'owner(uid) && request.resource.data == '+value(p);
  const rootChecks=[create(base),'get('+firestorePath(markerPath)+').data == '+literal(marker),...direct.map(after),after(view)];
  const indent='      ';
  const rootBlock=[
    '    match /deda_lab_uid_authority/{uid} {',
    indent+'allow get: if owner(uid);',
    indent+'allow list, update, delete: if false;',
    indent+'allow create: if '+rootChecks.join(' &&\n        ')+';',
  ];
  for(const p of [...direct,view,...inv]){
    const rel=p.slice(base.length+1);
    if(!/^[A-Za-z0-9_-]+\/[A-Za-z0-9_-]+$/.test(rel))throw Error('unexpected path');
    const checks=[create(p),rootCreation,...(p===view?inv.map(after):[])];
    rootBlock.push(indent+'match /'+rel+' {',
      indent+'  allow get: if '+(p===view?'owner(uid)':'false')+';',
      indent+'  allow create: if '+checks.join(' &&\n          ')+';',
      indent+'  allow list, update, delete: if false;',
      indent+'}');
  }
  rootBlock.push('    }');
  const start='    match /deda_lab_uid_authority/{uid} {';
  const end='    match /{document=**} { allow read, write: if false; }';
  const a=original.indexOf(start),z=original.indexOf(end);
  if(a<0||z<=a||original.indexOf(start,a+1)!==-1)throw Error('unexpected candidate layout');
  return original.slice(0,a)+rootBlock.join('\n')+'\n'+original.slice(z);
}
if(require.main===module){
  if(process.argv.length!==4)throw Error('input and output paths required');
  writeFileSync(process.argv[3],generate(readFileSync(process.argv[2],'utf8')));
}
// Generate a separately reviewed, immutable exact-account-only lab rules
// candidate. Console publication itself is owner authorization. No marker
// reactivation, root/inventory writes, real IDs, payout or broad permission.
function generateAccount(original){
  const docs=buildAccount(),paths=Object.keys(docs);
  const view=base+'/account/current';
  const old='      match /account/current {\n        allow get: if owner(uid);\n        allow list, create, update, delete: if false;\n      }';
  if(original.split(old).length!==2||paths.length!==3||!docs[view])throw Error('unexpected account candidate layout');
  const check=paths.map(p=>'getAfter(/databases/$(database)/documents/'+p+').data == '+literal(docs[p])).join(' &&\n          ');
  const blocks=paths.map(p=>{
    const relative=p.slice(base.length+1);
    return '      match /'+relative+' {\n        allow get: if '+(p===view?'owner(uid)':'false')+
      ';\n        allow create: if owner(uid) && request.resource.data == '+literal(docs[p])+
      ' &&\n          '+check+';\n        allow list, update, delete: if false;\n      }';
  }).join('\n');
  return original.replace(old,()=>blocks);
}
module.exports={generate,marker,markerPath,generateAccount};
