"""Configuration management for the Minecraft-Slack bridge."""

import json
import os
from dataclasses import dataclass
from pathlib import Path


def _read_secret(name: str) -> str:
    """Read a secret from a file path specified by {NAME}_FILE env var."""
    file_path = os.environ[f"{name}_FILE"]
    return Path(file_path).read_text().strip()


@dataclass
class Config:
    """Bridge configuration loaded from environment variables."""

    slack_bot_token: str
    slack_app_token: str
    slack_channel_id: str
    rcon_host: str
    rcon_port: int
    rcon_password: str
    minecraft_log_path: str
    user_mapping: dict[str, str]  # Slack user ID -> MC username

    @classmethod
    def from_env(cls) -> "Config":
        """Load configuration from environment variables."""
        with open(os.environ["USER_MAPPING_FILE"], encoding="utf-8") as f:
            user_mapping = json.load(f)

        return cls(
            slack_bot_token=_read_secret("SLACK_BOT_TOKEN"),
            slack_app_token=_read_secret("SLACK_APP_TOKEN"),
            slack_channel_id=os.environ["SLACK_CHANNEL_ID"],
            rcon_host=os.environ["RCON_HOST"],
            rcon_port=int(os.environ["RCON_PORT"]),
            rcon_password=_read_secret("RCON_PASSWORD"),
            minecraft_log_path=os.environ["MINECRAFT_LOG_PATH"],
            user_mapping=user_mapping,
        )

    def get_mc_username(self, slack_user_id: str) -> str | None:
        """Get Minecraft username for a Slack user ID."""
        return self.user_mapping.get(slack_user_id)

    def get_slack_user_id(self, mc_username: str) -> str | None:
        """Get Slack user ID for a Minecraft username."""
        for slack_id, mc_name in self.user_mapping.items():
            if mc_name.lower() == mc_username.lower():
                return slack_id
        return None
