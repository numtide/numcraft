package main

import (
	"bufio"
	"io"
	"log"
	"os"
	"regexp"
	"strings"
	"time"
)

type EventKind int

const (
	EventChat EventKind = iota
	EventJoin
	EventLeave
	EventServerStop
)

type LogEvent struct {
	Kind   EventKind
	Player string
	Text   string
}

// NeoForge writes:
// [07Nov2026 17:58:09.520] [Server thread/INFO] [net.minecraft.server.MinecraftServer/]: Steve joined the game
var logLine = regexp.MustCompile(`^\[\d{2}\w{3}\d{4} \d{2}:\d{2}:\d{2}\.\d{3}\] \[[^\]]+/INFO\] \[[^\]]*\]: (.*)$`)

// a Minecraft name matches \w+, which keeps it safe for a URL and for mrkdwn
var (
	chatLine  = regexp.MustCompile(`^<(\w+)> (.+)$`)
	joinLine  = regexp.MustCompile(`^(\w+) joined the game$`)
	leaveLine = regexp.MustCompile(`^(\w+) left the game$`)
)

func parseLine(line string) (LogEvent, bool) {
	m := logLine.FindStringSubmatch(line)
	if m == nil {
		return LogEvent{}, false
	}
	content := m[1]
	// a chat line first, so that a player who types "x joined the game" is chat
	if m := chatLine.FindStringSubmatch(content); m != nil {
		return LogEvent{Kind: EventChat, Player: m[1], Text: m[2]}, true
	}
	if m := joinLine.FindStringSubmatch(content); m != nil {
		return LogEvent{Kind: EventJoin, Player: m[1]}, true
	}
	if m := leaveLine.FindStringSubmatch(content); m != nil {
		return LogEvent{Kind: EventLeave, Player: m[1]}, true
	}
	if content == "Stopping the server" {
		return LogEvent{Kind: EventServerStop}, true
	}
	return LogEvent{}, false
}

// tailLog follows the file through the rotation at every server restart:
// Minecraft gzips latest.log and starts a new one.
func tailLog(path string, interval time.Duration, fn func(LogEvent)) {
	var file *os.File
	var reader *bufio.Reader
	var partial string
	// the first open starts at the end, the lines before the bridge are old news
	whence := io.SeekEnd
	for {
		if file == nil {
			f, err := os.Open(path)
			if err != nil {
				time.Sleep(interval)
				continue
			}
			if _, err := f.Seek(0, whence); err != nil {
				log.Println("tailLog:", err)
			}
			whence = io.SeekStart
			file, reader, partial = f, bufio.NewReader(f), ""
		}
		for {
			line, err := reader.ReadString('\n')
			partial += line
			if err != nil {
				break
			}
			if event, ok := parseLine(strings.TrimRight(partial, "\r\n")); ok {
				fn(event)
			}
			partial = ""
		}
		if rotated(file, path) {
			file.Close()
			file = nil
			continue
		}
		time.Sleep(interval)
	}
}

// rotated reports whether path is another file now, or got truncated.
func rotated(file *os.File, path string) bool {
	current, err := os.Stat(path)
	if err != nil {
		return true
	}
	open, err := file.Stat()
	if err != nil {
		return true
	}
	if !os.SameFile(current, open) {
		return true
	}
	pos, err := file.Seek(0, io.SeekCurrent)
	return err != nil || current.Size() < pos
}
