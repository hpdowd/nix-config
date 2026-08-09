# Overlay for packages absent from nixpkgs, plus overrides.
{ inputs }:

# `_final` rather than `final`: the overlay signature is `final: prev:` even
# when the fixpoint argument is unused, and the underscore tells deadnix so.
_final: prev: {

  # ==========================================================================
  # papirus-icon-theme — Gruvbox-yellow folders
  # ==========================================================================
  # Stock Papirus folders are blue, which reads as broken against Gruvbox. The
  # usual `papirus-folders` CLI recolours the theme IN PLACE and so cannot work
  # on a read-only store path; nixpkgs exposes the same thing as `color`.
  #
  # An overlay rather than an override at the call sites: both
  # `gtk.iconTheme.package` and systemPackages reference the theme, and
  # overriding one would put two Papirus derivations on XDG_DATA_DIRS with the
  # folder colour decided by lookup order.
  papirus-icon-theme = prev.papirus-icon-theme.override { color = "yellow"; };

  # ==========================================================================
  # fsel — version override
  # ==========================================================================
  # nixpkgs has 3.1.0; the SUPER+Space launcher's config.toml is written for
  # 3.6.0. Delete this block once nixpkgs catches up.
  #
  # Must override the GitHub SOURCE, not the release binary tarball — nixpkgs
  # builds this with buildRustPackage, so a binary src leaves the cargo vendor
  # step with no Cargo.lock. Evaluation does not catch that; only a build does.
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
  # theme.nix and gtk-apply.sh both ask for `Gruvbox-Yellow-Dark`, but the
  # default nixpkgs build produces only Gruvbox-Dark and Gruvbox-Light. Without
  # this the theme name does not exist and every GTK app silently falls back to
  # Adwaita.
  gruvbox-gtk-theme = prev.gruvbox-gtk-theme.override {
    colorVariants = [ "dark" ];
    themeVariants = [ "yellow" ];
  };

  # ==========================================================================
  # Brother MFC-L3740CDW printer driver
  # ==========================================================================
  # Unused — driverless IPP Everywhere works for this model (printing.nix).
  # Kept as the fallback. 32-bit deb, so the CUPS filter needs 32-bit libs.
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
  # Still unpackaged — absent from nixpkgs as of 2026-07-27
  # ==========================================================================
  #   piavpn-bin, freedownloadmanager, betterbird, torbrowser-launcher,
  #   quickmedia, pipemixer, r-quick-share, haroopad, mdview, pdf-compress,
  #   qrookie-vrp, phosphor-icons, nerd-fonts-sf-mono
  #
  # `tor-browser` and `thunderbird` ARE in nixpkgs — prefer those over the
  # launcher/Betterbird if you ever package these.
}
