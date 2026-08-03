{
  python3,
}:
let
  python = python3.withPackages (ps: [
    ((ps.slack-bolt.override {
      pyramid = ps.pyramid.overridePythonAttrs (old: {
        build-system = [
          ps.setuptools_80
        ];
      });
    }).overridePythonAttrs (old: {
      build-system = [
        ps.setuptools_80
      ];
    }))
    ps.slack-sdk
    ps.watchdog
  ]);
in
python.pkgs.buildPythonApplication {
  pname = "minecraft-slack-bridge";
  version = "0.1.0";
  format = "other";

  src = ./src;

  dontBuild = true;

  installPhase = ''
    mkdir -p $out/lib/minecraft-slack-bridge $out/bin
    cp -r . $out/lib/minecraft-slack-bridge/

    cat > $out/bin/minecraft-slack-bridge << EOF
    #!${python}/bin/python
    import sys
    sys.path.insert(0, "$out/lib/minecraft-slack-bridge")
    from minecraft_slack_bridge.main import main
    main()
    EOF
    chmod +x $out/bin/minecraft-slack-bridge
  '';

  meta = {
    description = "Bidirectional Minecraft to Slack bridge";
    mainProgram = "minecraft-slack-bridge";
  };
}
