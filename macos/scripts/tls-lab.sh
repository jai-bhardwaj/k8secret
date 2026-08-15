#!/usr/bin/env bash
# Stand up a throwaway TLS "Kubernetes API server" and run the integration tests
# against it.
#
# The unit tests can't cover the thing that mattered most in this codebase:
# whether a bad server certificate is actually *refused*. That behaviour lives in
# URLSession's trust evaluation, so proving it needs a real handshake against a
# real server. This script generates two unrelated CAs, serves with a cert signed
# by one, and lets TLSIntegrationTests assert that the client accepts the matching
# CA and rejects the other.
#
# Usage:
#   ./macos/scripts/tls-lab.sh            # generate, serve, test, tear down
#   ./macos/scripts/tls-lab.sh --keep     # leave the server running afterwards

set -euo pipefail

KEEP=0
[[ "${1:-}" == "--keep" ]] && KEEP=1

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MACOS_DIR="$(dirname "$SCRIPT_DIR")"
LAB="$(mktemp -d /tmp/k8secret-tls-lab.XXXXX)"
PORT="${K8SECRET_TLS_PORT:-8443}"

cleanup() {
    [[ -n "${SERVER_PID:-}" ]] && kill "$SERVER_PID" 2>/dev/null || true
    [[ $KEEP -eq 0 ]] && rm -rf "$LAB"
    return 0
}
trap cleanup EXIT

echo "==> Generating certificates in $LAB"

# The CA the kubeconfig will trust, and a localhost cert signed by it.
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$LAB/ca.key" -out "$LAB/ca.crt" \
    -days 2 -subj "/CN=k8secret-test-ca" 2>/dev/null
openssl req -newkey rsa:2048 -nodes -keyout "$LAB/server.key" -out "$LAB/server.csr" \
    -subj "/CN=localhost" 2>/dev/null
printf "subjectAltName=DNS:localhost,IP:127.0.0.1\nextendedKeyUsage=serverAuth\n" > "$LAB/ext.cnf"
openssl x509 -req -in "$LAB/server.csr" -CA "$LAB/ca.crt" -CAkey "$LAB/ca.key" \
    -CAcreateserial -out "$LAB/server.crt" -days 2 -extfile "$LAB/ext.cnf" 2>/dev/null
cat "$LAB/server.crt" "$LAB/server.key" > "$LAB/server.pem"

# A second, unrelated CA — the MITM / misconfiguration case.
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$LAB/other.key" -out "$LAB/other.crt" \
    -days 2 -subj "/CN=unrelated-ca" 2>/dev/null

echo "    ✓ ca.crt, server.crt (localhost), other.crt"

cat > "$LAB/server.py" <<'PYEOF'
"""Minimal stand-in for a Kubernetes API server, over TLS."""
import json, ssl, sys
from http.server import BaseHTTPRequestHandler, HTTPServer

NS = {"items": [
    {"metadata": {"name": "default"},  "status": {"phase": "Active"}},
    {"metadata": {"name": "payments"}, "status": {"phase": "Active"}},
]}
SECRETS = {"items": [
    {"metadata": {"name": "app-config", "namespace": "payments",
                  "creationTimestamp": "2026-08-01T10:00:00Z"}, "type": "Opaque"},
]}
SECRET = {
    "metadata": {"name": "app-config", "namespace": "payments", "resourceVersion": "424242"},
    "data": {
        "DATABASE_URL": "cG9zdGdyZXM6Ly91c2VyOnBhc3NAZGIvcHJvZA==",
        "API_KEY": "c2stbGl2ZS1hYmMxMjM=",
    },
}

class H(BaseHTTPRequestHandler):
    def _send(self, obj, code=200):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        p = self.path.split("?")[0]
        if p == "/version":
            return self._send({"major": "1", "minor": "29"})
        if p == "/api/v1/namespaces":
            return self._send(NS)
        if p == "/api/v1/namespaces/payments/secrets":
            return self._send(SECRETS)
        if p == "/api/v1/namespaces/payments/secrets/app-config":
            return self._send(SECRET)
        return self._send({"kind": "Status", "code": 404}, 404)

    def do_PATCH(self):
        n = int(self.headers.get("Content-Length", 0))
        raw = self.rfile.read(n).decode()
        sys.stderr.write("PATCH %s ct=%s body=%s\n" %
                         (self.path, self.headers.get("Content-Type"), raw))
        sys.stderr.flush()
        return self._send(SECRET)

    def log_message(self, fmt, *a):
        sys.stderr.write("REQ " + (fmt % a) + "\n"); sys.stderr.flush()

ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
ctx.load_cert_chain(sys.argv[2])
srv = HTTPServer(("127.0.0.1", int(sys.argv[1])), H)
srv.socket = ctx.wrap_socket(srv.socket, server_side=True)
srv.serve_forever()
PYEOF

echo "==> Starting TLS server on 127.0.0.1:$PORT"
python3 "$LAB/server.py" "$PORT" "$LAB/server.pem" > "$LAB/server.log" 2>&1 &
SERVER_PID=$!

for _ in $(seq 1 30); do
    curl -fsS --cacert "$LAB/ca.crt" "https://localhost:$PORT/version" >/dev/null 2>&1 && break
    sleep 0.2
done
curl -fsS --cacert "$LAB/ca.crt" "https://localhost:$PORT/version" >/dev/null \
    || { echo "    ✗ server did not come up"; cat "$LAB/server.log"; exit 1; }
echo "    ✓ serving (pid $SERVER_PID)"

echo "==> Running integration tests"
cd "$MACOS_DIR"
K8SECRET_TLS_LAB="$LAB" K8SECRET_TLS_PORT="$PORT" \
    swift test --filter TLSIntegrationTests

echo ""
echo "==> Requests the client made"
grep -E "^REQ|^PATCH" "$LAB/server.log" | sed 's/^/    /'

if [[ $KEEP -eq 1 ]]; then
    echo ""
    echo "Lab kept at $LAB (server pid $SERVER_PID)"
    echo "  export KUBECONFIG=\$(mktemp) and point it at https://localhost:$PORT"
    trap - EXIT
fi
