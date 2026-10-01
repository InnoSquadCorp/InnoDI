"""Keep unreleased examples separate from the advertised stable installation."""
from pathlib import Path
import re
import unittest


class ReadmeInstallationTests(unittest.TestCase):
    def test_development_readmes_route_examples_to_the_matching_checkout(self):
        root = Path(__file__).resolve().parents[2]
        releases = (root / "CHANGELOG.md").read_text()
        stable_version = re.search(r"Latest stable public release: `(\d+\.\d+\.\d+)`", releases).group(1)
        development = re.search(r"Current development train: `(\d+\.\d+\.\d+)` \(unreleased\)", releases)
        for path in [root / "README.md", root / "README.ko.md"]:
            with self.subTest(readme=path.name):
                text = path.read_text()
                first_example = text.index("<!-- innodi:compile -->")
                banner = text[:first_example]
                stable = text.index('from: "' + stable_version + '"')
                if development is None:
                    self.assertNotIn('.package(name: "InnoDI", path: "../InnoDI")', text)
                    self.assertNotIn("> [!IMPORTANT]", banner)
                    continue
                development_version = development.group(1)
                self.assertIn("> [!IMPORTANT]", banner)
                self.assertIn(development_version, banner)
                stable_docs = "https://github.com/InnoSquadCorp/InnoDI/blob/" + stable_version + "/" + path.name
                self.assertIn(stable_docs, banner)
                local = text.index('.package(name: "InnoDI", path: "../InnoDI")')
                self.assertLess(local, stable)
                self.assertIn(stable_docs, text[local:stable])
                self.assertNotIn('from: "' + development_version + '"', text)


    def test_frozen_translations_are_notice_pages(self):
        root = Path(__file__).resolve().parents[2]
        for name in ["README.ja.md", "README.zh-Hans.md", "README.de.md", "README.es.md", "README.ru.md"]:
            with self.subTest(readme=name):
                text = (root / name).read_text()
                self.assertIn("(README.md)", text)
                self.assertIn("https://github.com/InnoSquadCorp/InnoDI/blob/6.0.0/" + name, text)
                self.assertNotIn(".package(", text)


if __name__ == "__main__":
    unittest.main()
