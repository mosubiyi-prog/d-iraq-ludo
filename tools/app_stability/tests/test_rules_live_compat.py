"""GET-only policy snapshot and additive scope guards; no remote credentials."""
import copy
import importlib.util
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'tools/app_stability/rules_compat'))
import merge as merger
import read_current as reader

BASE = '''rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    function signedIn() { return request.auth != null; }
    // Arabic label محفوظ and misleading braces }}} must be preserved.
    match /users/{uid} { allow get: if signedIn() && request.auth.uid == uid; }
    match /messages/{id} { allow read: if resource.data.label == "brace { and }"; }
  }
}
'''
CANDIDATE = (ROOT / 'tools/app_stability/progress_archive/firestore.rules').read_text()
RULESET = f'projects/{reader.PROJECT}/rulesets/fixture_ruleset_000001'


class Response:
    def __init__(self, data, status=200):
        self.data, self.status_code = data, status

    def json(self):
        return copy.deepcopy(self.data)


class Http:
    def __init__(self, source=BASE, changed=False, status=200):
        self.source, self.changed, self.status = source, changed, status
        self.calls = []
        self.releases = 0

    def get(self, url, **kwargs):
        self.calls.append((url, kwargs))
        if url.endswith('/releases/cloud.firestore'):
            self.releases += 1
            name = RULESET + ('changed' if self.changed and self.releases > 1 else '')
            return Response({'rulesetName': name, 'updateTime': 'fixture-time'}, self.status)
        return Response({'source': {'files': [{'name': 'firestore.rules', 'content': self.source}]}}, self.status)


class AdditiveRulesGuardTest(unittest.TestCase):
    def test_old_policy_is_exactly_reversible_with_unicode_and_quoted_braces(self):
        result, proof = merger.merge(BASE, CANDIDATE)
        offset, size = proof['insertAtUnicodeOffset'], proof['insertedUnicodeLength']
        self.assertEqual(result[:offset] + result[offset + size:], BASE)
        self.assertEqual(proof['originalSHA256'], merger.digest(BASE))
        self.assertTrue(proof['preservedByteExact'])
        self.assertNotIn('function ownsProgressAccount(', result)
        self.assertEqual(result.count('match /users/'), 1)
        self.assertEqual(result.count('match /deda_sessions/'), 0)
        self.assertEqual(proof['namespaces'], list(merger.NAMESPACES))

    def test_comments_do_not_create_a_false_documents_root_or_function_collision(self):
        source = BASE + '\n/* match /databases/{database}/documents { } dedaArchiveEvidenceV1 */'
        result, proof = merger.merge(source, CANDIDATE)
        self.assertTrue(result.endswith('*/'))
        self.assertTrue(proof['preservedByteExact'])

    def test_same_extension_cannot_be_applied_twice(self):
        result, _ = merger.merge(BASE, CANDIDATE)
        with self.assertRaisesRegex(merger.GuardError, 'already-present'):
            merger.merge(result, CANDIDATE)

    def test_existing_new_namespace_must_not_be_silently_replaced(self):
        for namespace in merger.NAMESPACES:
            source = BASE.replace('function signedIn()', f'match /{namespace}/{{id}} {{ allow read: if false; }}\n    function signedIn()')
            with self.subTest(namespace=namespace), self.assertRaisesRegex(merger.GuardError, 'namespace-already-defined'):
                merger.merge(source, CANDIDATE)

    def test_existing_helper_name_cannot_change_lexical_binding(self):
        source = BASE.replace('signedIn', 'dedaArchiveAccountOwnerV1')
        with self.assertRaisesRegex(merger.GuardError, 'identifier-collision'):
            merger.merge(source, CANDIDATE)

    def test_changed_or_malformed_root_is_rejected(self):
        for source in [BASE.replace("'2'", "'1'"), BASE.replace('{database}', '{db}'),
                       BASE + '\n}', BASE[:-3], BASE + '/* unclosed', BASE + '"unclosed']:
            with self.subTest(source=source[-20:]), self.assertRaises(merger.GuardError):
                merger.merge(source, CANDIDATE)

    def test_second_documents_scope_is_rejected(self):
        with self.assertRaisesRegex(merger.GuardError, 'one-firestore-documents-root'):
            merger.merge(BASE + BASE, CANDIDATE)

    def test_extension_cannot_add_an_unrelated_legacy_collection(self):
        changed = CANDIDATE.replace('    match /deda_sessions/{uid} {',
            '    match /admins/{uid} { allow write: if true; }\n    match /deda_sessions/{uid} {')
        with self.assertRaisesRegex(merger.GuardError, 'scope-changed'):
            merger.merge(BASE, changed)

    def test_combined_source_size_limit_fails_closed(self):
        with self.assertRaisesRegex(merger.GuardError, 'source-limit'):
            merger.merge(BASE + '\n//' + 'x' * (256 * 1024), CANDIDATE)

    def test_existing_recursive_grant_cannot_bypass_new_server_only_namespaces(self):
        for condition in ['true', 'signedIn()']:
            source = BASE.replace('function signedIn()',
                'match/{any=**}{allow read,write:if ' + condition + ';}\n    function signedIn()')
            with self.subTest(condition=condition), self.assertRaisesRegex(merger.GuardError, 'allow-overlaps'):
                merger.merge(source, CANDIDATE)

    def test_recursive_false_or_disjoint_legacy_grant_is_preserved(self):
        for block in ['match /{any=**} { allow read, write: if false; }',
                      'match /legacy/{any=**} { allow read, write: if true; }',
                      'match /legacy/{id} { match /{any=**} { allow read: if true; } }']:
            result, proof = merger.merge(BASE.replace('function signedIn()', block + '\n    function signedIn()'), CANDIDATE)
            self.assertIn(block, result)
            self.assertTrue(proof['preservedByteExact'])

    def test_two_segment_wildcard_grant_also_requires_review(self):
        source = BASE.replace('function signedIn()',
            'match /{collection}/{id} { allow write: if signedIn(); }\n    function signedIn()')
        with self.assertRaisesRegex(merger.GuardError, 'wildcard-allow'):
            merger.merge(source, CANDIDATE)


