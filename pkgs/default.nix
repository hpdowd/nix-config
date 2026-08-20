# Overlay for packages absent from nixpkgs, plus overrides.
{ inputs }:

# `final`, not `_final`: `lockscreen` below composes `lock-backgrounds` from
# this same overlay, and only the fixpoint argument sees it.
final: prev:

let
  # The selected scheme, as data. Same `import` the modules use — an overlay
  # runs before any module evaluates, so this is the only way in (docs/adr/0030).
  themeData = import ../modules/home/palette.nix;

  # One of the theme file's `packages.*` entries → a package, or `null` when the
  # name belongs to a toolkit built-in and there is nothing to install.
  #
  # `final.${d.attr}` rather than a lookup table: an attribute that does not
  # exist is an eval error naming the attribute, which is the loud failure this
  # repo wants. `base` is lazy, so the null guard runs first.
  #
  # `final`, not `prev`: `gruvbox-gtk-theme` below is defined by THIS overlay,
  # and `prev` is nixpkgs before it — a theme file naming an attribute the
  # overlay adds would not resolve.
  themePkg =
    d:
    let
      base = if (d.sub or null) == null then final.${d.attr} else final.${d.attr}.${d.sub};
      ov = d.override or { };
    in
    if d.attr == null then
      null
    else if ov == { } then
      base
    else
      base.override ov;
in

