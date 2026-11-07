package main

import (
	"bytes"
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"strings"
	"sync"
	"time"
)

// the Source RCON protocol, https://wiki.vg/RCON
const (
	rconAuth         int32 = 3
	rconCommand      int32 = 2
	rconAuthResponse int32 = 2
	rconResponse     int32 = 0

	rconTimeout    = 10 * time.Second
	rconMaxPayload = 4096
)

// Rcon keeps one connection, which the poller and the Slack relay share.
type Rcon struct {
	sync.Mutex
	addr     string
	password string
	conn     net.Conn
	id       int32
}

func writePacket(w io.Writer, id, kind int32, payload string) error {
	body := binary.LittleEndian.AppendUint32(nil, uint32(id))
	body = binary.LittleEndian.AppendUint32(body, uint32(kind))
	body = append(body, payload...)
	body = append(body, 0, 0)
	packet := binary.LittleEndian.AppendUint32(nil, uint32(len(body)))
	_, err := w.Write(append(packet, body...))
	return err
}

func readPacket(r io.Reader) (id, kind int32, payload string, err error) {
	var length int32
	if err = binary.Read(r, binary.LittleEndian, &length); err != nil {
		return
	}
	if length < 10 || length > rconMaxPayload+10 {
		err = fmt.Errorf("rcon: bad packet length %d", length)
		return
	}
	buf := make([]byte, length)
	if _, err = io.ReadFull(r, buf); err != nil {
		return
	}
	id = int32(binary.LittleEndian.Uint32(buf[0:4]))
	kind = int32(binary.LittleEndian.Uint32(buf[4:8]))
	payload = string(buf[8 : length-2])
	return
}

func (r *Rcon) connect() error {
	conn, err := net.DialTimeout("tcp", r.addr, rconTimeout)
	if err != nil {
		return err
	}
	conn.SetDeadline(time.Now().Add(rconTimeout))
	r.id++
	if err := writePacket(conn, r.id, rconAuth, r.password); err != nil {
		conn.Close()
		return err
	}
	id, kind, _, err := readPacket(conn)
	// some servers send an empty response before the auth response
	if err == nil && kind == rconResponse {
		id, kind, _, err = readPacket(conn)
	}
	if err != nil {
		conn.Close()
		return err
	}
	if id == -1 || kind != rconAuthResponse {
		conn.Close()
		return errors.New("rcon: authentication failed")
	}
	r.conn = conn
	return nil
}

// Command runs one command and returns what the server said.
func (r *Rcon) Command(cmd string) (string, error) {
	r.Lock()
	defer r.Unlock()
	if r.conn == nil {
		if err := r.connect(); err != nil {
			return "", err
		}
	}
	r.conn.SetDeadline(time.Now().Add(rconTimeout))
	r.id++
	err := writePacket(r.conn, r.id, rconCommand, cmd)
	var response string
	if err == nil {
		_, _, response, err = readPacket(r.conn)
	}
	if err != nil {
		r.conn.Close()
		r.conn = nil
	}
	return response, err
}

func (r *Rcon) Close() {
	r.Lock()
	defer r.Unlock()
	if r.conn != nil {
		r.conn.Close()
		r.conn = nil
	}
}

// parseList reads "There are 2 of a max of 20 players online: zoe, adam".
func parseList(response string) []string {
	_, after, ok := strings.Cut(response, ":")
	if !ok {
		return nil
	}
	var players []string
	for _, name := range strings.Split(after, ",") {
		if name = strings.TrimSpace(name); name != "" {
			players = append(players, name)
		}
	}
	return players
}

// Players asks the server who is online.
func (r *Rcon) Players() ([]string, error) {
	response, err := r.Command("list")
	if err != nil {
		return nil, err
	}
	return parseList(response), nil
}

// Tell shows a line from Slack to everybody in the game.
func (r *Rcon) Tell(name, text string) error {
	type part struct {
		Text  string `json:"text"`
		Color string `json:"color,omitempty"`
	}
	var message bytes.Buffer
	encoder := json.NewEncoder(&message)
	// the game reads JSON, not HTML, so a "<" can stay as it is
	encoder.SetEscapeHTML(false)
	err := encoder.Encode(map[string]any{
		"text": "",
		"extra": []part{
			{Text: "[Slack] ", Color: "light_purple"},
			{Text: "<" + name + "> ", Color: "white"},
			{Text: text, Color: "white"},
		},
	})
	if err != nil {
		return err
	}
	_, err = r.Command("tellraw @a " + strings.TrimSpace(message.String()))
	return err
}
