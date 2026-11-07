package main

import (
	"strings"
	"time"
)

// a variable so that the tests can travel in time
var now = time.Now

func today() string {
	return now().Format(time.DateOnly)
}

// Player stays on the list after they leave, so that the message shows who
// played today.
type Player struct {
	Name string
	Left bool
}

// Presence is the list of the day, and the Slack message that shows it.
type Presence struct {
	Players []Player
	// so that the server gets at most one new message a day
	TS  string
	Day string
}

func (p *Presence) present() bool {
	for _, player := range p.Players {
		if !player.Left {
			return true
		}
	}
	return false
}

func (p *Presence) online() map[string]bool {
	online := map[string]bool{}
	for _, player := range p.Players {
		if !player.Left {
			online[player.Name] = true
		}
	}
	return online
}

// join reports whether anything changed.
func (p *Presence) join(name string) bool {
	// a session that runs over midnight keeps the message it started with
	if !p.present() && p.Day != today() {
		p.Players = nil
		p.TS = ""
	}
	for i, player := range p.Players {
		if player.Name == name {
			if !player.Left {
				return false
			}
			p.Players[i].Left = false
			return true
		}
	}
	p.Players = append(p.Players, Player{Name: name})
	return true
}

// leave reports whether anything changed.
func (p *Presence) leave(name string) bool {
	for i, player := range p.Players {
		if player.Name == name && !player.Left {
			p.Players[i].Left = true
			return true
		}
	}
	return false
}

// leaveAll reports whether anything changed.
func (p *Presence) leaveAll() bool {
	changed := false
	for i, player := range p.Players {
		if !player.Left {
			p.Players[i].Left = true
			changed = true
		}
	}
	return changed
}

// a name goes into Slack mrkdwn, and inside a strikethrough once the player
// left. A "~" would cut the strikethrough short.
var nameEscaper = strings.NewReplacer("&", "&amp;", "<", "&lt;", ">", "&gt;", "~", "˜")

// unlike a name, a chat line is not inside a strikethrough, so its "~" can stay
var bodyEscaper = strings.NewReplacer("&", "&amp;", "<", "&lt;", ">", "&gt;")

// one entry per name, in first-join order so that edits do not reshuffle it.
func playersText(players []Player) string {
	if len(players) == 0 {
		return "*everybody left*"
	}
	names := make([]string, len(players))
	for i, player := range players {
		name := nameEscaper.Replace(player.Name)
		if player.Left {
			name = "~" + name + "~"
		}
		names[i] = name
	}
	return "Players: " + strings.Join(names, ", ")
}
