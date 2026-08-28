from __future__ import annotations

import unittest
from pathlib import Path


REPOSITORY = Path(__file__).resolve().parents[1]
PATH_PICKER = REPOSITORY / "PathPicker.qml"


class PathPickerRefreshRegressionTests(unittest.TestCase):
    def test_refresh_is_explicit_and_does_not_reinterpret_unsubmitted_path_text(self) -> None:
        source = PATH_PICKER.read_text(encoding="utf-8")

        self.assertIn("function refreshCurrentPath()", source)
        self.assertIn("var target = root.currentPath", source)
        self.assertIn('tooltipText: "Refresh current directory · F5"', source)
        self.assertGreaterEqual(source.count("event.key === Qt.Key_F5"), 2)
        self.assertIn("onClicked: root.refreshCurrentPath()", source)
        self.assertIn("onClicked: root.loadPath(pathField.text)", source)


if __name__ == "__main__":
    unittest.main()
