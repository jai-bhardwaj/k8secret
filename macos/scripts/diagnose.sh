#!/usr/bin/env bash
# Everything needed to place a K8Secret connection failure, in one paste.
#
# A cluster that connects on one Mac and not another is almost always something
# about the machine: its macOS, its openssl, a kubeconfig naming files that live
# somewhere else, or a TLS version the two ends negotiate differently.
#
#   ./macos/scripts/diagnose.sh                 # /Applications/K8Secret.app
#   ./macos/scripts/diagnose.sh /path/to/K8Secret.app
#
# Needs nothing installed beyond kubectl and the openssl macOS already ships.
# Prints versions, hostnames, validity dates and which files exist — never a
# key, a token, or a secret's contents. Hostnames are in it, so read it before
# pasting anywhere public.

set -uo pipefail

APP="${1:-/Applications/K8Secret.app}"
BIN="$APP/Contents/MacOS/k8secret"
LOG="$(mktemp)"
trap 'rm -f "$LOG"' EXIT

echo "K8Secret:  $(defaults read "$APP/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "not installed at $APP")"
echo "macOS:     $(sw_vers -productVersion) ($(sw_vers -buildVersion))"
echo "openssl:   $(/usr/bin/openssl version 2>&1)"
echo "kubectl:   $(kubectl version --client -o json 2>/dev/null | sed -n 's/.*"gitVersion": "\([^"]*\)".*/\1/p' | head -1 || echo 'not installed')"

echo
echo "--- active context (names and presence only) ---"
if command -v kubectl >/dev/null 2>&1; then
  # --minify without --raw: kubectl reports inline credentials as DATA+OMITTED
  # and leaves file paths as paths, which is exactly what is wanted here.
  kubectl config view --minify -o json 2>/dev/null \
    | grep -E '"(name|server|certificate-authority|certificate-authority-data|client-certificate|client-certificate-data|client-key|client-key-data|token|tokenFile|command|insecure-skip-tls-verify)"' \
    | sed 's/^ */  /'
  echo
  echo "  files named by this context:"
  kubectl config view --minify -o json 2>/dev/null \
    | sed -n 's/.*"\(certificate-authority\|client-certificate\|client-key\|tokenFile\)": "\([^"]*\)".*/\1 \2/p' \
    | while read -r KEY PATHNAME; do
        EXPANDED="${PATHNAME/#\~/$HOME}"
        if [ -r "$EXPANDED" ]; then echo "    $KEY: $PATHNAME  READABLE"
        else echo "    $KEY: $PATHNAME  *** MISSING OR UNREADABLE ***"; fi
      done
  EXEC_CMD="$(kubectl config view --minify -o jsonpath='{.users[0].user.exec.command}' 2>/dev/null)"
  if [ -n "$EXEC_CMD" ]; then
    echo "    exec plugin: $EXEC_CMD  $(command -v "$EXEC_CMD" >/dev/null 2>&1 && echo 'ON PATH' || echo '*** NOT ON PATH ***')"
  fi
else
  echo "  kubectl not installed — skipping"
fi

SERVER="$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}' 2>/dev/null)"
if [ -n "$SERVER" ]; then
  ENDPOINT="${SERVER#*://}"
  case "$ENDPOINT" in *:*) ;; *) ENDPOINT="$ENDPOINT:443" ;; esac
  HOST="${ENDPOINT%%:*}"
  echo
  echo "--- what the API server asks for, by TLS version ---"
  # Independent of the app. TLS 1.3 moved the client-certificate request to
  # after the handshake, and macOS does not do the post-handshake form — so a
  # server offering acceptable CA names at 1.2 and nothing at 1.3 can only be
  # authenticated to over 1.2.
  for VERSION in tls1_2 tls1_3; do
    OUT="$(echo | /usr/bin/openssl s_client -connect "$ENDPOINT" -servername "$HOST" -"$VERSION" 2>&1)"
    PROTO="$(printf '%s' "$OUT" | awk -F': *' '/^    Protocol/ {print $2; exit}')"
    if printf '%s' "$OUT" | grep -q "Acceptable client certificate CA names"; then ASKS=yes; else ASKS=no; fi
    echo "  ${VERSION}: protocol=${PROTO:-could-not-connect}  requests-client-certificate=${ASKS}"
  done
  echo "  (yes at 1.2 and no at 1.3 means this cluster needs K8Secret's TLS 1.2 cap)"
fi

echo
echo "--- the app's own handshake ---"
if [ ! -x "$BIN" ]; then
  echo "  no executable at $BIN"
  echo "  pass the app's path as the first argument, e.g. ./diagnose.sh ~/Downloads/K8Secret.app"
  exit 1
fi

K8SECRET_TLS_DEBUG=1 "$BIN" > "$LOG" 2>&1 &
PID=$!
sleep 3
if ! kill -0 "$PID" 2>/dev/null; then
  echo "  the app exited within 3 seconds. Everything it printed:"
  sed 's/^/    /' "$LOG" | head -20
  echo "  (a GUI app quitting immediately usually means macOS blocked it —"
  echo "   try opening K8Secret normally once, then run this again)"
  exit 1
fi
sleep 27
kill -9 "$PID" 2>/dev/null
wait "$PID" 2>/dev/null

MATCHED="$(grep -E "session:|probe:|metrics:|challenge:|serverTrust:|clientCert:|createIdentity:|buildPKCS12:|request FAILED|NSError|localizedDescription|underlying" "$LOG" | head -40)"
if [ -n "$MATCHED" ]; then
  printf '%s\n' "$MATCHED"
else
  echo "  no TLS trace lines. Everything the app printed:"
  sed 's/^/    /' "$LOG" | head -20
  echo "  (nothing at all here means tracing never started — check the version above is 0.6.7 or later)"
fi
echo
echo "trace lines captured: $(wc -l < "$LOG" | tr -d ' ')"
