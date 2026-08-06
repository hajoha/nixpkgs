{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.ocudu;
  settingsFormat = pkgs.formats.yaml { };
  configFile = settingsFormat.generate "ocudu.yml" cfg.settings;
in
{
  options.services.ocudu = {
    enable = lib.mkEnableOption "the OCUDU 5G NR gNB";

    package = lib.mkPackageOption pkgs "ocudu" { };

    application = lib.mkOption {
      type = lib.types.enum [
        "gnb"
        "ocu"
        "ocucp"
        "ocuup"
        "odu"
      ];
      default = "gnb";
      description = ''
        Which OCUDU application to run. `gnb` is the monolithic gNB; the
        others run individual CU/CU-CP/CU-UP/DU components for a
        disaggregated deployment.
      '';
    };

    settings = lib.mkOption {
      type = lib.types.submodule { freeformType = settingsFormat.type; };
      default = { };
      description = ''
        Configuration written to the OCUDU YAML config file. See
        <https://docs.ocudu.org/user_manual/config_reference/>.
      '';
      example = lib.literalExpression ''
        {
          cu_cp.amf = {
            addr = "127.0.0.1";
            bind_addr = "127.0.0.1";
          };
          ru_sdr = {
            device_driver = "uhd";
            srate = 23.04;
            tx_gain = 50;
            rx_gain = 60;
          };
          cell_cfg = {
            dl_arfcn = 368500;
            band = 3;
            channel_bandwidth_MHz = 20;
          };
        }
      '';
    };

    extraArgs = lib.mkOption {
      type = with lib.types; listOf str;
      default = [ ];
      description = "Extra command-line arguments passed to the application.";
    };

    openFronthaul = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Grant `CAP_NET_RAW`, required for Split 7.2 deployments that send
        Open Fronthaul traffic over raw Ethernet sockets.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # F1, E1, NG and E2 all run over SCTP.
    boot.kernelModules = [ "sctp" ];

    systemd.services.ocudu = {
      description = "OCUDU 5G NR gNB";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];

      serviceConfig = {
        ExecStart = lib.escapeShellArgs (
          [
            "${cfg.package}/bin/${cfg.application}"
            "-c"
            configFile
          ]
          ++ cfg.extraArgs
        );

        Restart = "on-failure";
        RestartSec = 5;

        DynamicUser = true;
        StateDirectory = "ocudu";
        RuntimeDirectory = "ocudu";

        # Realtime scheduling and memory locking are required for the PHY
        # to meet slot deadlines.
        AmbientCapabilities = [
          "CAP_SYS_NICE"
          "CAP_IPC_LOCK"
        ]
        ++ lib.optional cfg.openFronthaul "CAP_NET_RAW";
        CapabilityBoundingSet = [
          "CAP_SYS_NICE"
          "CAP_IPC_LOCK"
        ]
        ++ lib.optional cfg.openFronthaul "CAP_NET_RAW";
        LimitMEMLOCK = "infinity";
        LimitRTPRIO = 99;

        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        PrivateTmp = true;
        RestrictNamespaces = true;
        RestrictRealtime = false; # needed: the PHY uses SCHED_FIFO
        SystemCallArchitectures = "native";
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
          "AF_UNIX"
        ]
        ++ lib.optional cfg.openFronthaul "AF_PACKET";
      };
    };
  };

  meta.maintainers = with lib.maintainers; [ hajoha ];
}
