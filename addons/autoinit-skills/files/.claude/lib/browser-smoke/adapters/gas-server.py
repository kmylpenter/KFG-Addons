#!/usr/bin/env python3
"""
gas-server.py — Local HTTP server with google.script.run shim for testing GAS HTML frontends.

This is a SHIM, NOT a real GAS deployment server. It serves project HTML files
locally and proxies google.script.run calls to a deployed GAS Web App URL.

Args:
  --port N        TCP port to bind (use 0 for auto-discover with retry)
  --gas-url URL   Deployed GAS Web App URL (proxy target)
  --serve-root D  Directory to serve files from (default: cwd)
  --pid-file P    Path to write PID (default: thoughts/shared/petla/.smoke-server.pid)
  --health        Show /health endpoint URL on startup

Empirically validated: ported from Terminator-Umowy local_dev_server.py
(2026-05-01 session). Universal version — no project-specific paths/caches.

Environment:
  Termux Android. NOT for production. NOT for deployment.
"""

import argparse
import http.server
import json
import os
import signal
import socket
import socketserver
import sys
import threading
import time
import urllib.request
from urllib.parse import urlparse, parse_qs

# ── google.script.run shim (injected into .html responses) ──────────
SHIM_JS = '''<script>
(function() {
  function createRunner(ok, fail) {
    return new Proxy({}, {
      get(_, prop) {
        if (prop === 'withSuccessHandler') return function(cb) { return createRunner(cb, fail); };
        if (prop === 'withFailureHandler') return function(cb) { return createRunner(ok, cb); };
        return function() {
          var args = Array.prototype.slice.call(arguments);
          fetch('/api/proxy', {
            method: 'POST',
            headers: {'Content-Type': 'application/json'},
            body: JSON.stringify({method: prop, args: args})
          })
          .then(function(r) { return r.json(); })
          .then(function(data) {
            if (data.success) { if (ok) ok(data.data); }
            else { if (fail) fail(data.error || 'Proxy error'); }
          })
          .catch(function(err) { if (fail) fail(err.message || String(err)); });
        };
      }
    });
  }
  window.google = { script: { run: createRunner(null, null) } };
  console.log('[LOCAL DEV] google.script.run shim active');
})();
</script>'''


def find_free_port_with_retry(max_attempts=3):
    """Allocate a free TCP port; retry if reclaimed mid-window (TOCTOU)."""
    for _ in range(max_attempts):
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.bind(('127.0.0.1', 0))
            port = s.getsockname()[1]
        # Verify still free
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as check:
                check.bind(('127.0.0.1', port))
            return port
        except OSError:
            continue
    raise RuntimeError(f'SETUP_ERROR: port discovery exhausted after {max_attempts} attempts')


def make_handler(serve_root, gas_url):
    """Create a request handler bound to a serve-root directory and GAS URL."""

    class GasShimHandler(http.server.BaseHTTPRequestHandler):

        def log_message(self, format, *args):
            sys.stderr.write(f'[gas-server] {format % args}\n')

        def serve_file(self, abs_path):
            if not os.path.isfile(abs_path):
                self.send_error(404)
                return
            try:
                with open(abs_path, 'rb') as f:
                    body = f.read()
            except Exception as e:
                self.send_error(500, f'read failed: {e}')
                return

            ctype = 'text/html; charset=utf-8' if abs_path.endswith('.html') else 'application/octet-stream'
            if abs_path.endswith('.html'):
                # Inject shim before </head> (or at top if no </head>)
                content = body.decode('utf-8', errors='replace')
                if '</head>' in content:
                    content = content.replace('</head>', SHIM_JS + '\n</head>', 1)
                else:
                    content = SHIM_JS + '\n' + content
                body = content.encode('utf-8')
            elif abs_path.endswith('.css'):
                ctype = 'text/css'
            elif abs_path.endswith('.js'):
                ctype = 'application/javascript'
            elif abs_path.endswith('.json'):
                ctype = 'application/json'

            self.send_response(200)
            self.send_header('Content-Type', ctype)
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            parsed = urlparse(self.path)
            if parsed.path == '/health':
                self.json_response({'status': 'ok', 'gas': gas_url})
                return
            # Path traversal guard
            requested = parsed.path.lstrip('/') or 'index.html'
            abs_path = os.path.realpath(os.path.join(serve_root, requested))
            if not abs_path.startswith(os.path.realpath(serve_root) + os.sep) and abs_path != os.path.realpath(serve_root):
                self.send_error(403, 'path traversal blocked')
                return
            self.serve_file(abs_path)

        def do_POST(self):
            if self.path != '/api/proxy':
                self.send_error(404)
                return
            try:
                length = int(self.headers.get('Content-Length', 0))
                body = self.rfile.read(length)
                req = json.loads(body)
                method = req.get('method')
                args = req.get('args', [])
            except Exception as e:
                self.json_response({'success': False, 'error': f'bad request: {e}'})
                return

            try:
                payload = json.dumps({'action': 'proxy_call', 'method': method, 'args': args}).encode('utf-8')
                gas_req = urllib.request.Request(gas_url, data=payload,
                                                 headers={'Content-Type': 'application/json'})
                with urllib.request.urlopen(gas_req, timeout=30) as resp:
                    gas_body = resp.read().decode('utf-8')
                # GAS sometimes returns HTML error page
                if gas_body.lstrip().startswith('<'):
                    self.json_response({'success': False, 'error': 'GAS returned HTML, not JSON'})
                    return
                self.json_response({'success': True, 'data': json.loads(gas_body)})
            except Exception as e:
                self.json_response({'success': False, 'error': f'{type(e).__name__}: {e}'})

        def json_response(self, obj):
            body = json.dumps(obj).encode('utf-8')
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)

    return GasShimHandler


