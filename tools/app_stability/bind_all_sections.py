"""Bind reachable State lifetimes and async continuations, without rewriting auth.

No archive mutation, feature grants, retry, timeout of mutations or serialization
of navigation/dialogs. Existing backend helpers retain their shared auth lane.
"""
import bisect
import json
from pathlib import Path
import re
from bind_auth_runtime import tokens, pairs, guard_awaits

AUTH_STATES = {
    '_LoginPageState', '_DedaPinCreatePageState', '_DedaPinSignInPageState',
    '_DedaPinRecoveryPageState', '_AccountTypePageState',
    '_DedaAdminLoginPageState', '_DedaAdminInviteActivationPageState',
    '_DedaAdminRecoveryRequestPageState',
    # Already has its own read coordinator, generation and SDK observer.
    '_DedaQa32ActiveAccountScopeState',
}
INFRASTRUCTURE_STATES = {
    '_DedaLazySectionStackState', '_DedaProgressBackupHostState',
    '_DedaLabPremiumFrameArtworkState', '_DedaRoyalFrameMotionState',
}
ACCOUNT_METHODS = {'_logout', '_logoutPersonalAccount', 'dispose',
                   '_create', '_signIn', '_enterWithNewPin', 'login', '_continue'}
OWN_MODULES = {'deda_section_state.dart', 'deda_section_operation_context.dart'}
FOUNDATION_FILES = OWN_MODULES | {
    'deda_auth_session_runtime.dart','deda_backend.dart','deda_pin_auth.dart',
    'deda_protected_section_entry.dart','deda_incoming_request_lifecycle.dart',
    'deda_lazy_section_stack.dart','deda_progress_backup_runtime.dart',
    'deda_progress_backup_coordinator.dart','deda_progress_evidence_store.dart',
    'deda_legacy_progress_capture.dart','deda_legacy_purchase_evidence.dart',
    'deda_owner_session_firebase_port.dart','deda_admin_session_firebase_adapter.dart',
    'deda_session_principal_tracker.dart','deda_session_transition_gate.dart',
    'deda_session_flow_prototype.dart','deda_stability_read_scope.dart',
    'deda_startup_measurements.dart','deda_published_place_recovery.dart',
    'deda_qa32_active_account_scope.dart','deda_six_badge_cutout.dart',
}
STATE = re.compile(r'class\s+(\w+)\s+extends\s+State<([^>]+)>[^\{]*\{')
STATELESS = re.compile(r'class\s+(\w+)\s+extends\s+StatelessWidget[^\{]*\{')


def reachable(lib):
    seen, pending = set(), ['main.dart']
    while pending:
        relative = pending.pop()
        if relative in seen or relative in OWN_MODULES:
            continue
        path = (lib/relative).resolve()
        if not path.is_relative_to(lib.resolve()) or not path.is_file():
            raise ValueError('Reachable section source missing: ' + relative)
        seen.add(relative)
        source = path.read_text()
        for name in re.findall(r"\b(?:import|export)\s+['\"]([^'\"]+)['\"]", source):
            if ':' not in name:
                pending.append(str((path.parent/name).relative_to(lib.resolve())))
    return sorted(seen)


