import importlib.util
import json
from pathlib import Path
import sqlite3
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("backup", Path(__file__).parents[1] / "scripts/backup.py")
backup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(backup)


class BackupTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "memory").mkdir()
        (self.root / "config").mkdir()
        (self.root / "memory/önskemål.md").write_text("# Önskemål\nSvenska anteckningar.")
        (self.root / "config/config.json").write_text(json.dumps({"projects": {"main": "/data/memory"}}))
        with sqlite3.connect(self.root / "config/memory.db") as db:
            db.executescript("CREATE TABLE note_content(entity_id, db_version, file_version, file_checksum, file_write_status);"
                             "CREATE TABLE note_file_vacate(id);")
        self.archive = self.root / "backup.tar.gz"

    def test_round_trip_excludes_database_and_verifies_unicode(self):
        backup.create_archive(self.root, self.archive, delay=0)
        manifest = backup.verify_archive(self.archive)
        self.assertEqual(set(manifest["sha256"]), {"memory/önskemål.md", "config/config.json"})

    def test_pending_write_prevents_success(self):
        with sqlite3.connect(self.root / "config/memory.db") as db:
            db.execute("INSERT INTO note_content VALUES (1, 2, 1, 'old', 'pending')")
        with self.assertRaises(RuntimeError):
            backup.create_archive(self.root, self.archive, attempts=1)
        self.assertFalse(self.archive.exists())

    def test_concurrent_change_prevents_success(self):
        original = backup.snapshot
        calls = 0
        def changing(root):
            nonlocal calls
            calls += 1
            if calls == 2:
                (root / "memory/önskemål.md").write_text("Changed during archive")
            return original(root)
        with patch.object(backup, "snapshot", side_effect=changing):
            with self.assertRaises(RuntimeError):
                backup.create_archive(self.root, self.archive, attempts=1)
        self.assertFalse(self.archive.exists())

    def test_symlink_is_rejected(self):
        (self.root / "memory/link").symlink_to(self.root / "config/config.json")
        with self.assertRaises(RuntimeError):
            backup.create_archive(self.root, self.archive, attempts=1)


if __name__ == "__main__":
    unittest.main()
