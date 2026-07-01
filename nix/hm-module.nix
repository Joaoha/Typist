# Home-manager module for Typist speech-to-text
#
# Provides a systemd user service for autostart.
# Usage: imports = [ typist.homeManagerModules.default ];
#        services.typist.enable = true;
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.typist;
in
{
  options.services.typist = {
    enable = lib.mkEnableOption "Typist speech-to-text user service";

    package = lib.mkOption {
      type = lib.types.package;
      defaultText = lib.literalExpression "typist.packages.\${system}.typist";
      description = "The Typist package to use.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.user.services.typist = {
      Unit = {
        Description = "Typist speech-to-text";
        After = [ "graphical-session.target" ];
        PartOf = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${cfg.package}/bin/typist";
        Restart = "on-failure";
        RestartSec = 5;
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };
  };
}