def bind_file(source):
    if 'with DedaSectionState<' in source or ', DedaSectionState<' in source:
        raise ValueError('Sections already bound')
    ts = tokens(source)
    match = pairs(ts)
    reverse_match = {end: start for start, end in match.items()}
    offsets = {offset: i for i, (_, offset, _) in enumerate(ts)}
    starts = [offset for _, offset, _ in ts]
    edits, report = [], []
    for m in STATE.finditer(source):
        state, widget = m[1], m[2]
        if state in AUTH_STATES or state in INFRASTRUCTURE_STATES:
            report.append({'state': state, 'binding': 'existing-auth-or-identity'
                if state in AUTH_STATES else 'preserved-infrastructure-or-animation'})
            continue
        opening = offsets[m.end()-1]
        closing = match[opening]
        body_start, body_end = m.end(), ts[closing][1]
        header = m.group()[:-1].rstrip()
        mixin = (', ' if re.search(r'\bwith\b', header) else ' with ') + 'DedaSectionState<' + widget + '> '
        edits.append((m.end()-1, m.end()-1, mixin))
        body_source=source[body_start:body_end]
        subscriptions=re.findall(r'\bStreamSubscription(?:<[^;\n]+>)?\?\s+(\w+)\s*;',body_source)
        timers=re.findall(r'\bTimer\?\s+(\w+)\s*;',body_source)
        cleanup=[]
        for field in subscriptions:
            cleanup.append('    dedaCancelSectionResource(() => '+field+'?.cancel());\n    '+field+' = null;')
        for field in timers:
            cleanup.append('    '+field+'?.cancel();\n    '+field+' = null;')
        if state=='_DedaRoutePageState':
            cleanup.append('    dedaCancelSectionResource(() => _tts.stop());')
        if cleanup:
            if 'dedaOnSectionExpired' in body_source:raise ValueError('Section cleanup already declared')
            edits.append((body_start,body_start,'\n  @override\n  void dedaOnSectionExpired() {\n'+'\n'.join(cleanup)+'\n  }\n'))
        # Find declared Future methods and intentional account-transition spans.
        methods, excluded = {}, []
        for method in re.finditer(r'\bFuture<([^;\n]+?)>\s+(\w+)\s*\(', source[body_start:body_end]):
            pos = body_start + method.end()-1
            argument = offsets.get(pos)
            if argument is None: continue
            after = match[argument] + 1
            if after >= closing or ts[after][0] != 'async': continue
            if ts[after+1][0] != '{': continue
            start, end = after+1, match[after+1]
            methods[start] = (method[1], method[2])
            if method[2] in ACCOUNT_METHODS:
                excluded.append((start, end))
        def exempt(i):
            return any(a <= i <= b for a, b in excluded)
        asynchronous = []
        i = opening + 1
        while i < closing:
            if ts[i][0] == 'async' and ts[i+1][0] == '{' and not exempt(i+1):
                a, b = i+1, match[i+1]
                # Account-changing callbacks must retain the existing trusted
                # UI/logout flow, including navigation after selection changes.
                if any(ts[k][0] in ACCOUNT_METHODS - {'dispose'} and
                       k+1 < b and ts[k+1][0] == '(' for k in range(a+1, b)):
                    excluded.append((a,b)); i = b+1; continue
                asynchronous.append((a,b))
            i += 1
        # Each async body gets its own operation entry. Nested same-State calls
        # inherit one context; callbacks invoked later verify the same lease.
        for a,b in asynchronous:
            named = methods.get(a)
            if named:
                is_void = named[0] == 'void'
            else:
                children = [(x,y) for x,y in asynchronous if a < x < b]
                for k in range(a+1,b):
                    if ts[k][0]=='{' and ts[k-1][0]==')':
                        argument=reverse_match.get(k-1)
                        if argument is not None and ts[argument-1][0] not in {
                            'if','for','while','switch','catch','assert'}:
                            children.append((k,match[k]))
                is_void = not any(ts[k][0] == 'return' and ts[k+1][0] != ';'
                    and not any(x <= k <= y for x,y in children)
                    for k in range(a+1,b))
            helper = 'dedaRunSectionVoid' if is_void else 'dedaRunSection'
            edits.append((ts[a][2],ts[a][2], '\n    return '+helper+'(() async {\n'))
            edits.append((ts[b][1],ts[b][1], '\n    });\n  '))
        # Guard each await using the existing balanced-expression rewriter.
        # It also reaches awaited operations in nested callbacks. Keep original
        # login/logout methods byte-for-byte, rather than expiring their intent.
        for i in range(opening+1,closing):
            if ts[i][0] != 'await' or exempt(i): continue
            # Reuse the exact parser on an isolated single await expression.
            # Determine the inserted pair by diffing a suffix, then translate
            # back to original offsets; no text/string-based semicolon split.
            # Use the shared token grammar directly for precise ranges.
            j=i+1
            if ts[j][0]=='for':
                arg=j+1
                if ts[arg][0]!='(': raise ValueError('Unsupported await-for')
                end=match[arg]
                inside=[k for k in range(arg+1,end) if ts[k][0]=='in']
                if len(inside)!=1: raise ValueError('Ambiguous await-for source')
                edits.extend([(ts[inside[0]+1][1],ts[inside[0]+1][1],
                               'DedaSectionOperationContext.guardStream('),
                              (ts[end][1],ts[end][1],')')])
                continue
            begin=ts[j][1]
            helper='DedaSectionOperationContext.wait'
            if ts[j][0] in ('showDialog','showModalBottomSheet') and ts[j+1][0]=='<':
                depth,k=1,j+2
                while depth and k<closing:
                    if ts[k][0]=='<':depth+=1
                    if ts[k][0]=='>':depth-=1
                    k+=1
                result_type=source[ts[j+1][2]:ts[k-1][1]].strip()
                nullable=result_type if result_type=='void' or result_type.endswith('?') else result_type+'?'
                helper+='<'+nullable+'>'
            if ts[j][0]=='(': j=match[j]+1
            elif re.fullmatch(r'[A-Za-z_$][A-Za-z_0-9$]*',ts[j][0]): j+=1
            else: raise ValueError('Unsupported section await')
            while j < closing:
                word=ts[j][0]
                if word in ('.','?.'): j+=2
                elif word in ('(','['): j=match[j]+1
                elif word=='!': j+=1
                elif word=='<':
                    depth,k=1,j+1
                    while k<closing and depth:
                        if ts[k][0]=='<': depth+=1
                        if ts[k][0]=='>': depth-=1
                        if ts[k][0] in (';','{','}','='): break
                        k+=1
                    if depth or k>=closing or ts[k][0] not in ('(','.'): break
                    j=k
                else: break
            edits.extend([(begin,begin,helper+'(() => '),
                          (ts[j-1][2],ts[j-1][2],')')])
        for i in range(opening+1,closing):
            if ts[i][0]=='mounted' and not exempt(i) and ts[i-1][0] not in ('.','?.'):
                edits.append((ts[i][1],ts[i][2],'dedaSectionCurrent'))
            if ts[i][0]=='onUserEarnedReward' and ts[i+1][0]==':':
                args=i+2
                if ts[args][0]!='(': raise ValueError('Reward callback needs explicit review')
                body=match[args]+1
                if ts[body][0]=='async':body+=1
                if ts[body][0]!='{':raise ValueError('Reward callback form changed')
                edits.extend([(ts[args][1],ts[args][1],'dedaSectionCallback2('),
                              (ts[match[body]][2],ts[match[body]][2],')')])
        # Rendering an expired State removes its StreamBuilders and controls;
        # auth/account-change events schedule this via the mixin listener.
        build = re.search(r'\bWidget\s+build\s*\(BuildContext\s+\w+\)\s*(\{|=>)', source[body_start:body_end])
        if build is None:
            raise ValueError('State build form needs explicit review: '+state)
        pos = body_start+build.end()
        if build[1]=='{':
            edits.append((pos,pos,'\n    if (!dedaSectionCurrent) return dedaSectionExpiredView();\n'))
        else:
            k=bisect.bisect_left(starts,pos)
            while ts[k][0]!=';':
                k=match[k]+1 if k in match else k+1
            edits.append((pos,pos,' dedaSectionCurrent ? ('))
            edits.append((ts[k][1],ts[k][1],') : dedaSectionExpiredView()'))
        report.append({'state':state,'binding':'section-lifetime',
                       'asyncBodies':len(asynchronous),
                       'subscriptionsCancelled':subscriptions,'timersCancelled':timers,
                       'accountMethodsPreserved':[name for _,name in methods.values() if name in ACCOUNT_METHODS]})
    if not any(row['binding']=='section-lifetime' for row in report):
        return source, report
    # Multiple inserts at one offset follow deterministic nesting order.
    for start,end,text in sorted(edits,key=lambda x:(x[0],x[1]),reverse=True):
        source=source[:start]+text+source[end:]
    at=source.index('import ')
    source=source[:at]+"import 'deda_section_state.dart';\nimport 'deda_section_operation_context.dart';\n"+source[at:]
    pairs(tokens(source))
    return source,report


