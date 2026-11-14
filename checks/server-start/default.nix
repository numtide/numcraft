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

    # a round trip through both portal functions, with an armor stand as the traveller
    rcon("execute in minecraft:overworld run forceload add 0 0")
    server.wait_until_succeeds(
        "mcrcon -H 127.0.0.1 -P 25575 -p ${secret} 'execute in minecraft:overworld if loaded 8 100 8' | grep -F 'Test passed'"
    )
    rcon("execute in minecraft:overworld positioned 8 100 8 run function numcraft:portal/set_hub")
    rcon("execute in minecraft:overworld run summon minecraft:armor_stand 8 100 8 {Tags:[\"traveller\"],NoGravity:1b}")
    in_lab = "execute as @e[tag=traveller] at @s if dimension numcraft:lab"
    in_overworld = "execute as @e[tag=traveller] at @s if dimension minecraft:overworld"
    expect(in_overworld, "Test passed")
    rcon("execute as @e[tag=traveller] run function numcraft:portal/to_lab")
    server.wait_until_succeeds(
        f"mcrcon -H 127.0.0.1 -P 25575 -p ${secret} '{in_lab}' | grep -F 'Test passed'"
    )
    rcon("execute as @e[tag=traveller] run function numcraft:portal/to_hub")
    server.wait_until_succeeds(
        f"mcrcon -H 127.0.0.1 -P 25575 -p ${secret} '{in_overworld}' | grep -F 'Test passed'"
    )

    # a stop with the bridge connected must not run into the stop timeout
    server.succeed("timeout 75 systemctl stop minecraft-server.service")
  '';
}
