# Overlay for packages absent from nixpkgs, plus overrides.
{ inputs }:

# `final`, not `_final`: `lockscreen` below composes `lock-backgrounds` from
# this same overlay, and only the fixpoint argument sees it.
final: prev: {

  # ==========================================================================
  # papirus-icon-theme — Gruvbox-yellow folders
  # ==========================================================================
  # The `papirus-folders` CLI recolours in place and cannot touch a store path;
  # `color` is the same thing at build time. An overlay, not a call-site
  # override — two references would otherwise put two Papirus derivations on
  # XDG_DATA_DIRS with the colour decided by lookup order.
  papirus-icon-theme = prev.papirus-icon-theme.override { color = "yellow"; };

  # ==========================================================================
  # fsel — version override
  # ==========================================================================
  # nixpkgs has 3.1.0; our config.toml is written for 3.6.0. Delete once nixpkgs
  # catches up. Override the GitHub source, not the release tarball —
  # buildRustPackage needs a Cargo.lock, and only a build catches its absence.
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
  # gruvbox-gtk-theme — vendored; nixpkgs removed it
  # ==========================================================================
  # Dropped 2026-07-22 for depending on gtk-engine-murrine (GTK2). That was only
  # a `propagatedUserEnvPkgs` entry serving the theme's gtk-2.0/ files, so the
  # GTK3/4 CSS this system actually uses is unaffected — the upstream repo is
  # unchanged. Builds `Gruvbox-Yellow-Dark` only, which is the one name
  # theme.nix, gtk-apply.sh and $GTK_THEME ask for.
  gruvbox-gtk-theme = prev.stdenvNoCC.mkDerivation {
    pname = "gruvbox-gtk-theme";
    version = "0-unstable-2025-10-23";

    src = prev.fetchFromGitHub {
      owner = "Fausto-Korpsvart";
      repo = "Gruvbox-GTK-Theme";
      rev = "578cd220b5ff6e86b078a6111d26bb20ec8c733f";
      hash = "sha256-RXoPj/aj9OCTIi8xWatG0QpDAUh102nFOipdSIiqt7o=";
    };

    nativeBuildInputs = [ prev.sassc ];
    buildInputs = [ prev.gnome-themes-extra ];
    dontBuild = true;

    postPatch = "patchShebangs themes/install.sh";

    installPhase = ''
      runHook preInstall
      mkdir -p $out/share/themes
      cd themes
      ./install.sh -n Gruvbox -c dark -t yellow -d "$out/share/themes"
      runHook postInstall
    '';

    meta = {
      description = "GTK theme based on the Gruvbox colour palette";
      homepage = "https://github.com/Fausto-Korpsvart/Gruvbox-GTK-Theme";
      license = prev.lib.licenses.gpl3Plus;
      platforms = prev.lib.platforms.unix;
    };
  };

  # ==========================================================================
  # Brother MFC-L3740CDW printer driver
  # ==========================================================================
  # Unused — driverless IPP Everywhere works (printing.nix). Kept as fallback.
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
  # lock-backgrounds — the swaylock background pool
  # ==========================================================================
  # A pool rather than one image: the member is chosen per lock (docs/adr/0018).
  # Seeds are fixed, so which images exist is reproducible even though which one
  # gets used is not.
  #
  # 1920x1200 is the panel's native mode, and is load-bearing — see blocks.py.
  lock-backgrounds = prev.stdenv.mkDerivation {
    pname = "lock-backgrounds";
    version = "1";

    dontUnpack = true;
    nativeBuildInputs = [
      prev.python3
      prev.imagemagick
    ];

    buildPhase = ''
      runHook preBuild
      mkdir -p pool
      for i in $(seq 1 24); do
        python3 ${./lock-backgrounds/blocks.py} \
          --grid 12x8 --steps 9 --seed "$i" \
          --stops '#222222,#282828,#2e2e2e' \
          --out block.ppm
        magick block.ppm -filter Point -resize '1920x1200!' \
          "pool/$(printf 'lock-%02d' "$i").png"
      done
      runHook postBuild
    '';

    # The floor. A pool that generated wrong is invisible at lock time — the
    # screen just looks slightly off — and every wrong version so far looked
    # plausible, so check both properties the eye actually reads.
    #
    # Neutrality is exact: a tinted ramp is what "the colour still doesn't feel
    # right" turned out to be, and #282828 is R=G=B.
    #
    # The mean is a tolerance, not an equality. The ramp is symmetric about 40,
    # but 96 blocks drawn from 9 tones vary by ±1 through sampling alone — an
    # exact test fails on roughly one seed in four. ±1 still catches a shifted
    # band, which is the failure worth catching: earlier attempts sat at 54
    # and 70.
    doCheck = true;
    checkPhase = ''
      runHook preCheck
      n=$(find pool -name '*.png' | wc -l)
      [ "$n" -eq 24 ] || { echo "pool has $n members, expected 24" >&2; exit 1; }
      for f in pool/*.png; do
        mean=$(magick "$f" -format '%[fx:int(mean*255)]' info:)
        [ "$mean" -ge 39 ] && [ "$mean" -le 41 ] ||
          { echo "$f: mean $mean, expected 40±1 (#282828)" >&2; exit 1; }

        tinted=$(magick "$f" -unique-colors txt: |
          grep -oE '#[0-9A-F]{6}' |
          awk '{ if (substr($0,2,2) != substr($0,4,2) ||
                    substr($0,4,2) != substr($0,6,2)) n++ } END { print n+0 }')
        [ "$tinted" -eq 0 ] ||
          { echo "$f: $tinted non-neutral tones — the ramp is tinted" >&2; exit 1; }
      done
      runHook postCheck
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p "$out/share/lock-backgrounds"
      cp pool/*.png "$out/share/lock-backgrounds/"
      runHook postInstall
    '';

    meta.description = "Blocky Gruvbox background pool for swaylock";
  };

  # ==========================================================================
  # lockscreen — swaylock with a background picked per lock
  # ==========================================================================
  # Deliberately NOT named `swaylock`. A wrapper of that name would land earlier
  # in PATH and shadow swaylock-effects, which is the exact trap that makes
  # `programs.swaylock.package = null` load-bearing. docs/gotchas.md → swaylock.
  lockscreen = prev.writeShellApplication {
    name = "lockscreen";
    runtimeInputs = [ prev.swaylock-effects ];
    text = ''
      # nullglob so an empty pool yields an empty array rather than the literal
      # glob — otherwise the fallback below never fires and swaylock is handed a
      # path with a `*` in it.
      shopt -s nullglob
      pool=(${final.lock-backgrounds}/share/lock-backgrounds/*.png)

      # A lock that will not start is worse than a plain one, so an empty pool
      # falls back to the solid `color` still set in the swaylock config.
      if [ ''${#pool[@]} -eq 0 ]; then
        exec swaylock "$@"
      fi

      exec swaylock -i "''${pool[RANDOM % ''${#pool[@]}]}" "$@"
    '';
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
