#!/usr/bin/env bash
set -Eeuo pipefail
VERSION="v1.20260501.0"

if command -v dnstt-server >/dev/null 2>&1; then
  dnstt-server -gen-key
  exit 0
fi

if command -v docker >/dev/null 2>&1; then
  IMAGE="slowdns-wokku-keygen:local"
  docker build -t "$IMAGE" .
  docker run --rm --entrypoint /usr/local/bin/dnstt-server "$IMAGE" -gen-key
  exit 0
fi

if command -v go >/dev/null 2>&1; then
  echo "Generating keys with upstream dnstt ${VERSION}..."
  GOTOOLCHAIN=auto go run "www.bamsoftware.com/git/dnstt.git/dnstt-server@${VERSION}" -gen-key
  exit 0
fi

cat >&2 <<'MSG'
Cannot find dnstt-server, Docker, or Go.
Install Docker, or install Go 1.24+ and Git, then rerun this script.
The output contains BOTH a private key and a public key.
Keep the private key secret; paste it only into DNSTT_PRIVATE_KEY near the top of entrypoint.sh; keep the repository private.
MSG
exit 1
