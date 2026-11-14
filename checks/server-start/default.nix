{ pkgs, self }:
let
  inherit (pkgs) lib;

  minecraftVersion = (lib.importTOML ../../minecraft.toml).neoforge.minecraft_version;

  # The clan service, applied by hand. clan-core's own test harness merges
  # the test directory in a derivation and reads it back during evaluation,
  # and nixbot does not build during evaluation.
  service = import ../../clan-module.nix { inherit self; } { inherit lib; };
  instance = service.roles.default.perInstance {
    settings = {
      slackChannelId = "C000000000";
      slackUserMapping = { };
    };
  };

  secret = "test-secret";

  # Stands in for clan vars: every declared file exists and holds `secret`.
  vars =
    { config, lib, ... }:
    {
      options.clan.core.vars.generators = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule (
            { name, ... }:
            let
              generator = name;
            in
            {
              freeformType = lib.types.attrsOf lib.types.anything;
              options.files = lib.mkOption {
                type = lib.types.attrsOf (
                  lib.types.submodule (
                    { name, ... }:
                    {
                      freeformType = lib.types.attrsOf lib.types.anything;
                      options.path = lib.mkOption {
                        type = lib.types.str;
                        default = "/etc/vars/${generator}/${name}";
                      };
                    }
                  )
                );
              };
            }
          )
        );
      };

      config.environment.etc = lib.concatMapAttrs (
        generator: g:
        lib.mapAttrs' (
          file: _:
          lib.nameValuePair "vars/${generator}/${file}" {
            text = secret;
            mode = "0444";
          }
        ) g.files
      ) config.clan.core.vars.generators;
    };
in
pkgs.testers.runNixOSTest {
  name = "server-start";

  nodes.server = {
    imports = [
      instance.nixosModule
      vars
    ];
    environment.systemPackages = [ pkgs.mcrcon ];
    virtualisation.memorySize = 4096;
    virtualisation.cores = 2;
  };

  nodes.client.environment.systemPackages = [ pkgs.mcstatus ];

  testScript = ''
    start_all()
    server.wait_for_unit("minecraft-server.service")
    # the RCON listener starts last, after the world is loaded
    server.wait_for_open_port(25575)

    # the Slack bridge has no Slack here, but it polls RCON all the same
    server.wait_until_succeeds(
        "journalctl -u minecraft-server.service | grep -F 'RCON Client /127.0.0.1'"
    )

    players = server.succeed("mcrcon -H 127.0.0.1 -P 25575 -p ${secret} list")
    assert "players online" in players, players

    status = client.succeed("mcstatus server:25565 status")
    print(status)
    assert "${minecraftVersion}" in status, status

    def rcon(command):
        return server.succeed(f"mcrcon -H 127.0.0.1 -P 25575 -p ${secret} '{command}'")

    def expect(command, text):
        out = rcon(command)
        assert text in out, f"{command}: {out}"

    expect("datapack list enabled", "file/numcraft")
    # the load function ran, and the dimension exists
    expect("execute in numcraft:lab run forceload query 0 0", "is marked for force loading")
    expect("function numcraft:tick", "Running function numcraft:tick")

    def passes(command):
        server.wait_until_succeeds(
            f"mcrcon -H 127.0.0.1 -P 25575 -p ${secret} '{command}' | grep -F 'Test passed'", timeout=60
        )

    # The traveller is an armor stand: the test has no game client. It has
    # armor and hand slots, so it goes through the same save, wipe and restore
    # functions as a player.
    me = "execute as @e[tag=traveller]"
    vault = "execute in numcraft:vault"
    rcon("execute in minecraft:overworld run forceload add 0 0")
    passes("execute in minecraft:overworld if loaded 8 100 8")
    passes(f"{vault} if loaded 0 1 0")
    rcon("execute in minecraft:overworld positioned 8 100 8 run function numcraft:portal/set_hub")
    rcon("execute in minecraft:overworld run summon minecraft:armor_stand 8 100 8 {Tags:[\"traveller\"],NoGravity:1b}")
    rcon("item replace entity @e[tag=traveller,limit=1] armor.head with minecraft:diamond_helmet")
    rcon("item replace entity @e[tag=traveller,limit=1] weapon.offhand with minecraft:torch 5")
    passes(f"{me} at @s if dimension minecraft:overworld")

    # a vault that holds items with no traveller in the lab: no entry, nothing wiped
    rcon(f"{me} run function numcraft:lab/allocate")
    rcon(f"{vault} run setblock 0 1 0 minecraft:barrel")
    rcon(f"{vault} run item replace block 0 1 0 container.0 with minecraft:stone")
    print(rcon(f"{me} run function numcraft:portal/to_lab"))
    passes(f"{me} at @s if dimension minecraft:overworld unless entity @s[tag=numcraft.in_lab] if items entity @s armor.head minecraft:diamond_helmet")
    rcon(f"{vault} run data modify block 0 1 0 Items set value []")
    rcon(f"{me} run scoreboard players set @s numcraft.cooldown 0")

    # entry: the state goes to the vault, the traveller is empty
    print(rcon(f"{me} run function numcraft:portal/to_lab"))
    passes(f"{me} at @s if dimension numcraft:lab if entity @s[tag=numcraft.in_lab]")
    passes(f"{me} unless items entity @s armor.head * unless items entity @s weapon.offhand *")
    passes(f"{vault} if items block 0 2 0 container.9 minecraft:diamond_helmet if items block 0 2 0 container.13 minecraft:torch")

    # exit: what the traveller took in the lab is gone, the state is back, the vault is empty
    rcon("item replace entity @e[tag=traveller,limit=1] armor.chest with minecraft:netherite_chestplate")
    rcon("item replace entity @e[tag=traveller,limit=1] armor.head with minecraft:golden_helmet")
    print(rcon(f"{me} run function numcraft:portal/to_hub"))
    passes(f"{me} at @s if dimension minecraft:overworld unless entity @s[tag=numcraft.in_lab]")
    passes(f"{me} if items entity @s armor.head minecraft:diamond_helmet if items entity @s weapon.offhand minecraft:torch unless items entity @s armor.chest *")
    passes(f"{vault} unless data block 0 1 0 Items[0] unless data block 0 2 0 Items[0] unless data block 0 3 0 Items[0]")

    # a second exit restores nothing: the diamond helmet must not come from an empty vault
    rcon("item replace entity @e[tag=traveller,limit=1] armor.head with minecraft:leather_helmet")
    rcon(f"{me} run function numcraft:lab/leave")
    passes(f"{me} if items entity @s armor.head minecraft:leather_helmet")

    # the macro lines of a function are parsed only when it runs
    xp = rcon(f"{me} run function numcraft:lab/restore_xp {{levels:3,points:2}}")
    print(xp)
    assert "instantiate" not in xp and "Unknown" not in xp and "Incorrect" not in xp, xp


    # a stop with the bridge connected must not run into the stop timeout
    server.succeed("timeout 75 systemctl stop minecraft-server.service")
  '';
}
