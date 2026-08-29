package mcp

import (
	"context"
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/mark3labs/mcp-go/client"
	"github.com/mark3labs/mcp-go/client/transport"
	"github.com/mark3labs/mcp-go/mcp"
	"github.com/maximhq/bifrost/core/network"
)

// TestBuildHTTPClientBlocksPrivateIP verifies the transport built by
// buildHTTPClient routes dials through the MCP09 gate: a private IP is
// rejected before any packet is sent unless the client opted in.
func TestBuildHTTPClientBlocksPrivateIP(t *testing.T) {
	mgr := &MCPManager{logger: defaultLogger}

	c, err := mgr.buildHTTPClient(nil, false)
	if err != nil {
		t.Fatalf("buildHTTPClient: %v", err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, "http://10.255.255.1:9999/mcp", nil)
	if err != nil {
		t.Fatal(err)
	}
	start := time.Now()
	_, err = c.Do(req)
	if err == nil || !strings.Contains(err.Error(), "private IP") {
		t.Fatalf("expected private-IP gate error, got %v", err)
	}
	if time.Since(start) > 2*time.Second {
		t.Fatalf("gate should reject before dialing; took %v", time.Since(start))
	}

	// Opt-in client must attempt the dial (and fail on the network, not the gate).
	c2, err := mgr.buildHTTPClient(nil, true)
	if err != nil {
		t.Fatalf("buildHTTPClient opt-in: %v", err)
	}
	ctx2, cancel2 := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel2()
	req2, _ := http.NewRequestWithContext(ctx2, http.MethodPost, "http://10.255.255.1:9999/mcp", nil)
	_, err = c2.Do(req2)
	if err != nil && strings.Contains(err.Error(), "private IP") {
		t.Fatalf("opt-in client must not be gated, got %v", err)
	}
}

// TestStreamableHTTPConnectBlocksPrivateIP exercises the exact live connect
// path (StreamableHTTP transport + Start + Initialize) against a private IP.
func TestStreamableHTTPConnectBlocksPrivateIP(t *testing.T) {
	mgr := &MCPManager{logger: defaultLogger}
	httpClient, err := mgr.buildHTTPClient(nil, false)
	if err != nil {
		t.Fatal(err)
	}
	tr, err := transport.NewStreamableHTTP("http://10.255.255.1:9999/mcp",
		transport.WithHTTPBasicClient(httpClient))
	if err != nil {
		t.Fatal(err)
	}
	c := client.NewClient(tr)
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	_ = c.Start(ctx)
	initReq := mcp.InitializeRequest{}
	initReq.Params.ProtocolVersion = mcp.LATEST_PROTOCOL_VERSION
	initReq.Params.ClientInfo = mcp.Implementation{Name: "probe", Version: "1.0"}
	start := time.Now()
	_, err = c.Initialize(ctx, initReq)
	if err == nil || !strings.Contains(err.Error(), "private IP") {
		t.Fatalf("expected private-IP gate error, got %v", err)
	}
	if time.Since(start) > 5*time.Second {
		t.Fatalf("gate should reject before dialing; took %v", time.Since(start))
	}
}

// TestBlockedDialErrorIsNotTransient locks in the retry classification:
// policy-blocked dials must fail fast, not burn the connect retry budget.
func TestBlockedDialErrorIsNotTransient(t *testing.T) {
	blocked := network.CheckMCPDialIP([]byte{10, 0, 0, 5}, false)
	if blocked == nil {
		t.Fatal("expected CheckMCPDialIP to block 10.0.0.5")
	}
	if isTransientError(blocked) {
		t.Fatal("BlockedDialError must be classified permanent, not transient")
	}
	if isTransientError(wrapForTest(blocked)) {
		t.Fatal("wrapped BlockedDialError must still be classified permanent")
	}
}

func wrapForTest(err error) error {
	return &wrappedTestError{err}
}

type wrappedTestError struct{ inner error }

func (e *wrappedTestError) Error() string { return "transport error: " + e.inner.Error() }
func (e *wrappedTestError) Unwrap() error { return e.inner }
