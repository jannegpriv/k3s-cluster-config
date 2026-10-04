#!/usr/bin/env python3
"""Create a protected, online SQLite/config backup before K3s maintenance.

Run as root on the node. The destination must not already exist. This does
not stop services; copy the resulting directory off-node before maintenance.
"""
import argparse
from contextlib import closing
import hashlib
import json
import os
from pathlib import Path
import signal
import sqlite3
import tarfile


def snapshot_sqlite(source_path, target_path):
    if target_path.exists():
        raise RuntimeError("Refusing to overwrite an existing backup")
    with closing(sqlite3.connect(f"file:{source_path}?mode=ro", uri=True)) as source:
        if source.execute("PRAGMA journal_mode").fetchone()[0] != "wal":
            raise RuntimeError("Online snapshot requires WAL mode")
        # Pin a WAL read snapshot so busy K3s writes cannot repeatedly
        # restart incremental copying. Writers continue; retain ample
        # disk space for the WAL until this read transaction finishes.
        source.execute("BEGIN")
        source.execute("SELECT name FROM sqlite_master LIMIT 1").fetchone()
        with closing(sqlite3.connect(target_path)) as target:
            source.backup(target, pages=1024, sleep=0.05)
            if target.execute("PRAGMA journal_mode=DELETE").fetchone()[0] != "delete":
                raise RuntimeError("Backup did not become a standalone database")
            result = target.execute("PRAGMA integrity_check").fetchall()
            if result != [("ok",)]:
                raise RuntimeError("SQLite integrity check failed")
        source.rollback()
    # Some SQLite versions leave unused shared-memory bookkeeping behind.
    # All connections are closed and DELETE mode was confirmed above.
    wal = Path(str(target_path) + "-wal")
    if wal.exists() and wal.stat().st_size:
        raise RuntimeError("Backup still has WAL data; do not use it")
    wal.unlink(missing_ok=True)
    Path(str(target_path) + "-shm").unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("role", choices=("master", "worker"))
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    if os.geteuid() != 0:
        parser.error("Run as root")
    os.umask(0o077)
    destination = args.destination.resolve()
    destination.mkdir(mode=0o700, parents=True, exist_ok=False)

    def timeout(_signum, _frame):
        raise TimeoutError("Backup exceeded 30 minutes; do not restart K3s")

    signal.signal(signal.SIGALRM, timeout)
    signal.alarm(1800)
    paths = [Path("/etc/rancher/k3s"), Path("/etc/rancher/node"),
             Path("/home/janne/.kube/config")]
    for unit in ("k3s", "k3s-agent"):
        paths.extend(Path("/etc/systemd/system").glob(unit + ".service*"))
    agent = Path("/var/lib/rancher/k3s/agent")
    paths.extend(p for p in agent.iterdir() if p.is_file())
    if (agent / "etc").exists():
        paths.append(agent / "etc")
    if args.role == "master":
        server = Path("/var/lib/rancher/k3s/server")
        for name in ("tls", "cred", "token", "node-token", "agent-token"):
            if (server / name).exists():
                paths.append(server / name)
        if not (server / "token").is_file():
            raise RuntimeError("Missing server token: backup cannot be restored")
        snapshot_sqlite(server / "db/state.db", destination / "state.db")
        print("SQLite online backup: integrity_check=ok", flush=True)
    with tarfile.open(destination / "configuration.tar.gz", "w:gz") as archive:
        for path in sorted(set(paths)):
            if path.exists():
                archive.add(path, arcname=str(path).lstrip("/"))
    checksums = {}
    for path in sorted(destination.iterdir()):
        if path.is_file():
            digest = hashlib.sha256()
            with path.open("rb") as stream:
                for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b""):
                    digest.update(chunk)
            checksums[path.name] = digest.hexdigest()
    (destination / "checksums.json").write_text(json.dumps(checksums, indent=2) + "\n")
    signal.alarm(0)
    print(json.dumps({"complete": True, "directory": str(destination),
                      "files": list(checksums)}), flush=True)


if __name__ == "__main__":
    main()
