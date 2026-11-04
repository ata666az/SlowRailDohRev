# Build the upstream DNSTT server and the HTTP DoH-to-local-UDP gateway.
FROM golang:1.25-bookworm AS build
RUN apt-get update && apt-get install -y --no-install-recommends git ca-certificates && rm -rf /var/lib/apt/lists/*
RUN git clone --depth 1 --branch v1.20260501.0 https://www.bamsoftware.com/git/dnstt.git /src/dnstt
WORKDIR /src/dnstt/dnstt-server
RUN go build -trimpath -ldflags="-s -w" -o /out/dnstt-server .
COPY doh_gateway.go /src/doh_gateway.go
RUN go build -trimpath -ldflags="-s -w" -o /out/doh-gateway /src/doh_gateway.go

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends openssh-server ca-certificates bash passwd && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /run/sshd /var/run/sshd
COPY --from=build /out/dnstt-server /usr/local/bin/dnstt-server
COPY --from=build /out/doh-gateway /usr/local/bin/doh-gateway
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod 755 /usr/local/bin/entrypoint.sh /usr/local/bin/doh-gateway /usr/local/bin/dnstt-server

# Public ingress is HTTPS only. DNSTT UDP is loopback-only behind the DoH gateway.
EXPOSE 5000
CMD ["/usr/local/bin/entrypoint.sh"]