class ReusableTCPServer(socketserver.TCPServer):
    allow_reuse_address = True


def main():
    ap = argparse.ArgumentParser(description='gas-server.py — google.script.run shim for testing')
    ap.add_argument('--port', type=int, default=0, help='TCP port (0 = auto-discover with retry)')
    ap.add_argument('--gas-url', required=True, help='Deployed GAS Web App URL')
    ap.add_argument('--serve-root', default=os.getcwd(), help='Directory to serve files from')
    ap.add_argument('--pid-file', default=None, help='Path for PID file')
    ap.add_argument('--health', action='store_true', help='Print /health URL on startup')
    args = ap.parse_args()

    # Resolve port
    port = args.port
    if port == 0:
        port = find_free_port_with_retry()
        print(f'[gas-server] auto-allocated port: {port}', file=sys.stderr)

    # Resolve serve-root
    serve_root = os.path.realpath(args.serve_root)
    if not os.path.isdir(serve_root):
        print(f'[gas-server] ERROR: serve-root not a directory: {serve_root}', file=sys.stderr)
        sys.exit(3)

    # Resolve PID file path
    pid_file = args.pid_file
    if pid_file is None:
        # Default: thoughts/shared/petla/ relative to cwd
        pid_dir = os.path.join(os.getcwd(), 'thoughts', 'shared', 'petla')
        os.makedirs(pid_dir, exist_ok=True)
        pid_file = os.path.join(pid_dir, '.smoke-server.pid')

    # Bind with retry on EADDRINUSE
    handler_cls = make_handler(serve_root, args.gas_url)
    server = None
    for attempt in range(3):
        try:
            server = ReusableTCPServer(('127.0.0.1', port), handler_cls)
            break
        except OSError as e:
            print(f'[gas-server] bind attempt {attempt + 1} failed: {e}', file=sys.stderr)
            if attempt < 2:
                time.sleep(0.2)
                continue
            print('[gas-server] ERROR: bind exhausted', file=sys.stderr)
            sys.exit(3)

    # Write PID file
    try:
        with open(pid_file, 'w') as f:
            f.write(str(os.getpid()))
    except Exception as e:
        print(f'[gas-server] WARN: PID file write failed: {e}', file=sys.stderr)

    # Trap SIGTERM/SIGINT for graceful shutdown
    shutdown_event = threading.Event()

    def shutdown_handler(signum, _frame):
        print(f'[gas-server] received signal {signum}, shutting down', file=sys.stderr)
        shutdown_event.set()
        threading.Thread(target=server.shutdown, daemon=True).start()

    signal.signal(signal.SIGTERM, shutdown_handler)
    signal.signal(signal.SIGINT, shutdown_handler)

    # Print startup
    print(f'[gas-server] listening on http://127.0.0.1:{port}', file=sys.stderr)
    print(f'[gas-server] serve-root: {serve_root}', file=sys.stderr)
    print(f'[gas-server] gas-url:   {args.gas_url}', file=sys.stderr)
    print(f'[gas-server] PID file:  {pid_file}', file=sys.stderr)
    if args.health:
        print(f'[gas-server] health:    http://127.0.0.1:{port}/health', file=sys.stderr)

    try:
        server.serve_forever()
    finally:
        # Cleanup: remove PID file
        try:
            os.unlink(pid_file)
        except OSError:
            pass
        print('[gas-server] stopped cleanly', file=sys.stderr)


if __name__ == '__main__':
    main()
