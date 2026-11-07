{ buildGoModule }:
buildGoModule {
  name = "minecraft-slack-bridge";
  src = ./.;
  vendorHash = "sha256-cVjxIiOBe2cll1ioVJHIiB/+y/PIxcuDGtRchAQgvOQ=";
  meta.mainProgram = "minecraft-slack-bridge";
}
