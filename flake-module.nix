{ self }:
{ flake-parts-lib, ... }:
{
  clan.modules."@numtide/numcraft" = flake-parts-lib.importApply ./clan-module.nix { inherit self; };
}
