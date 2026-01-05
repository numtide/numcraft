{ self }:
{ lib, ... }:
{
  _class = "clan.service";
  manifest.name = "@numtide/numcraft";

  roles.default = {
    interface = {
      options = {
        whitelist = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          description = "Mapping of Minecraft usernames to UUIDs. Use https://mcuuid.net/ to find UUIDs.";
          example = {
            "zimbatm" = "8c5dfdf0-ffa0-4379-9e46-873c882d1929";
          };
        };

        slackChannelId = lib.mkOption {
          type = lib.types.str;
          description = "Slack channel ID to bridge messages to/from";
          example = "C09R5MZU346";
        };

        slackUserMapping = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          description = "Mapping of Slack user IDs to Minecraft usernames";
          example = {
            U1UFT3X3J = "zimbatm";
          };
        };
      };
    };

    perInstance =
      { settings, ... }:
      {
        nixosModule =
          { config, pkgs, ... }:
          let
            mods = [
              (pkgs.fetchurl {
                url = "https://cdn.modrinth.com/data/u6dRKJwZ/versions/ru8HioLg/jei-1.21.8-neoforge-24.2.0.6.jar";
                hash = "sha256-Kp5xYAy+G/+5R7K5Sf896Z6bgYEJ7lsV5fBDFa2hmVg=";
              })
              (pkgs.fetchurl {
                url = "https://cdn.modrinth.com/data/9eGKb6K1/versions/ET1xgBsF/voicechat-neoforge-1.21.8-2.6.6.jar";
                hash = "sha256-vSGVUip2GkaEAOaU1vEt+DMUCTslTri041oEzWGF8w8=";
              })
              (pkgs.fetchurl {
                url = "https://cdn.modrinth.com/data/qQyHxfxd/versions/yi6EjUqr/NoChatReports-NEOFORGE-1.21.8-v2.15.0.jar";
                hash = "sha256-fTTdxBTNNznAuo5t0TMHyKaVSIqeXUJSYyT+sV4/E3Y=";
              })
              (pkgs.fetchurl {
                url = "https://cdn.modrinth.com/data/uCdwusMi/versions/iej5xqn2/DistantHorizons-2.3.6-b-1.21.8-fabric-neoforge.jar";
                hash = "sha256-3vvXezWsCJzYI8dUdyw7lPCcfn2ZALvD63Ue32oVmHY=";
              })
              (pkgs.fetchurl {
                url = "https://cdn.modrinth.com/data/gvQqBUqZ/versions/TSzQRFtn/lithium-neoforge-0.18.1%2Bmc1.21.8.jar";
                hash = "sha256-1CA28BKl8HIpItI+Je1ljL30r+Xxp8ndF4zC2lvnJwM=";
              })
              (pkgs.fetchurl {
                url = "https://cdn.modrinth.com/data/gu7yAYhd/versions/dBPmp0IA/cc-tweaked-1.21.8-forge-1.116.1.jar";
                hash = "sha256-ruPrW3kHTM4kAP4c8t5YHrDWfjPnq5+O3R1bTxka60M=";
              })
              (pkgs.fetchurl {
                url = "https://cdn.modrinth.com/data/uXXizFIs/versions/WmGPid1l/ferritecore-8.0.0-neoforge.jar";
                hash = "sha256-HRKv2Ta3n4EW+mLr0lkgCGpF5mpYslVZRaXsSOrj00s=";
              })
              (pkgs.fetchurl {
                url = "https://cdn.modrinth.com/data/4WWQxlQP/versions/LovZDz4w/servercore-neoforge-1.5.14%2B1.21.8.jar";
                hash = "sha256-Iu3wCNOOfDQLOApXbC9mm0DjDk4kELZxUmYIcVm5QTs=";
              })
              (pkgs.fetchurl {
                url = "https://cdn.modrinth.com/data/r0v8vy1s/versions/KnldqVfO/alternate_current-mc1.21.5-1.9.0.jar";
                hash = "sha256-mdG1zT2Ag0PI8TdajyjdN90z+vOD0BGaaHArckMiv8c=";
              })
            ];

            neoforgeServer = pkgs.stdenv.mkDerivation {
              pname = "neoforge-server";
              version = "21.8.49";
              src = pkgs.fetchurl {
                url = "https://maven.neoforged.net/releases/net/neoforged/neoforge/21.8.49/neoforge-21.8.49-installer.jar";
                hash = "sha256-ZCYIF/pyTrQo0iZeQI75RizU93grq8Paut+QT0soCJY=";

                nativeBuildInputs = [
                  pkgs.jdk
                  pkgs.perl540Packages.strip-nondeterminism
                ];
                downloadToTemp = true;
                postFetch = ''
                  java -jar $downloadedFile --fat-offline --fat $out
                  strip-nondeterminism -t zip $out
                '';
              };

              phases = [
                "buildPhase"
                "fixupPhase"
              ];

              nativeBuildInputs = [
                pkgs.jdk
                pkgs.makeWrapper
              ];

              buildPhase = ''
                java -jar $src --install-server .
              '';

              fixupPhase = ''
                mkdir -p "$out/"{lib,bin,share}

                unix_args="$({ { grep java | tr ' ' '\n' | grep libraries ; } < run.sh ; })"
                unix_args="''${unix_args:1}"
                unix_args="''${unix_args/"libraries/"/"$out/lib/"}"

                cp -r libraries/. $out/lib/

                cp -r run.sh $out/bin/minecraft-server
                sed -i $out/bin/minecraft-server \
                  -e 's~@user_jvm_args.txt~@'"$out"'/share/jvm_args.txt~' \
                  -e 's~@libraries~@'"$out"'/lib~'
                sed -i "$unix_args" \
                  -e 's~libraries/~'"$out/lib/"'~g' \
                  -e 's~-DlibraryDirectory=libraries~-DlibraryDirectory='"$out/lib"'~'
                touch $out/share/jvm_args.txt
                patchShebangs $out/bin/minecraft-server
                wrapProgram $out/bin/minecraft-server --prefix PATH : "${pkgs.jdk}/bin"
              '';
            };

            slackBridgePackage = self.packages.${pkgs.stdenv.hostPlatform.system}.slack-bridge;
          in
          {
            # RCON password management (used by the Slack bridge)
            clan.core.vars.generators."minecraft-rcon" = {
              files."password".owner = "minecraft";

              runtimeInputs = [ pkgs.pwgen ];

              script = ''
                pwgen -s 32 1 > "$out/password"
              '';
            };

            # Slack bridge secrets
            clan.core.vars.generators."minecraft-slack-bridge" = {
              files."slack-bot-token" = { };
              files."slack-app-token" = { };

              prompts."slack-bot-token" = {
                description = "Slack Bot OAuth Token (xoxb-...)";
                persist = true;
                type = "hidden";
              };

              prompts."slack-app-token" = {
                description = "Slack App-Level Token for Socket Mode (xapp-...)";
                persist = true;
                type = "hidden";
              };
            };

            systemd.services."minecraft-server".preStart = ''
              # Mods installation
              if [ -d "/var/lib/minecraft/mods" ] ; then
                find "/var/lib/minecraft/mods" -mindepth 1 -delete
              else
                mkdir "/var/lib/minecraft/mods"
              fi
              ${lib.concatMapStringsSep "\n" (mod: "ln -s ${mod} /var/lib/minecraft/mods") mods}

              # Set RCON password from secrets
              rcon_password=$(cat "${config.clan.core.vars.generators."minecraft-rcon".files."password".path}")
              ${pkgs.gnused}/bin/sed -i "s|^rcon.password=.*|rcon.password=$rcon_password|" /var/lib/minecraft/server.properties
            '';

            # Voice chat UDP port
            networking.firewall.allowedUDPPorts = [ 24454 ];

            services.minecraft-server = {
              enable = true;
              eula = true;
              openFirewall = true;
              package = neoforgeServer;
              jvmOpts = lib.mkForce "";

              declarative = true;

              whitelist = settings.whitelist;

              serverProperties = {
                accepts-transfers = false;
                allow-flight = false;
                allow-nether = true;
                broadcast-console-to-ops = true;
                broadcast-rcon-to-ops = true;
                bug-report-link = "";
                difficulty = "normal";
                enable-command-block = false;
                enable-jmx-monitoring = false;
                enable-query = false;
                enable-rcon = true;
                enable-status = true;
                enforce-secure-profile = true;
                enforce-whitelist = false;
                entity-broadcast-range-percentage = 100;
                force-gamemode = false;
                function-permission-level = 2;
                gamemode = "survival";
                generate-structures = true;
                generator-settings = "{}";
                hardcore = false;
                hide-online-players = false;
                initial-disabled-packs = "";
                initial-enabled-packs = "vanilla";
                level-name = "world";
                level-seed = "numtide's amazing world";
                level-type = "minecraft:normal";
                log-ips = true;
                max-chained-neighbor-updates = 1000000;
                max-players = 50;
                max-tick-time = 60000;
                max-world-size = 29999984;
                motd = "Numtide Realm";
                network-compression-threshold = 256;
                online-mode = true;
                op-permission-level = 4;
                pause-when-empty-seconds = 60;
                player-idle-timeout = 0;
                prevent-proxy-connections = false;
                pvp = true;
                "query.port" = 25565;
                rate-limit = 0;
                "rcon.password" = ""; # Patched by preStart from secrets
                "rcon.port" = 25575;
                region-file-compression = "deflate";
                require-resource-pack = false;
                resource-pack = "";
                resource-pack-id = "";
                resource-pack-prompt = "";
                resource-pack-sha1 = "";
                server-ip = "";
                server-port = 25565;
                simulation-distance = 10;
                spawn-monsters = true;
                spawn-protection = 16;
                sync-chunk-writes = true;
                text-filtering-config = "";
                text-filtering-version = 0;
                use-native-transport = true;
                view-distance = 10;
                white-list = true;
              };
            };

            # Slack bridge for Numcraft
            systemd.services.minecraft-slack-bridge = {
              description = "Minecraft to Slack bidirectional bridge";
              after = [
                "minecraft-server.service"
                "network-online.target"
              ];
              wants = [
                "network-online.target"
              ];
              wantedBy = [ "multi-user.target" ];

              environment = {
                SLACK_BOT_TOKEN_FILE = "%d/slack-bot-token";
                SLACK_APP_TOKEN_FILE = "%d/slack-app-token";
                RCON_PASSWORD_FILE = "%d/rcon-password";
                SLACK_CHANNEL_ID = settings.slackChannelId;
                USER_MAPPING_FILE = pkgs.writeText "user-mapping.json" (builtins.toJSON settings.slackUserMapping);
                RCON_HOST = "127.0.0.1";
                RCON_PORT = "25575";
                MINECRAFT_LOG_PATH = "/var/lib/minecraft/logs/latest.log";
              };

              serviceConfig = {
                Type = "simple";
                User = "minecraft";
                Group = "minecraft";

                LoadCredential = [
                  "slack-bot-token:${
                    config.clan.core.vars.generators."minecraft-slack-bridge".files."slack-bot-token".path
                  }"
                  "slack-app-token:${
                    config.clan.core.vars.generators."minecraft-slack-bridge".files."slack-app-token".path
                  }"
                  "rcon-password:${config.clan.core.vars.generators."minecraft-rcon".files."password".path}"
                ];

                ExecStart = lib.getExe slackBridgePackage;

                Restart = "always";
                RestartSec = "10s";
              };
            };
          };
      };
  };
}
