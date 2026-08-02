{
  config,
  pkgs,
  lib,
  ...
}:

{
  time.timeZone = "Europe/Dublin";

  i18n.defaultLocale = "en_GB.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_GB.UTF-8";
    LC_IDENTIFICATION = "en_GB.UTF-8";
    LC_MEASUREMENT = "en_GB.UTF-8";
    LC_MONETARY = "en_GB.UTF-8";
    LC_NAME = "en_GB.UTF-8";
    LC_NUMERIC = "en_GB.UTF-8";
    LC_PAPER = "en_GB.UTF-8";
    LC_TELEPHONE = "en_GB.UTF-8";
    LC_TIME = "en_GB.UTF-8";
  };

  # From /etc/vconsole.conf
  console.keyMap = "uk";

  # From /etc/vconsole.conf (XKBLAYOUT=gb, XKBOPTIONS=terminate:ctrl_alt_bksp)
  services.xserver.xkb = {
    layout = "gb";
    model = "pc105";
    options = "terminate:ctrl_alt_bksp";
  };

  # keyd — transcribed from your /etc/keyd/default.conf.
  # NixOS's module generates /etc/keyd/*.conf from Nix, so the rules have to
  # live here rather than as a loose file you edit in place. `extraConfig`
  # takes raw keyd syntax, which keeps this a faithful copy rather than a
  # lossy translation into attrsets.
  services.keyd = {
    enable = true;
    keyboards.default = {
      ids = [ "*" ];
      extraConfig = ''
        [main]

        leftmeta+leftshift+f23 = sysrq

        # Navigation layer key
        capslock = overload(nav, esc)
        rightalt = layer(typst)
        leftshift = layer(shift)

        [shift:S]
        - = _

        [leftalt+shift]
        - = –

        # Navigation layer
        [nav:main]
        h = left
        j = down
        k = up
        l = right
        ; = home
        ' = end
        u = pageup
        i = pagedown
        f = backspace
        d = delete

        [special:main]
        p = ^
        a = *
        [ = {
        ] = }
        leftshift + [ = (
        leftshift + ] = )

        # Greek/Typst layer — from your greek-typst.conf. On Arch this file was
        # never actually pulled in by default.conf (the #include is commented
        # out and there is no [typst] section), so `rightalt` currently maps to
        # a layer that does not exist. Defining it here makes the binding work.
        [typst:main]
        a = macro(a l p h a)
        b = macro(b e t a)
        e = macro(e p s i l o n)
        g = macro(g a m m a)
        k = macro(k a p p a)
        o = macro(c i r c l e . s m a l l)
        p = macro(p a r t i a l)
        s = macro(s e c t i o n)
        t = macro(t h e t a)
        u = macro(u p s i l o n)
        x = macro(x i)
        z = macro(z e t a)
      '';
    };
  };
}
