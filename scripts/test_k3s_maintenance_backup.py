"""Exercise actual SQLite snapshots with a concurrent writer, without K3s."""
from contextlib import closing
import importlib.util
from pathlib import Path
import sqlite3
import tempfile
import threading
import unittest

spec = importlib.util.spec_from_file_location("backup", Path(__file__).with_name("k3s-maintenance-backup.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class BackupTests(unittest.TestCase):
    def test_busy_wal_snapshot_is_consistent_and_standalone(self):
        with tempfile.TemporaryDirectory() as tmp:
            source, target = Path(tmp)/"source.db", Path(tmp)/"backup.db"
            with closing(sqlite3.connect(source)) as db:
                db.execute("PRAGMA journal_mode=WAL")
                db.execute("CREATE TABLE counter(a,b)")
                db.execute("INSERT INTO counter VALUES(0,0)")
                db.execute("CREATE TABLE payload(data)")
                db.executemany("INSERT INTO payload VALUES(zeroblob(1048576))", [()] * 32)
                db.commit()
                stop, writing = threading.Event(), threading.Event()
                commits = []

                def writer():
                    with closing(sqlite3.connect(source)) as connection:
                        while not stop.is_set():
                            connection.execute("UPDATE counter SET a=a+1,b=b+1")
                            connection.commit()
                            commits.append(1)
                            writing.set()
                            stop.wait(0.001)

                thread = threading.Thread(target=writer)
                thread.start()
                try:
                    self.assertTrue(writing.wait(5))
                    start = len(commits)
                    module.snapshot_sqlite(source, target)
                    self.assertGreater(len(commits), start)
                finally:
                    stop.set(); thread.join(5)
                self.assertFalse(Path(str(target)+"-wal").exists())
                self.assertFalse(Path(str(target)+"-shm").exists())
                with closing(sqlite3.connect(f"file:{target}?mode=ro&immutable=1", uri=True)) as copy:
                    self.assertEqual(copy.execute("PRAGMA integrity_check").fetchall(), [("ok",)])
                    a,b=copy.execute("SELECT a,b FROM counter").fetchone()
                    self.assertEqual(a,b)
                    self.assertEqual(copy.execute("SELECT count(*) FROM payload").fetchone()[0],32)

    def test_existing_backup_is_not_overwritten(self):
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/"backup.db"; path.write_bytes(b"keep")
            with self.assertRaisesRegex(RuntimeError,"overwrite"):
                module.snapshot_sqlite(Path(tmp)/"missing.db",path)
            self.assertEqual(path.read_bytes(),b"keep")

    def test_non_wal_source_is_rejected_without_copy(self):
        with tempfile.TemporaryDirectory() as tmp:
            source,target=Path(tmp)/"source.db",Path(tmp)/"backup.db"
            with closing(sqlite3.connect(source)) as db:
                db.execute("CREATE TABLE data(value)")
            with self.assertRaisesRegex(RuntimeError,"WAL"):
                module.snapshot_sqlite(source,target)
            self.assertFalse(target.exists())


if __name__ == "__main__": unittest.main()
