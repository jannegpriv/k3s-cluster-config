#!/usr/bin/env python3
"""Encrypt a restricted tunnel runtime key without writing plaintext to disk."""

import getpass
import json
import os
from pathlib import Path
import re
import subprocess


def main():
    target = Path(__file__).resolve().parents[1] / "chatgpt-tunnel" / "credentials.secret.sops.yaml"
    if target.exists():
        raise SystemExit("Encrypted credentials already exist; use the normal SOPS rotation process.")
    tunnel_id = input("Tunnel ID: ").strip()
    if not re.fullmatch(r"tunnel_[0-9a-f]{32}", tunnel_id):
        raise SystemExit("Invalid tunnel ID.")
    key = getpass.getpass("Restricted OpenAI runtime key (Tunnels Read + Use only): ").strip()
    if not key.startswith("sk-") or len(key) < 30 or any(c.isspace() for c in key):
        raise SystemExit("Invalid API key format.")
    secret = {
        "apiVersion": "v1",
        "kind": "Secret",
        "metadata": {"name": "basic-memory-chatgpt-tunnel", "namespace": "basic-memory"},
        "type": "Opaque",
        "stringData": {"tunnel-id": tunnel_id, "api-key": key},
    }
    result = subprocess.run(
        ["sops", "--encrypt", "--pgp", "BE7CC9C5400AF50610072526D7332A14FB23EE47",
         "--encrypted-regex", "^(data|stringData)$", "--input-type", "json",
         "--filename-override", "clusters/production/apps/basic-memory/chatgpt-tunnel/credentials.secret.sops.yaml",
         "--output-type", "yaml", "/dev/stdin"],
        input=json.dumps(secret), capture_output=True, text=True,
    )
    if result.returncode or "sops:" not in result.stdout or key in result.stdout:
        raise SystemExit("Encryption failed. No credentials were written.")
    fd = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w") as stream:
        stream.write(result.stdout)
    print(f"Encrypted credentials saved to {target}")
    print("The tunnel is still inactive. Verify its account scope before enabling GitOps deployment.")


if __name__ == "__main__":
    main()
