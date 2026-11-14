{ self }:
{ lib, ... }:
{
  _class = "clan.service";
  manifest.name = "@numtide/numcraft";
  manifest.readme = "Numtide Minecraft server with a Slack chat bridge.";

  roles.default = {
    description = "Runs the Minecraft server and the Slack bridge.";
    interface = {
      options = {
        slackChannelId = lib.mkOption {
          type = lib.types.str;
          description = "Slack channel ID to bridge messages to/from";
          example = "C09R5MZU346";
        };

        memory = {
          min = lib.mkOption {
            type = lib.types.strMatching "[1-9][0-9]*[MG]";
            default = "1G";
            description = "Start size of the Java heap of the server (-Xms)";
          };

          max = lib.mkOption {
            type = lib.types.strMatching "[1-9][0-9]*[MG]";
            default = "2G";
            description = "Largest size of the Java heap of the server (-Xmx)";
          };
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
            minecraft = import ./minecraft.nix { inherit pkgs lib; };
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
              ${lib.concatMapStringsSep "\n" (
                mod: "ln -s ${mod} /var/lib/minecraft/mods"
              ) minecraft.server.modList}

              # A copy, not a link: the server refuses data packs behind a
              # symbolic link that allowed_symlinks.txt does not list.
              mkdir -p /var/lib/minecraft/world/datapacks
              rm -rf /var/lib/minecraft/world/datapacks/numcraft
              cp -r --no-preserve=mode ${./datapack} /var/lib/minecraft/world/datapacks/numcraft

              # Server icon (resized to 64x64)
              ${pkgs.imagemagick}/bin/convert ${./icon.png} -resize 64x64 /var/lib/minecraft/server-icon.png

              # Set RCON password from secrets
              rcon_password=$(cat "${config.clan.core.vars.generators."minecraft-rcon".files."password".path}")
              ${pkgs.gnused}/bin/sed -i "s|^rcon.password=.*|rcon.password=$rcon_password|" /var/lib/minecraft/server.properties
            '';

            # Voice chat UDP port
            networking.firewall.allowedUDPPorts = [ 24454 ];

            # Not openFirewall: it opens rcon.port too. RCON has no transport
            # encryption and no rate limit, and the bridge reaches it on
            # loopback.
            networking.firewall.allowedTCPPorts = [ 25565 ];

            services.minecraft-server = {
              enable = true;
              eula = true;
              package = minecraft.neoforgeServer;
              jvmOpts = lib.mkForce "";

              declarative = true;

              whitelist = minecraft.whitelist;

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
                # Never pause: a paused server loads no chunk, so a command sent
                # through RCON while no player is online cannot change the world.
                pause-when-empty-seconds = -1;
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

            # The bridge has its own user. From the server it gets only the
            # log directory, through the group minecraft-logs: the directory
            # is setgid, so each log file gets that group, and with a mask of
            # 0077 the server would create them unreadable for it.
            users.groups.minecraft-logs = { };
            users.groups.minecraft-slack-bridge = { };
            users.users.minecraft-slack-bridge = {
              isSystemUser = true;
              group = "minecraft-slack-bridge";
              extraGroups = [ "minecraft-logs" ];
            };
            systemd.tmpfiles.rules = [
              "d /var/lib/minecraft/logs 2750 minecraft minecraft-logs -"
            ];
            # Not jvmOpts: the unit puts those after the program name, where the
            # start script hands them to the game, not to the JVM. Without a
            # heap size the JVM takes a quarter of the memory of the host.
            systemd.services.minecraft-server.environment.JDK_JAVA_OPTIONS =
              "-Xms${settings.memory.min} -Xmx${settings.memory.max}";

            systemd.services.minecraft-server.serviceConfig.UMask = lib.mkForce "0027";

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
              # The server waits forever for open RCON client threads on
              # shutdown, and the bridge keeps one open. Without partOf, a
              # stop with the bridge connected runs into the stop timeout
              # and SIGKILL. With it and After=, systemd stops the bridge
              # first.
              partOf = [ "minecraft-server.service" ];
              wantedBy = [
                "multi-user.target"
                "minecraft-server.service"
              ];

              environment = {
                SLACK_BOT_TOKEN_FILE = "%d/slack-bot-token";
                SLACK_APP_TOKEN_FILE = "%d/slack-app-token";
                RCON_PASSWORD_FILE = "%d/rcon-password";
                SLACK_CHANNEL_ID = settings.slackChannelId;
                USER_MAPPING_FILE = pkgs.writers.writeJSON "user-mapping.json" settings.slackUserMapping;
                RCON_HOST = "127.0.0.1";
                RCON_PORT = "25575";
                MINECRAFT_LOG_PATH = "/run/minecraft-logs/latest.log";
              };

              serviceConfig = {
                Type = "simple";
                User = "minecraft-slack-bridge";
                Group = "minecraft-slack-bridge";

                # The directory and not the file: the server starts a new
                # latest.log at each start.
                BindReadOnlyPaths = [ "/var/lib/minecraft/logs:/run/minecraft-logs" ];
                InaccessiblePaths = [ "/var/lib/minecraft" ];

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

                CapabilityBoundingSet = "";
                LockPersonality = true;
                MemoryDenyWriteExecute = true;
                NoNewPrivileges = true;
                PrivateDevices = true;
                PrivateTmp = true;
                ProtectClock = true;
                ProtectControlGroups = true;
                ProtectHome = true;
                ProtectHostname = true;
                ProtectKernelLogs = true;
                ProtectKernelModules = true;
                ProtectKernelTunables = true;
                ProtectProc = "invisible";
                ProtectSystem = "strict";
                # AF_UNIX is for name resolution through nscd
                RestrictAddressFamilies = [
                  "AF_INET"
                  "AF_INET6"
                  "AF_UNIX"
                ];
                RestrictNamespaces = true;
                RestrictRealtime = true;
                RestrictSUIDSGID = true;
                SystemCallArchitectures = "native";
                SystemCallFilter = [
                  "@system-service"
                  "~@privileged"
                ];
                SystemCallErrorNumber = "EPERM";
                UMask = "0077";
              };
            };
          };
      };
  };
}
