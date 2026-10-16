package main

import (
	"bytes"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/hex"
	"encoding/json"
	"io"
	"log"
	"math/big"
	"net"
	"net/http"
	"net/url"
	"os"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"time"
)

// The request journal records every Management Interface request the mock WFM
// answered: who sent it, what was sent, and what was answered. The test runner
// reads it (GET /api/v1/test/requests) to judge what a real device did — a
// real device only ever calls out, so observing its requests is the only
// evidence there is.

const (
	journalMaxEntries   = 5000
	journalMaxBodyBytes = 64 * 1024
	miPathPrefix        = "/v1alpha2/margo"
)

// JournalEntry is one answered request.
type JournalEntry struct {
	Seq    int          `json:"seq"`
	Time   string       `json:"time"`
	Client string       `json:"client"` // caller's SPIFFE ID; "" when it presented no usable SVID
	Remote string       `json:"remote"` // caller's IP address
	Cert   *JournalCert `json:"cert,omitempty"`
	// ServerIdentity is "untrusted" when this connection was served with the
	// test certificate the MIS did not issue — a device must never get this far.
	ServerIdentity string `json:"server_identity"`
	// Expectations: the verdict of each assertions.json device_expectations rule
	// for this request — "pass", or what is wrong.
	Expectations map[string]string `json:"expectations,omitempty"`
	Method       string            `json:"method"`
	Path         string            `json:"path"` // without the /v1alpha2/margo prefix
	Status       int               `json:"status"`
	Headers      map[string]string `json:"headers"`
	Body         interface{}       `json:"body,omitempty"`     // request body (JSON when it parses)
	Response     interface{}       `json:"response,omitempty"` // response body when it is JSON (manifest, problem details)
}

// JournalCert describes the client certificate a request was sent with.
type JournalCert struct {
	SHA256   string `json:"sha256"`
	URISANs  int    `json:"uri_sans"`
	IsCA     bool   `json:"is_ca"`
	NotAfter string `json:"not_after"`
}

var (
	journalMu      sync.Mutex
	journalEntries []JournalEntry
	journalSeq     int
)

// journalWriter keeps the status and the first bytes of the response body.
type journalWriter struct {
	http.ResponseWriter
	status int
	body   bytes.Buffer
}

func (w *journalWriter) WriteHeader(code int) {
	w.status = code
	w.ResponseWriter.WriteHeader(code)
}

func (w *journalWriter) Write(b []byte) (int, error) {
	if room := journalMaxBodyBytes - w.body.Len(); room > 0 {
		if len(b) < room {
			room = len(b)
		}
		w.body.Write(b[:room])
	}
	return w.ResponseWriter.Write(b)
}

func jsonOrNil(b []byte) interface{} {
	var v interface{}
	if len(b) == 0 || json.Unmarshal(b, &v) != nil {
		return nil
	}
	return v
}

// journaled wraps a handler so its request and answer are recorded. The
// test-control routes are not recorded: they are the harness, not the device.
func journaled(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		path := strings.TrimPrefix(r.URL.Path, miPathPrefix)
		if !strings.HasPrefix(path, "/api/v1/") || strings.HasPrefix(path, "/api/v1/test/") {
			next.ServeHTTP(w, r)
			return
		}
		var reqBody []byte
		if r.Body != nil {
			reqBody, _ = io.ReadAll(io.LimitReader(r.Body, journalMaxBodyBytes))
			r.Body = io.NopCloser(io.MultiReader(bytes.NewReader(reqBody), r.Body))
		}
		rec := &journalWriter{ResponseWriter: w, status: 200}
		next.ServeHTTP(rec, r)

		client, _ := spiffeIDFromRequest(r)
		remote, _, _ := net.SplitHostPort(r.RemoteAddr)
		serverIdentity := "svid"
		if _, bad := untrustedConns.Load(r.RemoteAddr); bad {
			serverIdentity = "untrusted"
		}
		var cert *JournalCert
		if r.TLS != nil && len(r.TLS.PeerCertificates) > 0 {
			leaf := r.TLS.PeerCertificates[0]
			sum := sha256.Sum256(leaf.Raw)
			cert = &JournalCert{SHA256: hex.EncodeToString(sum[:]), URISANs: len(leaf.URIs), IsCA: leaf.IsCA, NotAfter: leaf.NotAfter.UTC().Format(time.RFC3339)}
		}
		var expectations map[string]string
		if obj, ok := jsonOrNil(reqBody).(map[string]interface{}); ok {
			switch {
			case r.Method == "PUT" && strings.HasPrefix(path, "/api/v1/capabilities/"):
				expectations = evaluateExpectations("PUT_capabilities", obj)
			case r.Method == "POST" && strings.HasSuffix(path, "/status"):
				expectations = evaluateExpectations("POST_status", obj)
			}
		}
		entry := JournalEntry{
			Expectations:   expectations,
			Time:           time.Now().UTC().Format(time.RFC3339),
			Client:         client,
			Remote:         remote,
			Cert:           cert,
			ServerIdentity: serverIdentity,
			Method:         r.Method,
			Path:           path,
			Status:         rec.status,
			Headers: map[string]string{
				"Accept":        r.Header.Get("Accept"),
				"If-None-Match": r.Header.Get("If-None-Match"),
				"Content-Type":  r.Header.Get("Content-Type"),
			},
			Body:     jsonOrNil(reqBody),
			Response: jsonOrNil(rec.body.Bytes()),
		}
		appendJournal(entry)
	})
}