{

  # ==========================================================================
  # theme* — the artefacts the palette cannot colour
  # ==========================================================================
  # Rendered SVG widget art, cursor bitmaps and compiled SCSS. No hex reaches
  # them, so the selected theme file NAMES them and this block resolves those
  # names to packages — one place, so a scheme is still one file to add.
  #
  # AN OVERLAY, not call-site overrides: `themeIcons` is a Papirus recolour for
  # two of the four schemes, and two references to `papirus-icon-theme.override`
  # would put two Papirus derivations on XDG_DATA_DIRS with the colour decided
  # by lookup order. That is what this was before, and it is why it stays here.
  #
  # The overlay reads the palette by `import`, which is the same reason
  # `scheme.nix` is a file rather than a home-manager option — an overlay is
  # applied before any module evaluates and cannot see `config.*` (docs/adr/0030).
  #
  # `attr = null` means "no package": the name is a GTK or Kvantum built-in that
  # ships with the toolkit. Resolving it to `null` here is what lets theme.nix
  # and dotfiles.nix set the name without installing anything.
  themeGtk = themePkg themeData.packages.gtk;
  themeKvantum = themePkg themeData.packages.kvantum;
  themeIcons = themePkg themeData.packages.icons;
  themeCursor = themePkg themeData.packages.cursor;

  # The yazi flavor: a `.yazi` PACKAGE — a directory whose entry point is
  # `flavor.toml`. Assembled rather than fetched whole because the upstreams
  # disagree on layout: catppuccin/yazi ships bare per-accent TOMLs under
  # `themes/<variant>/`, yazi-rs/flavors ships one directory per scheme, and the
  # single-scheme repos put `flavor.toml` at their root. The theme file gives the
  # path within its own source, so all three shapes land the same way here.
  #
  # `cp` a single named file rather than the directory: a path renamed upstream
  # then fails the BUILD, where a glob would install nothing and yazi would fall
  # back to its built-in theme with no error anywhere.
  #
  # This replaces a 916-line gruvbox flavor that lived under dotfiles/ as
  # third-party colour *data* — which `checks/static.sh` exempts from the
  # no-stray-hex rule, and which nothing here should have been hand-editing.
  themeYazi =
    let
      y = themeData.packages.yazi;
    in
    prev.runCommand "yazi-flavor-${y.repo}" { } ''
      mkdir -p "$out"
      cp ${
        prev.fetchFromGitHub {
          inherit (y)
            owner
            repo
            rev
            hash
            ;
        }
      }/${y.file} "$out/flavor.toml"
    '';

  # ==========================================================================
  # gruvbox-gtk-theme — the one shipped scheme nixpkgs cannot dress in GTK4
  # ==========================================================================
  # `gruvbox-dark-gtk`, which this replaces, ships gtk-2.0, gtk-3.0 and
  # gtk-3.20 and stops there. GTK4 reads none of those: it ignores
  # `gtk-theme-name` entirely, so home-manager themes it by writing an
  # `@import` of `<theme>/gtk-4.0/gtk.css` into ~/.config/gtk-4.0/gtk.css. That
  # file did not exist, the import failed at parse time, and every
  # GTK4/libadwaita app fell back to Adwaita while GTK3 stayed gruvbox — two
  # toolkits disagreeing, which reads as libadwaita being libadwaita rather
  # than as a fault. docs/gotchas.md → Theming.
  #
  # Nixpkgs has no gruvbox GTK theme that ships gtk-4.0 (`by-name/gr` holds
  # gruvbox-dark-gtk, gruvbox-dark-icons-gtk, gruvbox-kvantum,
  # gruvbox-plus-icons — that is all of them), so this builds upstream's SCSS,
  # the same way nixpkgs builds this author's Everforest theme. It is a
  # derivation, not vendored CSS: a rename upstream fails the build.
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
    dontFixup = true;

    postPatch = ''
      patchShebangs themes/install.sh
    '';

    # One variant, not `--theme all`: nine accents in nine sizes is 5 GB of
    # store for a machine that wears one. `default` is upstream's own gruvbox
    # accent — the `-Yellow` variant is a different colour, not this one.
    installPhase = ''
      runHook preInstall
      mkdir -p "$out/share/themes"
      themes/install.sh \
        --dest "$out/share/themes" \
        --name Gruvbox \
        --theme default \
        --color dark \
        --size standard
      runHook postInstall
    '';

    meta = {
      description = "Gruvbox colour palette for GTK, including GTK4";
      homepage = "https://github.com/Fausto-Korpsvart/Gruvbox-GTK-Theme";
      license = prev.lib.licenses.gpl3Only;
      platforms = prev.lib.platforms.unix;
    };
  };

  # ==========================================================================
  # noctalia-shell — its mango backend still speaks dwl's dead flags
  # ==========================================================================
  # `MangoService.qml` drives mango through `mmsg -s -d <func>`, the dwl-era
  # flag form. mango 0.16 answers `{"error":"unknown command"}` and EXITS 0, so
  # every one of these did nothing and reported nothing — the failure this repo
  # is named for. The launcher was the visible half: picking an app ran
  # `CompositorService.spawn` → `MangoService.spawn` → nothing. docs/adr/0025.
  #
  # A patch, not a settings workaround: there are five call sites and only one
  # is the launcher, and `mmsg dispatch spawn_shell` makes the app a child of
  # MANGO in the session scope rather than of the shell inside
  # `noctalia.service`, where a mode switch would kill it with the bar.
  #
  # `--replace-fail`, so a version bump that renames any of these is a BUILD
  # error. The verbs are checked against mango's own function table by
  # checks/static.sh. `-g -A` and `-s -t` are left alone deliberately — they
  # need a different call shape, not a different spelling (docs/adr/0020).
  noctalia-shell = prev.noctalia-shell.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      substituteInPlace Services/Compositor/MangoService.qml \
        --replace-fail '"mmsg", "-s", "-d",' '"mmsg", "dispatch",' \
        --replace-fail '"mmsg", "-s", "-q"' '"mmsg", "dispatch", "quit"' \
        --replace-fail 'mmsg -s -d ' 'mmsg dispatch '
    '';
  });

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
  # The ramp is centred on the palette's `bg0` rather than on a literal, so the
  # lock screen cannot end up the one surface still wearing the old scheme. Only
  # the centre comes from the palette; ±6 is the spread of the ramp, which is a
  # property of the gradient and not a colour.
  #
  # The ramp varies LIGHTNESS ONLY: all three channels move by the same ±6, so
  # every tone keeps bg0's exact channel offsets and therefore its hue. The
  # check below asserts the offsets are preserved rather than that they are
  # zero — a neutral base satisfies both, a tinted one only the first.
  # docs/adr/0029.
  lock-backgrounds =
    let
      palette = import ../modules/home/palette.nix;
      chan = i: prev.lib.fromHexString (builtins.substring i 2 palette.bg0);
      mid = [
        (chan 0)
        (chan 2)
        (chan 4)
      ];
      # Zero-padded: toHexString 5 is "5", which would build "#555" — a valid
      # colour, a different one, and nothing downstream would object.
      byte =
        v:
        let
          h = prev.lib.toLower (prev.lib.toHexString v);
        in
        if builtins.stringLength h == 1 then "0${h}" else h;
      tone = d: "#" + prev.lib.concatMapStrings (c: byte (c + d)) mid;
      stops = "${tone (-6)},${tone 0},${tone 6}";
      # The per-channel bounds the checkPhase asserts, as shell-safe literals.
      chanName = [
        "r"
        "g"
        "b"
      ];
    in
    prev.stdenv.mkDerivation {
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
            --stops '${stops}' \
            --out block.ppm
          # `-type TrueColor` so the PNG is RGB whatever the palette is. Without
          # it ImageMagick picks the colorspace from CONTENT, and a neutral bg0
          # (gruvbox's #282828 is r=g=b) writes a Gray PNG whose green and blue
          # channels then read as 0 — see the checkPhase below, which that broke.
          magick block.ppm -filter Point -resize '1920x1200!' -type TrueColor \
            "pool/$(printf 'lock-%02d' "$i").png"
        done
        runHook postBuild
      '';

      # The floor. A pool that generated wrong is invisible at lock time — the
      # screen just looks slightly off — and every wrong version so far looked
      # plausible.
      #
      # Bounds come from the same `mid` the ramp is drawn from, so the check
      # cannot go stale against a palette change. Exact per channel for hue,
      # ±1 for the mean because 96 blocks sampled from 9 tones vary that much
      # on their own: docs/adr/0029 argues both.
      #
      # `-colorspace sRGB` on every measurement, belt to `-type TrueColor` above
      # — ImageMagick reports mean.g and mean.b as 0 for an image it calls Gray,
      # so a NEUTRAL palette failed this claiming green was 0.
      # docs/gotchas.md → Theming.
      doCheck = true;
      checkPhase = ''
        runHook preCheck
        n=$(find pool -name '*.png' | wc -l)
        [ "$n" -eq 24 ] || { echo "pool has $n members, expected 24" >&2; exit 1; }
        for f in pool/*.png; do
          ${prev.lib.concatStrings (
            prev.lib.zipListsWith (name: want: ''
              mean=$(magick "$f" -colorspace sRGB -format '%[fx:int(mean.${name}*255)]' info:)
              [ "$mean" -ge ${toString (want - 1)} ] && [ "$mean" -le ${toString (want + 1)} ] ||
                { echo "$f: ${name} mean $mean, expected ${toString want}±1 (${tone 0})" >&2; exit 1; }
            '') chanName mid
          )}
          drifted=$(magick "$f" -colorspace sRGB -unique-colors txt: |
            grep -oE '#[0-9A-F]{6}' |
            awk 'function v(s, i) { return strtonum("0x" substr(s, i, 2)) }
                 { if (v($0,2) - v($0,4) != ${toString (builtins.elemAt mid 0 - builtins.elemAt mid 1)} ||
                       v($0,4) - v($0,6) != ${
                         toString (builtins.elemAt mid 1 - builtins.elemAt mid 2)
                       }) n++ }
                 END { print n+0 }')
          [ "$drifted" -eq 0 ] ||
            { echo "$f: $drifted tones off ${tone 0}'s hue — the ramp shifts colour, not just lightness" >&2; exit 1; }
        done
        runHook postCheck
      '';

      installPhase = ''
        runHook preInstall
        mkdir -p "$out/share/lock-backgrounds"
        cp pool/*.png "$out/share/lock-backgrounds/"
        runHook postInstall
      '';

      meta.description = "Blocky background pool for swaylock, on the palette's base tone";
    };

  # ==========================================================================
  # power-profiles-tlp — the PPD bus name, answered from TLP
  # ==========================================================================
  # TLP and power-profiles-daemon cannot both run (docs/adr/0017), so every
  # client that speaks PPD finds nothing and renders nothing — noctalia's
  # battery panel most visibly. This owns the name and translates.
  # docs/adr/0026; the unit and its `--power-mode` are in modules/system/power.nix.
  #
  # `--replace-fail` on the shebang, so a rewrite of the script that drops it
  # is a build error rather than a daemon that runs under the wrong python.
  power-profiles-tlp =
    let
      python = prev.python3.withPackages (ps: [
        ps.dbus-python
        ps.pygobject3
      ]);
    in
    prev.stdenv.mkDerivation {
      pname = "power-profiles-tlp";
      version = "1";

      dontUnpack = true;
      nativeBuildInputs = [ prev.makeWrapper ];

      installPhase = ''
        runHook preInstall
        install -Dm755 ${./power-profiles-tlp/daemon.py} $out/bin/power-profiles-tlp
        substituteInPlace $out/bin/power-profiles-tlp \
          --replace-fail '#!/usr/bin/env python3' '#!${python}/bin/python3'

        install -Dm644 ${./power-profiles-tlp/dbus-policy.conf} \
          $out/share/dbus-1/system.d/org.freedesktop.UPower.PowerProfiles.conf

        # Activation, and it is NOT redundant with the always-on unit. quickshell
        # bus-ACTIVATES this name at startup and gives up permanently when that
        # fails — observed: "Could not launch service …: The name is not
        # activatable", then "The PowerProfiles service will not work", after
        # which noctalia's every profile call returns early in silence. A unit
        # that merely happens to be running is not the same as a name dbus can
        # start. `SystemdService` is what dbus-broker uses; `Exec` is the
        # non-systemd fallback. docs/adr/0026.
        install -Dm644 ${./power-profiles-tlp/dbus-service.in} \
          $out/share/dbus-1/system-services/org.freedesktop.UPower.PowerProfiles.service
        substituteInPlace \
          $out/share/dbus-1/system-services/org.freedesktop.UPower.PowerProfiles.service \
          --replace-fail '@out@' "$out"

        # `gi.repository.Gio` and `.GLib` resolve through typelibs, not through
        # PYTHONPATH. Without this the imports raise at startup — which under a
        # systemd unit is a failure nothing in the session ever surfaces.
        wrapProgram $out/bin/power-profiles-tlp \
          --prefix GI_TYPELIB_PATH : "${prev.glib.out}/lib/girepository-1.0"
        runHook postInstall
      '';

      # The floor. `--help` imports dbus and gi and exits, so a missing python
      # dependency or an unwrapped typelib path fails the BUILD rather than
      # arriving as an inert widget three reboots later.
      doInstallCheck = true;
      installCheckPhase = ''
        runHook preInstallCheck
        $out/bin/power-profiles-tlp --help >/dev/null
        runHook postInstallCheck
      '';

      meta.description = "Serve the power-profiles-daemon D-Bus API from TLP";
    };

  # ==========================================================================
  # lockscreen — lock the session with whichever locker the mode owns
  # ==========================================================================
  # Deliberately NOT named `swaylock`. A wrapper of that name would land earlier
  # in PATH and shadow swaylock-effects, which is the exact trap that makes
  # `programs.swaylock.package = null` load-bearing. docs/gotchas.md → swaylock.
  #
  # Every lock path goes through this one name — swayidle's before-sleep, lock
  # and 5-minute timeout, wlogout, power-menu.sh — so mode-awareness belongs
  # here and nowhere else. docs/adr/0024.
  lockscreen = prev.writeShellApplication {
    name = "lockscreen";
    # Absolute paths for all four: swayidle runs this from `sh -c` with a PATH
    # that carries bash and little else, and an unqualified `sleep` or
    # `noctalia-shell` would exit 127 under `set -e` — before the swaylock
    # fallback below ever ran.
    # `final.noctalia-shell`, NOT `prev.` — and this one is load-bearing rather
    # than tidy. quickshell resolves an ipc target by the shell.qml PATH it was
    # started from ("No running instances for …/shell.qml" is its own wording),
    # so the unpatched derivation would look for instances of a path nothing
    # runs, find none, and hand every unattended lock back to swaylock. It would
    # also put two noctalia closures in the system.
    runtimeInputs = [
      prev.swaylock-effects
      final.noctalia-shell
      prev.systemd
      prev.coreutils
    ];
    text = ''
      # In `noctalia` mode the shell owns the lock screen, and it is already the
      # one SUPER+Delete opens; leaving the unattended locks on swaylock made
      # every resume look like a different machine. Ask noctalia first, then
      # fall through — swaylock below is BOTH the fallback and the proof, since
      # only one client may hold an `ext-session-lock-v1` lock and swaylock
      # exits non-zero exactly when the session is already locked. So this
      # returns with the session locked either way, which is the guarantee
      # swayidle's sleep inhibitor is built on. docs/adr/0024.
      mode=$(cat "''${XDG_STATE_HOME:-$HOME/.local/state}/mango/current-mode" 2>/dev/null || echo tiling)
      if [ "$mode" = noctalia ] && systemctl --user is-active --quiet noctalia; then
        # `ipc call` prints "Target not found." / "Function not found." and
        # EXITS 0, so output is the only signal (docs/adr/0023).
        out=$(noctalia-shell ipc call lockScreen lock 2>&1 || true)
        if [ -n "$out" ]; then
          # Not fatal: swaylock is still ahead, and stderr reaches the journal
          # of whatever called this.
          printf 'lockscreen: noctalia ipc call lockScreen lock: %s\n' "$out" >&2
        else
          # The shell raises its lock asynchronously — there is no IPC that
          # reports the lock is up, and mango has no session-lock query. This
          # wait therefore decides only WHICH locker wins, never whether one
          # does: too short and swaylock takes the lock instead, which is the
          # previous behaviour rather than an unlocked screen.
          sleep 1
        fi
      fi

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
