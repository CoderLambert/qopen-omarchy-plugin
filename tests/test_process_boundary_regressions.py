from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path


REPOSITORY = Path(__file__).resolve().parents[1]
QOPEN = REPOSITORY / "bin" / "qopen"


class ProcessBoundaryRegressionTests(unittest.TestCase):
    def run_qopen(
        self,
        *arguments: str,
        environment_overrides: dict[str, str] | None = None,
        timeout: float = 5,
    ) -> subprocess.CompletedProcess[str]:
        environment = os.environ.copy()
        environment.pop("DISPLAY", None)
        environment.pop("WAYLAND_DISPLAY", None)
        if environment_overrides:
            environment.update(environment_overrides)
        return subprocess.run(
            [str(QOPEN), *arguments],
            cwd=REPOSITORY,
            env=environment,
            text=True,
            capture_output=True,
            check=False,
            timeout=timeout,
        )

    @staticmethod
    def process_is_running(pid: int) -> bool:
        status = Path(f"/proc/{pid}/stat")
        try:
            fields = status.read_text(encoding="utf-8").split()
        except FileNotFoundError:
            return False
        return len(fields) > 2 and fields[2] != "Z"

    def test_helper_deadline_terminates_the_whole_process_group(self) -> None:
        """A helper child that inherits stdout must not survive its parent deadline."""
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            child_pid_file = root / "child.pid"
            helper = root / "wl-paste"
            helper.write_text(
                f"#!{sys.executable}\n"
                "import os, subprocess, sys, time\n"
                "child = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(60)'])\n"
                "with open(os.environ['QOPEN_TEST_CHILD_PID'], 'w', encoding='utf-8') as output:\n"
                "    output.write(str(child.pid))\n"
                "    output.flush()\n"
                "    os.fsync(output.fileno())\n"
                "time.sleep(60)\n",
                encoding="utf-8",
            )
            helper.chmod(0o700)
            environment = {
                "PATH": f"{root}:{os.environ.get('PATH', '')}",
                "QOPEN_TEST_CHILD_PID": str(child_pid_file),
            }

            started = time.monotonic()
            result = self.run_qopen(
                "api",
                "clipboard-read",
                environment_overrides=environment,
            )
            elapsed = time.monotonic() - started
            response = json.loads(result.stdout)

            self.assertFalse(response["ok"])
            self.assertIn("clipboard is unavailable", response["error"])
            self.assertLess(elapsed, 2.0)
            self.assertTrue(child_pid_file.exists())
            child_pid = int(child_pid_file.read_text(encoding="utf-8"))

            deadline = time.monotonic() + 1.0
            while self.process_is_running(child_pid) and time.monotonic() < deadline:
                time.sleep(0.02)
            self.assertFalse(
                self.process_is_running(child_pid),
                "helper descendant survived the bounded-process deadline",
            )


if __name__ == "__main__":
    unittest.main()
