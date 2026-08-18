#!/usr/bin/env bash
# Everything needed to place a K8Secret connection failure, in one paste.
#
# A cluster that connects on one Mac and not another is almost always something
# about the machine: its macOS, its openssl, a kubeconfig naming files that live
# somewhere else, or a TLS version the two ends negotiate differently. This
# gathers all of those, plus a live trace of the app's own handshake, so a bug
# report arrives with the answer already in it.
#
#   ./macos/scripts/diagnose.sh
#
# Prints versions, hostnames, byte counts, validity dates and which files exist.
# It never reads a key, a token, or a secret's contents — but read the output
# before pasting it somewhere public, as hostnames are in it.

set -uo pipefail

APP="${1:-/Applications/K8Secret.app}"
BIN="$APP/Contents/MacOS/k8secret"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG="$(mktemp)"
ENDPOINT_FILE="$(mktemp)"
trap 'rm -f "$LOG" "$ENDPOINT_FILE"' EXIT

echo "K8Secret:  $(defaults read "$APP/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo 'not installed at '"$APP")"
echo "macOS:     $(sw_vers -productVersion) ($(sw_vers -buildVersion))"
echo "openssl:   $(/usr/bin/openssl version 2>&1)"
echo "kubectl:   $(kubectl version --client -o json 2>/dev/null | python3 -c 'import json,sys;print(json.load(sys.stdin)["clientVersion"]["gitVersion"])' 2>/dev/null || echo 'not installed')"

echo
echo "--- active context (names and presence only) ---"
K8SECRET_ENDPOINT_OUT="$ENDPOINT_FILE" python3 "$SCRIPT_DIR/kubeconfig-shape.py"

ENDPOINT="$(cat "$ENDPOINT_FILE" 2>/dev/null || true)"
if [ -n "$ENDPOINT" ]; then
  echo
  echo "--- what the API server asks for, by TLS version ---"
  # Independent of the app: ask the endpoint directly whether it requests a
  # client certificate, and at which version. TLS 1.3 moved that request to
  # after the handshake and macOS does not do the post-handshake form, so a
  # server that offers acceptable CA names at 1.2 and nothing at 1.3 can only
  # be authenticated to over 1.2.
  HOST="${ENDPOINT%%:*}"
  for VERSION in tls1_2 tls1_3; do
    OUT="$(echo | /usr/bin/openssl s_client -connect "$ENDPOINT" -servername "$HOST" -"$VERSION" 2>&1)"
    PROTO="$(printf '%s' "$OUT" | awk -F': *' '/^    Protocol/ {print $2; exit}')"
    if printf '%s' "$OUT" | grep -q "Acceptable client certificate CA names"; then
      ASKS="yes"
    else
      ASKS="no"
    fi
    echo "  ${VERSION}: protocol=${PROTO:-could-not-connect}  requests-client-certificate=${ASKS}"
  done
  echo "  (yes at 1.2 and no at 1.3 means this cluster needs K8Secret's TLS 1.2 cap)"
fi

echo
echo "--- the app's own handshake ---"
if [ ! -x "$BIN" ]; then
  echo "  no executable at $BIN — pass the .app path as the first argument"
  exit 1
fi
K8SECRET_TLS_DEBUG=1 "$BIN" > "$LOG" 2>&1 &
PID=$!
sleep 30
kill -9 "$PID" 2>/dev/null
grep -E "session:|probe:|metrics:|challenge:|serverTrust:|clientCert:|createIdentity:|buildPKCS12:|request FAILED|NSError|localizedDescription|underlying" "$LOG" | head -40

LINES="$(wc -l < "$LOG" | tr -d ' ')"
echo
echo "trace lines captured: $LINES"
if [ "$LINES" = "0" ]; then
  echo "No trace at all means the app never reached a TLS challenge — either it"
  echo "did not launch, or this build predates tracing (0.6.7)."
fi