class RulesReadOnlyGuardTest(unittest.TestCase):
    def test_snapshot_uses_only_three_guarded_gets_and_stable_immutable_release(self):
        http = Http()
        text, metadata = reader.snapshot(reader.ReadOnlyRules(http))
        self.assertEqual(text, BASE)
        self.assertEqual(metadata['rulesetName'], RULESET)
        self.assertEqual(len(http.calls), 3)
        for url, options in http.calls:
            self.assertTrue(url.startswith(reader.API))
            self.assertEqual(options, {'timeout': 30, 'allow_redirects': False})

    def test_non_rules_endpoints_other_projects_queries_and_urls_are_blocked_before_http(self):
        http = Http()
        client = reader.ReadOnlyRules(http)
        for path in ['projects/other/rulesets/x', 'projects/deda-25b88/databases/x/documents/users',
                     'projects/deda-25b88/rulesets', reader.RELEASE + '?redirect=x',
                     RULESET + '/extra', 'https://evil.invalid/path']:
            with self.subTest(path=path), self.assertRaisesRegex(merger.GuardError, 'allowlist'):
                client.get(path)
        self.assertEqual(http.calls, [])

    def test_redirect_or_denial_is_not_followed_or_logged_as_private_response(self):
        for status in [302, 403, 500]:
            with self.subTest(status=status), self.assertRaisesRegex(merger.GuardError, 'http-denied'):
                reader.snapshot(reader.ReadOnlyRules(Http(status=status)))

    def test_concurrent_release_change_invalidates_read(self):
        with self.assertRaisesRegex(merger.GuardError, 'changed-during-read'):
            reader.snapshot(reader.ReadOnlyRules(Http(changed=True)))

    def test_snapshot_does_not_guess_between_multiple_policy_files(self):
        class Multiple(Http):
            def get(self, url, **kwargs):
                response = super().get(url, **kwargs)
                if '/rulesets/' in url:
                    response.data['source']['files'] *= 2
                return response
        with self.assertRaisesRegex(merger.GuardError, 'one-rules-file'):
            reader.snapshot(reader.ReadOnlyRules(Multiple()))

    def test_private_source_is_not_in_public_report_and_review_files_are_mode_600(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            report = reader.prepare(reader.ReadOnlyRules(Http()), root / 'private', root / 'public')
            self.assertNotIn('rulesetName', report)
            public = (root / 'public/rules-compat-report.json').read_text()
            self.assertNotIn('محفوظ', public)
            self.assertNotIn(RULESET, public)
            self.assertEqual((root / 'private/original.private.rules').read_text(), BASE)
            self.assertEqual((root / 'private/original.private.rules').stat().st_mode & 0o777, 0o600)
            self.assertEqual(report['readScope'], 'https://www.googleapis.com/auth/firebase.readonly')

    def test_private_output_cannot_be_inside_public_artifact_tree_or_repository(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for private, public in [(root / 'public/private', root / 'public'),
                                     (root / 'private', root / 'private/public'),
                                     (ROOT / 'private', root / 'public')]:
                with self.subTest(private=private), self.assertRaisesRegex(merger.GuardError, 'unsafe-private'):
                    reader.prepare(reader.ReadOnlyRules(Http()), private, public)

    def test_existing_private_output_is_never_overwritten(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            private = root / 'private'
            private.mkdir()
            (private / 'keep').write_text('keep')
            with self.assertRaisesRegex(merger.GuardError, 'must-be-empty'):
                reader.prepare(reader.ReadOnlyRules(Http()), private, root / 'public')
            self.assertEqual((private / 'keep').read_text(), 'keep')

    def test_post_test_check_requires_a_passed_emulator_report_and_unchanged_release(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            private, public = root / 'private', root / 'public'
            reader.prepare(reader.ReadOnlyRules(Http()), private, public)
            with self.assertRaisesRegex(merger.GuardError, 'emulator-result-not-passed'):
                reader.verify_after(reader.ReadOnlyRules(Http()), private, public)
            path = public / 'rules-compat-report.json'
            value = json.loads(path.read_text())
            value['status'] = 'emulator-passed-awaiting-release-verify'
            path.write_text(json.dumps(value))
            http = Http(changed=True)
            http.releases = 1
            with self.assertRaisesRegex(merger.GuardError, 'changed-during-emulator'):
                reader.verify_after(reader.ReadOnlyRules(http), private, public)
            verified = reader.verify_after(reader.ReadOnlyRules(Http()), private, public)
            self.assertEqual(verified['status'], 'verified')
            self.assertEqual(verified['rulesApiGets'], 4)

    def test_changed_review_files_cannot_receive_a_freshness_pass(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            private, public = root / 'private', root / 'public'
            reader.prepare(reader.ReadOnlyRules(Http()), private, public)
            path = public / 'rules-compat-report.json'
            value = json.loads(path.read_text())
            value['status'] = 'emulator-passed-awaiting-release-verify'
            path.write_text(json.dumps(value))
            (private / 'candidate.private.rules').write_text('changed')
            with self.assertRaisesRegex(merger.GuardError, 'review-files-changed'):
                reader.verify_after(reader.ReadOnlyRules(Http()), private, public)

    def test_missing_or_wrong_project_credentials_stop_without_network(self):
        for env in [{}, {'DEDA_RULES_PRIMARY_SA': '{}'},
                    {'DEDA_RULES_PRIMARY_SA': json.dumps({'type': 'service_account', 'project_id': 'other'})}]:
            with self.subTest(env=bool(env)), patch.dict(os.environ, env, clear=True), self.assertRaises(merger.GuardError):
                reader.session_reader()

    def test_crlf_policy_bytes_survive_private_storage_and_freshness_verification(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            private, public = root / 'private', root / 'public'
            original = BASE.replace('\n', '\r\n')
            reader.prepare(reader.ReadOnlyRules(Http(source=original)), private, public)
            self.assertEqual((private / 'original.private.rules').read_bytes(), original.encode('utf-8'))
            path = public / 'rules-compat-report.json'
            value = json.loads(path.read_text())
            value['status'] = 'emulator-passed-awaiting-release-verify'
            path.write_text(json.dumps(value))
            self.assertEqual(reader.verify_after(reader.ReadOnlyRules(Http()), private, public)['status'], 'verified')
