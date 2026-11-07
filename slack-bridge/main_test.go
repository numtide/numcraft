package main

import (
	"fmt"
	"net"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"sync"
	"testing"
	"time"

	"github.com/slack-go/slack"
	"github.com/slack-go/slack/slackevents"
)

// clock freezes time, and lets a test travel to another day.
func clock(t *testing.T, start time.Time) func(time.Duration) {
	t.Cleanup(func() { now = time.Now })
	at := start
	now = func() time.Time { return at }
	return func(d time.Duration) { at = at.Add(d) }
}

func TestPlayersText(t *testing.T) {
	tests := []struct {
		players []Player
		want    string
	}{
		{nil, "*everybody left*"},
		{[]Player{{Name: "zoe"}, {Name: "adam"}}, "Players: zoe, adam"},
		{[]Player{{Name: "zoe", Left: true}, {Name: "adam"}}, "Players: ~zoe~, adam"},
		// the log parser only passes \w+ names, but the escaping must hold anyway
		{[]Player{{Name: "<!channel> & ~x~", Left: true}}, "Players: ~&lt;!channel&gt; &amp; ˜x˜~"},
	}
	for _, tt := range tests {
		if got := playersText(tt.players); got != tt.want {
			t.Errorf("got %q, want %q", got, tt.want)
		}
	}
}

func TestJoinLeave(t *testing.T) {
	clock(t, time.Date(2026, 11, 7, 9, 0, 0, 0, time.UTC))
	var p Presence
	if !p.join("zoe") || p.join("zoe") || !p.join("adam") {
		t.Fatal("join did not report the changes")
	}
	if !p.leave("zoe") || p.leave("zoe") || p.leave("nobody") {
		t.Fatal("leave did not report the changes")
	}
	if got := playersText(p.Players); got != "Players: ~zoe~, adam" {
		t.Errorf("got %q", got)
	}
	// a rejoin keeps the first-join order
	if !p.join("zoe") {
		t.Fatal("rejoin not reported")
	}
	if got := playersText(p.Players); got != "Players: zoe, adam" {
		t.Errorf("after rejoin: got %q", got)
	}
	if !p.leaveAll() || p.leaveAll() || p.present() {
		t.Fatal("leaveAll did not report the changes")
	}
}

func TestOneMessagePerDay(t *testing.T) {
	advance := clock(t, time.Date(2026, 11, 7, 9, 0, 0, 0, time.UTC))
	p := Presence{Players: []Player{{Name: "zoe", Left: true}}, TS: "111.1", Day: today()}

	// the next session of the day reuses the message
	p.join("adam")
	if p.TS != "111.1" || len(p.Players) != 2 {
		t.Errorf("same day: got %+v, want the message kept", p)
	}

	// the next day starts a new message
	p.leaveAll()
	advance(24 * time.Hour)
	p.join("adam")
	if p.TS != "" || len(p.Players) != 1 {
		t.Errorf("next day: got %+v, want a new message", p)
	}
}

func TestSessionOverMidnight(t *testing.T) {
	advance := clock(t, time.Date(2026, 11, 7, 23, 50, 0, 0, time.UTC))
	p := Presence{Players: []Player{{Name: "zoe"}}, TS: "111.1", Day: today()}
	advance(20 * time.Minute)
	p.join("adam")
	if p.TS != "111.1" || len(p.Players) != 2 {
		t.Errorf("got %+v, want the message of the session kept", p)
	}
}

func TestParseLine(t *testing.T) {
	tests := []struct {
		line string
		want LogEvent
		ok   bool
	}{
		{"[07Nov2026 17:58:09.520] [Server thread/INFO] [net.minecraft.server.MinecraftServer/]: Steve joined the game", LogEvent{Kind: EventJoin, Player: "Steve"}, true},
		{"[07Nov2026 18:02:36.901] [Server thread/INFO] [net.minecraft.server.MinecraftServer/]: Alex_1 left the game", LogEvent{Kind: EventLeave, Player: "Alex_1"}, true},
		{"[05Nov2026 20:59:51.944] [Server thread/INFO] [net.minecraft.server.MinecraftServer/]: <Alex_1> a portal", LogEvent{Kind: EventChat, Player: "Alex_1", Text: "a portal"}, true},
		{"[07Nov2026 17:57:35.000] [Server thread/INFO] [net.minecraft.server.MinecraftServer/]: Stopping the server", LogEvent{Kind: EventServerStop}, true},
		// a player who types a join line is chat
		{"[07Nov2026 17:58:09.520] [Server thread/INFO] [net.minecraft.server.MinecraftServer/]: <zoe> adam joined the game", LogEvent{Kind: EventChat, Player: "zoe", Text: "adam joined the game"}, true},
		{"[07Nov2026 17:58:06.702] [Server thread/INFO] [net.minecraft.server.dedicated.DedicatedServer/]: Done (2.072s)! For help, type \"help\"", LogEvent{}, false},
		{"[07Nov2026 17:58:00.000] [main/ERROR] [minecraft/AbstractPackResources]: <zoe> not chat", LogEvent{}, false},
		{"", LogEvent{}, false},
	}
	for _, tt := range tests {
		got, ok := parseLine(tt.line)
		if ok != tt.ok || got != tt.want {
			t.Errorf("%q: got %+v %v, want %+v %v", tt.line, got, ok, tt.want, tt.ok)
		}
	}
}

