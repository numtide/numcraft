package main

import (
	"bytes"
	"errors"
	"log"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/slack-go/slack"
	"github.com/slack-go/slack/socketmode"
)

// journal collects what the bridge logs.
func journal(t *testing.T) *bytes.Buffer {
	var buf bytes.Buffer
	log.SetOutput(&buf)
	t.Cleanup(func() { log.SetOutput(os.Stderr) })
	return &buf
}

func TestState(t *testing.T) {
	logged := journal(t)
	var state State
	state.Set("rcon", "unreachable dial tcp 127.0.0.1:25575: connect: connection refused")
	state.Set("rcon", "unreachable dial tcp 127.0.0.1:25575: connect: connection refused")
	state.Set("slack", "connecting")
	state.Set("rcon", "connected to 127.0.0.1:25575")
	state.Set("slack", "connected")
	state.Set("slack", "connected")
	state.Set("log", "following /logs/latest.log")

	var lines []string
	for _, line := range strings.Split(strings.TrimSpace(logged.String()), "\n") {
		// drop the date and the time
		lines = append(lines, strings.SplitN(line, " ", 3)[2])
	}
	want := []string{
		"rcon: unreachable dial tcp 127.0.0.1:25575: connect: connection refused",
		"slack: connecting",
		"rcon: connected to 127.0.0.1:25575",
		"slack: connected",
		"log: following /logs/latest.log",
	}
	if strings.Join(lines, "|") != strings.Join(want, "|") {
		t.Errorf("got %q, want %q", lines, want)
	}
	if !state.Is("slack", "conn") || state.Is("slack", "failed") || state.Is("absent", "x") {
		t.Error("Is does not match the state")
	}
	if got := state.Health(); got != "log=following rcon=connected slack=connected" {
		t.Errorf("health: got %q", got)
	}
}

func TestSocketState(t *testing.T) {
	ticket := errors.New(`dial wss://wss.example/link/?ticket=SECRET&app_id=A1: i/o timeout`)
	tests := []struct {
		evt  socketmode.Event
		want string
	}{
		{socketmode.Event{Type: socketmode.EventTypeConnecting}, "connecting"},
		{socketmode.Event{Type: socketmode.EventTypeConnected}, "connected"},
		{socketmode.Event{Type: socketmode.EventTypeHello}, "connected"},
		{socketmode.Event{Type: socketmode.EventTypeInvalidAuth}, "refused: Slack does not accept the tokens"},
		{socketmode.Event{Type: socketmode.EventTypeConnectionError, Data: &slack.ConnectionErrorEvent{ErrorObj: ticket}}, "failed dial wss://wss.example/link/?[removed] i/o timeout"},
		{socketmode.Event{Type: socketmode.EventTypeIncomingError, Data: &slack.IncomingEventError{ErrorObj: errors.New("EOF")}}, "dropped EOF"},
		{socketmode.Event{Type: socketmode.EventTypeEventsAPI}, ""},
	}
	for _, tt := range tests {
		got := socketState(tt.evt)
		if got != tt.want {
			t.Errorf("%s: got %q, want %q", tt.evt.Type, got, tt.want)
		}
		if strings.Contains(got, "SECRET") {
			t.Errorf("%s: the ticket is in the state: %q", tt.evt.Type, got)
		}
	}
}

func TestTailLogReport(t *testing.T) {
	path := filepath.Join(t.TempDir(), "latest.log")
	states := make(chan string, 100)
	go tailLog(path, 10*time.Millisecond, func(LogEvent) {}, func(state string) { states <- state })
	expect := func(prefix string) {
		t.Helper()
		deadline := time.After(5 * time.Second)
		for {
			select {
			case state := <-states:
				if strings.HasPrefix(state, prefix) {
					return
				}
			case <-deadline:
				t.Fatalf("no state %q", prefix)
			}
		}
	}
	expect("unreadable ")
	if err := os.WriteFile(path, nil, 0o644); err != nil {
		t.Fatal(err)
	}
	expect("following " + path)
}
