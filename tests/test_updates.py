"""Offline Linux update integration tests. Run: python3 -m unittest discover -s tests."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'bin/rotorflight-tools-installer.sh'


class UpdatesTest(unittest.TestCase):
    def run_update(self, receipt=None, exists=True, fail=False):
        with tempfile.TemporaryDirectory() as root:
            app = Path(root) / 'rotorflight-configurator'
            if exists:
                app.mkdir()
                (app / 'rotorflight-configurator').write_text('old')
                if receipt is not None:
                    (app / '.rotorflight-release.json').write_text(json.dumps(receipt))
            # Run the actual installer with network and desktop integration replaced.
            harness = SCRIPT.read_text().rsplit('main "$@"', 1)[0] + r'''
BASE_DIR="$1"
AUTO_STABLE_RELEASES=1
UPDATE_ONLY=1
select_latest_stable_release() {
  SELECTED_RELEASE=$'1\tv2\tRelease\t2026-10-01T00:00:00Z\tstable\tapp.zip\thttps://example.invalid/app.zip'
}
download_with_candy() { echo DOWNLOAD; [[ "$2" != *app.zip ]] || [[ "$FAIL_DOWNLOAD" != 1 ]]; }
extract_archive() { mkdir -p "$2/payload"; echo new > "$2/payload/rotorflight-configurator"; }
configure_electron_sandbox() { :; }
install_extracted_shared_assets() { :; }
install_desktop_files() { :; }
install_app configurator
'''
            result = subprocess.run(['bash', '-c', harness, 'test', root],
                                    env={**os.environ, 'FAIL_DOWNLOAD': str(int(fail))},
                                    capture_output=True, text=True)
            state = (app / '.rotorflight-release.json')
            return result, json.loads(state.read_text()) if state.exists() else None

    def test_same_and_newer_are_not_downloaded(self):
        for tag, date in [('v2', '2026-10-01T00:00:00Z'), ('v3', '2026-11-01T00:00:00Z')]:
            result, _ = self.run_update({'Tag': tag, 'Published': date})
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertNotIn('DOWNLOAD', result.stdout)

    def test_unknown_is_not_downloaded(self):
        for receipt in [None, {}, {'Tag': 'v1'}]:
            result, _ = self.run_update(receipt)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('unknown installed version', result.stdout)
            self.assertNotIn('DOWNLOAD', result.stdout)

    def test_older_is_updated_and_recorded(self):
        result, receipt = self.run_update({'Tag': 'v1', 'Published': '2026-01-01T00:00:00Z'})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('DOWNLOAD', result.stdout)
        self.assertEqual(receipt['Tag'], 'v2')

    def test_missing_is_installed(self):
        result, receipt = self.run_update(exists=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(receipt['Tag'], 'v2')

    def test_failed_download_preserves_receipt(self):
        old = {'Tag': 'v1', 'Published': '2026-01-01T00:00:00Z'}
        result, receipt = self.run_update(old, fail=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(receipt, old)
