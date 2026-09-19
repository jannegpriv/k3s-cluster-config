"""Small MCP acceptance client; secrets come from Keychain or an environment variable.

Import Client for checks, or run this file to verify authenticated tool discovery.
CONNECT_IP is an optional rollout-only DNS override; TLS still verifies memory.k3s.nu.
"""
import base64
import http.client
import json
import os
import socket
import ssl
import subprocess
import sys
import time

HOST = "memory.k3s.nu"


class Connection(http.client.HTTPSConnection):
    def connect(self):
        address = os.environ.get("CONNECT_IP", self.host)
        self.sock = socket.create_connection((address, self.port), self.timeout)
        self.sock = self._context.wrap_socket(self.sock, server_hostname=self.host)


def authorization(account):
    password = os.environ.get("BASIC_MEMORY_PASSWORD")
    if password is None:
        password = subprocess.run(["/usr/bin/security", "find-generic-password", "-s",
                                   "basic-memory.k3s.nu", "-a", account, "-w"],
                                  check=True, capture_output=True, text=True).stdout.rstrip("\n")
    return "Basic " + base64.b64encode(f"{account}:{password}".encode()).decode()


class Client:
    def __init__(self, account, header=None):
        self.account = account
        self.headers = {"Authorization": header or authorization(account),
                        "Content-Type": "application/json",
                        "Accept": "application/json, text/event-stream"}
        self.sequence = 0
        self.context = ssl.create_default_context()
        self.initialize = self.request("initialize", {
            "protocolVersion": "2025-03-26", "capabilities": {},
            "clientInfo": {"name": f"basic-memory-{account}-acceptance", "version": "1"}})
        self.headers["MCP-Protocol-Version"] = self.initialize["protocolVersion"]
        self.request("notifications/initialized", notification=True)

    def request(self, method, params=None, notification=False):
        self.sequence += 1
        payload = {"jsonrpc": "2.0", "method": method}
        if not notification:
            payload["id"] = self.sequence
        if params is not None:
            payload["params"] = params
        connection = Connection(HOST, timeout=60, context=self.context)
        try:
            started = time.monotonic()
            connection.request("POST", "/mcp", json.dumps(payload).encode(), self.headers)
            response = connection.getresponse()
            session = response.getheader("Mcp-Session-Id")
            if session:
                self.headers["Mcp-Session-Id"] = session
            body = response.read().decode()
            self.last_seconds = time.monotonic() - started
            if response.status not in (200, 202):
                raise RuntimeError(f"MCP HTTP {response.status}: {body[:500]}")
            if notification:
                return None
            if response.getheader("Content-Type", "").startswith("text/event-stream"):
                messages = [json.loads(line[5:].strip()) for line in body.splitlines()
                            if line.startswith("data:")]
                result = next(item for item in messages if item.get("id") == self.sequence)
            else:
                result = json.loads(body)
            if "error" in result:
                raise RuntimeError(result["error"])
            return result["result"]
        finally:
            connection.close()

    def call(self, name, **arguments):
        result = self.request("tools/call", {"name": name, "arguments": arguments})
        if result.get("isError"):
            raise RuntimeError(result)
        return result


if __name__ == "__main__":
    client = Client(sys.argv[1] if len(sys.argv) > 1 else "agent")
    result = client.request("tools/list")
    print(json.dumps({"server": client.initialize.get("serverInfo"),
                      "tools": [tool["name"] for tool in result["tools"]]}, ensure_ascii=False))
