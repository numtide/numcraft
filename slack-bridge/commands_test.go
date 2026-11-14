package main

import (
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/slack-go/slack/slackevents"
)

func TestSplitCommand(t *testing.T) {
	tests := []struct {
		text, name, rest string
		ok               bool
	}{
		{"!status", "status", "", true},
		{"!help me", "help", "me", true},
		{"!build  a tower of stone ", "build", "a tower of stone", true},
		// not a command: it stays chat
		{"!wow", "", "", false},
		{"!!!", "", "", false},
		{"status", "", "", false},
		{" !status", "", "", false},
	}
	for _, tt := range tests {
		name, rest, ok := splitCommand(tt.text)
		if name != tt.name || rest != tt.rest || ok != tt.ok {
			t.Errorf("%q: got %q %q %v", tt.text, name, rest, ok)
		}
	}
}

func TestTickLine(t *testing.T) {
	tests := []struct{ response, want string }{
		{"The game is running normallyTarget tick rate: 20.0 per second.\nAverage time per tick: 3.2ms (Target: 50.0ms)Percentiles: P50: 3.0ms P95: 4.1ms P99: 6.0ms, sample: 100", "Tick rate: 20.0 of 20.0 per second (3.2 ms for each tick)"},
		{"Target tick rate: 20.0 per second.\nAverage time per tick: 80.0ms (Target: 50.0ms)", "Tick rate: 12.5 of 20.0 per second (80.0 ms for each tick)"},
		{"Average time per tick: 10.0ms", "Tick rate: 20.0 of 20.0 per second (10.0 ms for each tick)"},
		{"Unknown or incomplete command, see below for error", ""},
		{"Average time per tick: 0.0ms", ""},
		{"", ""},
	}
	for _, tt := range tests {
		if got := tickLine(tt.response); got != tt.want {
			t.Errorf("%q: got %q, want %q", tt.response, got, tt.want)
		}
	}
}

func TestUptime(t *testing.T) {
	tests := []struct {
		d    time.Duration
		want string
	}{
		{-time.Minute, "0m"},
		{59 * time.Second, "0m"},
		{90 * time.Minute, "1h 30m"},
		{50 * time.Hour, "2d 2h"},
	}
	for _, tt := range tests {
		if got := uptime(tt.d); got != tt.want {
			t.Errorf("%v: got %q, want %q", tt.d, got, tt.want)
		}
	}
}

func serverLog(t *testing.T) string {
	path := filepath.Join(t.TempDir(), "latest.log")
	content := "[07Nov2026 17:57:40.100] [main/INFO] [cpw.mods.modlauncher.Launcher/MODLAUNCHER]: ModLauncher running\n" +
		"not a log line\n" +
		"[07Nov2026 17:58:04.000] [Server thread/INFO] [net.minecraft.server.dedicated.DedicatedServer/]: Starting minecraft server version 1.21.11\n" +
		"[07Nov2026 17:58:06.702] [Server thread/INFO] [net.minecraft.server.dedicated.DedicatedServer/]: Done (2.072s)! For help, type \"help\"\n"
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
	return path
}

func TestLogHead(t *testing.T) {
	version, started := logHead(serverLog(t))
	want := time.Date(2026, 11, 7, 17, 57, 40, 100e6, time.Local)
	if version != "1.21.11" || !started.Equal(want) {
		t.Errorf("got %q %v, want 1.21.11 %v", version, started, want)
	}
	if version, started := logHead(filepath.Join(t.TempDir(), "absent")); version != "" || !started.IsZero() {
		t.Errorf("an absent log gave %q %v", version, started)
	}
}

func TestStatus(t *testing.T) {
	clock(t, time.Date(2026, 11, 7, 20, 27, 40, 100e6, time.Local))
	answers := map[string]string{
		"list":       "There are 2 of a max of 50 players online: zoe, <adam>",
		"tick query": "The game is running normallyTarget tick rate: 20.0 per second.\nAverage time per tick: 3.2ms (Target: 50.0ms)",
	}
	bridge := &Bridge{
		logPath: serverLog(t),
		command: func(cmd string) (string, error) { return answers[cmd], nil },
	}
	want := "*Server status*\n" +
		"Players: 2 of 50 (zoe, &lt;adam&gt;)\n" +
		"Version: 1.21.11\n" +
		"Tick rate: 20.0 of 20.0 per second (3.2 ms for each tick)\n" +
		"Uptime: 2h 30m"
	if got := bridge.status(); got != want {
		t.Errorf("got %q, want %q", got, want)
	}

	// a server that knows no tick command, and a log that is gone
	answers["tick query"] = "Unknown or incomplete command"
	bridge.logPath = "/absent"
	answers["list"] = "There are 0 of a max of 50 players online:"
	if got, want := bridge.status(), "*Server status*\nPlayers: 0 of 50"; got != want {
		t.Errorf("got %q, want %q", got, want)
	}

	bridge.command = func(string) (string, error) { return "", errors.New("connection refused") }
	if got := bridge.status(); got != "*Server status*\nThe server does not answer." {
		t.Errorf("got %q", got)
	}
}

