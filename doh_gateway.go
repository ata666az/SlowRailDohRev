package main

import (
	"encoding/base64"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"strings"
	"time"
)

const maxDNSMessage = 4096

func main() {
	port := os.Getenv("PORT")
	if port == "" { port = "5000" }
	udpAddr := os.Getenv("DOH_UDP_ADDR")
	if udpAddr == "" { udpAddr = "127.0.0.1:5300" }
	zone := strings.TrimSuffix(strings.ToLower(os.Getenv("DNS_ZONE")), ".")
	if zone == "" { log.Fatal("DNS_ZONE is required") }

	mux := http.NewServeMux()
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet { http.Error(w, "slowdns railway doh gateway", http.StatusMethodNotAllowed); return }
		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
		_, _ = fmt.Fprintln(w, "slowdns Railway DoH gateway: running")
	})
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
		w.WriteHeader(http.StatusOK)
		_, _ = io.WriteString(w, "ok\n")
	})
	mux.HandleFunc("/dns-query", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost && r.Method != http.MethodGet {
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed); return
		}
		var query []byte
		var err error
		if r.Method == http.MethodPost {
			ct := strings.ToLower(strings.TrimSpace(strings.Split(r.Header.Get("Content-Type"), ";")[0]))
			if ct != "application/dns-message" { http.Error(w, "Content-Type must be application/dns-message", http.StatusUnsupportedMediaType); return }
			query, err = io.ReadAll(http.MaxBytesReader(w, r.Body, maxDNSMessage))
		} else {
			s := r.URL.Query().Get("dns")
			if s == "" { http.Error(w, "missing dns query parameter", http.StatusBadRequest); return }
			query, err = base64.RawURLEncoding.DecodeString(s)
		}
		if err != nil || len(query) < 17 || len(query) > maxDNSMessage {
			http.Error(w, "invalid DNS message", http.StatusBadRequest); return
		}
		if !questionWithinZone(query, zone) {
			http.Error(w, "DNS question is outside configured tunnel zone", http.StatusForbidden); return
		}

		conn, err := net.DialTimeout("udp", udpAddr, 2*time.Second)
		if err != nil { http.Error(w, "DNS backend unavailable", http.StatusBadGateway); return }
		defer conn.Close()
		_ = conn.SetDeadline(time.Now().Add(10 * time.Second))
		if _, err = conn.Write(query); err != nil { http.Error(w, "DNS backend write failed", http.StatusBadGateway); return }
		response := make([]byte, 65535)
		n, err := conn.Read(response)
		if err != nil { http.Error(w, "DNS backend timeout", http.StatusGatewayTimeout); return }
		if n < 12 { http.Error(w, "invalid DNS backend response", http.StatusBadGateway); return }
		w.Header().Set("Content-Type", "application/dns-message")
		w.Header().Set("Cache-Control", "no-store")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write(response[:n])
	})

	addr := ":" + port
	log.Printf("[doh] HTTP/DoH listening on %s; UDP backend=%s; zone=%s", addr, udpAddr, zone)
	log.Fatal(http.ListenAndServe(addr, mux))
}

// Accept only DNS questions whose QNAME is the configured tunnel zone or a
// subdomain of it. DNSTT client queries are encoded below that zone.
func questionWithinZone(msg []byte, zone string) bool {
	if len(msg) < 17 { return false }
	qd := int(msg[4])<<8 | int(msg[5])
	if qd < 1 || qd > 8 { return false }
	labels := strings.Split(strings.TrimSuffix(strings.ToLower(zone), "."), ".")
	if len(labels) == 0 { return false }
	pos := 12
	for q := 0; q < qd; q++ {
		var name []string
		for {
			if pos >= len(msg) { return false }
			l := int(msg[pos]); pos++
			if l == 0 { break }
			if l&0xC0 != 0 || l > 63 || pos+l > len(msg) { return false }
			name = append(name, strings.ToLower(string(msg[pos:pos+l])))
			pos += l
			if len(name) > 127 { return false }
		}
		if len(name) < len(labels) { return false }
		for i := 1; i <= len(labels); i++ {
			if name[len(name)-i] != labels[len(labels)-i] { return false }
		}
		if pos+4 > len(msg) { return false }
		pos += 4 // QTYPE and QCLASS
	}
	return true
}
