from __future__ import annotations

import importlib.machinery
import importlib.util
import json
import os
import stat
import subprocess
import tempfile
import threading
import unittest
from pathlib import Path
from unittest import mock


REPOSITORY = Path(__file__).resolve().parents[1]
QOPEN = REPOSITORY / "bin" / "qopen"


class StateBoundaryRegressionTests(unittest.TestCase):
    def run_qopen(
        self,
        *arguments: str,
        config: Path,
        check: bool = True,
        timeout: float = 10,
    ) -> subprocess.CompletedProcess[str]:
        environment = os.environ.copy()
        environment.pop("DISPLAY", None)
        environment.pop("WAYLAND_DISPLAY", None)
        environment["QOPEN_CONFIG"] = str(config)
        return subprocess.run(
            [str(QOPEN), *arguments],
            cwd=REPOSITORY,
            env=environment,
            text=True,
            capture_output=True,
            check=check,
            timeout=timeout,
        )

    def api(
        self,
        *arguments: str,
        config: Path,
        check: bool = True,
        timeout: float = 10,
    ) -> dict[str, object]:
        result = self.run_qopen(
            "api",
            *arguments,
            config=config,
            check=check,
            timeout=timeout,
        )
        return json.loads(result.stdout)

    def test_root_parent_state_directory_keeps_transferred_descriptor_open(self) -> None:
        """The root directory FD must stay owned by the store after transfer."""
        loader = importlib.machinery.SourceFileLoader("qopen_state_boundary", str(QOPEN))
        spec = importlib.util.spec_from_loader(loader.name, loader)
        self.assertIsNotNone(spec)
        assert spec is not None
        module = importlib.util.module_from_spec(spec)
        loader.exec_module(module)

        with mock.patch.object(module.os, "geteuid", return_value=0):
            with module.SecureStateStore(Path("/config.json")) as store:
                metadata = os.fstat(store.dir_fd)
                self.assertTrue(stat.S_ISDIR(metadata.st_mode))
                self.assertEqual(store.directory_path, Path("/"))

    def test_intermediate_parent_symlink_is_rejected(self) -> None:
        """Every ancestor component must be opened with O_NOFOLLOW."""
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            real_parent = root / "real-parent"
            real_state = real_parent / "qopen"
            real_state.mkdir(parents=True, mode=0o700)

            linked_parent = root / "linked-parent"
            linked_parent.symlink_to(real_parent, target_is_directory=True)
            config = linked_parent / "qopen" / "config.json"

            response = self.api("catalog", config=config, check=False)

            self.assertFalse(response["ok"])
            self.assertIn("secure state directory", str(response["error"]))
            self.assertFalse((real_state / "config.json").exists())

    def test_backup_path_race_never_writes_through_external_symlink(self) -> None:
        """Concurrent replacement of config.json.bak must never modify its target."""
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            state = root / "state"
            state.mkdir(mode=0o700)
            config = state / "config.json"

            initial = self.api("catalog", config=config)
            self.assertTrue(initial["ok"])

            sentinel = root / "sentinel"
            sentinel.write_text("external-target", encoding="utf-8")
            backup = state / "config.json.bak"
            stopped = threading.Event()

            def race_backup_path() -> None:
                counter = 0
                while not stopped.is_set():
                    temporary = state / f".attacker-backup-{counter % 2}"
                    counter += 1
                    try:
                        temporary.write_text("{}\n", encoding="utf-8")
                        os.replace(temporary, backup)
                    except OSError:
                        pass
                    try:
                        backup.unlink(missing_ok=True)
                        backup.symlink_to(sentinel)
                    except OSError:
                        pass

            attacker = threading.Thread(target=race_backup_path, daemon=True)
            attacker.start()
            try:
                for _index in range(16):
                    result = self.run_qopen(
                        "api",
                        "favorite",
                        "--id",
                        "omarchy",
                        "--mode",
                        "toggle",
                        config=config,
                        check=False,
                        timeout=5,
                    )
                    self.assertLess(len(result.stdout.encode("utf-8")), 4096)
                    response = json.loads(result.stdout)
                    self.assertIn("ok", response)
            finally:
                stopped.set()
                attacker.join(timeout=2)

            self.assertFalse(attacker.is_alive())
            self.assertEqual(
                sentinel.read_text(encoding="utf-8"),
                "external-target",
            )


if __name__ == "__main__":
    unittest.main()