func TestTailLogRotation(t *testing.T) {
	path := filepath.Join(t.TempDir(), "latest.log")
	line := func(content string) string {
		return "[07Nov2026 17:58:09.520] [Server thread/INFO] [net.minecraft.server.MinecraftServer/]: " + content + "\n"
	}
	if err := os.WriteFile(path, []byte(line("old joined the game")), 0o644); err != nil {
		t.Fatal(err)
	}

	events := make(chan LogEvent, 100)
	go tailLog(path, 10*time.Millisecond, func(e LogEvent) { events <- e })

	append := func(content string) {
		f, err := os.OpenFile(path, os.O_APPEND|os.O_WRONLY, 0o644)
		if err != nil {
			t.Fatal(err)
		}
		fmt.Fprint(f, content)
		f.Close()
	}

	// the tailer starts at the end of the file, so probe until it listens
	for listening := false; !listening; {
		append(line("probe joined the game"))
		select {
		case <-events:
			listening = true
		case <-time.After(10 * time.Millisecond):
		}
	}
	time.Sleep(30 * time.Millisecond)
	for drained := false; !drained; {
		select {
		case <-events:
		default:
			drained = true
		}
	}

	next := func() LogEvent {
		select {
		case e := <-events:
			return e
		case <-time.After(2 * time.Second):
			t.Fatal("no event")
			return LogEvent{}
		}
	}

	// a line in two writes, and lines after a restart of the server
	append("[07Nov2026 17:58:09.520] [Server thread/INFO] [net.minecraft.")
	append("server.MinecraftServer/]: zoe joined the game\n")
	if got := next(); got != (LogEvent{Kind: EventJoin, Player: "zoe"}) {
		t.Errorf("got %+v", got)
	}
	if err := os.Rename(path, path+".1"); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(line("adam joined the game")), 0o644); err != nil {
		t.Fatal(err)
	}
	if got := next(); got != (LogEvent{Kind: EventJoin, Player: "adam"}) {
		t.Errorf("after rotation: got %+v", got)
	}
	select {
	case e := <-events:
		t.Errorf("unexpected event %+v", e)
	default:
	}
}

func TestParseList(t *testing.T) {
	tests := []struct {
		response string
		want     []string
	}{
		{"There are 2 of a max of 20 players online: zoe, adam", []string{"zoe", "adam"}},
		{"There are 0 of a max of 20 players online:", nil},
		{"", nil},
	}
	for _, tt := range tests {
		got := parseList(tt.response)
		if fmt.Sprint(got) != fmt.Sprint(tt.want) {
			t.Errorf("%q: got %v, want %v", tt.response, got, tt.want)
		}
	}
}

// fakeRcon answers like a Minecraft server with one player online.
func fakeRcon(t *testing.T, password string) (addr string, commands *[]string) {
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { listener.Close() })
	var mu sync.Mutex
	commands = &[]string{}
	go func() {
		for {
			conn, err := listener.Accept()
			if err != nil {
				return
			}
			go func() {
				defer conn.Close()
				for {
					id, kind, payload, err := readPacket(conn)
					if err != nil {
						return
					}
					switch kind {
					case rconAuth:
						if payload != password {
							id = -1
						}
						writePacket(conn, id, rconAuthResponse, "")
					case rconCommand:
						mu.Lock()
						*commands = append(*commands, payload)
						mu.Unlock()
						writePacket(conn, id, rconResponse, "There are 1 of a max of 20 players online: zoe")
					}
				}
			}()
		}
	}()
	return listener.Addr().String(), commands
}

func TestRcon(t *testing.T) {
	addr, commands := fakeRcon(t, "secret")
	rcon := &Rcon{addr: addr, password: "secret"}
	defer rcon.Close()

	players, err := rcon.Players()
	if err != nil {
		t.Fatal(err)
	}
	if fmt.Sprint(players) != "[zoe]" {
		t.Errorf("got %v", players)
	}
	if err := rcon.Tell("zoe", `hi "there"`); err != nil {
		t.Fatal(err)
	}
	want := `tellraw @a {"extra":[{"text":"[Slack] ","color":"light_purple"},{"text":"<zoe> ","color":"white"},{"text":"hi \"there\"","color":"white"}],"text":""}`
	if got := (*commands)[1]; got != want {
		t.Errorf("got %q, want %q", got, want)
	}

	wrong := &Rcon{addr: addr, password: "wrong"}
	if _, err := wrong.Players(); err == nil {
		t.Error("a wrong password got through")
	}
}

