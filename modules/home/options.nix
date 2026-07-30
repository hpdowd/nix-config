# Options this config declares for itself.
#
# Kept in its own file because a module that declares `options` must put
# everything else under `config` — mixing `options.foo` with a bare
# `home.username` in one file is a "module has an unsupported attribute"
# evaluation error. A dedicated file avoids wrapping default.nix.
{ config, lib, ... }:

{
  options.local.checkout = lib.mkOption {
    type = lib.types.str;
    default = "${config.home.homeDirectory}/src/nix-config";
    example = "/home/henry/dev/nix-config";
    description = ''
      Absolute path to this repo's checkout on the live filesystem.

      This CANNOT be derived, which is worth understanding before trying to
      remove it. A flake always evaluates from a *copy of itself* in
      /nix/store, so `./.` and `self` both yield a store path. That is exactly
      right for `source = ../../home/kitty`, and useless for an out-of-store
      symlink, which by definition must point at a mutable path outside the
      store. `builtins.getEnv "PWD"` is not an escape hatch either: it returns
      "" under pure evaluation. Nix genuinely cannot discover where you cloned
      the repo, so somebody has to tell it — once.

      Declared here so that is the only place it is written down.
      `dotfiles.nix` uses it for the remaining `link` entries and `shell.nix`
      for the rebuild aliases. Clone the repo elsewhere and this default is the
      single line to change.

      This option becomes dead the moment the last out-of-store entry is
      converted to a store path, because at that point nothing in the flake
      cares where the checkout lives.
    '';
  };
}
