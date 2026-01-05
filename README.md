# Numcraft

The Numtide Minecraft server. Yes, this is serious :)

## How to Join

Requirements:

- A Minecraft Java Edition license. Get it on <https://minecraft.net>.
- A machine with Nix installed.

### Server Config

1. Find your UUID on <https://mcuuid.net/>
2. Add yourself to the whitelist in `inventory/numcraft.nix`
3. Send a PR and get it deployed

### Client Config

1. Run `nix run nixpkgs#prismlauncher`
2. Login to Microsoft
3. Click "Add Instance", pick 1.21.8 and NeoForge. Ok.
4. Click "1.21.8", click "Edit" and go to Mods.
5. Download mods:
   - CC: Tweaked
   - Simple Voice Chat
6. Launch
7. Add a new server with address "arcade1.m.ntd.one"
8. Connect!

## Components

- **NeoForge 21.8.49** - Modded Minecraft server
- **Slack Bridge** - Bidirectional chat bridge between Minecraft and Slack

### Server Mods

- JEI (Just Enough Items)
- Simple Voice Chat
- No Chat Reports
- Distant Horizons
- Lithium (performance)
- CC: Tweaked (ComputerCraft)
- Ferrite Core (memory optimization)
- Servercore (performance)
- Alternate Current (redstone optimization)

## Clan Module Usage

Add to your flake inputs:

```nix
numcraft = {
  url = "path:./projects/numcraft";
  inputs.nixpkgs.follows = "nixpkgs";
  inputs.flake-parts.follows = "flake-parts";
};
```

Import the flake module:

```nix
imports = [
  inputs.numcraft.flakeModules.default
];
```

Configure in inventory:

```nix
inventory.instances."numcraft" = {
  module.name = "@numtide/numcraft";
  module.input = "self";

  roles.default.machines."your-machine" = {
    settings = {
      whitelist = {
        player_name = "uuid";
      };
      slackChannelId = "C...";
      slackUserMapping = {
        SLACK_USER_ID = "minecraft_username";
      };
    };
  };
};
```
