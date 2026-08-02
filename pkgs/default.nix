# Overlay for packages that aren't in nixpkgs, plus any overrides.
#
# This file got a lot smaller after the 2026-07-27 verification pass. Most of
# what looked like it would need packaging is already in nixpkgs — including
# every Tier-1 blocker. What's left is genuinely absent upstream.
{ inputs }:

# `_final` rather than `final`: the overlay signature is conventionally
# `final: prev:` even when the fixpoint argument is unused, and the leading
# underscore is how you tell deadnix that is deliberate.
_final: prev: {

  # ==========================================================================
  # papirus-icon-theme — Gruvbox-yellow folders
  # ==========================================================================
  # Stock Papirus folders are BLUE, which clashes badly with Gruvbox — the
  # symptom is Thunar looking themed apart from every folder icon.
  #
  # The usual fix is the `papirus-folders` CLI, which recolours the theme
  # **in place**. That cannot work here: the icon theme is a read-only
  # /nix/store path, so the tool has nothing it is allowed to write to. It is
  # in systemPackages and is a no-op on this system.
  #
  # nixpkgs exposes the same thing as a build input instead — `color` runs
  # `papirus-folders -t $theme -o -C <color>` inside the derivation, producing
  # a recoloured copy. `yellow` to match `Gruvbox-Yellow-Dark`; `orange` is the
  # other reasonable choice, matching the terminals' gruvbox-orange palette.
  # Full set: adwaita black blue bluegrey breeze brown carmine cyan darkcyan
  # deeporange green grey indigo magenta nordic orange palebrown paleorange
  # pink red teal violet white yaru yellow.
  #
  # Done as an overlay, not at the two call sites, deliberately: the theme is
  # referenced by both `gtk.iconTheme.package` (theme.nix) and systemPackages
  # (desktop.nix), and overriding only one would put two different Papirus
  # derivations on XDG_DATA_DIRS with the folder colour decided by lookup
  # order.
  papirus-icon-theme = prev.papirus-icon-theme.override { color = "yellow"; };

  # ==========================================================================
  # fsel — version override
  # ==========================================================================
  # nixpkgs has fsel 3.1.0; Arch runs 3.6.0 (`fsel --version`, 2026-07-29).
  # This bumps it to match. fsel is your SUPER+Space launcher and its
  # config.toml is written for the current release, so the version matters.
  #
  # If 3.1.0 turns out to be fine, DELETE this block — one less thing to
  # maintain when nixpkgs catches up.
  #
  # The previous version of this override was broken and would have aborted
  # `nixos-install` partway through. It replaced `src` with the release
  # *binary* tarball (fsel-x86_64-unknown-linux-gnu.tar.xz), but nixpkgs builds
  # fsel with `rustPlatform.buildRustPackage` from source — so the cargo vendor
  # step had no Cargo.lock to read and died. Evaluation never caught it,
  # because a build failure is not an evaluation failure.
  #
  # Fixed by overriding with the GitHub *source* for the tag, and regenerating
  # cargoDeps to match. Both hashes were obtained by building.
  fsel = prev.fsel.overrideAttrs (_old: rec {
    version = "3.6.0";
    src = prev.fetchFromGitHub {
      owner = "Mjoyufull";
      repo = "fsel";
      tag = version;
      hash = "sha256-yUenkuZ5ryUSpeGjJPO7xgbMObZ5SeBs8/LKU3ROo4g=";
    };
    cargoDeps = prev.rustPlatform.fetchCargoVendor {
      inherit src;
      hash = "sha256-WmHrMALgP52OJH1acrB7DMgo/8FMgksPyXpeRL9Q7s0=";
    };
  });

  # ==========================================================================
  # gruvbox-gtk-theme — build the variant you actually use
  # ==========================================================================
  # Your GTK theme is `Gruvbox-Yellow-Dark`, named in seven places:
  # gtk-{3,4}.0/settings.ini, the two settings-tiling.ini files,
  # xsettingsd.conf, environment.d/gtk.conf and
  # mango/scripts/system/gtk-apply.sh line 9.
  #
  # The default nixpkgs build produces ONLY Gruvbox-Dark and Gruvbox-Light —
  # verified by building it and listing share/themes. On Arch the yellow
  # variant comes from the AUR build, which passes `-t yellow` to install.sh.
  # Without this override every GTK app silently falls back to Adwaita,
  # because the theme name your config asks for does not exist.
  #
  # The upstream derivation takes the install.sh flags as arguments, so this
  # is a plain override rather than a fork.
  gruvbox-gtk-theme = prev.gruvbox-gtk-theme.override {
    colorVariants = [ "dark" ];
    themeVariants = [ "yellow" ];
  };

  # ==========================================================================
  # Brother MFC-L3740CDW printer driver
  # ==========================================================================
  # Try driverless IPP Everywhere FIRST (see modules/system/printing.nix) —
  # this model supports it and `brlaser` (which IS in nixpkgs) covers most
  # Brother lasers. Only fall back to this if neither works.
  #
  # NOTE: 32-bit (i386) deb, so the CUPS filter binary needs 32-bit libs.
  brother-mfc-l3740cdw = prev.stdenv.mkDerivation rec {
    pname = "brother-mfc-l3740cdw";
    version = "3.5.1-1";

    src = prev.fetchurl {
      url = "https://download.brother.com/welcome/dlf105760/mfcl3740cdwpdrv-${version}.i386.deb";
      hash = "sha256-3weoQ4jJJ9h2fIm0LCyW9yY8dvuGESI26/isdmhzBZY=";
    };

    nativeBuildInputs = with prev; [
      dpkg
      autoPatchelfHook
      makeWrapper
    ];
    buildInputs = with prev; [
      cups
      ghostscript
      perl
      bash
    ];

    unpackPhase = "dpkg-deb -x $src .";

    installPhase = ''
      runHook preInstall
      mkdir -p $out
      cp -r opt $out/ 2>/dev/null || true
      cp -r usr/share $out/share 2>/dev/null || true
      mkdir -p $out/share/cups/model
      find $out/opt -name '*.ppd' -exec cp {} $out/share/cups/model/ \; 2>/dev/null || true
      runHook postInstall
    '';

    meta.description = "Brother MFC-L3740CDW CUPS driver";
    meta.platforms = [ "x86_64-linux" ];
  };

  # ==========================================================================
  # CurseForge (AppImage)
  # ==========================================================================
  curseforge = prev.appimageTools.wrapType2 rec {
    pname = "curseforge";
    version = "1.310.1-35445";
    src = prev.fetchurl {
      url = "https://curseforge.overwolf.com/electron/linux/CurseForge-${version}.AppImage";
      hash = "sha256-9GOk9GNPEYvw8adKny2NYd77KN82i7nVtfYCgWxltkU=";
    };
    extraPkgs = pkgs: with pkgs; [ libsecret ];
    meta.description = "CurseForge mod manager";
  };

  # ==========================================================================
  # Still unpackaged — verified absent from nixpkgs on 2026-07-27
  # ==========================================================================
  #   piavpn-bin          Private Internet Access (proprietary + systemd svc)
  #   freedownloadmanager your torrent/magnet handler
  #   torbrowser-launcher (but `tor-browser` itself IS in nixpkgs — use that)
  #   betterbird          (`thunderbird` 153.0 is in nixpkgs — use that)
  #   quickmedia, pipemixer, r-quick-share, haroopad, mdview, pdf-compress,
  #   qrookie-vrp, phosphor-icons, nerd-fonts-sf-mono
  #
  # PKGBUILDs for several of these are cached in ~/.cache/paru/clone/.
  # Convert a PKGBUILD sha256 to the SRI hash Nix wants with:
  #   echo <hex> | xxd -r -p | base64 -w0
  # then prefix with "sha256-".
  #
  # For the rest: https://aur.archlinux.org/cgit/aur.git/plain/PKGBUILD?h=<pkg>
}
