"""Exercise goal-fixture-run.sh orchestration with dummy files, never a simulator."""
from pathlib import Path
import os
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).with_name("goal-fixture-run.sh").read_text()


class GoalFixtureRunnerTests(unittest.TestCase):
    def run_case(self, codes, interrupt=False, backup_failure=False):
        with tempfile.TemporaryDirectory(prefix="hp-recovery-test-") as temporary:
            root = Path(temporary)
            folder = root / "container/Library/Application Support/HelloProtein"
            folder.mkdir(parents=True)
            store = folder / "app-state.json"
            original = b'{"schemaVersion":1,"logs":[],"goals":[],"settings":{}}'
            store.write_bytes(original)
            (root / "udid-17.txt").write_text("MOCK")
            binaries = root / "bin"
            binaries.mkdir()

            def executable(path, text):
                path.write_text("#!/bin/zsh\n" + text)
                path.chmod(0o755)

            executable(binaries / "xcrun", 'if [[ "$2" == get_app_container ]]; then print -r -- "$MOCK_CONTAINER"; fi\nexit 0\n')
            if backup_failure:
                executable(binaries / "cp", "exit 74\n")
            executable(root / "run-test.sh", '''
print -r -- "$3" >> "$MOCK_CALLS"
if [[ "$MOCK_INTERRUPT" == 1 ]]; then kill -TERM "$PPID"; exit 0; fi
case "$3" in
 test23GoalEmpty) exit "$MOCK_FIRST";;
 test24GoalNeedsReview) exit "$MOCK_SECOND";;
 test25GoalDateChanged) exit "$MOCK_LAST";;
esac
''')
            script = root / "goal-fixture-run.sh"
            script.write_text(SCRIPT.replace("/private/tmp/hp-iphone-ui", str(root)))
            env = dict(os.environ, PATH=str(binaries) + ":" + os.environ["PATH"],
                       MOCK_CONTAINER=str(root / "container"), MOCK_CALLS=str(root / "calls"),
                       MOCK_FIRST=str(codes[0]), MOCK_SECOND=str(codes[1]), MOCK_LAST=str(codes[2]),
                       MOCK_INTERRUPT=str(int(interrupt)))
            result = subprocess.run(["/bin/zsh", str(script), "17", "test"], env=env,
                                    capture_output=True, text=True, timeout=15)
            self.assertEqual(store.read_bytes(), original, result.stderr)
            calls = (root / "calls").read_text().splitlines() if (root / "calls").exists() else []
            return result.returncode, calls

    def test_success_and_each_failure_are_reported_after_restoration(self):
        for codes in [(0, 0, 0), (65, 0, 0), (0, 66, 0), (0, 0, 67), (65, 66, 67)]:
            with self.subTest(codes=codes):
                code, calls = self.run_case(codes)
                self.assertEqual(code, next((c for c in codes if c), 0))
                self.assertEqual(len(calls), 3)

    def test_termination_restores_original(self):
        code, calls = self.run_case((0, 0, 0), interrupt=True)
        self.assertEqual(code, 143)
        self.assertEqual(len(calls), 1)

    def test_failed_backup_never_changes_store(self):
        code, calls = self.run_case((0, 0, 0), backup_failure=True)
        self.assertEqual(code, 74)
        self.assertEqual(calls, [])


if __name__ == "__main__":
    unittest.main()
