"""Read-only three-way DEDA inventory. No runtime, Firebase, deployment or APK.
Outputs metadata, paths, line numbers, hashes, counts; never credential values.
Exact duplicate windows and static declarations are candidates, not defects.
"""
import argparse
import bisect
from collections import Counter, defaultdict
import difflib
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT/'tools/app_stability'))
from bind_auth_runtime import tokens

DECL = re.compile(r'(?m)^(?:abstract |base |final |sealed |interface )*(class|enum|mixin|extension|typedef)\s+([A-Za-z_$][\w$]*)\b')
# Lexical candidate index, not a Dart AST. Only conventional indented methods.
METHOD = re.compile(r'(?m)^  (?:static |external |abstract |covariant |factory )*(?:[\w$][\w$<>,.? \[\]]{0,180}\s+)?([A-Za-z_$][\w$]*)\s*(?:<[^;\n{}]{1,100}>)?\s*\(')
IMPORT = re.compile(r'''(?m)^\s*(?:import|export|part)\s+['"]([^'"]+)['"]''')
API = {
 'anonymous_auth': r'\bsignInAnonymously\s*\(',
 'password_auth': r'\bsignInWithEmailAndPassword\s*\(',
 'credential_auth': r'\bsignInWithCredential\s*\(',
 'credential_link': r'\blinkWithCredential\s*\(',
 'sign_out': r'\bsignOut\s*\(',
 'auth_instance': r'\bFirebaseAuth\.instance\b',
 'auth_instance_for': r'\bFirebaseAuth\.instanceFor\s*\(',
 'local_preferences': r'\bSharedPreferences\.getInstance\s*\(',
 'cloud_firestore': r'\bFirebaseFirestore\.instance\b',
 'cloud_firestore_for': r'\bFirebaseFirestore\.instanceFor\s*\(',
 'cloud_transaction': r'\brunTransaction\s*\(',
 'server_read': r'\bSource\.server\b',
 'local_login_write': r'\b(?:DedaPreferences\.)?saveLogin\s*\(',
 'pin_account_create': r'\bDedaPinAuth\.createAccount\s*\(',
 'pin_account_lookup': r'\bDedaPinAuth\.accountExists\s*\(',
 'routes': r'\b(?:MaterialPageRoute|CupertinoPageRoute)\s*(?:<[^>]+>)?\s*\(',
}
def digest(b):
    return hashlib.sha256(b).hexdigest()
def git(*args):
    return subprocess.check_output(['git', '-C', str(ROOT), *args])
def raw(ref):
    out={}
    for row in git('ls-tree','-r','-z',ref).split(b'\0'):
        if not row: continue
        meta,path=row.split(b'\t',1)
        mode,typ,oid=meta.decode().split()
        if typ=='blob': out[path.decode()]=oid
    return out
def tree(project):
    result={}
    for rel in ('lib','assets','android','ios','web','windows','macos','linux'):
        p=project/rel
        if p.is_dir():
            for f in p.rglob('*'):
                if f.is_file() and not f.is_symlink() and not any(x in ('.dart_tool','build','.gradle') for x in f.relative_to(project).parts):
                    result[f.relative_to(project).as_posix()]=digest(f.read_bytes())
    for name in ('pubspec.yaml','analysis_options.yaml'):
        if (project/name).is_file(): result[name]=digest((project/name).read_bytes())
    return result
def diff(a,b):
    x,y=set(a),set(b)
    return {'old':len(x),'new':len(y),'added':sorted(y-x),'missing':sorted(x-y),
            'modified':sorted(k for k in x&y if a[k]!=b[k]),
            'unchanged':sum(a[k]==b[k] for k in x&y)}
def source_map(project):
    return {p.relative_to(project).as_posix():p.read_text(encoding='utf-8')
            for p in sorted((project/'lib').rglob('*.dart'))}
