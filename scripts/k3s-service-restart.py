#!/usr/bin/env python3
"""Restart only a K3s service, without draining or changing scheduling.

Run on a host with kubectl access (normally the control node). Requires a
previously verified machine ID. Backups and application health checks belong
to the maintenance runbook; this tool validates service/node recovery only.
"""
import argparse
from datetime import datetime, timezone
import json
import re
import shlex
import socket
import subprocess
import sys
import time


class Runner:
    deadline = None

    def run(self, args):
        timeout = 12 if self.deadline is None else min(12, self.deadline - time.monotonic())
        if timeout <= 0:
            raise subprocess.TimeoutExpired(args, 0)
        return subprocess.run(args, check=True, capture_output=True, text=True,
                              timeout=timeout).stdout.strip()

    def kube(self, *args):
        return self.run(["kubectl", "--request-timeout=5s", *args])

    def host(self, node, address, command):
        if socket.gethostname().split(".")[0] == node:
            return self.run(["bash", "-c", command])
        return self.run(["ssh", "-F", "/dev/null", "-o", "BatchMode=yes",
                         "-o", "StrictHostKeyChecking=yes", "-o", "ConnectTimeout=5",
                         "janne@" + address, command])


def lease_time(value):
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def ready(node):
    return any(c["type"] == "Ready" and c["status"] == "True"
               for c in node.get("status", {}).get("conditions", []))


def restart(args, runner=None, clock=time.monotonic, sleep=time.sleep,
            now=lambda: datetime.now(timezone.utc)):
    runner = runner or Runner()
    node = json.loads(runner.kube("get", "node", args.node, "-o", "json"))
    labels = node["metadata"].get("labels", {})
    master = any(key in labels for key in
                 ("node-role.kubernetes.io/control-plane", "node-role.kubernetes.io/master"))
    if master != (args.role == "master"):
        raise RuntimeError("Requested role does not match Kubernetes node labels")
    if not ready(node):
        raise RuntimeError("Node is not Ready; no changes made")
    address = next(a["address"] for a in node["status"]["addresses"] if a["type"] == "InternalIP")
    service = "k3s" if master else "k3s-agent"
    remote = lambda command: runner.host(args.node, address, command)
    if remote("cat /etc/machine-id") != args.expected_machine_id:
        raise RuntimeError("Machine identity mismatch; no changes made")
    if remote("sudo -n id -u") != "0":
        raise RuntimeError("Noninteractive root access unavailable")

    def state():
        output = remote("systemctl show " + service +
                        " -p ActiveState -p SubState -p MainPID"
                        " -p ExecMainStartTimestampMonotonic -p KillMode -p ExecStop -p ExecStopPost")
        return dict(line.split("=", 1) for line in output.splitlines() if "=" in line)

    before = state()
    if before.get("KillMode") != "process" or before.get("ExecStop") or before.get("ExecStopPost"):
        raise RuntimeError("Unexpected service stop behavior; no changes made")
    if before.get("ActiveState") != "active" or before.get("SubState") != "running":
        raise RuntimeError("Service not running; no changes made")
    if int(before.get("ExecMainStartTimestampMonotonic", "0")) <= 0:
        raise RuntimeError("Cannot establish previous service start time")
    previous_lease = lease_time(runner.kube("-n", "kube-node-lease", "get", "lease", args.node,
                                          "-o", "jsonpath={.spec.renewTime}"))
    if runner.kube("get", "--raw=/readyz") != "ok":
        raise RuntimeError("API is not ready; no changes made")
    print(f"Verified {args.node} ({address}), {service}, KillMode=process", flush=True)
    if args.dry_run:
        print("DRY RUN: prechecks passed; no service or scheduling changes", flush=True)
        return
    deadline = clock() + 180
    runner.deadline = deadline
    remote("sudo -n systemctl --no-block restart " + shlex.quote(service))
    print(f"Restart requested for {service}; waiting for a new process and node heartbeat", flush=True)
    new_instance_seen = None
    while clock() < deadline:
        try:
            current = state()
            changed = current.get("ExecMainStartTimestampMonotonic") not in (
                None, "0", before["ExecMainStartTimestampMonotonic"])
            if changed and current.get("ActiveState") == "active" and current.get("SubState") == "running":
                if new_instance_seen is None:
                    new_instance_seen = now()
                fresh = lease_time(runner.kube("-n", "kube-node-lease", "get", "lease", args.node,
                                              "-o", "jsonpath={.spec.renewTime}"))
                after = json.loads(runner.kube("get", "node", args.node, "-o", "json"))
                healthy = (fresh > max(previous_lease, new_instance_seen) and ready(after)
                           and runner.kube("get", "--raw=/readyz") == "ok")
                if healthy and clock() < deadline:
                    if bool(after.get("spec", {}).get("unschedulable")) != bool(node.get("spec", {}).get("unschedulable")):
                        raise RuntimeError("Scheduling state changed externally; investigate before continuing")
                    print(f"RECOVERED {args.node}: new service start, PID={current.get('MainPID')}, "
                          f"fresh heartbeat={fresh.isoformat()}, Ready, API ready", flush=True)
                    return
        except (subprocess.SubprocessError, ValueError, KeyError):
            # API/SSH can briefly be unavailable while the service starts.
            pass
        sleep(min(5, max(0, deadline - clock())))
    raise RuntimeError("Recovery timeout after 180 seconds; stop maintenance and investigate via SSH. "
                       "No automatic retry, drain or restore performed")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("node")
    parser.add_argument("role", choices=("master", "worker"))
    parser.add_argument("--service-only", required=True, action="store_true")
    parser.add_argument("--expected-machine-id", required=True)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    if not re.fullmatch(r"[a-z0-9][a-z0-9.-]*", args.node) or not re.fullmatch(r"[0-9a-f]{32}", args.expected_machine_id):
        parser.error("Invalid node name or machine ID")
    try:
        restart(args)
    except (RuntimeError, subprocess.SubprocessError, ValueError, KeyError, StopIteration) as error:
        print(f"STOP: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