def bind_directory(output):
    output=Path(output)
    lib=output/'lib'
    main=lib/'main.dart'
    source=main.read_text()
    if source.count('static int _authAccountEpoch = 0;')!=1:
        raise ValueError('Complete account epoch binding required')
    source=source.replace('static int _authAccountEpoch = 0;',
        'static int _authAccountEpoch = 0;\n  static int get stabilityAccountEpoch => _authAccountEpoch;',1)
    hook='      DedaIncomingRequestNotifications.accountChanged();'
    if source.count(hook)!=3: raise ValueError('All account transitions required')
    source=source.replace(hook,hook+'\n      DedaSectionAccountChanges.changed();')
    # The awaited SDK expression becomes a closure. Snapshot the selected
    # nullable voice first so Dart promotion and the original choice survive.
    voice="""        if (female != null) {
          await _tts.setVoice({
            'name': (female['name'] ?? '').toString(),
            'locale': (female['locale'] ?? locale).toString(),
          });
        }"""
    replacement=voice.replace('if (female != null)',
        'final selectedVoice = female;\n        if (selectedVoice != null)').replace("female['", "selectedVoice['")
    if source.count(voice)!=1:raise ValueError('Original voice selection changed')
    source=source.replace(voice,replacement,1)
    reward='claimFuture = DedaDiamondsWallet.claimReward();'
    if source.count(reward)!=1:raise ValueError('Original reward future changed')
    source=source.replace(reward,'claimFuture = DedaSectionOperationContext.observe(DedaDiamondsWallet.claimReward());',1)
    main.write_text(source)
    report={}
    for name in reachable(lib):
        path=lib/name
        original=path.read_text()
        prepared=original
        if name=='deda_qa32_admin_gift_recipient_alias_bridge.dart':
            before='    if (canonical == null) return null;'
            if prepared.count(before)!=1:raise ValueError('Canonical recipient guard changed')
            prepared=prepared.replace(before,'    final canonicalTarget = canonical;\n    if (canonicalTarget == null) return null;',1)
            prepared=prepared.replace('adminDiamondGiftTarget(canonical)','adminDiamondGiftTarget(canonicalTarget)',1)
        if name=='deda_stage71_dual_admin_page.dart':
            before="        !RegExp(r'^@DEDA-[A-Z0-9]{6}$').hasMatch(target)) return;"
            if prepared.count(before)!=1:raise ValueError('Admin recipient selection changed')
            prepared=prepared.replace(before,before+'\n    final selectedTarget = target;',1)
            prepared=prepared.replace('recipientOriginalId: target,','recipientOriginalId: selectedTarget,',1)
            prepared=prepared.replace('            target,\n            row.identifier,','            selectedTarget,\n            row.identifier,',1)
        updated,rows=bind_file(prepared)
        updated,stateless_rows=bind_stateless(updated)
        rows+=stateless_rows
        if name=='main.dart':
            updated=bind_main_data_helpers(updated)
            rows.append({'state':'main-account-data-helpers','binding':'inherited-operation-checks'})
        elif name not in FOUNDATION_FILES and not STATE.search(original) and not STATELESS.search(original):
            if any(word=='await' for word,_,_ in tokens(original)):
                updated=bind_service(updated)
                rows.append({'state':name,'binding':'inherited-operation-checks'})
        if rows:
            path.write_text(updated)
            report[name]=rows
    (output/'section-bindings.json').write_text(json.dumps(report,indent=2)+'\n')
    return report


