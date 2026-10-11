package main

import (
	"bytes"
	"encoding/json"
	"io"
	"net/http"
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
	Seq      int               `json:"seq"`
	Time     string            `json:"time"`
	Client   string            `json:"client"` // caller's SPIFFE ID; "" when it presented no usable SVID
	Method   string            `json:"method"`
	Path     string            `json:"path"` // without the /v1alpha2/margo prefix
	Status   int               `json:"status"`
	Headers  map[string]string `json:"headers"`
	Body     interface{}       `json:"body,omitempty"`     // request body (JSON when it parses)
	Response interface{}       `json:"response,omitempty"` // response body when it is JSON (manifest, problem details)
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
		entry := JournalEntry{
			Time:   time.Now().UTC().Format(time.RFC3339),
			Client: client,
			Method: r.Method,
			Path:   path,
			Status: rec.status,
			Headers: map[string]string{
				"Accept":        r.Header.Get("Accept"),
				"If-None-Match": r.Header.Get("If-None-Match"),
				"Content-Type":  r.Header.Get("Content-Type"),
			},
			Body:     jsonOrNil(reqBody),
			Response: jsonOrNil(rec.body.Bytes()),
		}
		journalMu.Lock()
		journalSeq++
		entry.Seq = journalSeq
		journalEntries = append(journalEntries, entry)
		if len(journalEntries) > journalMaxEntries {
			journalEntries = journalEntries[len(journalEntries)-journalMaxEntries:]
		}
		journalMu.Unlock()
	})
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
