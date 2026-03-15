{
  description = "Numcraft - Numtide's Minecraft server";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  inputs.flake-parts.url = "github:hercules-ci/flake-parts";
  inputs.clan-core.url = "git+https://git.clan.lol/clan/clan-core";
  inputs.clan-core.inputs.nixpkgs.follows = "nixpkgs";
  inputs.drasl.url = "github:unmojang/drasl";
  inputs.drasl.inputs.nixpkgs.follows = "nixpkgs";
  inputs.fjordlauncher.url = "github:unmojang/FjordLauncher";
  inputs.fjordlauncher.inputs.nixpkgs.follows = "nixpkgs";

  outputs =
    {
      self,
      nixpkgs,
      flake-parts,
      clan-core,
      drasl,
      fjordlauncher,
    }:
    let
      inherit (nixpkgs) lib;
      forAllSystems =
        f: lib.genAttrs lib.systems.flakeExposed (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAllSystems (pkgs: rec {
        slack-bridge = pkgs.callPackage ./slack-bridge/package.nix { };
        client = pkgs.callPackage ./client/package.nix {
          fjordlauncher-packages = fjordlauncher.packages.${pkgs.stdenv.hostPlatform.system};
        };
        mrpack = pkgs.callPackage ./mrpack/package.nix { };
        default = client;
      });

      overlays.default = final: prev: {
        numcraft-client = final.callPackage ./client/package.nix {
          fjordlauncher-packages = fjordlauncher.packages.${final.stdenv.hostPlatform.system};
        };
        numcraft-slack-bridge = final.callPackage ./slack-bridge/package.nix { };
      };

      checks = lib.genAttrs [ "x86_64-linux" "aarch64-linux" ] (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          nixosLib = import (nixpkgs + "/nixos/lib") { };
        in
        lib.optionalAttrs pkgs.stdenv.isLinux {
          server-start = import ./checks/server-start {
            inherit
              pkgs
              nixosLib
              clan-core
              self
              drasl
              ;
          };
        }
      );

      flakeModules.default = flake-parts.lib.importApply ./flake-module.nix { inherit self drasl; };
    };
}