// fakeSlack records the calls, and rate-limits the first one.
func fakeSlack(t *testing.T) (*slack.Client, *[]url.Values) {
	var mu sync.Mutex
	calls := &[]url.Values{}
	limited := false
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		mu.Lock()
		defer mu.Unlock()
		if !limited {
			limited = true
			w.Header().Set("Retry-After", "0")
			w.WriteHeader(http.StatusTooManyRequests)
			return
		}
		if err := r.ParseForm(); err != nil {
			t.Error(err)
		}
		form := r.PostForm
		form.Set("method", r.URL.Path)
		*calls = append(*calls, form)
		fmt.Fprint(w, `{"ok": true, "channel": "C1", "ts": "111.1"}`)
	}))
	t.Cleanup(srv.Close)
	return slack.New("x", slack.OptionAPIURL(srv.URL+"/")), calls
}

func TestBridgeDay(t *testing.T) {
	clock(t, time.Date(2026, 11, 7, 9, 0, 0, 0, time.UTC))
	api, calls := fakeSlack(t)
	bridge := &Bridge{slack: api, channelID: "C1"}

	// a chat line before any join posts the message, then the line
	if err := bridge.Chat("zoe", "hi <!channel> ~/x"); err != nil {
		t.Fatal(err)
	}
	if err := bridge.PlayerJoined("zoe"); err != nil {
		t.Fatal(err)
	}
	if err := bridge.SyncPlayers([]string{"zoe", "adam"}); err != nil {
		t.Fatal(err)
	}
	if err := bridge.ServerStopped(); err != nil {
		t.Fatal(err)
	}
	// nothing changed, so nothing to post
	if err := bridge.SyncPlayers(nil); err != nil {
		t.Fatal(err)
	}

	want := []struct{ method, text, thread string }{
		{"/chat.postMessage", "Players: zoe", ""},
		{"/chat.postMessage", "hi &lt;!channel&gt; ~/x", "111.1"},
		{"/chat.update", "Players: zoe, adam", ""},
		{"/chat.update", "Players: ~zoe~, ~adam~", ""},
	}
	if len(*calls) != len(want) {
		t.Fatalf("got %d calls, want %d: %v", len(*calls), len(want), *calls)
	}
	for i, w := range want {
		form := (*calls)[i]
		if form.Get("method") != w.method || form.Get("text") != w.text || form.Get("thread_ts") != w.thread {
			t.Errorf("call %d: got %v, want %+v", i, form, w)
		}
	}
	chat := (*calls)[1]
	if chat.Get("username") != "zoe" || chat.Get("icon_url") != "https://mc-heads.net/avatar/zoe/64" {
		t.Errorf("chat not as the player: %v", chat)
	}
	if chat.Get("unfurl_links") != "false" || chat.Get("unfurl_media") != "false" {
		t.Errorf("previews are on: %v", chat)
	}
}

func TestHandleSlack(t *testing.T) {
	var relayed []string
	bridge := &Bridge{
		channelID: "C1",
		presence:  Presence{TS: "111.1"},
		users:     map[string]string{"U1": "zoe"},
		relay: func(name, text string) error {
			relayed = append(relayed, name+": "+text)
			return nil
		},
	}
	reply := func(user, channel, thread, text string) *slackevents.MessageEvent {
		return &slackevents.MessageEvent{User: user, Channel: channel, ThreadTimeStamp: thread, Text: text}
	}
	for _, ev := range []*slackevents.MessageEvent{
		reply("U1", "C1", "111.1", "hello"),
		// not in the thread of the day
		reply("U1", "C1", "", "top level"),
		reply("U1", "C1", "222.2", "another thread"),
		// another channel, an unmapped user, a bot, an edit
		reply("U1", "C2", "111.1", "elsewhere"),
		reply("U2", "C1", "111.1", "stranger"),
		{BotID: "B1", Channel: "C1", ThreadTimeStamp: "111.1", Text: "echo"},
		{User: "U1", Channel: "C1", ThreadTimeStamp: "111.1", Text: "edit", SubType: "message_changed"},
	} {
		if err := bridge.HandleSlack(ev); err != nil {
			t.Fatal(err)
		}
	}
	if fmt.Sprint(relayed) != "[zoe: hello]" {
		t.Errorf("got %v", relayed)
	}
}
