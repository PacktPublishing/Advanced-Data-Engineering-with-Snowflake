"""Mock marketing API that receives the high-risk segment push.

This stands in for the external marketing tool. It accepts ``POST /segments``
with a JSON array of merchant records, honors the ``Idempotency-Key`` header so
the chapter's retry-safety claim is observable rather than asserted, logs each
push so ``docker compose logs marketing-api`` shows it, and returns 200. A
``GET /health`` endpoint lets Docker Compose report the container healthy.

It uses only the standard library so the container needs no dependencies. The
idempotency store is an in-memory dict, which is enough to demonstrate the
contract and is deliberately not what a deployed endpoint would use: there is
no auth, no TLS, and no persistence, which the manuscript calls out as the gap
between this mock and a real endpoint.
"""

from __future__ import annotations

import json
import logging
import os
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(message)s")
logger = logging.getLogger("marketing-api")

MAX_BODY_BYTES = 8 * 1024 * 1024


class Handler(BaseHTTPRequestHandler):
    # Shared across threads: ThreadingHTTPServer builds one handler instance
    # per request, so the store and its lock belong to the class.
    _seen: dict[str, int] = {}
    _seen_lock = threading.Lock()

    def _send(self, status: int, payload: dict[str, object]) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:  # noqa: N802 (stdlib naming)
        if self.path == "/health":
            self._send(200, {"status": "ok"})
        else:
            self._send(404, {"error": "not found"})

    def do_POST(self) -> None:  # noqa: N802 (stdlib naming)
        if self.path != "/segments":
            self._send(404, {"error": "not found"})
            return

        length = int(self.headers.get("Content-Length", "0") or "0")
        if length <= 0 or length > MAX_BODY_BYTES:
            self._send(400, {"error": "missing or oversized body"})
            return

        try:
            segment = json.loads(self.rfile.read(length))
        except json.JSONDecodeError:
            self._send(400, {"error": "invalid JSON"})
            return

        if not isinstance(segment, list):
            self._send(400, {"error": "expected a JSON array"})
            return

        idempotency_key = self.headers.get("Idempotency-Key")

        # A replayed partition presents the key it presented the first time, so
        # the second push is acknowledged without being applied twice. This is
        # what makes the reverse-ETL step safe to retry.
        if idempotency_key:
            with self._seen_lock:
                previous = self._seen.get(idempotency_key)
            if previous is not None:
                logger.info(
                    "duplicate segment ignored: rows=%d idempotency_key=%s",
                    len(segment),
                    idempotency_key,
                )
                self._send(200, {"received": previous, "duplicate": True})
                return

        logger.info(
            "received segment: rows=%d idempotency_key=%s",
            len(segment),
            idempotency_key or "-",
        )

        if idempotency_key:
            with self._seen_lock:
                self._seen[idempotency_key] = len(segment)

        self._send(200, {"received": len(segment), "duplicate": False})

    def log_message(self, *_args: object) -> None:
        """Silence the default per-request stderr line; we log explicitly."""


def main() -> None:
    port = int(os.environ.get("PORT", "8080"))
    server = ThreadingHTTPServer(("0.0.0.0", port), Handler)
    logger.info("marketing-api listening on :%d", port)
    server.serve_forever()


if __name__ == "__main__":
    main()