func TestHandleCommand(t *testing.T) {
	advance := clock(t, time.Date(2026, 11, 7, 9, 0, 0, 0, time.UTC))
	logged := journal(t)
	api, calls := fakeSlack(t)
	var relayed []string
	bridge := &Bridge{
		slack:     api,
		channelID: "C1",
		presence:  Presence{TS: "111.1"},
		users:     map[string]string{"U1": "zoe"},
		relay: func(name, text string) error {
			relayed = append(relayed, text)
			return nil
		},
		command: func(string) (string, error) { return "There are 0 of a max of 50 players online:", nil },
		logPath: "/absent",
	}
	message := func(user, channel, ts, thread, text string) *slackevents.MessageEvent {
		return &slackevents.MessageEvent{User: user, Channel: channel, TimeStamp: ts, ThreadTimeStamp: thread, Text: text}
	}
	send := func(ev *slackevents.MessageEvent) {
		t.Helper()
		if err := bridge.HandleSlack(ev); err != nil {
			t.Fatal(err)
		}
	}

	// a command at the top of the channel gets its answer in a new thread
	send(message("U1", "C1", "200.1", "", "!help"))
	// too soon: dropped, with no answer
	send(message("U1", "C1", "200.2", "", "!status"))
	// another user has their own limit, and needs no mapping for the status
	send(message("U2", "C1", "200.3", "", "!status"))
	advance(commandInterval)
	// in the thread of the day the answer stays there, and nothing goes to the game
	send(message("U1", "C1", "200.4", "111.1", "!build a stone tower\nwith a \"roof\""))
	advance(commandInterval)
	// only a player can ask for a build
	send(message("U2", "C1", "200.5", "", "!build a moat"))
	advance(commandInterval)
	send(message("U1", "C1", "200.6", "", "!build"))
	advance(commandInterval)
	send(message("U1", "C1", "200.7", "", "!build "+strings.Repeat("x", buildTextLimit+1)))
	advance(commandInterval)
	// not the bridged channel, a bot, an edit
	send(message("U1", "C2", "200.8", "", "!status"))
	send(&slackevents.MessageEvent{BotID: "B1", Channel: "C1", TimeStamp: "200.9", Text: "!status"})
	send(&slackevents.MessageEvent{User: "U1", Channel: "C1", TimeStamp: "201.0", Text: "!status", SubType: "message_changed"})
	// not a command: chat in the thread of the day
	send(message("U1", "C1", "201.1", "111.1", "!wow"))

	want := []struct{ thread, text string }{
		{"200.1", helpText},
		{"200.3", "*Server status*\nPlayers: 0 of 50"},
		{"111.1", "Request recorded."},
		{"200.5", "Only a player of the server can ask for a build."},
		{"200.6", "Say what to build: `!build <text>`"},
		{"200.7", "The request is too long. The limit is 500 characters."},
	}
	if len(*calls) != len(want) {
		t.Fatalf("got %d calls, want %d: %v", len(*calls), len(want), *calls)
	}
	for i, w := range want {
		form := (*calls)[i]
		if form.Get("method") != "/chat.postMessage" || form.Get("channel") != "C1" || form.Get("thread_ts") != w.thread || form.Get("text") != w.text {
			t.Errorf("call %d: got %v, want %+v", i, form, w)
		}
	}
	if len(relayed) != 1 || relayed[0] != "!wow" {
		t.Errorf("relayed to the game: %v", relayed)
	}

	requests := 0
	for _, line := range strings.Split(logged.String(), "\n") {
		if strings.Contains(line, buildRequestPrefix) {
			requests++
			// one request is one line, whatever the text holds
			if !strings.HasSuffix(line, `build-request: user=U1 player=zoe ts=200.4 text="a stone tower\nwith a \"roof\""`) {
				t.Errorf("request line: %q", line)
			}
		}
	}
	if requests != 1 {
		t.Errorf("got %d request lines, want 1:\n%s", requests, logged.String())
	}
	if !strings.Contains(logged.String(), "command: status from U1 dropped") {
		t.Errorf("the dropped command is not in the journal:\n%s", logged.String())
	}
}