func appendJournal(entry JournalEntry) {
	journalMu.Lock()
	journalSeq++
	entry.Seq = journalSeq
	journalEntries = append(journalEntries, entry)
	if len(journalEntries) > journalMaxEntries {
		journalEntries = journalEntries[len(journalEntries)-journalMaxEntries:]
	}
	journalMu.Unlock()
}

// ── A TLS handshake that fails never becomes a request. It is recorded as an
// entry of its own (method "TLS", path "/handshake-error"), so the runner can
// tell "the device refused the connection" from "the device did not try". ──

var handshakeErrorLine = regexp.MustCompile(`TLS handshake error from ([^:]+|\[[^\]]+\]):\d+: (.*)`)

type handshakeErrorRecorder struct{}

func (handshakeErrorRecorder) Write(p []byte) (int, error) {
	os.Stderr.Write(p)
	if m := handshakeErrorLine.FindSubmatch(p); m != nil {
		identity := "svid"
		if untrustedIdentityActive() {
			identity = "untrusted"
		}
		appendJournal(JournalEntry{
			Time: time.Now().UTC().Format(time.RFC3339), Remote: strings.Trim(string(m[1]), "[]"),
			Method: "TLS", Path: "/handshake-error", ServerIdentity: identity,
			Headers: map[string]string{}, Body: strings.TrimSpace(string(m[2])),
		})
	}
	return len(p), nil
}

// ── Untrusted WFM identity window ──

var (
	untrustedMu    sync.Mutex
	untrustedUntil time.Time
	untrustedCert  *tls.Certificate
	untrustedConns sync.Map // remote "ip:port" of connections served with the untrusted certificate
)

func untrustedIdentityActive() bool {
	untrustedMu.Lock()
	defer untrustedMu.Unlock()
	return time.Now().Before(untrustedUntil)
}

// untrustedServerCertificate is self-signed and carries the WFM's own SPIFFE
// ID: everything about it is right except that the MIS did not issue it.
func untrustedServerCertificate(spiffeID string) (tls.Certificate, error) {
	untrustedMu.Lock()
	defer untrustedMu.Unlock()
	if untrustedCert != nil {
		return *untrustedCert, nil
	}
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		return tls.Certificate{}, err
	}
	id, err := url.Parse(spiffeID)
	if err != nil {
		return tls.Certificate{}, err
	}
	tmpl := &x509.Certificate{
		SerialNumber: big.NewInt(time.Now().UnixNano()), Subject: pkix.Name{CommonName: "ctt-untrusted-wfm"},
		NotBefore: time.Now().Add(-time.Minute), NotAfter: time.Now().Add(24 * time.Hour),
		KeyUsage: x509.KeyUsageDigitalSignature, ExtKeyUsage: []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
		BasicConstraintsValid: true, URIs: []*url.URL{id},
	}
	der, err := x509.CreateCertificate(rand.Reader, tmpl, tmpl, &key.PublicKey, key)
	if err != nil {
		return tls.Certificate{}, err
	}
	untrustedCert = &tls.Certificate{Certificate: [][]byte{der}, PrivateKey: key}
	return *untrustedCert, nil
}

// PUT /v1alpha2/margo/api/v1/test/server-identity {"untrustedSeconds": N} —
// for the next N seconds new connections get the untrusted certificate.
func handleTestServerIdentity(w http.ResponseWriter, r *http.Request) {
	var body struct {
		UntrustedSeconds int `json:"untrustedSeconds"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil || body.UntrustedSeconds < 0 || body.UntrustedSeconds > 600 {
		respondMalformedBody(w, r, `expected {"untrustedSeconds": 0..600}`)
		return
	}
	untrustedMu.Lock()
	untrustedUntil = time.Now().Add(time.Duration(body.UntrustedSeconds) * time.Second)
	until := untrustedUntil
	untrustedMu.Unlock()
	log.Printf("[MIAF/TestControl] untrusted WFM certificate presented for %ds (until %s)", body.UntrustedSeconds, until.Format(time.RFC3339))
	respondJSON(w, 200, map[string]interface{}{"untrustedSeconds": body.UntrustedSeconds, "untrustedUntil": until.UTC().Format(time.RFC3339)})
}

// GET /v1alpha2/margo/api/v1/test/requests?since=<seq> — entries after <seq>.
func handleTestRequests(w http.ResponseWriter, r *http.Request) {
	since, _ := strconv.Atoi(r.URL.Query().Get("since"))
	journalMu.Lock()
	out := make([]JournalEntry, 0)
	for _, e := range journalEntries {
		if e.Seq > since {
			out = append(out, e)
		}
	}
	last := journalSeq
	journalMu.Unlock()
	respondJSON(w, 200, map[string]interface{}{"requests": out, "last": last})
}
