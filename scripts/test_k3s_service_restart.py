"""Failure-path tests; all cluster and service commands are simulated."""
import argparse
from datetime import datetime, timezone
import importlib.util
import json
from pathlib import Path
import subprocess
import unittest

spec = importlib.util.spec_from_file_location("restart", Path(__file__).with_name("k3s-service-restart.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class Fake:
    def __init__(self, master=False):
        self.calls = []
        self.elapsed = 0
        self.restarted = False
        self.change_start = True
        self.change_lease = True
        self.identity = "a" * 32
        self.kill_mode = "process"
        self.stop_hook = ""
        self.api_ok = True
        self.node_ready = True
        self.master = master
        self.recovery_error = False

    def host(self, node, address, command):
        self.calls.append(command)
        if command == "cat /etc/machine-id": return self.identity
        if command == "sudo -n id -u": return "0"
        if command.startswith("systemctl show"):
            start = "200" if self.restarted and self.change_start else "100"
            return (f"ActiveState=active\nSubState=running\nMainPID=42\n"
                    f"ExecMainStartTimestampMonotonic={start}\nKillMode={self.kill_mode}\nExecStop={self.stop_hook}")
        if command.startswith("sudo -n systemctl --no-block restart"):
            self.restarted = True
            return ""
        raise AssertionError("Unexpected host command: " + command)

    def kube(self, *args):
        self.calls.append("kubectl " + " ".join(args))
        if self.restarted and self.recovery_error:
            raise subprocess.TimeoutExpired("kubectl", 5)
        if "lease" in args:
            return "2026-10-04T07:00:20Z" if self.restarted and self.change_lease else "2026-10-04T07:00:00Z"
        if "--raw=/readyz" in args: return "ok" if self.api_ok else "failed"
        if "node" in args:
            return json.dumps({"metadata":{"labels":{"node-role.kubernetes.io/control-plane":""} if self.master else {}},
                "spec":{}, "status":{"addresses":[{"type":"InternalIP","address":"192.0.2.1"}],
                "conditions":[{"type":"Ready","status":"True" if self.node_ready else "False"}]}})
        raise AssertionError("Unexpected kubectl call: " + repr(args))

    def sleep(self, seconds): self.elapsed += seconds


class RestartTests(unittest.TestCase):
    def run_fake(self, fake, dry=False, role=None):
        args = argparse.Namespace(node="k3s-test", role=role or ("master" if fake.master else "worker"),
                                  expected_machine_id="a"*32, dry_run=dry)
        try:
            module.restart(args, fake, clock=lambda:fake.elapsed, sleep=fake.sleep,
                           now=lambda:datetime(2026,10,4,7,0,10,tzinfo=timezone.utc))
        finally:
            for forbidden in (" drain ", " cordon ", " uncordon ", " delete ", " patch ", "killall", "reboot"):
                self.assertFalse(any(forbidden in c for c in fake.calls), fake.calls)

    def test_master_uses_server_service_once(self):
        f=Fake(master=True); self.run_fake(f)
        self.assertEqual([c for c in f.calls if "--no-block restart" in c], ["sudo -n systemctl --no-block restart k3s"])

    def test_worker_uses_agent_service_once(self):
        f=Fake(); self.run_fake(f)
        self.assertEqual([c for c in f.calls if "--no-block restart" in c], ["sudo -n systemctl --no-block restart k3s-agent"])

    def test_dry_run_never_restarts(self):
        f=Fake(); self.run_fake(f,dry=True); self.assertFalse(f.restarted)

    def test_wrong_identity_never_restarts(self):
        f=Fake(); f.identity="b"*32
        with self.assertRaisesRegex(RuntimeError,"identity"): self.run_fake(f)
        self.assertFalse(f.restarted)

    def test_wrong_role_never_restarts(self):
        f=Fake()
        with self.assertRaisesRegex(RuntimeError,"role"): self.run_fake(f,role="master")
        self.assertFalse(f.restarted)

    def test_unsafe_kill_mode_never_restarts(self):
        f=Fake(); f.kill_mode="control-group"
        with self.assertRaisesRegex(RuntimeError,"stop behavior"):self.run_fake(f)
        self.assertFalse(f.restarted)

    def test_stop_hook_never_restarts(self):
        f=Fake(); f.stop_hook="/usr/local/bin/k3s-killall.sh"
        with self.assertRaisesRegex(RuntimeError,"stop behavior"):self.run_fake(f)
        self.assertFalse(f.restarted)

    def test_unready_node_never_restarts(self):
        f=Fake(); f.node_ready=False
        with self.assertRaisesRegex(RuntimeError,"not Ready"):self.run_fake(f)
        self.assertFalse(f.restarted)

    def test_unready_api_never_restarts(self):
        f=Fake(); f.api_ok=False
        with self.assertRaisesRegex(RuntimeError,"API"):self.run_fake(f)
        self.assertFalse(f.restarted)

    def test_stale_ready_with_no_new_process_times_out(self):
        f=Fake(); f.change_start=False
        with self.assertRaisesRegex(RuntimeError,"180 seconds"):self.run_fake(f)
        self.assertEqual(f.elapsed,180)

    def test_stale_lease_after_new_process_times_out(self):
        f=Fake(); f.change_lease=False
        with self.assertRaisesRegex(RuntimeError,"180 seconds"):self.run_fake(f)
        self.assertEqual(f.elapsed,180)

    def test_api_loss_does_not_repeat_restart(self):
        f=Fake(); f.recovery_error=True
        with self.assertRaisesRegex(RuntimeError,"180 seconds"):self.run_fake(f)
        self.assertEqual(sum("--no-block restart" in c for c in f.calls),1)

    def test_late_success_cannot_pass_recovery_deadline(self):
        f=Fake()
        original=f.kube
        def late(*args):
            value=original(*args)
            if f.restarted:f.elapsed=181
            return value
        f.kube=late
        with self.assertRaisesRegex(RuntimeError,"180 seconds"):self.run_fake(f)

    def test_shell_rejects_dry_run_without_explicit_mode(self):
        result=subprocess.run(["bash",str(Path(__file__).with_name("safe-k3s-restart.sh")),
                               "k3s-test","worker","--dry-run"],capture_output=True,text=True)
        self.assertEqual(result.returncode,2)
        self.assertIn("no changes made",result.stderr)


if __name__ == "__main__": unittest.main()
