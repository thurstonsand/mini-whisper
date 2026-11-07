import os
from pathlib import Path
import subprocess
import tempfile
import unittest


class RunUITestsTests(unittest.TestCase):
    def test_returns_build_status_and_profiles_success_and_failure(self):
        runner = Path(__file__).with_name("run_ui_tests").resolve()
        for status in (0, 65):
            with (
                self.subTest(status=status),
                tempfile.TemporaryDirectory() as directory,
            ):
                root = Path(directory)
                (root / "scripts").mkdir()
                commands = {
                    "xcodebuild": f"echo test-output; exit {status}",
                    "xcbeautify": "cat",
                    "scripts/profile_uitest_bundle": 'echo "$1" > profiled',
                }
                for name, body in commands.items():
                    path = root / name
                    path.write_text(f"#!/bin/sh\n{body}\n")
                    path.chmod(0o755)
                result = subprocess.run(
                    [str(runner)],
                    cwd=root,
                    env={**os.environ, "PATH": f"{root}:{os.environ['PATH']}"},
                    capture_output=True,
                    text=True,
                )
                self.assertEqual(result.returncode, status, result.stderr)
                self.assertIn("test-output", result.stdout)
                self.assertEqual(
                    (root / "profiled").read_text().strip(), ".build/uitest.xcresult"
                )


if __name__ == "__main__":
    unittest.main()