def bind_service(source):
    updated=guard_awaits(source,helper='DedaSectionOperationContext.wait')
    ts=tokens(updated);match=pairs(ts);edits=[]
    for i,(word,_,_) in enumerate(ts):
        if word=='catch' and i+1<len(ts) and ts[i+1][0]=='(':
            body=match[i+1]+1
            if ts[body][0]!='{':raise ValueError('Unsupported service catch')
            edits.append(ts[body][2])
    for pos in reversed(edits):
        updated=updated[:pos]+' DedaSectionOperationContext.checkCurrent();'+updated[pos:]
    if updated!=source and "import 'deda_section_operation_context.dart';\n" not in updated:
        pos=updated.index('import ')
        updated=updated[:pos]+"import 'deda_section_operation_context.dart';\n"+updated[pos:]
    return updated


def bind_main_data_helpers(source):
    edits=[];ts=tokens(source);match=pairs(ts);offsets={a:i for i,(_,a,_) in enumerate(ts)}
    for name in ('DedaTaskEngine','DedaDiamondsWallet','DedaSocialProgressWallet',
                 'DedaPlacesStore','DedaRegisteredPlacesStore'):
        m=re.search(r'\bclass '+name+r'\s*\{',source)
        if not m:raise ValueError('Account data helper missing: '+name)
        opening=m.end()-1;end=ts[match[offsets[opening]]][2]
        original=source[m.start():end]
        # No import is added inside a class. The outer main already imports it.
        guarded=bind_service("import 'deda_section_operation_context.dart';\n"+original)
        guarded=guarded[guarded.index('class '+name):]
        edits.append((m.start(),end,guarded))
    for start,end,text in sorted(edits,reverse=True):source=source[:start]+text+source[end:]
    return source


