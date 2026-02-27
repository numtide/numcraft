{
  description = "Numcraft - Numtide's Minecraft server";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  inputs.flake-parts.url = "github:hercules-ci/flake-parts";

  outputs =
    {
      self,
      nixpkgs,
      flake-parts,
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
        default = client;
      });

      overlays.default = final: prev: {
        numcraft-client = final.callPackage ./client/package.nix { };
        numcraft-slack-bridge = final.callPackage ./slack-bridge/package.nix { };
      };

      flakeModules.default = flake-parts.lib.importApply ./flake-module.nix { inherit self; };
    };
}
