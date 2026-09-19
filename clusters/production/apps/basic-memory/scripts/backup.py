"""Verified file backup for Basic Memory 0.23.2. No live SQLite files in archives."""

import datetime
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import shlex
import sqlite3
import subprocess
import tarfile
import tempfile
import time


def digest(stream):
    result = hashlib.sha256()
    for chunk in iter(lambda: stream.read(1024 * 1024), b""):
        result.update(chunk)
    return result.hexdigest()


def file_digest(path):
    with path.open("rb") as stream:
        return digest(stream)


def materialized_state(root):
    # An accepted MCP write may still exist only in SQLite. Refuse to call a
    # file archive successful until every write and moved-path cleanup settles.
    with sqlite3.connect((root / "config/memory.db").as_uri() + "?mode=ro", uri=True) as db:
        pending = db.execute("SELECT count(*) FROM note_content WHERE "
                             "file_write_status != 'synced' OR file_version IS NULL "
                             "OR file_version != db_version").fetchone()[0]
        vacated = db.execute("SELECT count(*) FROM note_file_vacate").fetchone()[0]
        if pending or vacated:
            raise RuntimeError("Pending or failed materialization; backup postponed")
        return db.execute("SELECT entity_id, db_version, file_checksum FROM note_content "
                          "ORDER BY entity_id").fetchall()


def snapshot(root):
    paths = [root / "config/config.json"]
    for path in sorted((root / "memory").rglob("*")):
        if path.is_symlink():
            raise RuntimeError("Symlinks are not supported in memory backups")
        if path.is_file():
            paths.append(path)
    return {str(path.relative_to(root)): file_digest(path) for path in paths}


def verify_archive(archive):
    with tarfile.open(archive, "r:gz") as tar:
        for member in tar.getmembers():
            path = PurePosixPath(member.name)
            allowed = member.name in {"manifest.json", "config/config.json"} or (
                len(path.parts) > 1 and path.parts[0] == "memory")
            if not member.isfile() or path.is_absolute() or ".." in path.parts or not allowed:
                raise RuntimeError("Unsafe archive member")
        manifest = json.load(tar.extractfile("manifest.json"))
        expected = manifest["sha256"]
        if sorted(tar.getnames()) != sorted([*expected, "manifest.json"]):
            raise RuntimeError("Unexpected archive members")
        for name, checksum in expected.items():
            if digest(tar.extractfile(name)) != checksum:
                raise RuntimeError("Archive content verification failed")
    return manifest


def create_archive(root, archive, attempts=3, delay=10):
    for attempt in range(attempts):
        try:
            state_before = materialized_state(root)
            before = snapshot(root)
            with tarfile.open(archive, "w:gz") as tar:
                for name in before:
                    tar.add(root / name, arcname=name, recursive=False)
                manifest = json.dumps({"format": 1, "basic_memory": "0.23.2",
                                       "created_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
                                       "sha256": before}, sort_keys=True).encode()
                info = tarfile.TarInfo("manifest.json")
                info.size = len(manifest)
                info.mode = 0o600
                tar.addfile(info, io.BytesIO(manifest))
            if before != snapshot(root) or state_before != materialized_state(root):
                raise RuntimeError("Content changed during backup")
            verify_archive(archive)
            return
        except (RuntimeError, OSError, sqlite3.Error):
            archive.unlink(missing_ok=True)
            if attempt + 1 == attempts:
                raise
            time.sleep(delay)


def ssh_options():
    return ["-p", "4711", "-o", "StrictHostKeyChecking=yes", "-o",
            "UserKnownHostsFile=/ssh/known_hosts", "-o", "ConnectTimeout=15",
            "-o", "ServerAliveInterval=15", "-o", "ServerAliveCountMax=3",
            "-o", "PreferredAuthentications=password", "-o", "PubkeyAuthentication=no"]


def remote(command, **kwargs):
    return subprocess.run(["sshpass", "-e", "ssh", *ssh_options(),
                           "jannenasadm@192.168.50.25", command],
                          check=True, timeout=600, **kwargs)


def upload(archive):
    destination = "/volume1/k3s_backups/basic-memory"
    name = archive.name
    checksum = file_digest(archive)
    temporary = f"{destination}/.{name}.uploading"
    final = f"{destination}/{name}"
    remote(f"umask 077; mkdir -p {shlex.quote(destination)}")
    with archive.open("rb") as stream:
        remote(f"umask 077; cat > {shlex.quote(temporary)}", stdin=stream)
    result = remote(f"sha256sum {shlex.quote(temporary)}", capture_output=True, text=True)
    if result.stdout.split()[0] != checksum:
        raise RuntimeError("NAS checksum mismatch; existing backups retained")
    remote(f"mv {shlex.quote(temporary)} {shlex.quote(final)} && "
           f"printf '%s\\n' {shlex.quote(checksum + '  ' + name)} > {shlex.quote(final + '.sha256')}")
    # Unique UTC timestamp names sort chronologically. Restrict deletion to our
    # archive pattern and only rotate after verified upload and atomic rename.
    result = remote(f"find {shlex.quote(destination)} -maxdepth 1 -type f "
                    "-name 'basic-memory-*.tar.gz' -print", capture_output=True, text=True)
    candidates = sorted(p for p in result.stdout.splitlines()
                        if p.startswith(destination + "/basic-memory-") and p.endswith(".tar.gz"))
    for old in candidates[:-14]:
        remote(f"rm -- {shlex.quote(old)} {shlex.quote(old + '.sha256')}")
    print(f"Verified NAS backup: {name}; sha256={checksum}", flush=True)


def main():
    os.umask(0o077)
    # sshpass reads its password from the environment, never from command args.
    os.environ["SSHPASS"] = Path("/credentials/password").read_text().rstrip("\n")
    with tempfile.TemporaryDirectory(dir="/work") as temporary:
        stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
        archive = Path(temporary) / f"basic-memory-{stamp}.tar.gz"
        create_archive(Path("/data"), archive)
        upload(archive)


if __name__ == "__main__":
    main()
