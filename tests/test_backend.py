from __future__ import annotations

import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY = Path(__file__).resolve().parents[1]
QOPEN = REPOSITORY / "bin" / "qopen"


class QOpenBackendTests(unittest.TestCase):
    def run_qopen(
        self,
        *arguments: str,
        config: Path | None = None,
        check: bool = True,
    ) -> subprocess.CompletedProcess[str]:
        environment = os.environ.copy()
        environment.pop("DISPLAY", None)
        environment.pop("WAYLAND_DISPLAY", None)
        if config is not None:
            environment["QOPEN_CONFIG"] = str(config)
        return subprocess.run(
            [str(QOPEN), *arguments],
            cwd=REPOSITORY,
            env=environment,
            text=True,
            capture_output=True,
            check=check,
        )

    def test_version_matches_manifest(self) -> None:
        manifest = json.loads((REPOSITORY / "manifest.json").read_text(encoding="utf-8"))
        result = self.run_qopen("--version")
        self.assertEqual(result.stdout.strip(), f"qopen {manifest['version']}")

    def test_project_browser_returns_directories_only(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            (root / "project").mkdir()
            (root / "notes.txt").write_text("fixture", encoding="utf-8")

            result = self.run_qopen(
                "api", "browse-path", "--path", str(root), "--type", "project"
            )
            payload = json.loads(result.stdout)

            self.assertTrue(payload["ok"])
            self.assertEqual([entry["name"] for entry in payload["result"]["entries"]], ["project"])
            self.assertTrue(all(entry["kind"] == "directory" for entry in payload["result"]["entries"]))

    def test_file_browser_returns_directories_and_files(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            (root / "project").mkdir()
            (root / "notes.txt").write_text("fixture", encoding="utf-8")

            result = self.run_qopen(
                "api", "browse-path", "--path", str(root), "--type", "file"
            )
            entries = json.loads(result.stdout)["result"]["entries"]

            self.assertEqual(
                [(entry["name"], entry["kind"]) for entry in entries],
                [("project", "directory"), ("notes.txt", "file")],
            )

    def test_create_uses_isolated_catalog_and_atomic_backup(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            config = root / "config.json"
            payload = json.dumps(
                {
                    "id": "fixture",
                    "name": "Fixture",
                    "type": "project",
                    "group": "projects",
                    "target": str(root),
                }
            )

            result = self.run_qopen(
                "api", "create", "--payload", payload, config=config
            )
            response = json.loads(result.stdout)
            catalog = json.loads(config.read_text(encoding="utf-8"))

            self.assertTrue(response["ok"])
            self.assertEqual(catalog["items"][0]["id"], "fixture")
            self.assertEqual(catalog["items"][0]["target"], str(root))

            second_payload = json.dumps(
                {
                    "id": "second",
                    "name": "Second",
                    "type": "project",
                    "group": "projects",
                    "target": str(root),
                }
            )
            self.run_qopen(
                "api", "create", "--payload", second_payload, config=config
            )

            backup = config.with_name("config.json.bak")
            self.assertTrue(backup.exists())
            self.assertEqual(
                [item["id"] for item in json.loads(backup.read_text(encoding="utf-8"))["items"]],
                ["fixture"],
            )

    def test_qml_does_not_load_native_file_dialogs(self) -> None:
        qml_source = "\n".join(
            path.read_text(encoding="utf-8") for path in REPOSITORY.glob("*.qml")
        )
        self.assertNotIn("QtQuick.Dialogs", qml_source)
        self.assertNotIn("FileDialog {", qml_source)
        self.assertNotIn("FolderDialog {", qml_source)


if __name__ == "__main__":
    unittest.main()
