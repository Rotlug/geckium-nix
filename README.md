# Geckium Nix flake

Nix packaging for [Geckium](https://github.com/Neo-Kitchenfox/Geckium), a CSS/JS
mod that makes Firefox look like Chrome 1–58, with optional
[Aero UserChrome](https://gitgud.io/souris/aero-userchrome) (Windows 7/Vista
window frames on KDE).

The flake wraps nixpkgs' Firefox with Geckium's autoconfig and provides a
`geckium-firefox` launcher. On first run it copies Geckium's `chrome/` and
`chrThemes/` into a writable profile at `~/.local/share/geckium/profile`
(override with `$GECKIUM_PROFILE`) and rebuilds `chrome/` and clears the
startup cache whenever the Geckium/Aero version or variant changes. Geckium's
first-run setup window may restart Firefox once or twice.

## Quick start

```sh
nix run github:<you>/<this-repo>               # plain Geckium
nix run github:<you>/<this-repo>#geckium-aero  # Geckium + Aero
```

## Outputs

| Output | What |
| --- | --- |
| `packages.default` | Geckium Firefox launcher |
| `packages.geckium-aero` | Same, with Aero UserChrome |
| `packages.geckium`, `packages.aero-userchrome` | Raw theme files |
| `lib.mkGeckiumFirefox pkgs { withAero; aeroStyle; }` | Build a custom variant (`aeroStyle` = `"7"` or `"vista"`) |
| `overlays.default` | `geckium`, `aero-userchrome`, `geckium-firefox`, `geckium-firefox-aero` |
| `homeManagerModules.default` | Home Manager module (below) |

Aero is entirely optional; nothing Aero-related is used unless you ask for it.

## Aero requirements

Aero UserChrome targets **KDE Plasma** and requires the **Aero Glass Blur**
KWin effect from [AeroThemePlasma](https://gitgud.io/wackyideas/aerothemeplasma).
Install it and enable *Aero Glass Blur* in System Settings → Window Management →
Desktop Effects. This flake does not install it.

Aero also needs a `shadow.css` snippet in `~/.config/gtk-3.0/gtk.css`. The Home
Manager module does that for you (see `gtkShadow`); if you don't use the module,
copy `GTK/shadow.css` from `packages.aero-userchrome` yourself.

## Home Manager

```nix
{
  inputs.geckium.url = "github:<you>/<this-repo>";
  inputs.home-manager.url = "github:nix-community/home-manager";
  # ...
}
```

```nix
# in your home-manager configuration
{ inputs, ... }:
{
  imports = [ inputs.geckium.homeManagerModules.default ];

  programs.geckium = {
    enable = true;
    withAero = true;      # optional, default false
    aeroStyle = "7";      # or "vista"
    gtkShadow = true;     # writes shadow.css via gtk.gtk3.extraCss
  };
}
```

### Using it together with `programs.firefox`

If `programs.firefox.enable = true`, the module sets `programs.firefox.package`
to Geckium's wrapped Firefox (at `mkDefault` priority), and the `geckium-firefox`
launcher runs `programs.firefox.finalPackage`. So your existing `policies`
(e.g. `ExtensionSettings` with uBlock Origin force-installed) apply to Geckium
too. Just enable both:

```nix
{ inputs, ... }:
{
  imports = [ inputs.geckium.homeManagerModules.default ];

  programs.geckium.enable = true; # add withAero = true; for Aero

  programs.firefox = {
    enable = true;
    policies.ExtensionSettings = {
      "*".installation_mode = "blocked";
      "uBlock0@raymondhill.net" = {
        install_url = "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi";
        installation_mode = "force_installed";
      };
    };
  };
}
```

Notes: Geckium runs from its own profile (`~/.local/share/geckium/profile`), so
`programs.firefox.profiles.*` settings do not carry over to it; policies,
`nativeMessagingHosts` and other wrapper-level options do. Your normal
`firefox` binary from `programs.firefox` will also have Geckium's autoconfig
baked in, but without the Geckium profile it looks like stock Firefox.

With `withAero = false` the module only installs the plain Geckium launcher and
leaves your GTK config alone.

Aero's other `about:config` options (`aero-userchrome.force-css-glow`,
`aero-userchrome.modern-chromium-titlebutton-margins`) can be set from
Firefox's `about:config` as described upstream.

## Updating

Bump `version`/URL/`hash` in `flake.nix` (`nix hash file` on the downloaded
archive, or use a fake hash and copy the reported one).
