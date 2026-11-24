"""Stage01: triage every duplicate fingerprint, index auth/saving sites,
and remove production config from disposable QA trees ONLY after parity audit.
No account creation, app launch, cloud access, deployment, or runtime changes.
"""
import argparse
from collections import Counter, defaultdict
import hashlib
import json
from pathlib import Path
import re

ROOT=Path(__file__).resolve().parents[3]
IDENTITY=re.compile(r'\b(?:FirebaseAuth|signInAnonymously|signInWithCredential|linkWithCredential|signOut|currentUser|uid|accountKey|ownerUid|authStateChanges|DedaAuthRuntime)\b',re.I)
STORAGE=re.compile(r'\b(?:FirebaseFirestore|SharedPreferences|runTransaction|serverTimestamp|Source\.server|setString|setInt|setBool|remove|commit|wallet|diamonds|balance|points|level|inventory)\b',re.I)
VISUAL=re.compile(r'\b(?:Widget|Text|Container|Row|Column|Padding|SizedBox|Icon|Color|BorderRadius|TextStyle|EdgeInsets|Scaffold|ListTile|BoxDecoration|Theme|Navigator|BuildContext)\b')
ADMIN='deda_stage2_isolated_admin_'
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def check_temp(p):
    p=p.resolve()
    if p==ROOT or ROOT in p.parents or p in ROOT.parents or not p.is_dir():
        raise ValueError('QA_DISPOSABLE_TREE_REQUIRED')
    return p
def read_span(root,loc):
    name,a,b=loc
    p=(root/name).resolve()
    if root not in p.parents or p.suffix!='.dart': raise ValueError('invalid source range')
    lines=p.read_text(encoding='utf-8').splitlines()
    if not 1<=a<=b<=len(lines): raise ValueError('invalid source line')
    return '\n'.join(lines[a-1:b])
def classify(root,locs):
    spans=[read_span(root,x) for x in locs]
    text='\n'.join(spans)
    files={x[0] for x in locs}
    admin=any(ADMIN in x for x in files)
    if IDENTITY.search(text): risk='identity_or_session_review'
    elif STORAGE.search(text): risk='persistence_or_entitlement_review'
    elif VISUAL.search(text): risk='presentation_candidate_preserve'
    else: risk='shared_logic_review'
    relation='isolated_admin_involved' if admin else ('same_file' if len(files)==1 else 'cross_file')
    return risk,relation
def group_locations(idx,keys):
    byfile=defaultdict(list)
    for key in keys:
        for loc in idx[key]: byfile[loc[0]].append(loc[1:])
    out={}
    for p,spans in byfile.items():
        merged=[]
        for a,b in sorted(spans):
            if merged and a<=merged[-1][1]+1: merged[-1][1]=max(merged[-1][1],b)
            else: merged.append([a,b])
        out[p]=merged
    return out
def review_repeat_context(index, fingerprints):
    """Associate repeat locations with nearest lexical declaration/method.
    This is navigation evidence only, never a semantic or deletion decision.
    """
    symbols=defaultdict(list)
    for kind in ('declarations','method_candidates'):
        for name,locs in index[kind].items():
            for file,line in locs:
                symbols[file].append((line,kind,name))
    for entries in symbols.values():
        entries.sort()
    reviewed=[]
    for entry in fingerprints:
        if entry['risk'] not in ('identity_or_session_review','persistence_or_entitlement_review'):
            continue
        contexts=[]
        for file,start,end in entry['locations']:
            before=[x for x in symbols[file] if x[0]<=start]
            nearest=before[-1] if before else None
            within=[{'line':line,'kind':kind,'name':name}
                    for line,kind,name in symbols[file] if start<line<=end]
            contexts.append({'file':file,'start':start,'end':end,
                             'preceding_symbol':dict(zip(('line','kind','name'),nearest)) if nearest else None,
                             'symbols_inside_range':within})
        keys={(c['file'], (c['preceding_symbol'] or {}).get('line')) for c in contexts}
        reviewed.append({'fingerprint':entry['fingerprint'],'status':entry['status'],
                         'risk':entry['risk'],'contexts':contexts,
                         'lexical_context_relation':'different_anchors' if len(keys)>1 else 'same_anchor',
                         'disposition':'preserve_pending_semantic_review'})
    return reviewed

