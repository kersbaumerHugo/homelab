"""Offline tests for OPNsense backup preflight and encrypted save."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("opnsense_backup", ROOT / "scripts/opnsense-config-backup.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

VALID_XML = b'<?xml version="1.0"?><opnsense><system><hostname>fw</hostname></system></opnsense>'
RECIPIENT = 'age1' + 'x' * 55


class BackupTests(unittest.TestCase):
    def test_valid_xml_accepted(self):
        module.validate_xml(VALID_XML)

    def test_html_response_rejected(self):
        with self.assertRaises(module.BackupError):
            module.validate_xml(b'<html><body>login</body></html>')

    def test_malformed_xml_rejected(self):
        with self.assertRaises(module.BackupError):
            module.validate_xml(b'<opnsense><system></opnsense>')

    def test_empty_response_rejected(self):
        with self.assertRaises(module.BackupError):
            module.validate_xml(b'')

    def test_oversized_response_rejected(self):
        with self.assertRaises(module.BackupError):
            module.validate_xml(b'x' * (module.MAX_BYTES + 1))

    def test_insecure_netrc_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            cert, netrc = Path(directory) / 'cert', Path(directory) / 'netrc'
            cert.write_text('cert')
            netrc.write_text('key')
            netrc.chmod(0o644)
            with self.assertRaises(module.BackupError):
                module.credentials_ok(cert, netrc)

    def test_api_uses_get_with_verified_tls(self):
        with mock.patch.object(module.subprocess, 'run') as runner:
            runner.return_value.returncode = 0
            runner.return_value.stdout = VALID_XML
            value = module.download(Path('/crt'), Path('/netrc'))
        self.assertEqual(value, VALID_XML)
        cmd = runner.call_args.args[0]
        self.assertIn('--cacert', cmd)
        self.assertIn('--netrc-file', cmd)
        self.assertIn('--resolve', cmd)
        self.assertNotIn('--insecure', cmd)
        self.assertNotIn('-k', cmd)
        self.assertNotIn('-X', cmd)
        self.assertTrue(cmd[-1].endswith('/api/core/backup/download/this'))

    def test_encrypted_save_has_no_plaintext_file(self):
        def fake_encrypt(*args, **kwargs):
            kwargs['stdout'].write(b'encrypted bytes' * 10)
            return mock.Mock(returncode=0)
        with tempfile.TemporaryDirectory() as d:
            with mock.patch.object(module.shutil, 'which', return_value='/usr/bin/age'):
                with mock.patch.object(module.subprocess, 'run', side_effect=fake_encrypt):
                    output = module.encrypted_save(VALID_XML, Path(d), RECIPIENT)
            self.assertTrue(output.name.endswith('.xml.age'))
            self.assertTrue(output.is_file())
            self.assertEqual(len(list(Path(d).iterdir())), 1)
            self.assertEqual(output.read_bytes(), b'encrypted bytes' * 10)

    def test_failed_encryption_cleans_temp(self):
        with tempfile.TemporaryDirectory() as d:
            with mock.patch.object(module.shutil, 'which', return_value='/usr/bin/age'):
                with mock.patch.object(module.subprocess, 'run', return_value=mock.Mock(returncode=1)):
                    with self.assertRaises(module.BackupError):
                        module.encrypted_save(VALID_XML, Path(d), RECIPIENT)
            self.assertEqual(list(Path(d).iterdir()), [])


if __name__ == '__main__':
    unittest.main()
