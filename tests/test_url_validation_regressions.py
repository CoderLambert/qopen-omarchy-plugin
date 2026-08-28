from __future__ import annotations

import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY = Path(__file__).resolve().parents[1]
QOPEN = REPOSITORY / "bin" / "qopen"


class UrlValidationRegressionTests(unittest.TestCase):
    def run_qopen(
        self,
        *arguments: str,
        config_path: Path | None = None,
    ) -> subprocess.CompletedProcess[str]:
        environment = os.environ.copy()
        environment.pop("DISPLAY", None)
        environment.pop("WAYLAND_DISPLAY", None)
        if config_path is not None:
            environment["QOPEN_CONFIG"] = str(config_path)
        return subprocess.run(
            [str(QOPEN), *arguments],
            cwd=REPOSITORY,
            env=environment,
            text=True,
            capture_output=True,
            check=False,
            timeout=5,
        )

    def check_web_target(self, value: str) -> dict[str, object]:
        result = self.run_qopen(
            "api",
            "check-target",
            "--type",
            "web",
            "--value",
            value,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        response = json.loads(result.stdout)
        self.assertTrue(response["ok"])
        return response["result"]

    def test_bare_single_label_is_rejected_but_common_local_targets_remain_valid(self) -> None:
        invalid = self.check_web_target("asd")
        self.assertFalse(invalid["valid"])
        self.assertEqual(invalid["level"], "error")
        self.assertIn("domain", str(invalid["message"]).lower())

        valid_cases = {
            "example.com": "https://example.com",
            "localhost:3000": "https://localhost:3000",
            "127.0.0.1:3000": "https://127.0.0.1:3000",
            "[::1]:3000": "https://[::1]:3000",
            "https://intranet": "https://intranet",
        }
        for value, expected in valid_cases.items():
            with self.subTest(value=value):
                response = self.check_web_target(value)
                self.assertTrue(response["valid"])
                self.assertEqual(response["level"], "ok")
                self.assertEqual(response["normalized"], expected)

    def test_editor_validation_uses_the_same_url_rule(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            config_path = Path(temporary_directory) / "qopen" / "config.json"
            payload = {
                "name": "Invalid URL",
                "type": "web",
                "group": "web",
                "target": "asd",
                "mode": "app",
            }
            result = self.run_qopen(
                "api",
                "validate",
                "--payload",
                json.dumps(payload),
                config_path=config_path,
            )
            self.assertEqual(result.returncode, 1)
            response = json.loads(result.stdout)
            self.assertFalse(response["ok"])
            self.assertIn("domain", response["error"].lower())

    def test_embedded_credentials_remain_rejected(self) -> None:
        response = self.check_web_target("https://user:pass@example.com")
        self.assertFalse(response["valid"])
        self.assertEqual(response["level"], "error")
        self.assertIn("credentials", str(response["message"]).lower())


if __name__ == "__main__":
    unittest.main()
