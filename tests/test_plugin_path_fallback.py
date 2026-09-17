from pathlib import Path
import unittest


REPOSITORY = Path(__file__).resolve().parents[1]


class PluginDirectoryFallbackSourceTests(unittest.TestCase):
    def test_fallback_strips_the_complete_manifest_entry_point(self) -> None:
        qopen_source = (REPOSITORY / "QOpen.qml").read_text(encoding="utf-8")

        self.assertIn("omarchy >= 4.0.3", qopen_source)
        self.assertIn("var entryPoint = manifest && manifest.entryPoints", qopen_source)
        self.assertIn(
            'entryPoint.split("/").map(encodeURIComponent).join("/")',
            qopen_source,
        )
        self.assertIn('var suffix = "/" + encodedEntryPoint', qopen_source)
        self.assertIn(
            "if (entryUrl.slice(-suffix.length) === suffix)",
            qopen_source,
        )
        self.assertIn(
            "var rootUrl = entryUrl.slice(0, -suffix.length)",
            qopen_source,
        )
        self.assertIn(
            'decodeURIComponent(rootUrl.slice("file://".length))',
            qopen_source,
        )

    def test_fallback_rejects_non_file_entry_urls(self) -> None:
        qopen_source = (REPOSITORY / "QOpen.qml").read_text(encoding="utf-8")

        self.assertIn(
            'if (!entryUrl || entryUrl.indexOf("file://") !== 0) return ""',
            qopen_source,
        )


if __name__ == "__main__":
    unittest.main()
