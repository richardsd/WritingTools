"""
Codex OAuth Callback Server
----------------------------

A lightweight HTTP server that listens on localhost:1455/auth/callback
to capture the OAuth authorization code from the browser redirect.
Runs in a background thread with a configurable timeout.
"""

import logging
import threading
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs

from codex_auth import REDIRECT_PORT, CALLBACK_TIMEOUT_SECONDS

_SUCCESS_HTML = """\
<!DOCTYPE html>
<html>
<head>
    <title>Authorization Successful</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
            display: flex; justify-content: center; align-items: center;
            height: 100vh; margin: 0;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
        }
        .container {
            background: white; padding: 3rem; border-radius: 1rem;
            box-shadow: 0 10px 40px rgba(0,0,0,0.2); text-align: center;
        }
        h1 { color: #333; margin-bottom: 1rem; }
        p { color: #666; }
    </style>
</head>
<body>
    <div class="container">
        <h1>&#x2713; Authorization Successful</h1>
        <p>You can close this window and return to Writing Tools.</p>
    </div>
    <script>setTimeout(() => window.close(), 2000)</script>
</body>
</html>
"""


class _CallbackHandler(BaseHTTPRequestHandler):
    """HTTP request handler for the OAuth callback."""

    def log_message(self, format, *args):
        # Suppress default stderr logging from BaseHTTPRequestHandler
        logging.debug(f"Callback server: {format % args}")

    def do_GET(self):
        parsed = urlparse(self.path)
        if parsed.path != "/auth/callback":
            self.send_response(404)
            self.end_headers()
            self.wfile.write(b"Not found")
            return

        params = parse_qs(parsed.query)

        # Check for error
        if "error" in params:
            error_desc = params.get("error_description", params["error"])[0]
            logging.error(f"OAuth error: {error_desc}")
            self.send_response(400)
            self.end_headers()
            self.wfile.write(b"Authorization failed")
            self.server.callback_error = error_desc
            self.server.callback_event.set()
            return

        # Validate state
        received_state = params.get("state", [None])[0]
        if not received_state or received_state != self.server.expected_state:
            logging.error("OAuth state mismatch")
            self.send_response(400)
            self.end_headers()
            self.wfile.write(b"Invalid state parameter")
            self.server.callback_error = "State validation failed"
            self.server.callback_event.set()
            return

        # Get code
        code = params.get("code", [None])[0]
        if not code:
            logging.error("Missing authorization code")
            self.send_response(400)
            self.end_headers()
            self.wfile.write(b"Missing authorization code")
            self.server.callback_error = "Missing authorization code"
            self.server.callback_event.set()
            return

        # Success — send HTML response and store the code
        self.send_response(200)
        self.send_header("Content-Type", "text/html")
        self.end_headers()
        self.wfile.write(_SUCCESS_HTML.encode("utf-8"))

        self.server.callback_code = code
        self.server.callback_event.set()


class CodexCallbackServer:
    """
    Manages a temporary HTTP server on port 1455 that waits for the OAuth callback.

    Usage:
        server = CodexCallbackServer()
        code = server.wait_for_code(expected_state, timeout=300)
        # code is the authorization code, or None on error/timeout
    """

    def __init__(self):
        self._httpd: HTTPServer | None = None
        self._thread: threading.Thread | None = None

    def wait_for_code(self, expected_state: str, timeout: float = CALLBACK_TIMEOUT_SECONDS) -> str:
        """
        Start the callback server, wait for the browser redirect, return the auth code.
        Raises RuntimeError on timeout, cancellation, or OAuth error.
        """
        event = threading.Event()

        httpd = HTTPServer(("127.0.0.1", REDIRECT_PORT), _CallbackHandler)
        httpd.expected_state = expected_state
        httpd.callback_code = None
        httpd.callback_error = None
        httpd.callback_event = event
        httpd.timeout = 1  # poll interval for handle_request

        self._httpd = httpd

        def serve():
            while not event.is_set():
                httpd.handle_request()

        self._thread = threading.Thread(target=serve, daemon=True)
        self._thread.start()

        logging.debug(f"Callback server listening on port {REDIRECT_PORT}")

        # Wait for the callback (or timeout)
        event.wait(timeout=timeout)

        # Shut down
        self.stop()

        if httpd.callback_error:
            raise RuntimeError(f"OAuth error: {httpd.callback_error}")
        if httpd.callback_code:
            return httpd.callback_code
        raise RuntimeError("OAuth callback timed out")

    def stop(self):
        """Shut down the callback server."""
        if self._httpd:
            try:
                self._httpd.server_close()
            except Exception:
                pass
            self._httpd = None
        self._thread = None
