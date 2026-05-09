# Generates a Modrinth modpack (.mrpack) for Numcraft
#
# The .mrpack is a ZIP containing modrinth.index.json (mod metadata with
# download URLs and hashes) and overrides/servers.dat (pre-configured server).
# PrismLauncher downloads the mod JARs on import -- no JARs are in the archive.
{ pkgs, lib }:
let
  data = lib.importTOML ../minecraft.toml;
  minecraft = import ../minecraft.nix { inherit pkgs lib; };

  fetchMod =
    _name: info:
    pkgs.fetchurl {
      url = "https://cdn.modrinth.com/data/${info.modrinth_id}/versions/${info.version_id}/${info.filename}";
      hash = info.hash;
    };

  # Only mods that run on the client belong in a client modpack
  clientMods = lib.filterAttrs (name: info: info.client or false) data.mods;

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
    files = lib.mapAttrsToList (name: info: {
      inherit name;
      path = "mods/${info.filename}";
      env = {
        client = "required";
        server = if info.server or false then "required" else "unsupported";
      };
      downloads = [
        "https://cdn.modrinth.com/data/${info.modrinth_id}/versions/${info.version_id}/${info.filename}"
      ];
    }) clientMods;
  };
in
pkgs.runCommand "numcraft.mrpack"
  {
    nativeBuildInputs = [ pkgs.zip pkgs.jq ];
    passAsFile = [ "index" "mods" ];
    mods = builtins.toJSON (lib.mapAttrs fetchMod clientMods);
    index = modrinthIndex;
  }
  ''
    mkdir -p staging/overrides

    cp "$indexPath" staging/modrinth.index.json

    for _mod_name in $(jq --raw-output 'keys | .[]' < "$modsPath") ; do
      printf 'Processing mod %s\n' "$_mod_name"
      _mod_file=$(jq --arg mod_name "$_mod_name" --raw-output '.[$mod_name]' < "$modsPath")
      _sha1=$(( sha1sum | cut -f 1 -d ' ' ) < "$_mod_file")
      _sha512=$(( sha512sum | cut -f 1 -d ' ' ) < "$_mod_file")
      _file_size=$( stat --format %s "$_mod_file")

      jq \
        --arg mod_name "$_mod_name" \
        --arg sha1 "$_sha1" \
        --arg sha512 "$_sha512" \
        --arg file_size "$_file_size" \
        '
          ( .files[] | select(.name == $mod_name) ) |= ( . + {
              "hashes": {
                "sha1": $sha1,
                "sha512": $sha512
              },
              "fileSize": $file_size | tonumber
            } | del(.name) )
        ' < staging/modrinth.index.json > staging/modrinth.index.json.tmp
      mv staging/modrinth.index.json.tmp staging/modrinth.index.json
    done

    cp ${../icon.png} staging/icon.png
    cp ${serversDat} staging/overrides/servers.dat
    (cd staging && zip -r "$out" .)
  ''
