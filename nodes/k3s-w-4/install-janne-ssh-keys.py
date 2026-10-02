#!/usr/bin/env python3
"""Add the two approved public keys to janne on the verified w-4 host.

Run as root on w-4. Stdin: {"keys": [<Mac public key>, <m-1 public key>]}.
Use --check for validation without writes. Never pass private keys.
"""
import base64
import datetime
import hashlib
import json
import os
from pathlib import Path
import pwd
import shutil
import stat
import sys
import tempfile

MACHINE_ID = "c7b0d03e0da640c996578c3aa724f29a"
APPROVED = {
    "SHA256:0PGZ4TgVOqorCZ9M4v+U8rostSXVftFUNR8W+Agu1nI": "janne-mac",
    "SHA256:RllKMJNzfZOxUqaQUtM9jjNs3aYCpiRwjx6tQ6tQazc": "janne-k3s-m-1",
}

if os.geteuid() != 0 or Path("/etc/machine-id").read_text().strip() != MACHINE_ID:
    sys.exit("Must run as root on the verified k3s-w-4 host")
user = pwd.getpwnam("janne")
home = Path(user.pw_dir)
ssh_dir = home / ".ssh"
target = ssh_dir / "authorized_keys"
for path, mode, directory in [(home, 0o700, True), (ssh_dir, 0o700, True), (target, 0o600, False)]:
    info = path.lstat()
    valid_type = stat.S_ISDIR(info.st_mode) if directory else stat.S_ISREG(info.st_mode)
    if not valid_type or info.st_uid != user.pw_uid or stat.S_IMODE(info.st_mode) != mode:
        sys.exit(f"Unexpected ownership, permissions, or type: {path}")

keys = {}
for key in json.load(sys.stdin)["keys"]:
    fields = key.split()
    if len(fields) < 2 or fields[0] not in ("ssh-ed25519", "ssh-rsa"):
        sys.exit("Only plain ED25519/RSA public keys are accepted")
    raw = base64.b64decode(fields[1], validate=True)
    fingerprint = "SHA256:" + base64.b64encode(hashlib.sha256(raw).digest()).decode().rstrip("=")
    if fingerprint not in APPROVED:
        sys.exit("Unapproved public key fingerprint")
    keys[fingerprint] = f"{fields[0]} {fields[1]} {APPROVED[fingerprint]}"
if set(keys) != set(APPROVED):
    sys.exit("Both approved public keys are required")

original = target.read_bytes()
existing = [line.split() for line in original.decode().splitlines() if not line.lstrip().startswith("#")]
additions = [line for line in keys.values() if not any(line.split()[1] in fields for fields in existing)]
if "--check" in sys.argv or not additions:
    print(json.dumps({"check_only": "--check" in sys.argv, "keys_to_add": len(additions)}))
    sys.exit(0)

stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
backup_dir = Path("/root") / ("janne-ssh-backup-" + stamp)
backup_dir.mkdir(mode=0o700)
backup = backup_dir / "authorized_keys"
shutil.copy2(target, backup)
backup.chmod(0o600)
updated = original + (b"\n" if original and not original.endswith(b"\n") else b"")
updated += ("\n".join(additions) + "\n").encode()
fd, temp_name = tempfile.mkstemp(prefix=".authorized_keys-", dir=ssh_dir)
try:
    with os.fdopen(fd, "wb") as output:
        output.write(updated)
        output.flush()
        os.fsync(output.fileno())
        os.fchown(output.fileno(), user.pw_uid, user.pw_gid)
        os.fchmod(output.fileno(), 0o600)
    if target.read_bytes() != original:
        sys.exit("authorized_keys changed during installation; refusing to replace it")
    os.replace(temp_name, target)
finally:
    if os.path.exists(temp_name):
        os.unlink(temp_name)
print(json.dumps({"keys_added": len(additions), "backup": str(backup), "existing_keys_preserved": True}))
