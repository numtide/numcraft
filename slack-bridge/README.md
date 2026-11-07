# minecraft-slack-bridge

A little tool that lets us know in Slack whenever someone plays on the
Minecraft server, and bridges the chat.

## How it works

This is all very eventually-consistent.

It tails the server log for joins, leaves and chat, and polls the player list
over RCON every few seconds to catch what the log missed.

- When the first player joins, it posts a message on Slack.
- When players join or leave, it updates the message with the names of the
  players. A name gets a strikethrough when the player leaves.
- When the server stops, it strikes through all the names. Whether the
  server is up is a job for the monitoring, not for Slack.
- Each chat line of the game goes as a reply in the thread of that message, as
  the player with their avatar.
- Each reply in that thread goes to the game, for the Slack users of the
  mapping. Messages elsewhere in the channel stay out.

The server gets at most one new message a day. The later sessions of the day
update that message, so the channel stays quiet. A session that runs over
midnight keeps the message it started with. A restart of the bridge in the
middle of the day posts a fresh message.

NOTE: If the message doesn't show up, check that the bot is invited to the
channel.

## Configuration

The clan module in `clan-module.nix` sets this up. The Go program reads:

- `SLACK_BOT_TOKEN_FILE`: the token of the Slack bot (xoxb-…).
- `SLACK_APP_TOKEN_FILE`: the app-level token for Socket Mode (xapp-…).
- `SLACK_CHANNEL_ID`: the channel of the presence message.
- `USER_MAPPING_FILE`: JSON that maps Slack user IDs to Minecraft names.
- `RCON_HOST`, `RCON_PORT`, `RCON_PASSWORD_FILE`: the RCON of the server.
- `MINECRAFT_LOG_PATH`: the `latest.log` of the server.

The bot needs the `chat:write` and `chat:write.customize` scopes, and the
`message.channels` event in Socket Mode.

## Development

```console
$ CGO_ENABLED=0 go test ./...
$ nix build .#slack-bridge
```
