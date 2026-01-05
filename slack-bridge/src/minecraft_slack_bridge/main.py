"""Main entry point for the Minecraft-Slack bridge."""

import logging
import os
import signal
import sys
import threading
import time

from .config import Config
from .log_parser import LogWatcher, MinecraftEvent, EventType
from .rcon import RconClient, RconError
from .slack import SlackBridge

log_level = logging.DEBUG if os.environ.get("DEBUG") else logging.INFO
logging.basicConfig(
    level=log_level,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)
logger = logging.getLogger(__name__)


class Bridge:
    """Main bridge orchestrator."""

    def __init__(self, config: Config):
        self.config = config
        self.rcon = RconClient(
            host=config.rcon_host,
            port=config.rcon_port,
            password=config.rcon_password,
        )
        self.slack = SlackBridge(
            bot_token=config.slack_bot_token,
            app_token=config.slack_app_token,
            channel_id=config.slack_channel_id,
            on_message=self._handle_slack_message,
        )
        self.log_watcher = LogWatcher(
            log_path=config.minecraft_log_path,
            callback=self._handle_mc_event,
        )
        self._running = False

    def _handle_mc_event(self, event: MinecraftEvent) -> None:
        """Handle events from Minecraft log."""
        logger.debug("MC event: %s", event)

        if event.event_type == EventType.CHAT:
            if event.player and event.message:
                self.slack.post_as_player(event.player, event.message)

        elif event.event_type == EventType.JOIN:
            if event.player:
                self.slack.player_joined(event.player)

        elif event.event_type == EventType.LEAVE:
            if event.player:
                self.slack.player_left(event.player)

        elif event.event_type == EventType.SERVER_START:
            self.slack.server_started()

        elif event.event_type == EventType.SERVER_STOP:
            self.slack.server_stopped()

    def _handle_slack_message(self, slack_user_id: str, text: str) -> None:
        """Handle messages from Slack."""
        mc_username = self.config.get_mc_username(slack_user_id)
        if not mc_username:
            logger.debug("Ignoring message from unmapped user: %s", slack_user_id)
            return

        logger.info("Relaying message from %s to MC", mc_username)

        try:
            # Use tellraw for formatted messages
            message = {
                "text": "",
                "extra": [
                    {"text": "[Slack] ", "color": "light_purple"},
                    {"text": f"<{mc_username}> ", "color": "white"},
                    {"text": text, "color": "white"},
                ],
            }
            self.rcon.tellraw("@a", message)
        except RconError as e:
            logger.error("Failed to send message to MC: %s", e)

    def _check_server_status(self) -> None:
        """Periodically check server status and sync players via RCON."""
        while self._running:
            try:
                players = self.rcon.list_players()
                self.slack._online_players = set(players)
                self.slack._server_online = True
            except (RconError, ConnectionRefusedError, OSError) as e:
                if self.slack._server_online:
                    logger.warning("RCON check failed: %s", e)
                self.slack._server_online = False
                self.slack._online_players.clear()
            self.slack.update_topic()  # Caching prevents duplicate API calls
            time.sleep(8)

    def start(self) -> None:
        """Start the bridge."""
        self._running = True

        # Start Slack handler
        self.slack.start()

        # Start server status checker in background
        # This handles RCON connection and keeping it alive
        status_thread = threading.Thread(target=self._check_server_status, daemon=True)
        status_thread.start()

        # Start log watcher (blocks)
        logger.info("Bridge started")
        self.log_watcher.start()

    def stop(self) -> None:
        """Stop the bridge."""
        self._running = False
        self.log_watcher.stop()
        self.slack.stop()
        self.rcon.disconnect()
        logger.info("Bridge stopped")


def main() -> None:
    """Main entry point."""
    try:
        config = Config.from_env()
    except KeyError as e:
        logger.error("Missing required environment variable: %s", e)
        sys.exit(1)

    bridge = Bridge(config)

    def signal_handler(signum: int, frame: object) -> None:
        logger.info("Received signal %d, shutting down...", signum)
        bridge.stop()
        sys.exit(0)

    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    bridge.start()


if __name__ == "__main__":
    main()
