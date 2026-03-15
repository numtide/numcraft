# Minecraft configuration loaded from minecraft.toml
{ pkgs, lib }:
let
  data = lib.importTOML ./minecraft.toml;
  fetchMod =
    _name: info:
    pkgs.fetchurl {
      url = "https://cdn.modrinth.com/data/${info.modrinth_id}/versions/${info.version_id}/${info.filename}";
      hash = info.hash;
    };

  filterMods = pred: lib.mapAttrs fetchMod (lib.filterAttrs (_name: pred) data.mods);

  neoforgeServer = pkgs.stdenv.mkDerivation {
    pname = "neoforge-server";
    version = data.neoforge.version;

    src = pkgs.fetchurl {
      url = data.neoforge.url;
      hash = data.neoforge.hash;

      nativeBuildInputs = [
        pkgs.jdk
        pkgs.perl5Packages.strip-nondeterminism
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

  serverMods = filterMods (info: info.server or false);
  clientMods = filterMods (info: info.client or false);

  serversDat =
    pkgs.runCommand "servers-dat"
      {
        nativeBuildInputs = [ (pkgs.python3.withPackages (ps: [ ps.nbtlib ])) ];
      }
      ''
        python3 << 'EOF'
        import os
        from nbtlib import File, Compound, List, String, Byte

        servers = File(gzipped=False)
        servers["servers"] = List[Compound]([
            Compound({
                "name": String("${data.server.name}"),
                "ip": String("${data.server.address}"),
                "acceptTextures": Byte(1),
            })
        ])

        servers.save(os.environ["out"])
        EOF
      '';
in
{
  inherit neoforgeServer serversDat;

  minecraftVersion = data.neoforge.minecraft_version;
  neoforgeVersion = data.neoforge.version;
  serverName = data.server.name;
  serverAddress = data.server.address;

  server = {
    mods = serverMods;
    modList = lib.attrValues serverMods;
  };

  client = {
    mods = clientMods;
    modList = lib.attrValues clientMods;
  };
}
