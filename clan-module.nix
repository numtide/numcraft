{ self }:
{ lib, ... }:
{
  _class = "clan.service";
  manifest.name = "@numtide/numcraft";

  roles.default = {
    interface = {
      options = {
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
                USER_MAPPING_FILE = pkgs.writers.writeJSON "user-mapping.json" settings.slackUserMapping;
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
