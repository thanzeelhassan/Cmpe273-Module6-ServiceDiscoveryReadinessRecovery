"""Inventory service: tiny HTTP API that reports which Pod answered.

Endpoints
  GET /items   -> JSON list of items plus the name of the Pod that served it
  GET /ready   -> 200 normally, 503 if the file /tmp/not-ready exists
  GET /health  -> always 200 (liveness)

To make a Pod fail readiness (without killing it):
  kubectl exec <pod> -- touch /tmp/not-ready
To restore it:
  kubectl exec <pod> -- rm /tmp/not-ready
"""
import json
import os
import socket
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

POD_NAME = os.environ.get("POD_NAME", socket.gethostname())
NOT_READY_FLAG = "/tmp/not-ready"

ITEMS = [
    {"id": 1, "name": "widget", "qty": 120},
    {"id": 2, "name": "gadget", "qty": 45},
    {"id": 3, "name": "doohickey", "qty": 8},
]


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, body):
        data = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path == "/items":
            self._send(200, {"pod": POD_NAME, "items": ITEMS})
        elif self.path == "/ready":
            if os.path.exists(NOT_READY_FLAG):
                self._send(503, {"pod": POD_NAME, "ready": False})
            else:
                self._send(200, {"pod": POD_NAME, "ready": True})
        elif self.path == "/health":
            self._send(200, {"pod": POD_NAME, "status": "alive"})
        else:
            self._send(404, {"error": "not found"})

    def log_message(self, fmt, *args):
        print(f"[{POD_NAME}] {self.address_string()} {fmt % args}", flush=True)


if __name__ == "__main__":
    port = int(os.environ.get("PORT", "8080"))
    print(f"[{POD_NAME}] inventory listening on :{port}", flush=True)
    ThreadingHTTPServer(("0.0.0.0", port), Handler).serve_forever()
