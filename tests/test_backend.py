from __future__ import annotations

import json
import os
import shlex
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY = Path(__file__).resolve().parents[1]
QOPEN = REPOSITORY / "bin" / "qopen"
STARTER_IDS = (
    "omarchy",
    "github",
    "home",
    "omarchy-shell-config",
    "btop",
    "fastfetch",
)


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

    def api(
        self,
        action: str,
        *arguments: str,
        config: Path,
        check: bool = True,
    ) -> dict[str, object]:
        result = self.run_qopen(
            "api", action, *arguments, config=config, check=check
        )
        return json.loads(result.stdout)

    def project_payload(self, root: Path, item_id: str = "fixture") -> str:
        return json.dumps(
            {
                "id": item_id,
                "name": item_id.title(),
                "type": "project",
                "group": "projects",
                "target": str(root),
            }
        )

    def test_version_matches_manifest(self) -> None:
        manifest = json.loads((REPOSITORY / "manifest.json").read_text(encoding="utf-8"))
        result = self.run_qopen("--version")
        self.assertEqual(result.stdout.strip(), f"qopen {manifest['version']}")

    def test_first_catalog_request_creates_starter_resources(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            config = Path(temporary_directory) / "config.json"

            response = self.api("catalog", config=config)

            self.assertTrue(response["ok"])
            items = response["result"]["items"]
            self.assertEqual(tuple(item["id"] for item in items), STARTER_IDS)
            self.assertEqual(
                {item["type"] for item in items},
                {"web", "project", "file", "tui", "command"},
            )
            self.assertFalse(any(item["type"] == "ssh" for item in items))
            self.assertEqual(stat.S_IMODE(config.stat().st_mode), 0o600)

    def test_existing_catalog_is_never_seeded(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            config = Path(temporary_directory) / "config.json"
            config.write_text(
                json.dumps({"version": 1, "defaults": {}, "items": []}),
                encoding="utf-8",
            )
            original = config.read_bytes()

            response = self.api("catalog", config=config)

            self.assertTrue(response["ok"])
            self.assertEqual(response["result"]["items"], [])
            self.assertEqual(config.read_bytes(), original)

    def test_project_browser_returns_directories_only(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            (root / "project").mkdir()
            (root / "notes.txt").write_text("fixture", encoding="utf-8")

            result = self.run_qopen(
                "api", "browse-path", "--path", str(root), "--type", "project",
                "--request-id", "17"
            )
            payload = json.loads(result.stdout)

            self.assertTrue(payload["ok"])
            self.assertEqual(payload["result"]["requestId"], "17")
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
            fixture = next(item for item in catalog["items"] if item["id"] == "fixture")
            self.assertEqual(fixture["target"], str(root))
            self.assertEqual(
                tuple(item["id"] for item in catalog["items"]),
                (*STARTER_IDS, "fixture"),
            )

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
                [*STARTER_IDS, "fixture"],
            )

    def test_qml_does_not_load_native_file_dialogs(self) -> None:
        qml_source = "\n".join(
            path.read_text(encoding="utf-8") for path in REPOSITORY.glob("*.qml")
        )
        self.assertNotIn("QtQuick.Dialogs", qml_source)
        self.assertNotIn("FileDialog {", qml_source)
        self.assertNotIn("FolderDialog {", qml_source)

    def test_qml_uses_native_mutations_and_closes_the_stock_menu(self) -> None:
        qopen_source = (REPOSITORY / "QOpen.qml").read_text(encoding="utf-8")

        self.assertIn('root.shell.hide("omarchy.menu")', qopen_source)
        self.assertIn('"api", "favorite"', qopen_source)
        self.assertIn('"api", "delete"', qopen_source)
        self.assertIn('"api", "recover"', qopen_source)
        self.assertNotIn('[root.backendPath, "favorite"', qopen_source)
        self.assertNotIn('[root.backendPath, "remove"', qopen_source)

    def test_path_picker_tracks_and_rejects_stale_requests(self) -> None:
        picker_source = (REPOSITORY / "PathPicker.qml").read_text(encoding="utf-8")

        self.assertIn('"--request-id", String(root.activeRequestSerial)', picker_source)
        self.assertIn("Number(result.requestId) !== root.requestSerial", picker_source)
        self.assertIn("if (browseProcess.running) browseProcess.running = false", picker_source)

    def test_command_arguments_round_trip_through_the_editor_format(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            config = Path(temporary_directory) / "config.json"
            arguments = ["notify-send", "hello world", "it's ready", "--icon=dialog info"]
            payload = json.dumps(
                {
                    "id": "quoted-command",
                    "name": "Quoted command",
                    "type": "command",
                    "group": "system",
                    "command": shlex.join(arguments),
                }
            )

            response = self.api("create", "--payload", payload, config=config)

            self.assertTrue(response["ok"])
            self.assertEqual(response["item"]["command"], arguments)
            editor_source = (REPOSITORY / "ResourceEditor.qml").read_text(encoding="utf-8")
            self.assertIn("function argvToCommand(argv)", editor_source)
            self.assertNotIn('item.command.join(" ")', editor_source)
            self.assertNotIn('item.editor.join(" ")', editor_source)

    def test_api_favorite_and_delete_are_atomic(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            config = root / "config.json"
            created = self.api(
                "create", "--payload", self.project_payload(root), config=config
            )["item"]

            favorite = self.api(
                "favorite", "--id", "fixture", "--mode", "toggle", config=config
            )
            self.assertTrue(favorite["favorite"])
            catalog = json.loads(config.read_text(encoding="utf-8"))
            original = next(item for item in catalog["items"] if item["id"] == "fixture")
            self.assertTrue(original["favorite"])

            deleted = self.api(
                "delete", "--original", json.dumps(original), config=config
            )
            self.assertTrue(deleted["ok"])
            remaining = json.loads(config.read_text(encoding="utf-8"))["items"]
            self.assertEqual([item["id"] for item in remaining], list(STARTER_IDS))
            self.assertEqual(created["id"], deleted["item"]["id"])

    def test_update_rejects_a_stale_original(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            config = root / "config.json"
            original = self.api(
                "create", "--payload", self.project_payload(root), config=config
            )["item"]
            self.api("favorite", "--id", "fixture", "--mode", "on", config=config)
            updated = dict(original)
            updated["name"] = "Changed"

            response = self.api(
                "update",
                "--payload", json.dumps(updated),
                "--original", json.dumps(original),
                config=config,
                check=False,
            )

            self.assertFalse(response["ok"])
            self.assertIn("changed while editing", response["error"])

    def test_invalid_urls_ssh_options_and_control_characters_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            config = Path(temporary_directory) / "config.json"
            fixtures = [
                {
                    "id": "bad-url", "name": "Bad URL", "type": "web",
                    "group": "web", "target": "https://",
                },
                {
                    "id": "bad-host", "name": "Bad Host", "type": "web",
                    "group": "web", "target": "https://_/docs",
                },
                {
                    "id": "bad-ssh", "name": "Bad SSH", "type": "ssh",
                    "group": "infra", "target": "-oProxyCommand=bad",
                },
                {
                    "id": "bad-control", "name": "Bad\u0000Name", "type": "project",
                    "group": "projects", "target": temporary_directory,
                },
                {
                    "id": "bad-boolean", "name": "Bad Boolean", "type": "project",
                    "group": "projects", "target": temporary_directory,
                    "favorite": "false",
                },
            ]

            for fixture in fixtures:
                with self.subTest(item_id=fixture["id"]):
                    response = self.api(
                        "create", "--payload", json.dumps(fixture),
                        config=config, check=False,
                    )
                    self.assertFalse(response["ok"])

    def test_recover_validates_backup_and_preserves_the_invalid_catalog(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            config = root / "config.json"
            self.api("create", "--payload", self.project_payload(root), config=config)
            self.api(
                "create", "--payload", self.project_payload(root, "second"), config=config
            )
            config.write_text("{broken", encoding="utf-8")

            response = self.api("recover", config=config)

            self.assertTrue(response["ok"])
            restored = json.loads(config.read_text(encoding="utf-8"))
            self.assertEqual(
                [item["id"] for item in restored["items"]],
                [*STARTER_IDS, "fixture"],
            )
            snapshot = Path(response["snapshot"])
            self.assertTrue(snapshot.exists())
            self.assertEqual(snapshot.read_text(encoding="utf-8"), "{broken")
            self.assertEqual(stat.S_IMODE(config.stat().st_mode), 0o600)
            self.assertEqual(stat.S_IMODE(snapshot.stat().st_mode), 0o600)

    def test_recover_does_not_replace_catalog_with_an_invalid_backup(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            config = root / "config.json"
            self.api("create", "--payload", self.project_payload(root), config=config)
            backup = config.with_name("config.json.bak")
            backup.write_text("{also-broken", encoding="utf-8")
            before = config.read_bytes()

            response = self.api("recover", config=config, check=False)

            self.assertFalse(response["ok"])
            self.assertEqual(config.read_bytes(), before)
            self.assertEqual(list(root.glob("config.json.invalid-*")), [])

    def test_catalog_api_rejects_semantically_invalid_json(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            config = Path(temporary_directory) / "config.json"
            config.write_text(
                json.dumps({"version": 1, "defaults": {}, "items": [{}]}),
                encoding="utf-8",
            )

            response = self.api("catalog", config=config, check=False)

            self.assertFalse(response["ok"])
            self.assertIn("items[0].id", response["error"])
            qopen_source = (REPOSITORY / "QOpen.qml").read_text(encoding="utf-8")
            self.assertIn('catalogProcess.command = [root.backendPath, "api", "catalog"]', qopen_source)

    def test_catalog_waits_for_the_host_to_inject_the_plugin_directory(self) -> None:
        qopen_source = (REPOSITORY / "QOpen.qml").read_text(encoding="utf-8")

        self.assertIn(
            'readonly property string backendPath: pluginDir ? pluginDir + "/bin/qopen" : ""',
            qopen_source,
        )
        self.assertIn("onPluginDirChanged:", qopen_source)
        self.assertIn("if (root.pluginDir) root.requestCatalogReload()", qopen_source)
        self.assertNotIn('readonly property string backendPath: pluginDir + "/bin/qopen"', qopen_source)

    def test_missing_catalog_requests_first_run_initialization(self) -> None:
        qopen_source = (REPOSITORY / "QOpen.qml").read_text(encoding="utf-8")

        self.assertIn('root.configError = "Preparing first-run resources…"', qopen_source)
        self.assertIn("onLoadFailed: function(error)", qopen_source)
        self.assertIn("root.requestCatalogReload()", qopen_source)

    def test_fix_permissions_secures_all_state_files(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            config = root / "config.json"
            self.api("create", "--payload", self.project_payload(root), config=config)
            self.api(
                "create", "--payload", self.project_payload(root, "second"), config=config
            )
            lock = config.with_name("config.json.lock")
            backup = config.with_name("config.json.bak")
            for path in (config, lock, backup):
                path.chmod(0o644)

            result = self.run_qopen("fix-permissions", config=config)

            self.assertIn("3 changed", result.stdout)
            for path in (config, lock, backup):
                self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)

    def test_doctor_reports_insecure_config_permissions(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            config = root / "config.json"
            self.api("create", "--payload", self.project_payload(root), config=config)
            config.chmod(0o644)

            result = self.run_qopen("--doctor", config=config, check=False)

            self.assertEqual(result.returncode, 1)
            self.assertIn("expected 0600", result.stdout)


if __name__ == "__main__":
    unittest.main()
