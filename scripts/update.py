"""Compare minecraft.toml with NeoForge and Modrinth, and update it.

  update.py                    report updates for the pinned Minecraft version
  update.py --target 26.3      report which mods have a build for 26.3
  update.py --write            apply the updates to minecraft.toml

A mod with a `hold = "reason"` key in minecraft.toml is skipped.

The NeoForge hash is the hash of the unpacked installer, not of the download,
so --write leaves it empty when the NeoForge version changes: build the server
once and copy the hash that Nix reports.

Exit status: 0 nothing to do, 1 updates exist, 2 a mod has no build for the
target.
"""

import argparse
import base64
import json
import re
import sys
import tomllib
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

MODRINTH = "https://api.modrinth.com/v2"
NEOFORGE = "https://maven.neoforged.net"
STABILITY = {"release": 0, "beta": 1, "alpha": 2}


def get(url: str, **params: str) -> Any:
    if params:
        url += "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers={"User-Agent": "numcraft-update"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.load(resp)


def neoforge_prefix(minecraft: str) -> str:
    """1.21.11 is NeoForge 21.11.x, 26.3 is NeoForge 26.3.x."""
    parts = minecraft.split(".")
    if parts[0] == "1":
        parts = parts[1:]
    return ".".join((parts + ["0"])[:2]) + "."


def latest_neoforge(minecraft: str) -> str | None:
    listing = get(f"{NEOFORGE}/api/maven/versions/releases/net/neoforged/neoforge")
    prefix = neoforge_prefix(minecraft)
    stable = [
        v for v in listing["versions"] if v.startswith(prefix) and "-" not in v
    ]
    return stable[-1] if stable else None


def candidate(mod: dict[str, Any], minecraft: str, channel: str) -> dict[str, Any] | None:
    """The newest build for `minecraft` that is not less stable than `channel`."""
    versions = get(
        f"{MODRINTH}/project/{mod['modrinth_id']}/version",
        loaders='["neoforge"]',
        game_versions=json.dumps([minecraft]),
    )
    allowed = [
        v for v in versions if STABILITY[v["version_type"]] <= STABILITY[channel]
    ]
    return max(allowed, key=lambda v: v["date_published"], default=None)


def sri(hex_digest: str) -> str:
    return "sha512-" + base64.b64encode(bytes.fromhex(hex_digest)).decode()


def set_key(text: str, table: str, key: str, value: str) -> str:
    pattern = re.compile(
        rf'(^\[{re.escape(table)}\]\n(?:(?!^\[).*\n)*?^{key} = )"[^"]*"', re.M
    )
    text, count = pattern.subn(lambda m: f'{m.group(1)}"{value}"', text, count=1)
    if count != 1:
        raise SystemExit(f"cannot find {key} in [{table}]")
    return text


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--file", type=Path, default=Path("minecraft.toml"))
    parser.add_argument("--target", help="Minecraft version, default: the pinned one")
    parser.add_argument("--write", action="store_true")
    args = parser.parse_args()

    text = args.file.read_text()
    data = tomllib.loads(text)
    pinned = data["neoforge"]["minecraft_version"]
    target = args.target or pinned

    ids = [mod["version_id"] for mod in data["mods"].values()]
    current = {v["id"]: v for v in get(f"{MODRINTH}/versions", ids=json.dumps(ids))}

    updates = 0
    missing = 0

    neoforge = latest_neoforge(target)
    if neoforge is None:
        print(f"neoforge: no release for {target}")
        missing += 1
    elif neoforge != data["neoforge"]["version"]:
        print(f"neoforge: {data['neoforge']['version']} -> {neoforge}")
        updates += 1
        if args.write:
            url = f"{NEOFORGE}/releases/net/neoforged/neoforge/{neoforge}/neoforge-{neoforge}-installer.jar"
            text = set_key(text, "neoforge", "minecraft_version", target)
            text = set_key(text, "neoforge", "version", neoforge)
            text = set_key(text, "neoforge", "url", url)
            text = set_key(text, "neoforge", "hash", "")
    else:
        print(f"neoforge: {neoforge} is current")

    for name, mod in data["mods"].items():
        if "hold" in mod:
            print(f"{name}: held, {mod['hold']}")
            continue
        now = current.get(mod["version_id"])
        channel = now["version_type"] if now else "alpha"
        new = candidate(mod, target, channel)
        if new is None:
            print(f"{name}: no {channel} or better build for {target}")
            missing += 1
        elif new["id"] == mod["version_id"]:
            print(f"{name}: current")
        elif now and target == pinned and new["date_published"] <= now["date_published"]:
            print(f"{name}: current")
        else:
            file = next(f for f in new["files"] if f["primary"])
            print(f"{name}: {mod['filename']} -> {file['filename']}")
            updates += 1
            if args.write:
                table = f"mods.{name}"
                text = set_key(text, table, "version_id", new["id"])
                text = set_key(text, table, "filename", file["filename"])
                text = set_key(text, table, "hash", sri(file["hashes"]["sha512"]))

    print(f"\n{target}: {updates} updates, {missing} without a build")
    if args.write and updates and not missing:
        args.file.write_text(text)
        print(f"wrote {args.file}")
    return 2 if missing else 1 if updates else 0


if __name__ == "__main__":
    sys.exit(main())