def code_index(sources):
    declarations, methods, api, imports, windows, whole = defaultdict(list), defaultdict(list), defaultdict(list), {}, defaultdict(list), defaultdict(list)
    lengths={}
    for path,s in sources.items():
        ts=tokens(s)
        # Hide string contents and comments for API/declaration matching. Keep
        # offsets stable so every report location maps to the original file.
        chars=[' ']*len(s)
        for i,c in enumerate(s):
            if c=='\n': chars[i]='\n'
        line_starts=[0]+[m.end() for m in re.finditer('\n',s)]
        line=lambda offset:bisect.bisect_right(line_starts,offset)
        code_lines=defaultdict(list)
        for word,a,z in ts:
            code_lines[line(a)].append(word)
            if word.startswith(("'",'"',"r'",'r"')): continue
            chars[a:z]=s[a:z]
        clean=''.join(chars)
        lengths[path]={'physical_lines':len(s.splitlines()),'token_lines':len(code_lines),'tokens':len(ts)}
        whole[digest(s.encode())].append(path)
        decl=list(DECL.finditer(clean))
        for m in decl:
            declarations[m.group(1)+':'+m.group(2)].append([path,line(m.start())])
        for m in METHOD.finditer(clean):
            name=m.group(1)
            if name in ('if','for','while','switch','return','catch','assert','else','throw','await','super'): continue
            owner=next((d.group(2) for d in reversed(decl) if d.start()<m.start()),'<top>')
            methods[owner+'.'+name].append([path,line(m.start())])
        for kind,pattern in API.items():
            for m in re.finditer(pattern,clean):
                api[kind].append([path,line(m.start())])
        # Only actual import lines with a code-side directive; not commented strings.
        imports[path]=[m.group(1) for m in IMPORT.finditer(s)
                       if re.match(r'\s*(import|export|part)\b',clean[m.start():m.end()])]
        # Exact 12 consecutive significant token-bearing lines; comments and
        # whitespace ignored, strings retained, line breaks retained. Distinct
        # fingerprints, not a count of duplicated functions or logical defects.
        rows=[(ln, digest(json.dumps(words,ensure_ascii=False).encode()),len(words))
              for ln,words in sorted(code_lines.items()) if len(words)>=3]
        for i in range(len(rows)-11):
            chunk=rows[i:i+12]
            if sum(x[2] for x in chunk)<80: continue
            key=digest(''.join(x[1] for x in chunk).encode())
            windows[key].append([path,chunk[0][0],chunk[-1][0]])
    repeats={k:v for k,v in windows.items() if len(v)>1}
    # Coalesce overlapping hits into source ranges, separately for each file.
    ranges=defaultdict(list)
    for locs in repeats.values():
        for p,a,z in locs: ranges[p].append((a,z))
    merged={}
    for p,spans in ranges.items():
        result=[]
        for a,z in sorted(spans):
            if result and a<=result[-1][1]+1: result[-1][1]=max(z,result[-1][1])
            else: result.append([a,z])
        merged[p]=result
    reachable=set()
    queue=['lib/main.dart']
    missing_local=[]
    while queue:
        p=queue.pop()
        if p in reachable or p not in sources: continue
        reachable.add(p)
        for target in imports[p]:
            if target.startswith('package:d_iraq_ludo/'):
                q='lib/'+target.split('/',1)[1]
            elif ':' not in target:
                import posixpath
                q=posixpath.normpath(posixpath.join(posixpath.dirname(p),target))
            else: continue
            if q in sources: queue.append(q)
            else: missing_local.append([p,q])
    return {'lengths':lengths,'declarations':dict(declarations),'method_candidates':dict(methods),
            'api_sites':dict(api),'imports':imports,'reachable_local_dart':sorted(reachable),
            'outside_static_import_graph':sorted(set(sources)-reachable),
            'unresolved_local_imports':missing_local,
            'duplicate_whole_files':[v for v in whole.values() if len(v)>1],
            'duplicate_windows':repeats,'duplicate_merged_ranges':merged,
            'duplicate_declaration_name_candidates':{k:v for k,v in declarations.items() if len(v)>1}}
def summary(idx):
    return {'dart_files':len(idx['lengths']),
            'physical_lines':sum(v['physical_lines'] for v in idx['lengths'].values()),
            'token_lines':sum(v['token_lines'] for v in idx['lengths'].values()),
            'declared_names':len(idx['declarations']),
            'method_candidate_names':len(idx['method_candidates']),
            'duplicate_full_file_groups':len(idx['duplicate_whole_files']),
            'duplicate_window_fingerprints':len(idx['duplicate_windows']),
            'duplicate_window_occurrences':sum(map(len,idx['duplicate_windows'].values())),
            'duplicate_merged_ranges':sum(map(len,idx['duplicate_merged_ranges'].values())),
            'duplicate_declaration_name_candidates':len(idx['duplicate_declaration_name_candidates']),
            'reachable_local_dart':len(idx['reachable_local_dart']),
            'outside_static_import_graph':len(idx['outside_static_import_graph']),
            'unresolved_local_imports':idx['unresolved_local_imports'],
            'api_call_sites':{k:len(v) for k,v in idx['api_sites'].items()}}
