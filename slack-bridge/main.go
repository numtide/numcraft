// A bridge between the Minecraft server and Slack, in the shape of
// one message a day that lists the players, and the chat as replies in its
// thread.
package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"os"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/slack-go/slack"
	"github.com/slack-go/slack/slackevents"
	"github.com/slack-go/slack/socketmode"
)

type Config struct {
	BotToken     string
	AppToken     string
	ChannelID    string
	RconAddr     string
	RconPassword string
	LogPath      string
	// Slack user ID to Minecraft name
	Users map[string]string
}

func secret(name string) (string, error) {
	path := os.Getenv(name + "_FILE")
	if path == "" {
		return "", fmt.Errorf("set %s_FILE", name)
	}
	b, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(b)), nil
}

func loadConfig() (*Config, error) {
	config := &Config{
		ChannelID: os.Getenv("SLACK_CHANNEL_ID"),
		RconAddr:  os.Getenv("RCON_HOST") + ":" + os.Getenv("RCON_PORT"),
		LogPath:   os.Getenv("MINECRAFT_LOG_PATH"),
	}
	if config.ChannelID == "" || config.LogPath == "" || os.Getenv("RCON_HOST") == "" || os.Getenv("RCON_PORT") == "" {
		return nil, errors.New("set SLACK_CHANNEL_ID, RCON_HOST, RCON_PORT and MINECRAFT_LOG_PATH")
	}
	var err error
	if config.BotToken, err = secret("SLACK_BOT_TOKEN"); err != nil {
		return nil, err
	}
	if config.AppToken, err = secret("SLACK_APP_TOKEN"); err != nil {
		return nil, err
	}
	if config.RconPassword, err = secret("RCON_PASSWORD"); err != nil {
		return nil, err
	}
	b, err := os.ReadFile(os.Getenv("USER_MAPPING_FILE"))
	if err != nil {
		return nil, fmt.Errorf("USER_MAPPING_FILE: %w", err)
	}
	if err := json.Unmarshal(b, &config.Users); err != nil {
		return nil, fmt.Errorf("USER_MAPPING_FILE: %w", err)
	}
	return config, nil
}

type Bridge struct {
	sync.Mutex
	slack     *slack.Client
	channelID string
	presence  Presence
	users     map[string]string
	// relay shows a line from Slack in the game
	relay func(name, text string) error
}

// retry waits when Slack rate-limits, so that no line gets lost.
func retry(call func() error) error {
	for {
		err := call()
		var limited *slack.RateLimitedError
		if errors.As(err, &limited) {
			time.Sleep(limited.RetryAfter)
			continue
		}
		return err
	}
}

// notify posts or updates the message of the day. Call with the lock held.
func (b *Bridge) notify() error {
	if b.presence.TS == "" && !b.presence.present() {
		return nil
	}
	text := slack.MsgOptionText(playersText(b.presence.Players), false)
	if b.presence.TS == "" {
		return retry(func() error {
			_, ts, err := b.slack.PostMessage(b.channelID, text)
			if err != nil {
				return err
			}
			b.presence.TS = ts
			b.presence.Day = today()
			return nil
		})
	}
	return retry(func() error {
		_, _, _, err := b.slack.UpdateMessage(b.channelID, b.presence.TS, text)
		return err
	})
}

func (b *Bridge) PlayerJoined(name string) error {
	b.Lock()
	defer b.Unlock()
	if !b.presence.join(name) {
		return nil
	}
	return b.notify()
}

func (b *Bridge) PlayerLeft(name string) error {
	b.Lock()
	defer b.Unlock()
	if !b.presence.leave(name) {
		return nil
	}
	return b.notify()
}

func (b *Bridge) ServerStopped() error {
	b.Lock()
	defer b.Unlock()
	if !b.presence.leaveAll() {
		return nil
	}
	return b.notify()
}

// SyncPlayers reconciles the list with what the server says.
func (b *Bridge) SyncPlayers(online []string) error {
	b.Lock()
	defer b.Unlock()
	changed := false
	listed := map[string]bool{}
	for _, name := range online {
		listed[name] = true
	}
	for name := range b.presence.online() {
		if !listed[name] {
			changed = b.presence.leave(name) || changed
		}
	}
	sort.Strings(online)
	for _, name := range online {
		changed = b.presence.join(name) || changed
	}
	if !changed {
		return nil
	}
	return b.notify()
}