def verify_store_route_separation(index):
    """Prevent the historical proof-only renderer joining the active route.
    Both original declarations are intentionally retained; never rename or
    delete the inactive library just to reduce a lexical duplicate count.
    """
    active = 'lib/deda_100377_my_store_page_staged.dart'
    proof = 'lib/deda_100377_my_store_owned_profile_staged.dart'
    gate = 'lib/deda_stage2_profile_owner_my_store_gate_2026_11_23.dart'
    reachable = set(index['reachable_local_dart'])
    names = index['duplicate_declaration_name_candidates'].get('class:DedaMyStorePage', [])
    if {p for p, _ in names} != {active, proof} or len(names) != 2:
        raise ValueError('STAGE01_STORE_DECLARATION_DRIFT')
    if active not in reachable or gate not in reachable or proof in reachable:
        raise ValueError('STAGE01_STORE_PROOF_ROUTE_ACTIVATION_HOLD')
    imports = index['imports']
    if active.rsplit('/', 1)[1] not in imports.get(gate, []):
        raise ValueError('STAGE01_STORE_ORIGINAL_RENDERER_ROUTE_DRIFT')
    return {'active_renderer':active,'preserved_proof_only_renderer':proof,
            'owner_route_gate':gate,'static_import_graph_only':True}

def group_priority_contexts(contexts):
    """Group overlapping fingerprints by their indexed context anchors.
    This is an inspection queue, not a semantic-equivalence verdict.
    """
    groups = defaultdict(list)
    for item in contexts:
        key = tuple(sorted((c['file'], (c['preceding_symbol'] or {}).get('name','?'))
                           for c in item['contexts']))
        groups[key].append(item['fingerprint'])
    result = [{'anchors':[{'file':f,'symbol':n} for f,n in key],
               'fingerprints':sorted(values),'count':len(values)}
              for key,values in sorted(groups.items())]
    if sorted(fp for group in result for fp in group['fingerprints']) != sorted(
            x['fingerprint'] for x in contexts):
        raise ValueError('STAGE01_PRIORITY_GROUP_COVERAGE')
    return result

