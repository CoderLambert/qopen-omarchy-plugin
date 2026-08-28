from __future__ import annotations

import re
import unittest
from pathlib import Path


REPOSITORY = Path(__file__).resolve().parents[1]
ENGLISH_README = REPOSITORY / "README.md"
CHINESE_README = REPOSITORY / "README.zh-CN.md"
MARKETPLACE_PREVIEW = REPOSITORY / "preview.png"
README_SCREENSHOT = REPOSITORY / "docs" / "assets" / "qopen-usage.png"


SECTION_PAIRS = [
    (2, "Highlights", "功能亮点"),
    (2, "Why QOpen exists", "为什么需要 QOpen"),
    (2, "Relationship to Omarchy Menu", "与 Omarchy Menu 的关系"),
    (2, "Requirements", "环境要求"),
    (2, "Installation", "安装"),
    (3, "Add QOpen to the Omarchy menu", "将 QOpen 添加到 Omarchy 菜单"),
    (3, "Recommended keyboard shortcut", "推荐快捷键"),
    (2, "Using the interface", "使用界面"),
    (3, "Usage preview", "使用截图"),
    (3, "Search and collections", "搜索与集合"),
    (3, "Adding or editing resources", "新增或编辑资源"),
    (3, "Main interface keys", "主界面快捷键"),
    (3, "Safe path browser keys", "安全路径浏览器快捷键"),
    (2, "Resource types", "资源类型"),
    (2, "Catalog format", "目录格式"),
    (2, "Command-line interface", "命令行界面"),
    (2, "Architecture and safety", "架构与安全"),
    (2, "Updating and removing", "更新和卸载"),
    (2, "Troubleshooting", "故障排查"),
    (3, "QOpen does not appear", "QOpen 不显示"),
    (3, "A resource will not open", "资源无法打开"),
    (3, "The catalog is invalid", "目录无效"),
    (3, "Development reload issues", "开发热重载问题"),
    (2, "Development", "开发"),
    (2, "License", "许可证"),
]


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def headings(document: str) -> list[tuple[int, str]]:
    result: list[tuple[int, str]] = []
    in_fence = False
    for line in document.splitlines():
        if line.startswith("```"):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        match = re.match(r"^(#{2,3})\s+(.+)$", line)
        if match:
            result.append((len(match.group(1)), match.group(2)))
    return result


def executable_examples(document: str) -> list[tuple[str, tuple[str, ...]]]:
    blocks: list[tuple[str, tuple[str, ...]]] = []
    language = ""
    lines: list[str] = []
    in_fence = False

    for line in document.splitlines():
        if line.startswith("```"):
            if in_fence:
                if language in {"bash", "json", "jsonc", "lua"}:
                    normalized = tuple(
                        code
                        for source in lines
                        if (code := source.split("#", 1)[0].rstrip())
                    )
                    blocks.append((language, normalized))
                in_fence = False
                language = ""
                lines = []
            else:
                in_fence = True
                language = line[3:].strip()
            continue
        if in_fence:
            lines.append(line)

    return blocks


class ReadmeParityTests(unittest.TestCase):
    def test_bilingual_readme_sections_have_the_same_order(self) -> None:
        english = [(level, title) for level, title, _ in SECTION_PAIRS]
        chinese = [(level, title) for level, _, title in SECTION_PAIRS]

        self.assertEqual(headings(read(ENGLISH_README)), english)
        self.assertEqual(headings(read(CHINESE_README)), chinese)

    def test_bilingual_readme_examples_stay_in_sync(self) -> None:
        self.assertEqual(
            executable_examples(read(ENGLISH_README)),
            executable_examples(read(CHINESE_README)),
        )

    def test_bilingual_readmes_use_the_same_release_and_screenshot(self) -> None:
        english = read(ENGLISH_README)
        chinese = read(CHINESE_README)

        self.assertIn("Current release: **2.4.0**", english)
        self.assertIn("当前版本：**2.4.0**", chinese)
        self.assertEqual(english.count("docs/assets/qopen-usage.png"), 1)
        self.assertEqual(chinese.count("docs/assets/qopen-usage.png"), 1)

    def test_marketplace_preview_matches_the_documented_interface(self) -> None:
        self.assertTrue(MARKETPLACE_PREVIEW.is_file())
        self.assertEqual(MARKETPLACE_PREVIEW.read_bytes(), README_SCREENSHOT.read_bytes())


if __name__ == "__main__":
    unittest.main()
