"""Execute canonical/renamed-fork consumers and reject invalid anchors."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("remote_consumer", ROOT / "Tools/materialize-remote-consumer.py")
consumer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(consumer)


class RemoteConsumerTests(unittest.TestCase):
    def test_canonical_and_renamed_fork_preserve_products_and_plugins(self):
        for url, expected in [("https://github.com/InnoSquadCorp/InnoDI.git", "innodi"),
                              ("https://github.com/Contributor/DI-Fork.git", "di-fork")]:
            with tempfile.TemporaryDirectory(prefix="innodi-remote-fixture-") as directory:
                output = Path(directory)
                identity = consumer.materialize(ROOT / "Tests/RemoteConsumerSmoke", output, url, "a" * 40)
                self.assertEqual(identity, expected)
                manifest = (output / "Package.swift").read_text()
                self.assertIn('url: "' + url + '"', manifest)
                self.assertIn('revision: "' + "a" * 40 + '"', manifest)
                self.assertEqual(manifest.count('package: "' + expected + '"'), 3)
                self.assertIn('.product(name: "InnoDI",', manifest)
                self.assertIn('.plugin(name: "InnoDIDAGValidationPlugin",', manifest)
                self.assertNotIn("{{INNODI_", manifest)

    def test_invalid_url_sha_or_missing_fixture_creates_no_consumer(self):
        with tempfile.TemporaryDirectory(prefix="innodi-remote-negative-") as directory:
            output = Path(directory) / "output"
            fixtures = ROOT / "Tests/RemoteConsumerSmoke"
            for url in ["file:///tmp/repo", "https://evil.invalid/InnoDI.git", "-c core.sshCommand=bad",
                        "https://github.com/User/Fork.git\nINNODI_REVISION=x", "https://github.com/../Fork.git"]:
                with self.assertRaises(ValueError):
                    consumer.materialize(fixtures, output, url, "a" * 40)
                self.assertFalse(output.exists())
            for sha in ["main", "A" * 40, "a" * 39, "a" * 40 + "\n", "$(touch bad)"]:
                with self.assertRaises(ValueError):
                    consumer.materialize(fixtures, output, "https://github.com/User/Fork.git", sha)
                self.assertFalse(output.exists())
            with self.assertRaises(ValueError):
                consumer.materialize(Path(directory) / "missing", output, "https://github.com/User/Fork.git", "a" * 40)


if __name__ == "__main__":
    unittest.main()
