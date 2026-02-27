# Generates a Modrinth modpack (.mrpack) for Numcraft
#
# The .mrpack is a ZIP containing modrinth.index.json (mod metadata with
# download URLs and hashes) and overrides/servers.dat (pre-configured server).
# PrismLauncher downloads the mod JARs on import -- no JARs are in the archive.
{ pkgs, lib }:
let
  data = lib.importTOML ../minecraft.toml;
  minecraft = import ../minecraft.nix { inherit pkgs lib; };

  # Only mods that run on the client belong in a client modpack
  clientMods = lib.filterAttrs (_: info: info.client or false) data.mods;

  inherit (minecraft) serversDat;

  modrinthIndex = builtins.toJSON {
    formatVersion = 1;
    game = "minecraft";
    versionId = "1.0.0";
    name = "Numcraft";
    dependencies = {
      minecraft = data.neoforge.minecraft_version;
      neoforge = data.neoforge.version;
    };
    files = lib.mapAttrsToList (_: info: {
      path = "mods/${info.filename}";
      hashes = {
        sha1 = info.sha1;
        sha512 = info.sha512;
      };
      env = {
        client = "required";
        server = if info.server or false then "required" else "unsupported";
      };
      downloads = [
        "https://cdn.modrinth.com/data/${info.modrinth_id}/versions/${info.version_id}/${info.filename}"
      ];
      fileSize = info.file_size;
    }) clientMods;
  };
in
pkgs.runCommand "numcraft.mrpack"
  {
    nativeBuildInputs = [ pkgs.zip ];
    passAsFile = [ "index" ];
    index = modrinthIndex;
  }
  ''
    mkdir -p staging/overrides
    cp "$indexPath" staging/modrinth.index.json
    cp ${serversDat} staging/overrides/servers.dat
    (cd staging && zip -r "$out" .)
  ''
