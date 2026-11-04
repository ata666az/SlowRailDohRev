# SSH DNSTT over Custom DoH Gateway — Railway

This package runs three local services in one Railway container:

1. Upstream `dnstt-server`, bound only to `127.0.0.1:5300/udp`.
2. OpenSSH, bound only to `127.0.0.1:2222/tcp`.
3. A small RFC 8484 HTTP DoH gateway exposed through Railway HTTPS at `/dns-query`.

The gateway accepts DNS wire-format messages over HTTPS and forwards them to the local DNSTT UDP socket. **No public UDP ingress, public SSH port, VPS, or public authoritative NS delegation is required.** The client must use a DNSTT-compatible client and point its `-doh` option directly at this Railway gateway (not at Cloudflare/Google public DNS).

## Important distinction

This is a custom, direct DoH transport endpoint for DNSTT. It is not a general recursive DNS resolver. The gateway only forwards questions whose names are inside `DNS_ZONE` and returns the DNSTT server's DNS response. Do not configure a public DNS resolver as the `-doh` endpoint for this architecture.

## Deploy to Railway

1. Push this folder to a GitHub repository or deploy it using Railway's supported repository workflow.
2. Create a Railway service from the repository. Railway detects the Dockerfile.
3. In **Settings → Networking → Public Networking**, generate a Railway domain. Railway routes HTTPS requests to the app's `PORT`.
4. Edit the three configuration values in `entrypoint.sh`, commit, push, and redeploy.

### Configure the three values inside the script

Open `entrypoint.sh` and edit only the three lines near the top:

```bash
DNS_ZONE="ata.jijah.loc.cc"
DNSTT_PRIVATE_KEY="PASTE_YOUR_64_HEX_PRIVATE_KEY_HERE"
SSH_PASSWORD="SET_A_STRONG_SSH_PASSWORD_HERE"
```

- `DNS_ZONE`: the tunnel domain suffix. The current value is prefilled from the earlier deployment log; change it if you use another zone.
- `DNSTT_PRIVATE_KEY`: the 64-character hexadecimal **private** key from `dnstt-server -gen-key`.
- `SSH_PASSWORD`: the password for SSH user `ata`. Use 12–128 characters, restricted to letters, numbers, and `_ . - @ ! # % + =` so the value can be safely written inside the shell script.

Everything else is set in the script: SSH user `ata`, SSH port `2222`, internal DNSTT UDP address `127.0.0.1:5300`, and MTU `1232`. Railway supplies `PORT` automatically for the HTTPS gateway, so you do not need to add it manually.

**Security:** because these secrets are written directly into `entrypoint.sh`, keep the Git repository private and do not share the edited ZIP or repository. Do not paste the private key or password into public logs, issues, or chat. If the repository has already been public after adding real secrets, rotate the DNSTT keypair and SSH password.

No custom Railway Variables are required for these three settings. Railway's automatically supplied `PORT` is still used by the HTTPS gateway. After editing the file, commit and push it, then redeploy the Railway service.

## Generate the DNSTT keypair

Run locally on Termux, Ubuntu, or another machine with Docker or Go:

```bash
chmod +x generate-keys.sh
./generate-keys.sh
```

Copy the 64-character `privkey` value into `DNSTT_PRIVATE_KEY` at the top of `entrypoint.sh`. Save `pubkey` as `server.pub` on the Android/client device. Never publish the private key. Because it is stored in the script, keep the repository private.

## Verify the Railway deployment

After deployment, the logs should contain messages similar to:

```text
[doh] HTTP/DoH listening on :<PORT>; UDP backend=127.0.0.1:5300; zone=ata.jijah.loc.cc
[Railway SlowDNS DoH] zone=ata.jijah.loc.cc doh=/dns-query udp_backend=127.0.0.1:5300 mtu=1232 ssh=127.0.0.1:2222 user=ata
Server listening on 127.0.0.1 port 2222.
```

Open these URLs in a browser:

- `https://YOUR-RAILWAY-DOMAIN/` — should show `slowdns Railway DoH gateway: running`.
- `https://YOUR-RAILWAY-DOMAIN/healthz` — should show `ok`.

A browser GET to `/dns-query` is not a valid tunnel test; it needs a DNS wire-format query. A successful health check proves only that the HTTP gateway is running, not that DNSTT handshakes or SSH authentication work.

## Connect from Android / a compatible DNSTT client

Use a build of the upstream `dnstt-client` that supports `-doh`. Put `server.pub` on the client device and run:

```bash
dnstt-client -doh https://YOUR-RAILWAY-DOMAIN/dns-query \
  -pubkey-file server.pub ata.jijah.loc.cc 127.0.0.1:7000
```

Then connect your SSH app to the local listener:

```text
Host: 127.0.0.1
Port: 7000
Username: ata
Password: the SSH_PASSWORD value
```

Replace `YOUR-RAILWAY-DOMAIN` with the generated `*.up.railway.app` domain (or a custom domain with Railway HTTPS configured). Keep `DNS_ZONE` identical between server and client.

The command-line example is for a compatible DNSTT client. A generic Android app branded “SlowDNS” will not necessarily support this custom DoH endpoint. The client must send RFC 8484 `application/dns-message` requests to the exact configured URL.

## Security and limitations

- SSH and DNSTT UDP remain loopback-only; only HTTPS is publicly exposed.
- The gateway validates that DNS question names are within `DNS_ZONE`, but it is not an authentication layer. Anyone who knows the endpoint, zone, and DNSTT public key may attempt a tunnel; SSH password authentication remains the access control.
- Use a strong SSH password, protect the private key, monitor Railway usage, and follow Railway's acceptable-use policy. DNS tunnelling can generate significant request volume and cost.
- This provides a TCP tunnel to SSH, not a full-device VPN/TUN automatically.
- Railway edge HTTP request limits/timeouts apply. High-throughput or long-running tunnels may be constrained by platform behavior; test real client sessions before relying on it.
- The gateway currently accepts standard DoH POST and GET. It does not act as a recursive resolver and does not support arbitrary DNS lookups.
