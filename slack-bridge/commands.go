package main

import (
	"bufio"
	"fmt"
	"log"
	"os"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/slack-go/slack"
	"github.com/slack-go/slack/slackevents"
)

// one command for each Slack user in this time
const commandInterval = 5 * time.Second

const helpText = "*Commands*\n" +
	"`!status` players, version, tick rate and uptime of the server\n" +
	"`!help` this text"

var (
	listCount   = regexp.MustCompile(`There are (\d+) of a max of (\d+) players online`)
	tickTarget  = regexp.MustCompile(`Target tick rate: ([0-9.]+)`)
	tickAverage = regexp.MustCompile(`Average time per tick: ([0-9.]+)ms`)
	logStamp    = regexp.MustCompile(`^\[(\d{2}\w{3}\d{4} \d{2}:\d{2}:\d{2}\.\d{3})\]`)
	logVersion  = regexp.MustCompile(`Starting minecraft server version (\S+)`)
)

// command splits "!help me" into "help" and "me".
func splitCommand(text string) (name, rest string, ok bool) {
	if !strings.HasPrefix(text, "!") {
		return "", "", false
	}
	name, rest, _ = strings.Cut(strings.TrimPrefix(text, "!"), " ")
	switch name {
	case "help", "status":
		return name, strings.TrimSpace(rest), true
	}
	return "", "", false
}

// allow tells whether the user may run a command now.
func (b *Bridge) allow(user string) bool {
	b.Lock()
	defer b.Unlock()
	if b.lastCommand == nil {
		b.lastCommand = map[string]time.Time{}
	}
	if last, ok := b.lastCommand[user]; ok && now().Sub(last) < commandInterval {
		return false
	}
	b.lastCommand[user] = now()
	return true
}

// HandleCommand answers a command in the thread of the message that holds it.
func (b *Bridge) HandleCommand(ev *slackevents.MessageEvent, name, rest string) error {
	if !b.allow(ev.User) {
		log.Printf("command: %s from %s dropped, too soon after the last one", name, ev.User)
		return nil
	}
	var answer string
	switch name {
	case "help":
		answer = helpText
	case "status":
		answer = b.status()
	}
	thread := ev.ThreadTimeStamp
	if thread == "" {
		thread = ev.TimeStamp
	}
	return retry(func() error {
		_, _, err := b.slack.PostMessage(b.channelID,
			slack.MsgOptionText(answer, false),
			slack.MsgOptionTS(thread),
			slack.MsgOptionDisableLinkUnfurl(),
			slack.MsgOptionDisableMediaUnfurl(),
		)
		return err
	})
}

// status asks the server over RCON, and reads the start of the server log for
// what RCON does not tell.
func (b *Bridge) status() string {
	lines := []string{"*Server status*"}
	list, err := b.command("list")
	if err != nil {
		return "*Server status*\nThe server does not answer."
	}
	players := parseList(list)
	if m := listCount.FindStringSubmatch(list); m != nil {
		line := fmt.Sprintf("Players: %s of %s", m[1], m[2])
		if len(players) > 0 {
			line += " (" + bodyEscaper.Replace(strings.Join(players, ", ")) + ")"
		}
		lines = append(lines, line)
	}
	version, started := logHead(b.logPath)
	if version != "" {
		lines = append(lines, "Version: "+bodyEscaper.Replace(version))
	}
	if tick, err := b.command("tick query"); err == nil {
		if line := tickLine(tick); line != "" {
			lines = append(lines, line)
		}
	}
	if !started.IsZero() {
		lines = append(lines, "Uptime: "+uptime(now().Sub(started)))
	}
	return strings.Join(lines, "\n")
}

// tickLine reads the answer of "tick query". It gives nothing when the
// answer has another shape.
func tickLine(response string) string {
	average := tickAverage.FindStringSubmatch(response)
	if average == nil {
		return ""
	}
	ms, err := strconv.ParseFloat(average[1], 64)
	if err != nil || ms <= 0 {
		return ""
	}
	target := 20.0
	if m := tickTarget.FindStringSubmatch(response); m != nil {
		if t, err := strconv.ParseFloat(strings.TrimRight(m[1], "."), 64); err == nil && t > 0 {
			target = t
		}
	}
	// the server does not tick faster than its target
	tps := min(target, 1000/ms)
	return fmt.Sprintf("Tick rate: %.1f of %.1f per second (%.1f ms for each tick)", tps, target, ms)
}

// logHead reads the version and the start time from the first lines of the
// server log. The server starts a new file at each start.
func logHead(path string) (version string, started time.Time) {
	file, err := os.Open(path)
	if err != nil {
		return "", time.Time{}
	}
	defer file.Close()
	scanner := bufio.NewScanner(file)
	for i := 0; i < 2000 && scanner.Scan(); i++ {
		line := scanner.Text()
		if started.IsZero() {
			if m := logStamp.FindStringSubmatch(line); m != nil {
				started, _ = time.ParseInLocation("02Jan2006 15:04:05.000", m[1], time.Local)
			}
		}
		if m := logVersion.FindStringSubmatch(line); m != nil {
			return m[1], started
		}
	}
	return "", started
}

func uptime(d time.Duration) string {
	if d < 0 {
		d = 0
	}
	days := int(d.Hours()) / 24
	hours := int(d.Hours()) % 24
	minutes := int(d.Minutes()) % 60
	switch {
	case days > 0:
		return fmt.Sprintf("%dd %dh", days, hours)
	case hours > 0:
		return fmt.Sprintf("%dh %dm", hours, minutes)
	}
	return fmt.Sprintf("%dm", minutes)
}
