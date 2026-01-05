"""Minecraft RCON client implementation.

Based on the Source RCON protocol:
https://wiki.vg/RCON
"""

import socket
import struct
import logging

logger = logging.getLogger(__name__)

# Packet types
SERVERDATA_AUTH = 3
SERVERDATA_AUTH_RESPONSE = 2
SERVERDATA_EXECCOMMAND = 2
SERVERDATA_RESPONSE_VALUE = 0


class RconError(Exception):
    """RCON communication error."""


class RconClient:
    """Minecraft RCON client."""

    def __init__(self, host: str, port: int, password: str, timeout: float = 10.0):
        self.host = host
        self.port = port
        self.password = password
        self.timeout = timeout
        self._socket: socket.socket | None = None
        self._request_id = 0

    def _next_request_id(self) -> int:
        """Get next request ID."""
        self._request_id = (self._request_id + 1) % 2147483647
        return self._request_id

    def _send_packet(self, packet_type: int, payload: str) -> None:
        """Send a packet to the RCON server."""
        if self._socket is None:
            raise RconError("Not connected")

        request_id = self._next_request_id()
        payload_bytes = payload.encode("utf-8") + b"\x00\x00"
        packet = struct.pack("<ii", request_id, packet_type) + payload_bytes
        length = len(packet)
        packet = struct.pack("<i", length) + packet

        self._socket.sendall(packet)

    def _recv_packet(self) -> tuple[int, int, str]:
        """Receive a packet from the RCON server."""
        if self._socket is None:
            raise RconError("Not connected")

        # Read length
        length_data = self._socket.recv(4)
        if len(length_data) < 4:
            raise RconError("Connection closed")

        (length,) = struct.unpack("<i", length_data)

        # Read the rest of the packet
        data = b""
        while len(data) < length:
            chunk = self._socket.recv(length - len(data))
            if not chunk:
                raise RconError("Connection closed")
            data += chunk

        request_id, packet_type = struct.unpack("<ii", data[:8])
        payload = data[8:-2].decode("utf-8")  # Strip null terminators

        return request_id, packet_type, payload

    def connect(self) -> None:
        """Connect and authenticate with the RCON server."""
        self._socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self._socket.settimeout(self.timeout)

        try:
            self._socket.connect((self.host, self.port))

            # Authenticate
            self._send_packet(SERVERDATA_AUTH, self.password)
            request_id, packet_type, _ = self._recv_packet()

            # Check auth result - request_id of -1 means auth failed
            if request_id == -1:
                raise RconError("Authentication failed")
            if packet_type not in (SERVERDATA_AUTH_RESPONSE, SERVERDATA_RESPONSE_VALUE):
                raise RconError(f"Unexpected packet type: {packet_type}")

            logger.debug("RCON connected to %s:%d", self.host, self.port)

        except Exception:
            self.disconnect()
            raise

    def disconnect(self) -> None:
        """Disconnect from the RCON server."""
        if self._socket:
            try:
                self._socket.close()
            except Exception:
                pass
            self._socket = None

    def command(self, cmd: str) -> str:
        """Execute a command on the server."""
        if self._socket is None:
            self.connect()

        try:
            self._send_packet(SERVERDATA_EXECCOMMAND, cmd)
            _, _, response = self._recv_packet()
            return response
        except Exception as e:
            logger.error("RCON command failed: %s", e)
            self.disconnect()
            raise

    def say(self, message: str) -> None:
        """Send a chat message to the server."""
        # Escape any quotes in the message
        escaped = message.replace("\\", "\\\\").replace('"', '\\"')
        self.command(f"say {escaped}")

    def tellraw(self, player: str, message: dict) -> None:
        """Send a raw JSON message to a player or @a for all."""
        import json

        json_str = json.dumps(message)
        response = self.command(f"tellraw {player} {json_str}")
        if response:
            logger.warning("tellraw response: %s", response)

    def list_players(self) -> list[str]:
        """Get list of online players."""
        response = self.command("list")
        # Response format: "There are X of a max of Y players online: player1, player2"
        # or "There are 0 of a max of Y players online:"
        if ":" in response:
            players_part = response.split(":", 1)[1].strip()
            if players_part:
                return [p.strip() for p in players_part.split(",") if p.strip()]
        return []

    def __enter__(self) -> "RconClient":
        self.connect()
        return self

    def __exit__(self, *args: object) -> None:
        self.disconnect()
