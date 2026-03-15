# Numcraft client launcher
{
  pkgs,
  lib,
  fjordlauncher-packages,
}:
let
  minecraft = import ../minecraft.nix { inherit pkgs lib; };

  inherit (minecraft) serversDat serverAddress;

  # Patch Fjord Launcher to remove the MSA account gate
  fjordlauncher-unwrapped-patched =
    fjordlauncher-packages.fjordlauncher-unwrapped.overrideAttrs
      (old: {
        patches = (old.patches or [ ]) ++ [ ./remove-msa-gate.patch ];
      });
  fjordlauncher = fjordlauncher-packages.fjordlauncher.override {
    fjordlauncher-unwrapped = fjordlauncher-unwrapped-patched;
  };

  # Instance configuration for Fjord Launcher
  instanceCfg = pkgs.writeText "instance.cfg" ''
    [General]
    ConfigVersion=1.2
    iconKey=default
    name=Numcraft
    InstanceType=OneSix
    JoinServerOnLaunch=true
    JoinServerOnLaunchAddress=${serverAddress}
  '';

  # MMC pack configuration
  mmcPackJson = pkgs.writeText "mmc-pack.json" (
    builtins.toJSON {
      formatVersion = 1;
      components = [
        {
          uid = "net.minecraft";
          version = minecraft.minecraftVersion;
          important = true;
        }
        {
          uid = "net.neoforged";
          version = minecraft.neoforgeVersion;
        }
      ];
    }
  );

  # Wrapper script
  wrapperScript = pkgs.writeShellScript "numcraft-client" ''
    set -euo pipefail

    # XDG Base Directory Specification
    : "''${XDG_DATA_HOME:=$HOME/.local/share}"

    instance_dir="$XDG_DATA_HOME/FjordLauncher/instances/Numcraft"
    minecraft_dir="$instance_dir/.minecraft"
    mods_dir="$minecraft_dir/mods"

    # Create instance directory structure
    mkdir -p "$instance_dir"
    mkdir -p "$minecraft_dir"
    mkdir -p "$mods_dir"

    # Copy instance configuration (overwrite each time to stay in sync)
    # Use --no-preserve=all so files are writable (Fjord Launcher needs to modify these)
    cp -f --no-preserve=all "${instanceCfg}" "$instance_dir/instance.cfg"
    cp -f --no-preserve=all "${mmcPackJson}" "$instance_dir/mmc-pack.json"

    # Set up servers.dat (writable for in-game edits)
    cp -f --no-preserve=all "${serversDat}" "$minecraft_dir/servers.dat"

    # Clear and set up mods directory with symlinks
    find "$mods_dir" -type l -delete 2>/dev/null || true
    ${lib.concatMapStringsSep "\n" (mod: ''
      ln -sf "${mod}" "$mods_dir/"
    '') minecraft.client.modList}

    echo "Numcraft instance configured at: $instance_dir"
    echo "Mods installed: ${toString (lib.length minecraft.client.modList)}"
    echo ""
    echo "NOTE: You must own a Minecraft license. Log in with your Microsoft"
    echo "account first, then add the Drasl auth server account."
    echo ""
    echo "Launching Fjord Launcher..."

    exec "${fjordlauncher}/bin/fjordlauncher" --launch Numcraft "$@"
  '';
in
pkgs.stdenv.mkDerivation {
  pname = "numcraft-client";
  version = minecraft.minecraftVersion;

  dontUnpack = true;

  installPhase = ''
    mkdir -p $out/bin
    cp ${wrapperScript} $out/bin/numcraft-client
  '';

  meta = {
    description = "Numcraft Minecraft client with pre-configured mods";
    mainProgram = "numcraft-client";
  };
}
