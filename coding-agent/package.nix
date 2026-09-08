{
  lib,
  stdenv,
  buildNpmPackage,
  makeWrapper,
  nodejs,
  typescript,
  typescript-go,
  pkg-config,
  pixman,
  cairo,
  pango,
  libpng,
  libjpeg,
  giflib,
  librsvg,
  fd,
  gitMinimal,
  openssh,
  ripgrep,
  src,
  version,
  npmDepsHash,
}:
let
  runtimeBins = lib.makeBinPath [
    nodejs
    gitMinimal
    openssh # required for git SSH clones
    ripgrep
    fd
  ];
in
buildNpmPackage {
  pname = "pi-coding-agent";
  inherit src version npmDepsHash;

  nativeBuildInputs = [
    makeWrapper
    pkg-config
    typescript
    typescript-go
  ];

  buildInputs = [
    pixman
    cairo
    pango
    libpng
    libjpeg
    giflib
    librsvg
    fd
  ];

  postPatch = ''
    cp ${../package-lock.json} package-lock.json
  '';

  preBuild = ''
    find packages -name "package.json" -exec sed -i \
      -e 's/--watch --preserveWatchOutput//g' \
      {} \;

    for f in packages/ai/src/models.ts packages/agent/src/agent.ts packages/tui/src/utils.ts; do
      [ -f "$f" ] && echo '// @ts-nocheck' | cat - "$f" > tmp && mv tmp "$f"
    done

    changelogReplacement='`https://github.com/earendil-works/pi/blob/v''${newVersion}/packages/coding-agent/CHANGELOG.md`'
    for changelogUrl in \
      '"https://github.com/badlogic/pi-mono/blob/main/packages/coding-agent/CHANGELOG.md"' \
      '"https://github.com/earendil-works/pi-mono/blob/main/packages/coding-agent/CHANGELOG.md"'
    do
      if grep -qF "$changelogUrl" packages/coding-agent/src/modes/interactive/interactive-mode.ts; then
        substituteInPlace packages/coding-agent/src/modes/interactive/interactive-mode.ts \
          --replace-fail "$changelogUrl" "$changelogReplacement"
      fi
    done

    cp ${../ai/models.generated.ts} packages/ai/src/models.generated.ts
    cp -R ${../ai/providers}/. packages/ai/src/providers/

    # Live catalogs may omit an API that the provider still implements. Pin
    # the full stream union so inference does not reject the extra handler.
    cloudflareGatewayProvider=packages/ai/src/providers/cloudflare-ai-gateway.ts
    if grep -qF 'return createProvider({' "$cloudflareGatewayProvider"; then
      substituteInPlace "$cloudflareGatewayProvider" \
        --replace-fail \
          'return createProvider({' \
          $'return createProvider<\n\t\t"anthropic-messages" | "openai-completions" | "openai-responses"\n\t>({'
    fi

    # Generated catalogs can retain completion-only xAI models after upstream
    # narrows its provider to Responses, so keep each model on its declared API.
    xaiProvider=packages/ai/src/providers/xai.ts
    if grep -q '"openai-completions"' packages/ai/src/providers/data/xai.json \
      && grep -q 'Provider<"openai-responses">' "$xaiProvider"
    then
      substituteInPlace "$xaiProvider" \
        --replace-fail \
          'import { openAIResponsesApi } from "../api/openai-responses.lazy.ts";' \
          $'import { openAICompletionsApi } from "../api/openai-completions.lazy.ts";\nimport { openAIResponsesApi } from "../api/openai-responses.lazy.ts";' \
        --replace-fail \
          'export function xaiProvider(): Provider<"openai-responses"> {' \
          'export function xaiProvider(): Provider<"openai-completions" | "openai-responses"> {' \
        --replace-fail \
          'api: openAIResponsesApi(),' \
          $'api: {\n\t\t\t"openai-completions": openAICompletionsApi(),\n\t\t\t"openai-responses": openAIResponsesApi(),\n\t\t},'
    fi

    substituteInPlace packages/ai/package.json \
      --replace-fail 'npm run generate-models && ' '''
  '';

  buildPhase = ''
    runHook preBuild
    npm run build:offline
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin $out/lib/node_modules/@earendil-works

    for pkg in tui telemetry ai agent protocol client coding-agent mom pods; do
      [ -d "packages/$pkg/dist" ] || continue
      mkdir -p "$out/lib/node_modules/@earendil-works/pi-$pkg"
      cp -r packages/$pkg/dist/* "$out/lib/node_modules/@earendil-works/pi-$pkg/"
      cp packages/$pkg/package.json "$out/lib/node_modules/@earendil-works/pi-$pkg/"
    done

    cp -rL node_modules/. "$out/lib/node_modules/"

    makeWrapper ${nodejs}/bin/node $out/bin/pi \
      --add-flags "$out/lib/node_modules/@earendil-works/pi-coding-agent/dist/cli.js" \
      --set PI_PACKAGE_DIR "$out/lib/node_modules/@earendil-works/pi-coding-agent" \
      --prefix NODE_PATH : "$out/lib/node_modules" \
      --suffix PATH : "${runtimeBins}" \
      --run 'export NPM_CONFIG_PREFIX="''${NPM_CONFIG_PREFIX:-''${XDG_DATA_HOME:-$HOME/.local/share}/pi/npm}"'
    runHook postInstall
  '';

  meta = {
    description = "Pi - a minimal terminal coding harness";
    homepage = "https://github.com/earendil-works/pi";
    license = lib.licenses.mit;
    mainProgram = "pi";
    maintainers = [
      {
        name = "Lukas";
        email = "me@lukasl.dev";
        github = "lukasl-dev";
      }
    ];
  };
}
