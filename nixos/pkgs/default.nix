# Overlay for packages that aren't in nixpkgs, plus any overrides.
#
# This file got a lot smaller after the 2026-07-27 verification pass. Most of
# what looked like it would need packaging is already in nixpkgs — including
# every Tier-1 blocker. What's left is genuinely absent upstream.
{ inputs }:

final: prev: {

  # ==========================================================================
  # fsel — version override
  # ==========================================================================
  # nixpkgs has fsel 3.1.0; you're running 3.5.2 on Arch. This bumps it to
  # match, using the URL and checksum from the AUR PKGBUILD.
  #
  # If 3.1.0 is fine for you, DELETE this block — one less thing to maintain
  # when nixpkgs catches up.
  fsel = prev.fsel.overrideAttrs (old: rec {
    version = "3.5.2";
    src = prev.fetchurl {
      url = "https://github.com/Mjoyufull/fsel/releases/download/${version}/fsel-x86_64-unknown-linux-gnu.tar.xz";
      hash = "sha256-MaaRKSxi6inMSWJ8LHtW6EC5YPMaAinsF1oN4Clb0PQ=";
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

    nativeBuildInputs = with prev; [ dpkg autoPatchelfHook makeWrapper ];
    buildInputs = with prev; [ cups ghostscript perl bash ];

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
