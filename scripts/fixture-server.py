#!/usr/bin/env python3
"""Serves fixtures/ on 127.0.0.1:4599 plus HTTP Basic and Digest auth challenge routes."""
import base64
import hashlib
import http.server
import os
import secrets
import sys

PORT = 4599
USER = "alice@example.com"
PASSWORD = "correct-horse-battery-staple"
REALM = "evo-fixtures"
FIXTURES = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "fixtures")
NONCE = secrets.token_hex(16)

BODY_OK = b"<html><body><h1 id='status'>authorized</h1></body></html>"


def md5(text: str) -> str:
    return hashlib.md5(text.encode()).hexdigest()


class FixtureHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=FIXTURES, **kwargs)

    def do_GET(self):
        if self.path == "/basic-auth":
            return self.handle_basic()
        if self.path == "/digest-auth":
            return self.handle_digest()
        return super().do_GET()

    def handle_basic(self):
        header = self.headers.get("Authorization", "")
        expected = "Basic " + base64.b64encode(f"{USER}:{PASSWORD}".encode()).decode()
        if header == expected:
            return self.respond_ok()
        self.send_response(401)
        self.send_header("WWW-Authenticate", f'Basic realm="{REALM}"')
        self.end_headers()

    def handle_digest(self):
        header = self.headers.get("Authorization", "")
        if header.startswith("Digest ") and self.digest_valid(header):
            return self.respond_ok()
        self.send_response(401)
        self.send_header(
            "WWW-Authenticate",
            f'Digest realm="{REALM}", nonce="{NONCE}", qop="auth", algorithm=MD5',
        )
        self.end_headers()

    def digest_valid(self, header: str) -> bool:
        fields = {}
        for part in header[len("Digest "):].split(","):
            if "=" not in part:
                continue
            key, _, value = part.strip().partition("=")
            fields[key] = value.strip('"')
        ha1 = md5(f"{USER}:{REALM}:{PASSWORD}")
        ha2 = md5(f"GET:{fields.get('uri', '')}")
        if fields.get("qop") == "auth":
            expected = md5(
                f"{ha1}:{fields.get('nonce', '')}:{fields.get('nc', '')}:"
                f"{fields.get('cnonce', '')}:auth:{ha2}"
            )
        else:
            expected = md5(f"{ha1}:{fields.get('nonce', '')}:{ha2}")
        return fields.get("response") == expected

    def respond_ok(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/html")
        self.send_header("Content-Length", str(len(BODY_OK)))
        self.end_headers()
        self.wfile.write(BODY_OK)

    def log_message(self, fmt, *args):
        print(f"[fixture-server] {fmt % args}", file=sys.stderr)


if __name__ == "__main__":
    with http.server.ThreadingHTTPServer(("127.0.0.1", PORT), FixtureHandler) as server:
        print(f"[fixture-server] http://127.0.0.1:{PORT}/ serving {FIXTURES}", file=sys.stderr)
        server.serve_forever()
