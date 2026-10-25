import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location('offline_smoke', ROOT/'tools/app_stability/native_app/offline_smoke.py')
smoke = importlib.util.module_from_spec(spec)
spec.loader.exec_module(smoke)

class NativeOfflineBoundaryTest(unittest.TestCase):
    def test_report_uses_actual_apk_source_instead_of_a_fixed_prior_build(self):
        commit = '3179619841a46f96bb7db5da3a10eb6541d3f96a'
        self.assertEqual(smoke.artifact_source_commit([
            {'sourceCommit': commit}, {'sourceCommit': commit}]), commit)

    def test_missing_or_mixed_apk_provenance_is_refused_before_launch(self):
        commit = '3179619841a46f96bb7db5da3a10eb6541d3f96a'
        for records in ([], [{}], [{'sourceCommit': None}],
                        [{'sourceCommit': 'old-label'}],
                        [{'sourceCommit': commit}, {'sourceCommit': '0'*40}]):
            with self.assertRaises(ValueError): smoke.artifact_source_commit(records)

    def test_only_loopback_and_emulator_host_return_before_final_reject(self):
        text='-N X\n-A X -d 127.0.0.0/8 -j RETURN\n-A X -d 10.0.2.2/32 -j RETURN\n-A X -j REJECT --reject-with icmp-port-unreachable\n'
        self.assertTrue(smoke.valid_firewall(text, 'X'))
        for invalid in (text.replace('10.0.2.2/32','0.0.0.0/0'),text.replace('-j REJECT','-j ACCEPT'),text+'-A X -j ACCEPT\n',text.replace('-j RETURN','-j ACCEPT'),text.replace('-d 127.0.0.0/8','! -d 127.0.0.0/8'),text.replace('-j REJECT --reject-with icmp-port-unreachable','-p tcp --dport 443 -j REJECT')):
            self.assertFalse(smoke.valid_firewall(invalid, 'X'))

    def test_ipv6_requires_local_loopback_and_explicit_reject(self):
        text='-N X\n-A X -d ::1/128 -j RETURN\n-A X -j REJECT --reject-with icmp6-port-unreachable\n'
        self.assertTrue(smoke.valid_firewall(text, 'X', True))
        self.assertFalse(smoke.valid_firewall(text.replace('::1/128','::/0'), 'X', True))

    def test_missing_android_launch_measurement_never_becomes_zero(self):
        self.assertEqual(smoke.timings('TotalTime: 2500\nWaitTime: 2600\n'), {'TotalTimeMs':2500,'WaitTimeMs':2600})
        for invalid in ('','TotalTime: -1\nWaitTime: 2\n','TotalTime: 1\n'):
            with self.assertRaises(ValueError):
                smoke.timings(invalid)
