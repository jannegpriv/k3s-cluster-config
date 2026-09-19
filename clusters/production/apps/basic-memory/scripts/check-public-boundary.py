"""Run on a public GitHub runner, with no Tailscale or cluster credentials."""
import ipaddress
import os
import socket
import subprocess

address = ipaddress.ip_address(os.environ["PUBLIC_IPV4"])
if address.version != 4 or not address.is_global:
    raise SystemExit("A public IPv4 address is required")

# Distinguish a blocked target from a runner with no working Internet access.
subprocess.run(["curl", "--fail", "--silent", "--show-error", "--max-time", "20",
                "-o", "/dev/null", "https://github.com"], check=True)
try:
    socket.getaddrinfo("memory.k3s.nu", 443)
except socket.gaierror as error:
    if error.errno != socket.EAI_NONAME:
        raise
else:
    raise SystemExit("Unexpected public DNS record for memory.k3s.nu")

for extra in ([], ["-H", "X-Forwarded-For: 192.168.50.75"]):
    result = subprocess.run(["curl", "--silent", "--show-error", "--noproxy", "*",
                             "--connect-timeout", "10", "--max-time", "15",
                             "--resolve", f"memory.k3s.nu:443:{address}",
                             "--output", "/dev/null", "--write-out", "%{http_code}",
                             *extra, "https://memory.k3s.nu/mcp"], capture_output=True, text=True)
    # Only connection refusal and timeout with no HTTP response count as denial.
    # A TLS error also fails: it shows that a public listener could be reachable.
    if result.returncode not in (7, 28) or result.stdout != "000":
        raise SystemExit(f"Boundary check failed: curl={result.returncode}, HTTP={result.stdout}")
    print(f"Public connection denied; forwarded-header test={bool(extra)}")
