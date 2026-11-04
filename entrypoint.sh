#!/usr/bin/env bash
set -Eeuo pipefail

# =====================================================================
# USER CONFIGURATION — EDIT ONLY THESE THREE VALUES.
# Keep this repository private: the DNSTT private key and SSH password
# are stored in this file when you fill them in.
# =====================================================================
DNS_ZONE="ata.jijah.loc.cc"
DNSTT_PRIVATE_KEY="40b0793a81b985b1cec6dc52d19399f6d8079e72f7a1fde95b0b2fb469932a38"
SSH_PASSWORD="ata"
# =====================================================================

# Internal settings are fixed for the Railway deployment.
SSH_USER="ata"
SSH_PORT="2222"
DNS_LISTEN_ADDR="127.0.0.1:5300"
DNS_MTU="1232"
DOH_UDP_ADDR="127.0.0.1:5300"

# The DoH gateway reads the tunnel zone from its process environment.
export DNS_ZONE

if [[ ! "$DNS_ZONE" =~ ^[A-Za-z0-9.-]+$ ]]; then
  echo "[fatal] DNS_ZONE is not a valid DNS name" >&2
  exit 1
fi
if [[ ! "$SSH_USER" =~ ^[a-z_][a-z0-9_-]*$ || "$SSH_USER" == "root" ]]; then
  echo "[fatal] SSH_USER must be a non-root Linux username" >&2
  exit 1
fi
if [[ ! "$SSH_PORT" =~ ^[0-9]+$ ]] || (( SSH_PORT < 1024 || SSH_PORT > 65535 )); then
  echo "[fatal] SSH_PORT must be between 1024 and 65535" >&2
  exit 1
fi
if [[ ! "$DNSTT_PRIVATE_KEY" =~ ^[A-Fa-f0-9]{64}$ ]]; then
  echo "[fatal] DNSTT_PRIVATE_KEY must be exactly 64 hexadecimal characters" >&2
  exit 1
fi
if [[ ! "$SSH_PASSWORD" =~ ^[-A-Za-z0-9._@!#%+=]{12,128}$ ]]; then
  echo "[fatal] SSH_PASSWORD must be 12-128 chars using only letters, numbers, or _ . - @ ! # % + =" >&2
  exit 1
fi

if ! id "$SSH_USER" >/dev/null 2>&1; then
  useradd --create-home --shell /bin/bash "$SSH_USER"
fi
printf '%s:%s\n' "$SSH_USER" "$SSH_PASSWORD" | chpasswd

mkdir -p /run/sshd
ssh-keygen -A
cat > /etc/ssh/sshd_config <<SSHEOF
Port ${SSH_PORT}
AddressFamily inet
ListenAddress 127.0.0.1
HostKey /etc/ssh/ssh_host_ed25519_key
HostKey /etc/ssh/ssh_host_rsa_key
PermitRootLogin no
PasswordAuthentication yes
KbdInteractiveAuthentication no
PubkeyAuthentication yes
UsePAM no
AllowTcpForwarding yes
X11Forwarding no
PermitTunnel no
GatewayPorts no
PermitTTY yes
PrintMotd no
Subsystem sftp internal-sftp
AllowUsers ${SSH_USER}
SSHEOF

/usr/sbin/sshd -t

DOH_UDP_ADDR="$DOH_UDP_ADDR" /usr/local/bin/doh-gateway &
DOH_PID=$!
/usr/sbin/sshd -D -e &
SSHD_PID=$!
/usr/local/bin/dnstt-server \
  -mtu "$DNS_MTU" \
  -udp "$DNS_LISTEN_ADDR" \
  -privkey "$DNSTT_PRIVATE_KEY" \
  "$DNS_ZONE" "127.0.0.1:${SSH_PORT}" &
DNS_PID=$!

cleanup() {
  kill "$DNS_PID" "$SSHD_PID" "$DOH_PID" 2>/dev/null || true
  wait "$DNS_PID" "$SSHD_PID" "$DOH_PID" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

echo "[Railway SlowDNS DoH] zone=${DNS_ZONE} doh=/dns-query udp_backend=${DNS_LISTEN_ADDR} mtu=${DNS_MTU} ssh=127.0.0.1:${SSH_PORT} user=${SSH_USER}"
# Keep the container alive; if any essential service exits, terminate the app.
set +e
wait -n "$DNS_PID" "$SSHD_PID" "$DOH_PID"
STATUS=$?
set -e
cleanup
trap - EXIT INT TERM
exit "$STATUS"
