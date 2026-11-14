{
  description = "Numcraft - Numtide's Minecraft server";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  inputs.flake-parts.url = "github:hercules-ci/flake-parts";
  inputs.clan-core.url = "git+https://git.clan.lol/clan/clan-core";
  inputs.clan-core.inputs.nixpkgs.follows = "nixpkgs";

  outputs =
    {
      self,
      nixpkgs,
      flake-parts,
      ...
    }:
    let
      inherit (nixpkgs) lib;
      forAllSystems =
        f: lib.genAttrs lib.systems.flakeExposed (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAllSystems (pkgs: rec {
        slack-bridge = pkgs.callPackage ./slack-bridge/package.nix { };
        client = pkgs.callPackage ./client/package.nix { };
        mrpack = pkgs.callPackage ./mrpack/package.nix { };
        update = pkgs.writers.writePython3Bin "numcraft-update" {
          flakeIgnore = [ "E501" ];
        } (builtins.readFile ./scripts/update.py);
        default = client;
      });

      overlays.default = final: prev: {
        numcraft-client = final.callPackage ./client/package.nix { };
        numcraft-slack-bridge = final.callPackage ./slack-bridge/package.nix { };
      };

      checks = lib.genAttrs [ "x86_64-linux" ] (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        lib.optionalAttrs pkgs.stdenv.isLinux {
          server-start = import ./checks/server-start {
            inherit pkgs self;
          };
        }
      );

      ci = lib.genAttrs [ "x86_64-linux" ] (system: {
        inherit (self.packages.${system}) client mrpack slack-bridge update;
        inherit (self.checks.${system}) server-start;
      });

      flakeModules.default = flake-parts.lib.importApply ./flake-module.nix { inherit self; };
    };
}
