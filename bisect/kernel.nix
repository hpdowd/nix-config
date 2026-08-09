# Builds the kernel from a local linux git checkout instead of nixpkgs, so
# `git bisect` can drive which commit gets booted. NOT imported by the host —
# see bisect/README.md for the loop.
#
# Impure by construction: the source is whatever is checked out right now. That
# is the point; a pure flake input cannot bisect. This lives outside
# hosts/thinkpad so a stray rebuild can never pick it up.
{
  pkgs,
  lib ? pkgs.lib,
  # Path to the linux checkout, e.g. /home/henry/src/linux.
  src,
  # Must equal the built kernel's `uname -r`, or modules install to a path the
  # boot cannot find and the machine comes up with no modules at all.
  version,
  # KASAN catches the use-after-free where it happens, naming the alloc and free
  # stacks, instead of the downstream GPF. ~2-3x slower, but this is the output
  # that makes an upstream report actionable.
  kasan ? false,
}:

let
  # .git is most of the tree's bulk and changes every bisect step; excluding it
  # keeps the store copy to something tolerable per iteration.
  source = lib.cleanSourceWith {
    name = "linux-bisect-src";
    src = builtins.path {
      path = src;
      name = "linux-bisect-raw";
    };
    filter = path: _type: !lib.hasSuffix "/.git" path;
  };

  debugConfig = lib.optionalAttrs kasan (
    with lib.kernel;
    {
      KASAN = yes;
      KASAN_GENERIC = yes;
      # Outline is slower than inline but gives usable reports from module code,
      # which is where amdgpu and ttm live.
      KASAN_OUTLINE = yes;
      KASAN_INLINE = no;
      # A use-after-free report without allocating and freeing stacks is not
      # worth sending, and these are what produce them.
      STACKTRACE = yes;
      KALLSYMS = yes;
      KALLSYMS_ALL = yes;
      # Turns a corrupted list into a loud report at the point of corruption
      # rather than a wild pointer dereference much later.
      DEBUG_LIST = yes;
      DEBUG_SPINLOCK = yes;
      PROVE_LOCKING = yes;
    }
  );

  # Pin the version string. With LOCALVERSION_AUTO the tree appends -g<sha>,
  # which differs from `version` above and silently breaks modDirVersion.
  versionConfig = with lib.kernel; {
    LOCALVERSION_AUTO = no;
    DEBUG_INFO_DWARF5 = yes;
  };
in
pkgs.linuxPackagesFor (
  pkgs.linuxPackages_latest.kernel.override {
    argsOverride = {
      inherit version;
      modDirVersion = version;
      src = source;
    };
    structuredExtraConfig = debugConfig // versionConfig;
    # A bisected tree will disagree with nixpkgs' expected config in small ways;
    # without this every other step fails on a config assertion instead of
    # testing the commit.
    ignoreConfigErrors = true;
  }
)