def main():
    p=argparse.ArgumentParser()
    p.add_argument('reference',type=Path);p.add_argument('candidate',type=Path)
    p.add_argument('output',type=Path);p.add_argument('--baseline',required=True);p.add_argument('--head',required=True)
    a=p.parse_args()
    old,new,out=a.reference.resolve(),a.candidate.resolve(),a.output.resolve()
    if old==new or any(x==ROOT or ROOT in x.parents for x in (old,new,out)) or any(x==out or x in out.parents for x in (old,new)):
        raise ValueError('INVENTORY_REQUIRES_DISPOSABLE_READONLY_INPUTS')
    old_hash,new_hash=tree(old),tree(new)
    raw_a,raw_b=raw(a.baseline),raw(a.head)
    raw_diff=diff(raw_a,raw_b); app_diff=diff(old_hash,new_hash)
    original,current=source_map(old),source_map(new)
    ix,iy=code_index(original),code_index(current)
    paths=set(original)&set(current)
    line_changes={}
    for path in sorted(paths | (set(original)^set(current))):
        x=original.get(path,'').splitlines();y=current.get(path,'').splitlines()
        if x==y: continue
        add=delete=0
        for tag,i,j,k,l in difflib.SequenceMatcher(None,x,y,autojunk=True).get_opcodes():
            if tag!='equal': add+=l-k;delete+=j-i
        line_changes[path]={'added':add,'deleted':delete}
    counts={'added':sum(v['added'] for v in line_changes.values()),'deleted':sum(v['deleted'] for v in line_changes.values())}
    symbols={k:{'missing':sorted(set(ix[k])-set(iy[k])),'added':sorted(set(iy[k])-set(ix[k]))}
             for k in ('declarations','method_candidates')}
    old_dups=set(ix['duplicate_windows']);new_dups=set(iy['duplicate_windows'])
    dup_delta={'existing':len(old_dups&new_dups),'new':len(new_dups-old_dups),'removed':len(old_dups-new_dups)}
    # No automatic equivalence claim: every missing/added name and repeat
    # range is indexed for manual functional review, not deletion.
    if tree(old)!=old_hash or tree(new)!=new_hash: raise ValueError('INVENTORY_INPUT_MUTATED')
    report={'baseline':a.baseline,'raw_head':a.head,'raw':raw_diff,'assembly':app_diff,
            'assembly_dart_line_diff_heuristic':counts,'line_changes':line_changes,
            'old_summary':summary(ix),'new_summary':summary(iy),'symbol_delta':symbols,
            'duplicate_window_delta':dup_delta,'reference_index':ix,'candidate_index':iy,
            'limitations':['Lexical declarations/method candidates are not AST or call graph.',
                           'Static import graph does not prove runtime reachability; conditional imports not resolved.',
                           'Overlapping exact 12-line windows are not duplicated functions or proof of harmful duplication.',
                           'SequenceMatcher line counts are heuristic, not Git diff or semantic changes.',
                           'No device QA, account reads, Firebase access or activation.']}
    out.mkdir(parents=True,exist_ok=True)
    (out/'inventory.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    brief={k:report[k] for k in ('baseline','raw_head','old_summary','new_summary','assembly_dart_line_diff_heuristic','duplicate_window_delta','symbol_delta')}
    brief['assembly']={k:(len(v) if isinstance(v,list) else v) for k,v in app_diff.items()}
    brief['assembly_missing']=app_diff['missing']
    brief['assembly_added']=app_diff['added']
    brief['assembly_modified']=app_diff['modified']
    (out/'summary.json').write_text(json.dumps(brief,ensure_ascii=False,indent=2),encoding='utf-8')
    for k in ('old_summary','new_summary','assembly','assembly_dart_line_diff_heuristic','duplicate_window_delta'):
        print('DEDA_INVENTORY_'+k.upper(),json.dumps(brief[k],ensure_ascii=False),flush=True)
    print('DEDA_INVENTORY_MISSING_PATHS',json.dumps(app_diff['missing']),flush=True)
    print('DEDA_INVENTORY_MISSING_DECLARATION_NAMES',json.dumps(symbols['declarations']['missing']),flush=True)
    print('DEDA_INVENTORY_MISSING_METHOD_CANDIDATE_NAMES',json.dumps(symbols['method_candidates']['missing']),flush=True)
    print('PASS_READ_ONLY_INVENTORY_INPUTS_UNCHANGED_NO_RUNTIME_ACTIVATION',flush=True)

if __name__=='__main__': main()
