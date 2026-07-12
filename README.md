# pi.nix

<p align="center">
  <a href="https://lukasl-dev.github.io/pi.nix/">
    <img src="https://img.shields.io/badge/options-5277C3?style=for-the-badge&logo=nixos&logoColor=white" alt="Options">
  </a>
  <a href="https://app.cachix.org/cache/pi">
    <img src="https://img.shields.io/badge/cache-Cachix-5277C3?style=for-the-badge&logo=nixos&logoColor=white" alt="Cachix cache">
  </a>
</p>

A Nix flake for [pi](https://github.com/earendil-works/pi), the terminal coding agent.

It provides:

- packages for `nix run` / `nix build`
- a default npm-built package and an optional Bun-built variant
- NixOS and Home Manager modules
- an overlay exposing `pkgs.pi-coding-agent` and `pkgs.pi-coding-agent-bun`
- `lib.mkCodingAgent` for building a configured wrapper

> [!IMPORTANT]
> This is not the official Nix flake for pi (there isn't one). See [earendil-works/pi#2310](https://github.com/earendil-works/pi/issues/2310) for context.

## Quick start

```bash
nix run github:lukasl-dev/pi.nix --accept-flake-config
```

Or build it locally:

```bash
nix build .#coding-agent --accept-flake-config
```

To build the Bun-based variant instead:

```bash
nix build .#coding-agent-bun --accept-flake-config
```

## Usage

```nix
{
  inputs.pi.url = "github:lukasl-dev/pi.nix";
}
```

### Binary cache

Build results are pushed to [pi.cachix.org](https://pi.cachix.org), and the Bun toolchain is fetched through the nix-community cache used by `bun2nix`. The flake declares both substituters and public keys via `nixConfig`, so consumers can use `--accept-flake-config` or configure them explicitly:

```nix
nix.settings = {
  extra-substituters = [
    "https://pi.cachix.org"
    "https://nix-community.cachix.org"
  ];
  extra-trusted-public-keys = [
    "pi.cachix.org-1:lGeoGJaZ5ZDabuRzkcD5EBTNnDM4HJ1vqeOxlWk1Flk="
    "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
  ];
};
```

### NixOS

```nix
{ inputs, config, ... }:
{
  imports = [ inputs.pi.nixosModules.default ];

  programs.pi.coding-agent = {
    enable = true;
    # rules = ''Be concise.'';
    # skills = [ ./skills/my-skill ];
    # extensions = [ ./extensions/my-extension.ts ];
    # themes = [ ./themes/catppuccin-mocha.json ];
    # promptTemplates = [ ./prompts ];
    # models = ./models.json;
    # settings = {
    #   model = "gpt-5";
    # };
    # extraArgs = [ "--provider" "openai" "--model" "gpt-5" ];
    # environment.PI_CODING_AGENT_DIR = "/path/to/pi-agent";
    # environment.OPENAI_API_KEY = ./openai-api-key;
  };
}
```

### Home Manager

```nix
{ inputs, config, ... }:
{
  imports = [ inputs.pi.homeModules.default ];

  programs.pi.coding-agent = {
    enable = true;
    # rules = ''Be concise.'';
    # skills = [ ./skills/my-skill ];
    # models = ./models.json;
    # settings.model = "gpt-5";
    # environment.PI_CODING_AGENT_DIR = "${config.home.homeDirectory}/.pi/agent";
    # environment.OPENAI_API_KEY = ./openai-api-key;
  };
}
```

### Overlay

```nix
{ inputs, pkgs, ... }:
{
  nixpkgs.overlays = [ inputs.pi.overlays.default ];
  environment.systemPackages = [
    pkgs.pi-coding-agent
    # or pkgs.pi-coding-agent-bun
  ];
}
```

### Custom package

```nix
{ inputs, pkgs, ... }:
let
  pi = inputs.pi.lib.mkCodingAgent {
    inherit pkgs;
    modules = [{
      pi.coding-agent = {
        rules = ''Be concise.'';
        skills = [ ./skills/my-skill ];
        extraArgs = [ "--provider" "openai" "--model" "gpt-5" ];
      };
    }];
  };
in
pi.package
```

### Selecting the Bun package

The NixOS/Home Manager modules still default to the npm-built package. To opt into the Bun-built variant, set `package` explicitly:

```nix
{ inputs, pkgs, ... }:
{
  programs.pi.coding-agent.package = inputs.pi.packages.${pkgs.system}.coding-agent-bun;
}
```

## Options

Common options under `programs.pi.coding-agent` / `pi.coding-agent` are listed below. See the [full option reference](https://lukasl-dev.github.io/pi.nix/) for details:

- `enable`
- `package`
- `rules`
- `skills`
- `extensions`
- `themes`
- `promptTemplates`
- `models`
- `extraArgs`
- `environment`
- `settings`

Generate the complete option reference in Markdown or HTML with:

```sh
nix build .#docs-md
nix build .#docs-html
```

The outputs are available at `result/index.md` and `result/index.html`,
respectively.
