#!/usr/bin/env sh
# Kith Bridge — one-command setup to host your circle's always-on mailbox.
#
# A "bridge" is just an S3-compatible bucket your circle shares. Every post is stored
# SEALED (the bridge can't read it) and re-served to anyone who's offline, so messages
# arrive even when the sender and receiver are never online at the same time.
#
# This script self-hosts that bucket with MinIO (open-source, S3-compatible) — via
# Docker (any OS) or a native binary (Linux/macOS) — and prints the exact settings to
# paste into Kith. If you'd rather use a managed bucket (AWS S3 / Cloudflare R2 /
# Backblaze B2), you don't need this script at all — see README.md.
#
# Usage:   curl -fsSL https://wemiller.com/apps/kith/bridge/install.sh | sh
#   or:    sh install.sh [--native] [--port 9000] [--dir ~/kith-bridge]
set -eu

PORT=9000
CONSOLE_PORT=9001
DATADIR="${KITH_BRIDGE_DIR:-$HOME/kith-bridge}"
MODE=docker
BUCKET=kith

while [ $# -gt 0 ]; do
  case "$1" in
    --native) MODE=native ;;
    --port) PORT="$2"; shift ;;
    --dir) DATADIR="$2"; shift ;;
    *) echo "unknown option: $1"; exit 1 ;;
  esac
  shift
done

OS="$(uname -s 2>/dev/null || echo unknown)"
ARCH="$(uname -m 2>/dev/null || echo unknown)"
mkdir -p "$DATADIR"

# A stable, random-ish credential pair derived once and saved (so re-runs are stable).
CREDFILE="$DATADIR/.kith-bridge-creds"
if [ -f "$CREDFILE" ]; then
  . "$CREDFILE"
else
  AKEY="kith$(head -c 9 /dev/urandom | od -An -tx1 | tr -d ' \n')"
  SKEY="$(head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n')"
  printf 'AKEY=%s\nSKEY=%s\n' "$AKEY" "$SKEY" > "$CREDFILE"
  chmod 600 "$CREDFILE"
fi

echo "▸ Kith Bridge setup  (OS=$OS ARCH=$ARCH mode=$MODE)"
echo "▸ Data dir: $DATADIR"

start_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    echo "✗ Docker not found. Install Docker, or re-run with --native (Linux/macOS)."
    exit 1
  fi
  docker rm -f kith-bridge >/dev/null 2>&1 || true
  docker run -d --name kith-bridge --restart unless-stopped \
    -p "$PORT:9000" -p "$CONSOLE_PORT:9001" \
    -e "MINIO_ROOT_USER=$AKEY" -e "MINIO_ROOT_PASSWORD=$SKEY" \
    -v "$DATADIR/data:/data" \
    minio/minio server /data --console-address ":9001" >/dev/null
  echo "✓ MinIO running in Docker (container: kith-bridge, auto-restarts)."
}

start_native() {
  BIN="$DATADIR/minio"
  if [ ! -x "$BIN" ]; then
    case "$OS-$ARCH" in
      Linux-x86_64)  URL="https://dl.min.io/server/minio/release/linux-amd64/minio" ;;
      Linux-aarch64) URL="https://dl.min.io/server/minio/release/linux-arm64/minio" ;;
      Darwin-arm64)  URL="https://dl.min.io/server/minio/release/darwin-arm64/minio" ;;
      Darwin-x86_64) URL="https://dl.min.io/server/minio/release/darwin-amd64/minio" ;;
      *) echo "✗ No native MinIO for $OS-$ARCH. Use Docker (drop --native)."; exit 1 ;;
    esac
    echo "▸ Downloading MinIO for $OS-$ARCH…"
    curl -fsSL "$URL" -o "$BIN"
    chmod +x "$BIN"
  fi
  # Run in the background; install a service for always-on (best-effort).
  MINIO_ROOT_USER="$AKEY" MINIO_ROOT_PASSWORD="$SKEY" \
    nohup "$BIN" server "$DATADIR/data" --address ":$PORT" --console-address ":$CONSOLE_PORT" \
    >"$DATADIR/minio.log" 2>&1 &
  echo "✓ MinIO running natively (pid $!, log: $DATADIR/minio.log)."
  echo "  For always-on, see README.md (systemd / launchd snippets)."
}

[ "$MODE" = docker ] && start_docker || start_native

# Create the bucket via the S3 API (wait for MinIO to come up).
echo "▸ Creating bucket '$BUCKET'…"
i=0
while [ $i -lt 30 ]; do
  if curl -fsS "http://127.0.0.1:$PORT/minio/health/ready" >/dev/null 2>&1; then break; fi
  i=$((i+1)); sleep 1
done
# mc (MinIO client) via docker if available; else the bucket is auto-creatable on first PUT
if command -v docker >/dev/null 2>&1; then
  docker run --rm --network host minio/mc sh -c \
    "mc alias set b http://127.0.0.1:$PORT $AKEY $SKEY >/dev/null 2>&1 && mc mb -p b/$BUCKET >/dev/null 2>&1" || true
fi

# Figure out a reachable address (LAN ip) for other devices.
LANIP="$(ipconfig getifaddr en0 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}' || echo 127.0.0.1)"

cat <<EOF

═══════════════════════════════════════════════════════════════
✓ Your Kith bridge is live.

Paste these into Kith → You → Advanced → Storage → Custom S3 bucket,
then turn on "Volunteer as tribute":

   Endpoint:    $LANIP:$PORT
   Region:      us-east-1
   Bucket:      $BUCKET
   Access key:  $AKEY
   Secret key:  $SKEY

• Reachable on your network at  http://$LANIP:$PORT
• Admin console:                http://$LANIP:$CONSOLE_PORT
• For your circle to reach it from anywhere, expose the port (router
  port-forward, Tailscale, or a $5 VPS). Everything stored is sealed —
  the bridge never sees your messages.
═══════════════════════════════════════════════════════════════
EOF
