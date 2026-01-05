"""Slack integration for the Minecraft bridge."""

import logging
from slack_bolt import App
from slack_bolt.adapter.socket_mode import SocketModeHandler
from slack_sdk import WebClient
from slack_sdk.errors import SlackApiError

logger = logging.getLogger(__name__)

# MC-Heads API for player avatars
AVATAR_URL_TEMPLATE = "https://mc-heads.net/avatar/{username}/64"


class SlackBridge:
    """Handles Slack communication for the bridge."""

    def __init__(
        self,
        bot_token: str,
        app_token: str,
        channel_id: str,
        on_message: callable = None,
    ):
        self.bot_token = bot_token
        self.app_token = app_token
        self.channel_id = channel_id
        self.on_message = on_message

        self.client = WebClient(token=bot_token)
        self.app = App(token=bot_token)
        self._handler: SocketModeHandler | None = None
        self._online_players: set[str] = set()
        self._server_online = False
        self._last_topic: str | None = None

        # Register message handler
        @self.app.message("")
        def handle_message(message: dict, say: callable) -> None:
            self._handle_slack_message(message)

    def _handle_slack_message(self, message: dict) -> None:
        """Handle incoming Slack messages."""
        # Ignore messages from bots
        if message.get("bot_id") or message.get("subtype"):
            return

        # Only process messages from our channel
        if message.get("channel") != self.channel_id:
            return

        user_id = message.get("user")
        text = message.get("text", "")

        if self.on_message and text:
            self.on_message(user_id, text)

    def start(self) -> None:
        """Start the Socket Mode handler."""
        self._handler = SocketModeHandler(self.app, self.app_token)
        self._handler.connect()
        logger.info("Slack Socket Mode connected")

        # Read current topic to avoid unnecessary updates
        try:
            info = self.client.conversations_info(channel=self.channel_id)
            self._last_topic = info["channel"]["topic"]["value"]
            logger.info("Current topic: %s", self._last_topic)
        except SlackApiError as e:
            logger.warning("Failed to read current topic: %s", e.response["error"])

    def stop(self) -> None:
        """Stop the Socket Mode handler."""
        if self._handler:
            self._handler.close()
            self._handler = None

    def post_as_player(self, username: str, message: str) -> None:
        """Post a message as a Minecraft player with their avatar."""
        avatar_url = AVATAR_URL_TEMPLATE.format(username=username)

        try:
            self.client.chat_postMessage(
                channel=self.channel_id,
                text=message,
                username=username,
                icon_url=avatar_url,
            )
        except SlackApiError as e:
            logger.error("Failed to post message: %s", e.response["error"])

    def post_system_message(self, message: str) -> None:
        """Post a system message (server events)."""
        try:
            self.client.chat_postMessage(
                channel=self.channel_id,
                text=message,
            )
        except SlackApiError as e:
            logger.error("Failed to post system message: %s", e.response["error"])

    def update_topic(self) -> None:
        """Update channel topic with server status and online players."""
        if self._server_online:
            if self._online_players:
                players_list = ", ".join(sorted(self._online_players))
                topic = f":large_green_circle: Online: {players_list}"
            else:
                topic = ":large_green_circle: No players online"
        else:
            topic = ":red_circle: Server offline"

        if topic == self._last_topic:
            return

        try:
            self.client.conversations_setTopic(
                channel=self.channel_id,
                topic=topic,
            )
            self._last_topic = topic
            logger.info("Updated topic: %s", topic)
        except SlackApiError as e:
            logger.error("Failed to update topic: %s", e.response["error"])

    def player_joined(self, username: str) -> None:
        """Handle player join event."""
        self._online_players.add(username)
        self.update_topic()

    def player_left(self, username: str) -> None:
        """Handle player leave event."""
        self._online_players.discard(username)
        self.update_topic()

    def server_started(self) -> None:
        """Handle server start event."""
        self._server_online = True
        self._online_players.clear()
        self.update_topic()

    def server_stopped(self) -> None:
        """Handle server stop event."""
        self._server_online = False
        self._online_players.clear()
        self.update_topic()

