import unittest
from security_check import osv_findings, pub_packages, secret_findings


class SecurityChecksTest(unittest.TestCase):
    def test_hosted_versions_include_transitive(self):
        lock = '''packages:
  http:
    dependency: transitive
    description:
      url: "https://pub.dev"
    source: hosted
    version: "1.2.0"
  flutter:
    source: sdk
    version: "0.0.0"
sdks:
  dart: ">=3.3.0"
'''
        self.assertEqual(pub_packages(lock), [('http', '1.2.0')])
        with self.assertRaises(ValueError):
            pub_packages(lock.replace('https://pub.dev', 'https://private.example'))

    def test_osv_detects_advisories_and_incomplete_results(self):
        packages = [('http', '1.0.0')]
        self.assertEqual(osv_findings(packages, {'results': [{}]}), [])
        self.assertEqual(osv_findings(packages, {'results': [{'vulns': [{'id': 'TEST-1'}]}]}),
                         ['http@1.0.0: TEST-1'])
        for results in ([], [{'next_page_token': 'more'}]):
            with self.assertRaises(ValueError):
                osv_findings(packages, {'results': results})

    def test_fixtures_are_scoped_and_real_values_redacted(self):
        prefix = 'sk_' + 'sandbox_'
        self.assertEqual(list(secret_findings('server/test/client_test.dart', prefix + 'test_key')), [])
        self.assertTrue(list(secret_findings('lib/client.dart', prefix + 'test_key')))
        value = prefix + 'a' * 32
        findings = list(secret_findings('server/test/client_test.dart', value))
        self.assertEqual(len(findings), 1)
        self.assertNotIn(value, findings[0])
        self.assertTrue(list(secret_findings('test/fixture.dart', 'gh' + 'p_' + 'a' * 36)))


if __name__ == '__main__':
    unittest.main()
