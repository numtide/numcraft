# Numcraft

The Numtide Minecraft server. Yes, this is serious :)

It's a place for meetings (with the voice plugin). It's a place to code with ComputerCraft. And we're also toying with the deployment of Minecraft itself.

Deployed at `arcade1.m.ntd.one`.

## How to Join

Requirements:

- A Minecraft Java Edition license. Get it on <https://minecraft.net>.
- A machine with Nix installed.
- Add yourself to the whitelist (so we don't deal with griefers).

### Join the Whitelist

1. Find your UUID on <https://mcuuid.net/>
2. Add yourself to `whitelist.toml`:
   ```toml
   [players]
   your_username = "your-uuid-here"
   ```
3. Send a PR and get it merged and deployed.

### Client Config

```bash
nix run
```

This launches Prism Launcher with a pre-configured Numcraft instance, with all the mods and server address pre-configured.

On first run, log in to Microsoft and the instance will be ready to play.