def bind_stateless(source):
    ts=tokens(source);match=pairs(ts);offsets={a:i for i,(_,a,_) in enumerate(ts)}
    edits,report=[],[]
    for m in STATELESS.finditer(source):
        name=m[1];opening=m.end()-1;end=ts[match[offsets[opening]]][2]
        original=source[m.start():end]
        if name=='DedaApp' or name=='DedaSixBadgeCutout':
            continue
        if not name.endswith('Page') and not re.search(r'\b(?:StreamBuilder|FutureBuilder)\b',original):
            continue
        # Stateless event methods already receive their caller's BuildContext.
        # Refuse a new unsupported method rather than silently leaving it out.
        for method in re.finditer(r'\bFuture<[^;\n]+?>\s+(\w+)\s*\(',original):
            arg=original.index('(',method.start())
            end_arg=original.index(') async',arg) if ') async' in original[arg:] else -1
            if end_arg<0 or 'BuildContext context' not in original[arg:end_arg]:
                raise ValueError('Stateless event requires explicit context: '+name+'.'+method[1])
        pseudo=original.replace('extends StatelessWidget','extends State<'+name+'>',1)
        rewritten,rows=bind_file("import 'placeholder.dart';\n"+pseudo)
        rewritten=rewritten[rewritten.index('class '+name):]
        rewritten=re.sub(r'extends\s+State<'+re.escape(name)+r'>\s+with DedaSectionState<'+re.escape(name)+r'>',
                         'extends StatelessWidget',rewritten,count=1)
        rewritten=rewritten.replace('dedaRunSectionVoid(', 'DedaSectionBoundary.runVoidForContext(context, ')
        rewritten=rewritten.replace('dedaRunSection(', 'DedaSectionBoundary.runForContext(context, ')
        rewritten=rewritten.replace('\n    if (!dedaSectionCurrent) return dedaSectionExpiredView();\n','\n',1)
        build=re.search(r'\bWidget\s+build\s*\(BuildContext\s+context\)\s*(\{|=>)',rewritten)
        if not build: raise ValueError('Stateless build needs review: '+name)
        rts=tokens(rewritten);rmatch=pairs(rts);rix={a:i for i,(_,a,_) in enumerate(rts)}
        if build[1]=='{':
            start=build.end();close=rts[rmatch[rix[start-1]]][1]
            rewritten=rewritten[:start]+'\n    return DedaSectionBoundary(builder: (context) {\n'+rewritten[start:close]+'\n    });\n'+rewritten[close:]
        else:
            start=build.end();k=bisect.bisect_left([a for _,a,_ in rts],start)
            while rts[k][0]!=';': k=rmatch[k]+1 if k in rmatch else k+1
            close=rts[k][1];expression=rewritten[start:close]
            prefix=' dedaSectionCurrent ? (';suffix=') : dedaSectionExpiredView()'
            if not expression.startswith(prefix) or not expression.endswith(suffix):
                raise ValueError('Stateless expression changed')
            expression=expression[len(prefix):-len(suffix)]
            rewritten=rewritten[:start]+' DedaSectionBoundary(builder: (context) => '+expression+')'+rewritten[close:]
        pairs(tokens(rewritten))
        edits.append((m.start(),end,rewritten))
        report.append({'state':name,'binding':'stateless-section-boundary',
                       'asyncBodies':sum(r.get('asyncBodies',0) for r in rows)})
    for start,end,text in reversed(edits): source=source[:start]+text+source[end:]
    if report:
        for dependency in ('deda_section_state.dart','deda_section_operation_context.dart'):
            directive="import '"+dependency+"';\n"
            if directive not in source:
                pos=source.index('import ');source=source[:pos]+directive+source[pos:]
    return source,report
