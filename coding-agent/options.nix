{
  self,
  jail-nix,
  optionPath ? [
    "pi"
    "coding-agent"
  ],
}:
{
  config,
  pkgs,
  lib,
  ...
}:

let
  inherit (pkgs.stdenv.hostPlatform) system;
  inherit (self.packages.${system}) coding-agent;
  cfg = lib.attrByPath optionPath { } config;
in
{
  options = lib.setAttrByPath optionPath {
    package = lib.mkOption {
      type = lib.types.package;
      default = coding-agent;
      description = "The pi coding-agent package to install.";
    };

    jail = {
      enable = lib.mkEnableOption "bubblewrap isolation for pi using jail.nix";

      permissions = lib.mkOption {
        type = lib.types.functionTo (lib.types.listOf lib.types.raw);
        default =
          combinators: with combinators; [
            network
            mount-cwd
          ];
        defaultText =
          lib.literalExpression
            # nix
            ''
              combinators: with combinators; [
                network
                mount-cwd
              ]
            '';
        description = ''
          Additional permissions passed to jail.nix when wrapping pi. The
          default allows model API access and mounts the runtime working
          directory read-write.

          Access to pi's agent configuration directory is always provided
          separately and does not need to be included here. The jail is
          supported only on Linux.
        '';
        example =
          lib.literalExpression # nix
            ''
              combinators: with combinators; [
                network
                mount-cwd
                (add-pkg-deps [
                  pkgs.jq
                  pkgs.gnumake
                  pkgs.python3
                ])
                (try-readonly (noescape "~/.gitconfig"))
              ]
            '';
      };
    };

    models = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Path to a pi models.json file to install in pi's agent configuration
        directory. This defaults to {file}`~/.pi/agent/models.json` and can be
        overridden with `environment.PI_CODING_AGENT_DIR`.
      '';
      example = lib.literalExpression "./models.json";
    };

    rules = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.either lib.types.lines (lib.types.addCheck lib.types.path builtins.isPath)
      );
      default = null;
      description = ''
        Extra instructions to append to pi's system prompt via
        `--append-system-prompt`. This can be inline text or a Nix path.
      '';
      example = lib.literalExpression ''
        ./AGENTS.md
      '';
    };

    extensions = lib.mkOption {
      type = lib.types.listOf (lib.types.either lib.types.path lib.types.str);
      default = [ ];
      description = ''
        Extension paths to pass to pi via repeated `--extension` flags for every invocation.
      '';
    };

    skills = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [ ];
      description = ''
        Skill paths to pass to pi via repeated `--skill` flags for every invocation.
      '';
      example = lib.literalExpression ''
        [
          ./skills/my-skill
          ./skills/nixpkgs
        ]
      '';
    };

    themes = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [ ];
      description = ''
        Theme paths to pass to pi via repeated `--theme` flags for every invocation.
      '';
    };

    promptTemplates = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [ ];
      description = ''
        Prompt template paths to pass to pi via repeated `--prompt-template` flags for every invocation.
      '';
    };

    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Extra raw CLI arguments to always append when launching pi.
      '';
      example = lib.literalExpression ''
        [ "--provider" "openai" "--model" "gpt-5" ]
      '';
    };

    environment = lib.mkOption {
      type =
        let
          attrs = lib.types.submodule {
            freeformType = lib.types.attrsOf (
              lib.types.either lib.types.str (lib.types.addCheck lib.types.path builtins.isPath)
            );

            options.PI_CODING_AGENT_DIR = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = ''
                Directory pi uses for its agent configuration.
                Corresponds to the `PI_CODING_AGENT_DIR` environment variable.
              '';
              example = lib.literalExpression ''"''${config.home.homeDirectory}/.pi/agent"'';
            };
          };
        in
        lib.types.nullOr ((lib.types.either lib.types.path attrs) // { inherit (attrs) getSubOptions; });
      default = null;
      description = ''
        Extra environment to set before launching pi.

        This can either be a shell environment file that is sourced with `set -a`,
        or an attribute set mapping environment variable names to values. Strings are
        exported directly, while the contents of Nix paths are exported.
      '';
      example = lib.literalExpression ''
        {
          PI_CODING_AGENT_DIR = "/home/user/.pi/agent";
          OPENAI_API_KEY = ./openai-api-key;
        }
      '';
    };

    settings = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = ''
        Contents of `settings.json` in pi's agent configuration directory.
        The directory can be overridden with `environment.PI_CODING_AGENT_DIR`.
      '';
    };

    finalRules = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      internal = true;
      readOnly = true;
    };

    finalArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      internal = true;
      readOnly = true;
    };

    finalPackage = lib.mkOption {
      type = lib.types.package;
      internal = true;
      readOnly = true;
    };
  };

  config = lib.setAttrByPath optionPath (
    let
      inherit (cfg)
        package
        jail
        models
        rules
        extensions
        skills
        themes
        promptTemplates
        extraArgs
        environment
        settings
        ;

      pathFlags =
        flag: paths:
        lib.concatMap (path: [
          flag
          "${path}"
        ]) paths;

      rulesPath =
        if rules == null then
          null
        else if builtins.isPath rules then
          rules
        else
          pkgs.writeText "pi-AGENTS.md" rules;

      resourceArgs =
        (lib.optionals (rulesPath != null) [
          "--append-system-prompt"
          "${rulesPath}"
        ])
        ++ pathFlags "--skill" skills
        ++ pathFlags "--extension" extensions
        ++ pathFlags "--theme" themes
        ++ pathFlags "--prompt-template" promptTemplates;

      envPrelude = lib.optionalString (environment != null) (
        if lib.isAttrs environment && !lib.isDerivation environment then
          lib.concatLines (
            lib.mapAttrsToList (
              name: value: # bash
              if builtins.isPath value then
                ''
                  export ${name}="$(cat ${lib.escapeShellArg "${value}"})"
                ''
              else
                ''
                  export ${name}=${lib.escapeShellArg value}
                ''
            ) (lib.filterAttrs (_name: value: value != null) environment)
          )
        else
          ''
            set -a
            . ${lib.escapeShellArg "${environment}"}
            set +a
          ''
      );

      configDirPrelude = lib.optionalString (models != null || settings != { }) ''
        PI_CODING_AGENT_DIR="''${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"
      '';

      jailConfigDirRuntime =
        let
          runtimeDefault = ''"''${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"'';
        in
        if
          environment != null
          && lib.isAttrs environment
          && !lib.isDerivation environment
          && environment.PI_CODING_AGENT_DIR != null
        then
          "agent_dir=${lib.escapeShellArg environment.PI_CODING_AGENT_DIR}"
        else if environment != null && (!lib.isAttrs environment || lib.isDerivation environment) then
          ''
            agent_dir="$(${pkgs.runtimeShell} -c '
              exec 3>&1
              set -a
              . ${lib.escapeShellArg "${environment}"} >&2
              set +a
              printf %s "''${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}" >&3
            ')"
          ''
        else
          "agent_dir=${runtimeDefault}";

      modelsPrelude =
        lib.optionalString (models != null) # bash
          ''
            if [ -L "$PI_CODING_AGENT_DIR/models.json" ]; then
              rm "$PI_CODING_AGENT_DIR/models.json"
            fi
            if [ ! -f "$PI_CODING_AGENT_DIR/models.json" ]; then
              mkdir -p "$PI_CODING_AGENT_DIR"
              install -m 0600 ${models} "$PI_CODING_AGENT_DIR/models.json"
            fi
          '';

      settingsPath =
        if settings == { } then null else pkgs.writeText "pi-settings.json" (builtins.toJSON settings);

      settingsPrelude =
        lib.optionalString (settingsPath != null) # bash
          ''
            settings_file="$PI_CODING_AGENT_DIR/settings.json"

            if [ -L "$settings_file" ]; then
              rm "$settings_file"
            fi

            mkdir -p "$PI_CODING_AGENT_DIR"
            tmp="$(mktemp "$PI_CODING_AGENT_DIR/settings.json.XXXXXX")"

            if [ -f "$settings_file" ]; then
              ${lib.getExe pkgs.jq} -s '.[0] * .[1]' "$settings_file" ${lib.escapeShellArg settingsPath} > "$tmp"
            else
              printf '%s\n' '{}' | ${lib.getExe pkgs.jq} -s '.[0] * .[1]' - ${lib.escapeShellArg settingsPath} > "$tmp"
            fi

            chmod 0600 "$tmp"

            if [ ! -f "$settings_file" ] || ! cmp -s "$tmp" "$settings_file"; then
              mv "$tmp" "$settings_file"
            else
              rm "$tmp"
            fi
          '';

      argsStr = lib.concatMapStringsSep " " lib.escapeShellArg resourceArgs;
      extraArgsStr = lib.concatMapStringsSep " " lib.escapeShellArg extraArgs;

      wrapped =
        if
          resourceArgs == [ ]
          && environment == null
          && models == null
          && settingsPath == null
          && extraArgs == [ ]
        then
          package
        else
          pkgs.writeShellScriptBin "pi" # bash
            ''
              ${envPrelude}
              ${configDirPrelude}
              ${modelsPrelude}
              ${settingsPrelude}

              case "''${1-}" in install|remove|uninstall|update|list|config)
                  exec ${lib.escapeShellArg (lib.getExe package)} "$@"
                  ;;
                *)
                  exec ${lib.escapeShellArg (lib.getExe package)} ${argsStr} ${extraArgsStr} "$@"
                  ;;
              esac
            '';
    in
    {
      finalRules = rulesPath;
      finalArgs = resourceArgs ++ extraArgs;
      finalPackage =
        if jail.enable && !pkgs.stdenv.hostPlatform.isLinux then
          throw "pi.coding-agent.jail is supported only on Linux"
        else if jail.enable then
          let
            jailBuilder = jail-nix.lib.init pkgs;
            inherit (jailBuilder) combinators;
            configPermission = combinators.compose [
              (combinators.add-runtime ''
                ${jailConfigDirRuntime}
                case "$agent_dir" in
                  /*) ;;
                  *) agent_dir="$PWD/$agent_dir" ;;
                esac
                mkdir -p -- "$agent_dir"
                agent_dir_source="$(realpath "$agent_dir")"
                RUNTIME_ARGS+=(--bind "$agent_dir_source" "$agent_dir")
              '')
              (combinators.try-fwd-env "PI_CODING_AGENT_DIR")
            ];
            permissions = jail.permissions combinators ++ [ configPermission ];
          in
          jailBuilder "pi" wrapped permissions
        else
          wrapped;
    }
  );
}