// Chat posts a line of the game in the thread, as the player with their skin.
func (b *Bridge) Chat(name, text string) error {
	// a chat line proves the player is online, and a missed join must not
	// drop the chat of the day
	if err := b.PlayerJoined(name); err != nil {
		return err
	}
	b.Lock()
	thread := b.presence.TS
	b.Unlock()
	if thread == "" {
		return errors.New("no presence message, line dropped")
	}
	return retry(func() error {
		_, _, err := b.slack.PostMessage(b.channelID,
			slack.MsgOptionText(bodyEscaper.Replace(text), false),
			slack.MsgOptionTS(thread),
			slack.MsgOptionUsername(name),
			slack.MsgOptionIconURL("https://mc-heads.net/avatar/"+name+"/64"),
			// a player must not get to pick what the thread previews
			slack.MsgOptionDisableLinkUnfurl(),
			slack.MsgOptionDisableMediaUnfurl(),
		)
		return err
	})
}

// HandleSlack relays the replies in the thread of the message of the day,
// from the Slack users of the mapping.
func (b *Bridge) HandleSlack(ev *slackevents.MessageEvent) error {
	if ev.BotID != "" || ev.SubType != "" || ev.Channel != b.channelID || ev.Text == "" {
		return nil
	}
	b.Lock()
	thread := b.presence.TS
	b.Unlock()
	if thread == "" || ev.ThreadTimeStamp != thread {
		return nil
	}
	name, ok := b.users[ev.User]
	if !ok {
		log.Println("HandleSlack: no Minecraft name for", ev.User)
		return nil
	}
	return b.relay(name, ev.Text)
}

func (b *Bridge) HandleLog(event LogEvent) {
	var err error
	switch event.Kind {
	case EventChat:
		err = b.Chat(event.Player, event.Text)
	case EventJoin:
		err = b.PlayerJoined(event.Player)
	case EventLeave:
		err = b.PlayerLeft(event.Player)
	case EventServerStop:
		err = b.ServerStopped()
	}
	if err != nil {
		log.Println("HandleLog:", err)
	}
}

// poll reconciles the list with the server. A server that does not answer
// has nobody online.
func (b *Bridge) poll(rcon *Rcon, interval time.Duration) {
	reachable := false
	for {
		players, err := rcon.Players()
		if err != nil && reachable {
			log.Println("poll:", err)
		}
		reachable = err == nil
		if err := b.SyncPlayers(players); err != nil {
			log.Println("poll:", err)
		}
		time.Sleep(interval)
	}
}

const (
	pollInterval = 8 * time.Second
	tailInterval = time.Second
)

func main() {
	config, err := loadConfig()
	if err != nil {
		log.Fatal(err)
	}

	rcon := &Rcon{addr: config.RconAddr, password: config.RconPassword}
	api := slack.New(config.BotToken, slack.OptionAppLevelToken(config.AppToken))
	bridge := &Bridge{
		slack:     api,
		channelID: config.ChannelID,
		users:     config.Users,
		relay:     rcon.Tell,
	}

	go bridge.poll(rcon, pollInterval)
	go tailLog(config.LogPath, tailInterval, bridge.HandleLog)

	client := socketmode.New(api)
	go func() {
		for evt := range client.Events {
			// every request wants an ack, or Slack sends it again
			if evt.Request != nil {
				client.Ack(*evt.Request)
			}
			switch evt.Type {
			case socketmode.EventTypeConnectionError:
				log.Println("socketmode:", evt.Data)
			case socketmode.EventTypeEventsAPI:
				event, ok := evt.Data.(slackevents.EventsAPIEvent)
				if !ok {
					continue
				}
				if message, ok := event.InnerEvent.Data.(*slackevents.MessageEvent); ok {
					if err := bridge.HandleSlack(message); err != nil {
						log.Println("HandleSlack:", err)
					}
				}
			}
		}
	}()
	log.Fatal(client.Run())
}
