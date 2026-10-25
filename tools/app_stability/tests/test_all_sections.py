import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/'tools/app_stability'))
from bind_all_sections import bind_file, reachable, STATE, AUTH_STATES, INFRASTRUCTURE_STATES
from bind_auth_runtime import body_range, tokens, pairs
spec=importlib.util.spec_from_file_location('all_sections_restore',ROOT/'tools/restore_deda_stability_baseline.py')
restore=importlib.util.module_from_spec(spec);spec.loader.exec_module(restore)


class AllSectionBindingTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp=tempfile.TemporaryDirectory();root=Path(cls.tmp.name)
        cls.base=root/'base';cls.bound=root/'bound'
        restore.restore(cls.base,auth_runtime=True,pilot=True,startup_metrics=True,progress_backup_runtime=True,lazy_sections=True)
        restore.restore(cls.bound,section_entry=True,pilot=True,startup_metrics=True,progress_backup_runtime=True,lazy_sections=True)
        cls.report=json.loads((cls.bound/'section-bindings.json').read_text())
    @classmethod
    def tearDownClass(cls):cls.tmp.cleanup()

    def test_every_reachable_state_has_an_explicit_binding_or_preservation_reason(self):
        lib=self.bound/'lib'
        for name in reachable(lib):
            source=(lib/name).read_text()
            states={m[1] for m in STATE.finditer(source)}
            actual={r['state'] for r in self.report.get(name,[])}
            self.assertTrue(states<=actual,(name,states-actual))
        rows=[r for rs in self.report.values() for r in rs]
        self.assertGreaterEqual(sum(r['binding']=='section-lifetime' for r in rows),70)
        self.assertGreaterEqual(sum(r['binding']=='stateless-section-boundary' for r in rows),20)

    def test_stateless_admin_streams_and_confirmation_methods_are_included(self):
        for name in ['DedaPlaceRequestTrashPage','DedaSupportTrashPage',
                     'DedaAdminRecoveryInboxPage','DedaAdminInvitationsPage',
                     'DedaAdminAuditPage','DedaMyRequestsPage','DedaMyStorePage']:
            matches=[r for rs in self.report.values() for r in rs if r['state']==name]
            self.assertEqual([r['binding'] for r in matches],['stateless-section-boundary'],name)
        admin=(self.bound/'lib/admin_pages.dart').read_text()
        self.assertTrue('DedaSectionBoundary.runVoidForContext(context,' in admin)
        self.assertTrue('DedaSectionBoundary.runForContext(context,' in admin)

    def test_long_lived_root_and_tab_coordinators_are_not_account_pages(self):
        for name in ['deda_progress_backup_runtime.dart','deda_lazy_section_stack.dart',
                     'deda_lab_premium_frame_artwork.dart']:
            self.assertEqual((self.base/'lib'/name).read_bytes(),(self.bound/'lib'/name).read_bytes(),name)
        main=(self.bound/'lib/main.dart').read_text()
        start=main.index('class DedaApp ');opening=main.index('{',start)
        ts=tokens(main[opening:]);closing=opening+ts[pairs(ts,True)[0]][2]
        app=main[start:closing]
        self.assertNotIn('DedaSectionBoundary',app)

    def test_existing_logout_methods_remain_exact_so_navigation_can_finish(self):
        old=(self.base/'lib/main.dart').read_text();new=(self.bound/'lib/main.dart').read_text()
        for state,method in [('_DedaSettingsPageState','_logoutPersonalAccount'),('_DedaAccountHubPageState','_logout')]:
            bodies=[]
            for text in (old,new):
                a,b,_,_=body_range(text,method,after=text.index('class '+state+' '))
                bodies.append(text[a:b+1])
            self.assertEqual(*bodies)

    def test_account_change_events_reach_all_three_original_transition_hooks(self):
        main=(self.bound/'lib/main.dart').read_text()
        self.assertEqual(main.count('DedaSectionAccountChanges.changed();'),3)
        self.assertEqual(main.count('static int get stabilityAccountEpoch'),1)

    def test_backend_rules_and_all_purchase_contracts_are_untouched(self):
        for old in (self.base/'lib').glob('*.dart'):
            if old.name not in self.report and old.name not in ('main.dart',):
                self.assertEqual(old.read_bytes(),(self.bound/'lib'/old.name).read_bytes(),old.name)
        for name in ['deda_backend.dart','deda_pin_auth.dart','deda_lab_frame_secure_checkout.dart',
                     'deda_owner18_frame_checkout.dart','deda_social_service.dart']:
            old=(self.base/'lib'/name).read_text();new=(self.bound/'lib'/name).read_text()
            self.assertEqual(old,remove_section_guards(new),name)

    def test_generated_sources_stay_balanced_and_cannot_be_bound_twice(self):
        for name in self.report:
            text=(self.bound/'lib'/name).read_text();pairs(tokens(text))
            if any(r['binding']=='section-lifetime' for r in self.report[name]):
                with self.assertRaises(ValueError):bind_file(text)

    def test_new_state_uses_same_lease_and_keeps_dialogs_without_mutation_retries(self):
        source="""import 'package:flutter/material.dart';
class _ExampleState extends State<Example> {
 Future<void> act() async { await showDialog<void>(context: context, builder: (_) { return const SizedBox(); }); await service.buy(); }
 Widget build(BuildContext context) => const SizedBox();
}
"""
        updated,rows=bind_file(source)
        self.assertTrue('with DedaSectionState<Example>' in updated)
        self.assertTrue('return dedaRunSectionVoid' in updated)
        self.assertTrue('DedaSectionOperationContext.wait<void>(() => showDialog<void>' in updated)
        self.assertEqual(updated.count('service.buy()'),1)
        self.assertNotIn('.timeout(',updated)
        self.assertNotIn('retry',updated)
        self.assertEqual(rows[0]['asyncBodies'],1)

    def test_nullable_dialog_results_and_expired_navigation_cleanup_are_explicit(self):
        source="""import 'package:flutter/material.dart';
class _ExampleState extends State<Example> {
 Future<bool> confirm() async { return (await showDialog<bool>(context: context, builder: (_) => const SizedBox())) ?? false; }
 Widget build(BuildContext context) => const SizedBox();
}
"""
        updated,_=bind_file(source)
        self.assertTrue('DedaSectionOperationContext.wait<bool?>(() => showDialog<bool>' in updated)
        route=next(r for r in self.report['main.dart'] if r['state']=='_DedaRoutePageState')
        self.assertEqual(set(route['subscriptionsCancelled']),{'_positionSubscription','_compassSubscription'})
        self.assertIn('_positionAnimationTimer',route['timersCancelled'])
        main=(self.bound/'lib/main.dart').read_text()
        self.assertTrue('dedaCancelSectionResource(() => _tts.stop());' in main)


def remove_section_guards(source):
    """Verify that inherited service guards cannot alter financial statements."""
    ts=tokens(source);match=pairs(ts);edits=[]
    for i,(word,start,_) in enumerate(ts):
        if word=='DedaSectionOperationContext' and [t[0] for t in ts[i+1:i+7]]==['.','wait','(','(',')','=>']:
            opening=i+3;closing=match[opening]
            edits.extend([(start,ts[i+7][1]),(ts[closing][1],ts[closing][2])])
    for start,end in sorted(edits,reverse=True):source=source[:start]+source[end:]
    return source.replace("import 'deda_section_operation_context.dart';\n",'',1).replace(' DedaSectionOperationContext.checkCurrent();','')
