{
  description = "Geckium - Chrome-style theme for Firefox, packaged as a wrapped Firefox";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      mkGeckium =
        pkgs:
        pkgs.stdenvNoCC.mkDerivation rec {
          pname = "geckium";
          version = "0.20.21.2";

          src = pkgs.fetchzip {
            url = "https://github.com/Neo-Kitchenfox/Geckium/releases/download/b${version}/Geckium_Public_Beta_1.19.7.zip";
            hash = "sha256-OvtJiCsPVzMl43jjaPZuMvGp9Le5oGuIamzeauCVeSY=";
            stripRoot = false;
          };

          dontBuild = true;
          installPhase = ''
            mkdir -p $out
            cp -r "Profile Folder/chrome" "Profile Folder/chrThemes" $out/
            cp "Firefox Folder/config.js" $out/config.js
          '';

          meta = {
            description = "Firefox CSS/JS mod that recreates Chromium 1-58 UIs";
            homepage = "https://github.com/Neo-Kitchenfox/Geckium";
            license = pkgs.lib.licenses.mit;
          };
        };

      mkAero =
        pkgs:
        pkgs.stdenvNoCC.mkDerivation rec {
          pname = "aero-userchrome";
          version = "2025.04.12";

          src = pkgs.fetchzip {
            url = "https://gitgud.io/souris/aero-userchrome/-/archive/${version}/aero-userchrome-${version}.zip";
            hash = "sha256-cerINUXi0sMNnKAZd4CP9nsm3IerdDJMjdZiXOHyc+s=";
          };

          nativeBuildInputs = [ pkgs.dart-sass ];

          # The repo only ships SCSS; compile each top-level theme entry point
          # (Geckium.scss, Default.scss, ...) next to its sources.
          buildPhase = ''
            runHook preBuild
            cd chrome/Aero
            for f in *.scss; do
              sass --quiet --no-source-map "$f" "''${f%.scss}.css"
            done
            cd ../..
            runHook postBuild
          '';

          installPhase = ''
            mkdir -p $out
            cp -r chrome GTK $out/
          '';

          meta = {
            description = "Windows 7/Vista Aero window frame for Firefox on KDE";
            homepage = "https://gitgud.io/souris/aero-userchrome";
            license = pkgs.lib.licenses.mpl20;
          };
        };

      # Aero is opt-in: `withAero = false` (default) gives plain Geckium.
      mkFirefox =
        pkgs:
        {
          withAero ? false,
          # "7" (default) or "vista"
          aeroStyle ? "7",
        }:
        let
          geckium = mkGeckium pkgs;
          aero = mkAero pkgs;
          firefox = pkgs.wrapFirefox pkgs.firefox-unwrapped {
            # Geckium's install-dir config.js is fx-autoconfig; nixpkgs already
            # sets up autoconfig (mozilla.cfg), so append it there.
            extraPrefsFiles = [ "${geckium}/config.js" ];
            extraAutoConfig = ''
              pref("general.config.sandbox_enabled", false);
            '';
            extraPrefs = pkgs.lib.optionalString withAero ''
              defaultPref("toolkit.legacyUserProfileCustomizations.stylesheets", true);
              defaultPref("widget.gtk.rounded-bottom-corners.enabled", true);
              defaultPref("aero-userchrome.alternative", ${if aeroStyle == "vista" then "true" else "false"});
            '';
          };
          variant = if withAero then "${geckium.version}+aero-${aero.version}" else geckium.version;
          importLine = ''@import url("Aero/Geckium.css"); /* geckium-nix:aero */'';
        in
        assert pkgs.lib.assertOneOf "aeroStyle" aeroStyle [
          "7"
          "vista"
        ];
        pkgs.writeShellScriptBin "geckium-firefox" ''
          set -eu
          profile="''${GECKIUM_PROFILE:-''${XDG_DATA_HOME:-$HOME/.local/share}/geckium/profile}"
          stamp="$profile/.geckium-nix-version"

          mkdir -p "$profile"
          [ -d "$profile/chrThemes" ] || cp -r --no-preserve=mode ${geckium}/chrThemes "$profile/"

          # New Geckium/Aero version or variant: rebuild the chrome folder and
          # clear the startup cache.
          if [ "$(cat "$stamp" 2>/dev/null || true)" != "${variant}" ]; then
            rm -rf "$profile/chrome"
            cp -r --no-preserve=mode ${geckium}/chrome "$profile/"
            ${pkgs.lib.optionalString withAero ''
              cp -r --no-preserve=mode ${aero}/chrome/. "$profile/chrome/"
              printf '\n%s\n' '${importLine}' >> "$profile/chrome/userChrome.css"
            ''}
            rm -rf "$profile/startupCache"
            echo "${variant}" > "$stamp"
          fi

          exec ${firefox}/bin/firefox --profile "$profile" "$@"
        '';
    in
    {
      packages = forAllSystems (pkgs: {
        geckium = mkGeckium pkgs;
        aero-userchrome = mkAero pkgs;
        default = mkFirefox pkgs { };
        geckium-aero = mkFirefox pkgs { withAero = true; };
      });

      # For consumers: inputs.geckium.lib.mkGeckiumFirefox pkgs { withAero = true; aeroStyle = "vista"; }
      lib.mkGeckiumFirefox = mkFirefox;

      homeManagerModules.default = self.homeManagerModules.geckium;
      homeManagerModules.geckium =
        {
          config,
          lib,
          pkgs,
          ...
        }:
        let
          cfg = config.programs.geckium;
        in
        {
          options.programs.geckium = {
            enable = lib.mkEnableOption "Geckium-themed Firefox (installs `geckium-firefox`)";

            withAero = lib.mkEnableOption "the Aero UserChrome window frame (needs the KDE Aero Glass Blur effect)";

            aeroStyle = lib.mkOption {
              type = lib.types.enum [
                "7"
                "vista"
              ];
              default = "7";
              description = "Aero window style.";
            };

            gtkShadow = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = ''
                Add Aero UserChrome's `shadow.css` to `~/.config/gtk-3.0/gtk.css`
                (through `gtk.gtk3.extraCss`). Only used when `withAero` is set.
                Note this applies to every GTK3 client-side-decorated window.
              '';
            };
          };

          config = lib.mkIf cfg.enable {
            home.packages = [
              (mkFirefox pkgs {
                inherit (cfg) withAero aeroStyle;
              })
            ];

            gtk.gtk3.extraCss = lib.mkIf (cfg.withAero && cfg.gtkShadow) (
              builtins.readFile "${mkAero pkgs}/GTK/shadow.css"
            );
          };
        };

      apps = forAllSystems (pkgs: {
        default = {
          type = "app";
          program = "${mkFirefox pkgs { }}/bin/geckium-firefox";
        };
      });

      overlays.default = final: _prev: {
        geckium = mkGeckium final;
        aero-userchrome = mkAero final;
        geckium-firefox = mkFirefox final { };
        geckium-firefox-aero = mkFirefox final { withAero = true; };
      };

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = with pkgs; [
            curl
            unzip
            jq
          ];
        };
      });
    };
}
