import unittest
from tools.deda_owner18_verify_signers import compare, certificates

class SignerVerification(unittest.TestCase):
    def test_old_and_new_android_tools_output_identifies_same_certificate(self):
        digest = 'a53d855b82d1280f324037428421838139ecf2e30174f9fcd0bd1878698b5f4a'
        old = 'Signer #1 certificate SHA-256 digest: ' + digest + '\n'
        new = 'V2 Signer: certificate SHA-256 digest: ' + digest + '\n'
        self.assertEqual(compare(old, new), digest)
    def test_missing_unrelated_and_changed_certificates_stop(self):
        a = 'Signer #1 certificate SHA-256 digest: ' + 'a' * 64
        for bad in ['', 'Source Stamp certificate SHA-256 digest: ' + 'a' * 64,
                    'V2 Signer: certificate SHA-256 digest: ' + 'b' * 64]:
            with self.assertRaises(ValueError):
                compare(a, bad)
    def test_multiple_distinct_signers_stop(self):
        with self.assertRaises(ValueError):
            certificates('V2 Signer: certificate SHA-256 digest: ' + 'a' * 64 +
                         '\nV3 Signer: certificate SHA-256 digest: ' + 'b' * 64)

if __name__ == '__main__':
    unittest.main()
