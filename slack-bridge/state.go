package main

import (
	"fmt"
	"log"
	"regexp"
	"sort"
	"strings"
	"sync"
	"time"
)

// State holds what the bridge knows about each of its links. A change goes
// to the journal once, so a quiet journal means that nothing changed.
type State struct {
	sync.Mutex
	links map[string]string
}

// Set records the state of one link, and logs it when it is new.
func (s *State) Set(link, state string) {
	s.Lock()
	defer s.Unlock()
	if s.links == nil {
		s.links = map[string]string{}
	}
	if s.links[link] == state {
		return
	}
	s.links[link] = state
	log.Printf("%s: %s", link, state)
}

// Is tells whether the state of a link starts with the prefix.
func (s *State) Is(link, prefix string) bool {
	s.Lock()
	defer s.Unlock()
	return strings.HasPrefix(s.links[link], prefix)
}

// Health is one line with every link, in a stable order.
func (s *State) Health() string {
	s.Lock()
	defer s.Unlock()
	links := make([]string, 0, len(s.links))
	for link := range s.links {
		links = append(links, link)
	}
	sort.Strings(links)
	parts := make([]string, 0, len(links))
	for _, link := range links {
		// the first word is the state, the rest is detail for the change line
		state, _, _ := strings.Cut(s.links[link], " ")
		parts = append(parts, fmt.Sprintf("%s=%s", link, state))
	}
	return strings.Join(parts, " ")
}

// report logs the health line at each interval, so the journal shows that
// the bridge is alive when nothing changes.
func (s *State) report(interval time.Duration, players func() int) {
	for {
		time.Sleep(interval)
		log.Printf("health: %s players=%d", s.Health(), players())
	}
}

// the socket address of Slack carries a ticket in its query
var urlQuery = regexp.MustCompile(`\?[^\s"]*`)

// redact removes what an error text of the Slack client can hold of a secret.
func redact(text string) string {
	return urlQuery.ReplaceAllString(text, "?[removed]")
}