def main():
    p=argparse.ArgumentParser()
    p.add_argument('reference',type=Path);p.add_argument('candidate',type=Path);p.add_argument('inventory',type=Path)
    args=p.parse_args()
    old,new=map(check_temp,(args.reference,args.candidate))
    if old==new: raise ValueError('distinct QA trees required')
    inv=args.inventory.resolve()
    if ROOT in inv.parents or old in inv.parents or new in inv.parents: raise ValueError('external evidence required')
    data=json.loads(inv.read_text())
    ix,iy=data['reference_index'],data['candidate_index']
    a,b=ix['duplicate_windows'],iy['duplicate_windows']
    prior,current=set(a),set(b)
    result=[];counts=Counter();new_counts=Counter()
    for key in sorted(current):
        locs=b[key]
        risk,relation=classify(new,locs)
        state='preexisting' if key in prior else 'new'
        counts[risk]+=1
        if state=='new': new_counts[risk]+=1
        result.append({'fingerprint':key,'status':state,'risk':risk,'relation':relation,'locations':locs})
    assert len(result)==len(b) and sum(counts.values())==len(b)
    assert len(current-prior)==sum(new_counts.values())
    contexts=review_repeat_context(iy,result)
    priority_count=counts['identity_or_session_review']+counts['persistence_or_entitlement_review']
    if len(contexts)!=priority_count:
        raise ValueError('STAGE01_PRIORITY_REVIEW_COVERAGE_MISMATCH')
    if {x['fingerprint'] for x in contexts} != {x['fingerprint'] for x in result if x['risk'] in ('identity_or_session_review','persistence_or_entitlement_review')}:
        raise ValueError('STAGE01_PRIORITY_REVIEW_FINGERPRINT_MISMATCH')
    print('STAGE01_PRIORITY_CONTEXT_INDEXED',len(contexts),flush=True)
    priority_groups=group_priority_contexts(contexts)
    store_separation=verify_store_route_separation(iy)
    print('STAGE01_PRIORITY_ANCHOR_GROUPS',len(priority_groups),flush=True)
    print('STAGE01_STORE_SINGLE_ACTIVE_RENDERER_PROOF_LIBRARY_PRESERVED',
          json.dumps(store_separation),flush=True)
    if data['assembly']['missing'] or data['symbol_delta']['declarations']['missing'] or data['symbol_delta']['method_candidates']['missing'] or iy['unresolved_local_imports']:
        raise ValueError('REFERENCE_PARITY_HOLD')
    # Index all lexical mutation entrypoints. Do not confuse occurrence with execution.
    sites={k:v for k,v in iy['api_sites'].items() if k in
        ('anonymous_auth','password_auth','credential_auth','credential_link','sign_out','auth_instance_for','local_login_write','pin_account_create','pin_account_lookup','local_preferences','cloud_firestore_for','cloud_transaction','server_read')}
    for kind in ('anonymous_auth','password_auth','credential_auth','credential_link','sign_out','auth_instance_for'):
        print('STAGE01_AUTH_SITE',kind,json.dumps(sites.get(kind,[])),flush=True)
    # Report actual location of each newly detected fingerprint, coalesced for review.
    for risk in sorted(new_counts):
        subset=[x['fingerprint'] for x in result if x['status']=='new' and x['risk']==risk]
        print('STAGE01_NEW_REPEAT',risk,json.dumps(group_locations(b,subset)),flush=True)
    print('STAGE01_REPEAT_TRIAGE',json.dumps(dict(counts)),flush=True)
    print('STAGE01_NEW_REPEAT_TRIAGE',json.dumps(dict(new_counts)),flush=True)
    # Verify existing primary guards are still present. Not an assertion that
    # flags are enabled or that legacy entrypoints are safe for a live lab.
    backend=(new/'lib/deda_backend.dart').read_text()
    pin=(new/'lib/deda_pin_auth.dart').read_text()
    google=(new/'lib/deda_stable_google_login_2026_11_21.dart').read_text()
    for s,marker in ((backend,'deda-stability-explicit-auth-entry-no-new-uid'),
                     (backend,'deda-stability-admin-isolated-auth-required'),
                     (pin,'deda-stability-original-login-no-anonymous-uid'),
                     (google,'DEDA_STABILITY_GOOGLE_LOGIN'),(google,'pendingGoogleUid')):
        if marker not in s: raise ValueError('guard drift '+marker)
    # prepare.py uses the published Firebase config to reconstruct exact platform
    # parity. Remove it only from disposable trees after the inventory has been
    # written. Never modify checked-in Firebase configuration or copy credentials
    # to another project. Do not build/run Android with this incomplete scaffold.
    configs=[]
    for root in (old,new):
        f=root/'android/app/google-services.json'
        if not f.is_file() or f.is_symlink(): raise ValueError('expected disposable config missing')
        config=json.loads(f.read_text())
        if config.get('project_info',{}).get('project_id')!='deda-25b88': raise ValueError('unexpected source configuration')
        configs.append({'tree':root.name,'sha256_before_removal':sha(f),'removed_from_QA_tree':True})
        f.unlink()
        if list(root.rglob('google-services.json')): raise ValueError('remaining android Firebase config')
    report={'counts':dict(counts),'new_counts':dict(new_counts),'all_fingerprints':result,
            'new_ranges':group_locations(b,current-prior),'old_only_count':len(prior-current),
            'priority_repeat_contexts':contexts,
            'priority_anchor_groups':priority_groups,'store_route_separation':store_separation,
            'duplicate_declarations':iy['duplicate_declaration_name_candidates'],
            'outside_import_graph':iy['outside_static_import_graph'],'auth_and_storage_sites':sites,
            'qa_configs':configs,'runtime_release_hold':True,
            'limitations':['Lexical triage, not proof of semantic equivalence or absence of harmful duplicates.',
                           'No source code was deleted or changed by this review; no production or historical identity access.',
                           'Live lab launch prohibited until independently approved project configuration and runtime guard are verified.']}
    (inv.parent/'stage01-review.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print('STAGE01_ALL_REPEAT_FINGERPRINTS_TRIAGED',len(result),flush=True)
    print('STAGE01_DUPLICATE_DECLARATIONS',json.dumps(report['duplicate_declarations']),flush=True)
    print('STAGE01_QA_PRODUCTION_CONFIG_REMOVED_BOTH_TEMP_TREES_NO_APK',flush=True)
    print('STAGE01_LIVE_IDENTITY_ACTIVATION_HOLD',flush=True)
if __name__=='__main__': main()
