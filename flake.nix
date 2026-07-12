{
  description = "pi-mono";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    systems.url = "github:nix-systems/default";
    bun2nix.url = "github:nix-community/bun2nix?ref=2.1.0";
    bun2nix.inputs.nixpkgs.follows = "nixpkgs";
    bun2nix.inputs.systems.follows = "systems";
  };

  nixConfig = {
    extra-substituters = [
      "https://pi.cachix.org"
      "https://nix-community.cachix.org"
    ];
    extra-trusted-public-keys = [
      "pi.cachix.org-1:lGeoGJaZ5ZDabuRzkcD5EBTNnDM4HJ1vqeOxlWk1Flk="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
  };

  outputs =
    {
      self,
      nixpkgs,
      systems,
      bun2nix,
    }:
    let
      current = builtins.fromJSON (builtins.readFile ./VERSION.json);
      inherit (current) rev hash;
      inherit (current.projects.coding-agent) npmDepsHash;
      version = nixpkgs.lib.removePrefix "v" rev;

      forEachSystem = nixpkgs.lib.genAttrs (import systems);
    in
    rec {
      packages = forEachSystem (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          bunPkgs = import nixpkgs {
            inherit system;
            overlays = [ bun2nix.overlays.default ];
          };

          src = pkgs.fetchFromGitHub {
            owner = "earendil-works";
            repo = "pi";
            inherit rev hash;
          };

        in
        rec {
          default = coding-agent;

          coding-agent = pkgs.callPackage ./coding-agent/package.nix {
            inherit src version npmDepsHash;
          };
          coding-agent-bun = bunPkgs.callPackage ./coding-agent/package-bun.nix {
            inherit src version;
          };

          docs-md =
            let
              agent = self.lib.mkCodingAgent { inherit pkgs; };
              docs = pkgs.nixosOptionsDoc {
                options = builtins.removeAttrs agent.options [ "_module" ];
              };
            in
            pkgs.runCommand "pi-options.md" { } # bash
              ''
                mkdir -p $out
                cp ${docs.optionsCommonMark} $out/index.md
              '';

          docs-html =
            pkgs.runCommand "pi-options.html" { nativeBuildInputs = [ pkgs.pandoc ]; } # bash
              ''
                mkdir -p $out
                pandoc \
                  --standalone \
                  --metadata title="pi.nix options" \
                  ${docs-md}/index.md \
                  --output $out/index.html
              '';
        }
      );

      lib =
        let
          coding-agent = import ./coding-agent/lib.nix {
            inherit self;
            inherit (nixpkgs) lib;
          };
        in
        {
          inherit (coding-agent) mkCodingAgent;
        };

      nixosModules = rec {
        default = coding-agent;
        coding-agent = import ./coding-agent/module.nix self;
      };

      homeModules = rec {
        default = coding-agent;
        coding-agent = import ./coding-agent/home-manager.nix self;
      };
      homeManagerModules = homeModules;

      overlays = {
        default =
          _final: prev:
          let
            inherit (prev.stdenv.hostPlatform) system;
          in
          {
            pi-coding-agent = self.packages.${system}.coding-agent;
            pi-coding-agent-bun = self.packages.${system}.coding-agent-bun;
          };
      };

      formatter = forEachSystem (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        pkgs.nixfmt
      );

      apps = forEachSystem (
        system:
        let
          pkgs = import nixpkgs { inherit system; };

          syncUpstream = pkgs.writeShellApplication {
            name = "pi-sync-upstream";
            runtimeInputs = with pkgs; [
              bun
              coreutils
              gawk
              git
              gnugrep
              gnused
              jq
              nix
              npm-lockfile-fix
              prefetch-npm-deps
              bun2nix.packages.${system}.bun2nix
            ];
            text = # bash
              ''
                set -euo pipefail

                tmpdir=$(mktemp -d)
                trap 'rm -rf "$tmpdir"' EXIT

                rev=$(git ls-remote --tags --refs https://github.com/earendil-works/pi.git 'v*' \
                  | awk -F/ '{print $3}' \
                  | grep -E '^v[0-9]+(\.[0-9]+)*$' \
                  | sort -V \
                  | tail -n1)
                [[ -n "$rev" ]]

                source=$(nix store prefetch-file --json --unpack \
                  "https://github.com/earendil-works/pi/archive/refs/tags/$rev.tar.gz")
                hash=$(jq -r .hash <<< "$source")
                src=$(jq -r .storePath <<< "$source")

                cp -R "$src"/. "$tmpdir"
                chmod -R u+w "$tmpdir"
                npm-lockfile-fix "$tmpdir/package-lock.json"

                pushd "$tmpdir" >/dev/null
                bun install --ignore-scripts
                bun2nix -o bun.nix
                popd >/dev/null

                sed -i '/^  fetchurl,$/a\  workspaceRoot ? throw "coding-agent/bun.nix requires workspaceRoot (the upstream pi source root)",' "$tmpdir/bun.nix"
                sed -Ei 's|copyPathToStore \.\/packages\/([^ );]+)|copyPathToStore (workspaceRoot + "/packages/\1")|g' "$tmpdir/bun.nix"

                npm_deps_hash=$(prefetch-npm-deps "$tmpdir/package-lock.json" | tail -n1)

                jq \
                  --arg rev "$rev" \
                  --arg hash "$hash" \
                  --arg npmDepsHash "$npm_deps_hash" \
                  '.rev = $rev | .hash = $hash | .projects["coding-agent"].npmDepsHash = $npmDepsHash' \
                  VERSION.json > "$tmpdir/VERSION.json"

                cp "$tmpdir/package-lock.json" package-lock.json
                cp "$tmpdir/bun.lock" bun.lock
                cp "$tmpdir/bun.nix" coding-agent/bun.nix
                cp "$tmpdir/VERSION.json" VERSION.json
                echo "Updated lockfiles and VERSION.json for $rev"
              '';
          };

          regenerateModels = pkgs.writeShellApplication {
            name = "pi-regenerate-models";
            runtimeInputs = with pkgs; [
              coreutils
              jq
              nix
              nodejs
            ];
            text = # bash
              ''
                set -euo pipefail

                tmpdir=$(mktemp -d)
                trap 'rm -rf "$tmpdir"' EXIT

                rev=$(jq -r .rev VERSION.json)
                expected_hash=$(jq -r .hash VERSION.json)
                source=$(nix store prefetch-file --json --unpack \
                  "https://github.com/earendil-works/pi/archive/refs/tags/$rev.tar.gz")
                [[ "$(jq -r .hash <<< "$source")" == "$expected_hash" ]]
                src=$(jq -r .storePath <<< "$source")

                cp -R "$src"/. "$tmpdir"
                chmod -R u+w "$tmpdir"
                cp package-lock.json "$tmpdir/package-lock.json"

                pushd "$tmpdir" >/dev/null
                npm ci --ignore-scripts
                npm run generate-models --workspace=packages/ai
                popd >/dev/null

                generated="$tmpdir/packages/ai/src/models.generated.ts"
                [[ -s "$generated" ]]
                cp "$generated" models.generated.ts
                echo "Updated models.generated.ts for $rev"
              '';
          };

          update = pkgs.writeShellApplication {
            name = "pi-update";
            runtimeInputs = [
              regenerateModels
              syncUpstream
            ];
            text = # bash
              ''
                set -euo pipefail

                pi-sync-upstream
                pi-regenerate-models
              '';
          };

          scan = pkgs.writeShellApplication {
            name = "pi-scan";
            runtimeInputs = with pkgs; [
              gitleaks
              osv-scanner
              zizmor
            ];
            text = # bash
              ''
                set -euo pipefail

                zizmor .github/workflows
                osv-scanner scan source --lockfile package-lock.json
                osv-scanner scan source --lockfile bun.lock
                gitleaks dir --redact .
              '';
          };
        in
        {
          update = {
            type = "app";
            program = "${update}/bin/pi-update";
          };
          sync-upstream = {
            type = "app";
            program = "${syncUpstream}/bin/pi-sync-upstream";
          };
          regenerate-models = {
            type = "app";
            program = "${regenerateModels}/bin/pi-regenerate-models";
          };
          scan = {
            type = "app";
            program = "${scan}/bin/pi-scan";
          };
        }
      );
    };
}
