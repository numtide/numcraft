"""Minecraft server log parser."""

import re
from dataclasses import dataclass
from enum import Enum
from typing import Callable
import logging

logger = logging.getLogger(__name__)


class EventType(Enum):
    """Types of Minecraft events we track."""

    CHAT = "chat"
    JOIN = "join"
    LEAVE = "leave"
    SERVER_START = "server_start"
    SERVER_STOP = "server_stop"
    DEATH = "death"
    ADVANCEMENT = "advancement"


@dataclass
class MinecraftEvent:
    """A parsed Minecraft event."""

    event_type: EventType
    player: str | None
    message: str | None
    raw_line: str


# Log line patterns
# NeoForge format: [DDMonYYYY HH:MM:SS.mmm] [Thread/LEVEL] [LoggerName/]: message
# Vanilla format: [HH:MM:SS] [Thread/LEVEL]: message
LOG_PATTERN = re.compile(
    r"\[\d{2}\w{3}\d{4} (\d{2}:\d{2}:\d{2}\.\d{3})\] \[([^/]+)/(\w+)\] \[[^\]]+/?\]: (.+)"
)

# Chat: <PlayerName> message
CHAT_PATTERN = re.compile(r"<(\w+)> (.+)")

# Join: PlayerName joined the game
JOIN_PATTERN = re.compile(r"(\w+) joined the game")

# Leave: PlayerName left the game
LEAVE_PATTERN = re.compile(r"(\w+) left the game")

# Server start: Done (X.XXXs)! For help, type "help"
START_PATTERN = re.compile(r"Done \([\d.]+s\)!")

# Server stop: Stopping the server
STOP_PATTERN = re.compile(r"Stopping the server")

# Death messages - various patterns
DEATH_PATTERNS = [
    re.compile(r"(\w+) was slain by (.+)"),
    re.compile(r"(\w+) was shot by (.+)"),
    re.compile(r"(\w+) was killed by (.+)"),
    re.compile(r"(\w+) drowned"),
    re.compile(r"(\w+) fell from a high place"),
    re.compile(r"(\w+) hit the ground too hard"),
    re.compile(r"(\w+) burned to death"),
    re.compile(r"(\w+) went up in flames"),
    re.compile(r"(\w+) tried to swim in lava"),
    re.compile(r"(\w+) suffocated in a wall"),
    re.compile(r"(\w+) starved to death"),
    re.compile(r"(\w+) blew up"),
    re.compile(r"(\w+) was blown up by (.+)"),
    re.compile(r"(\w+) withered away"),
    re.compile(r"(\w+) was pricked to death"),
    re.compile(r"(\w+) walked into a cactus"),
    re.compile(r"(\w+) was squashed by (.+)"),
]


def parse_line(line: str) -> MinecraftEvent | None:
    """Parse a log line and return an event if relevant."""
    line = line.strip()
    if not line:
        return None

    match = LOG_PATTERN.match(line)
    if not match:
        return None

    _, thread, level, content = match.groups()

    # Only process INFO level from Server thread
    if level != "INFO":
        return None

    # Chat message
    chat_match = CHAT_PATTERN.match(content)
    if chat_match:
        player, message = chat_match.groups()
        return MinecraftEvent(
            event_type=EventType.CHAT,
            player=player,
            message=message,
            raw_line=line,
        )

    # Player join
    join_match = JOIN_PATTERN.match(content)
    if join_match:
        player = join_match.group(1)
        return MinecraftEvent(
            event_type=EventType.JOIN,
            player=player,
            message=None,
            raw_line=line,
        )

    # Player leave
    leave_match = LEAVE_PATTERN.match(content)
    if leave_match:
        player = leave_match.group(1)
        return MinecraftEvent(
            event_type=EventType.LEAVE,
            player=player,
            message=None,
            raw_line=line,
        )

    # Server start
    if START_PATTERN.search(content):
        return MinecraftEvent(
            event_type=EventType.SERVER_START,
            player=None,
            message=None,
            raw_line=line,
        )

    # Server stop
    if STOP_PATTERN.search(content):
        return MinecraftEvent(
            event_type=EventType.SERVER_STOP,
            player=None,
            message=None,
            raw_line=line,
        )

    # Death messages
    for pattern in DEATH_PATTERNS:
        death_match = pattern.match(content)
        if death_match:
            player = death_match.group(1)
            return MinecraftEvent(
                event_type=EventType.DEATH,
                player=player,
                message=content,
                raw_line=line,
            )

    return None


class LogWatcher:
    """Watch Minecraft log file for events."""

    def __init__(self, log_path: str, callback: Callable[[MinecraftEvent], None]):
        self.log_path = log_path
        self.callback = callback
        self._running = False
        self._file_position = 0

    def _process_new_lines(self) -> None:
        """Process new lines from the log file."""
        try:
            with open(self.log_path, encoding="utf-8", errors="replace") as f:
                f.seek(self._file_position)
                for line in f:
                    event = parse_line(line)
                    if event:
                        try:
                            self.callback(event)
                        except Exception as e:
                            logger.exception("Error processing event: %s", e)
                self._file_position = f.tell()
        except FileNotFoundError:
            logger.warning("Log file not found: %s", self.log_path)
            self._file_position = 0
        except Exception as e:
            logger.exception("Error reading log file: %s", e)

    def start(self) -> None:
        """Start watching the log file using watchdog."""
        from watchdog.observers import Observer
        from watchdog.events import FileSystemEventHandler, FileModifiedEvent
        import os

        self._running = True

        # Seek to end of file initially
        if os.path.exists(self.log_path):
            with open(self.log_path, encoding="utf-8") as f:
                f.seek(0, 2)  # Seek to end
                self._file_position = f.tell()

        class LogHandler(FileSystemEventHandler):
            def __init__(handler_self) -> None:
                super().__init__()

            def on_modified(handler_self, event: FileModifiedEvent) -> None:
                # Check if paths match (handle both str and Path objects)
                if str(event.src_path) == str(self.log_path):
                    self._process_new_lines()

        log_dir = os.path.dirname(self.log_path) or "."
        event_handler = LogHandler()
        observer = Observer()
        observer.schedule(event_handler, log_dir, recursive=False)
        observer.start()

        logger.info("Started watching %s", self.log_path)

        try:
            while self._running:
                observer.join(timeout=1)
        finally:
            observer.stop()
            observer.join()

    def stop(self) -> None:
        """Stop watching the log file."""
        self._running = False
