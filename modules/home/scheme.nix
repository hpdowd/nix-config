# The scheme this machine wears. Change this line, rebuild, reload.
#
# A FILE rather than a home-manager option, and that is not laziness. The
# lock-background ramp is built in `pkgs/default.nix`, which is an **overlay** —
# it runs outside the module system and cannot read `config.*`. An option would
# reach twelve consumers and not the thirteenth, and the one it missed is the
# surface nobody looks at closely enough to notice. A file both sides can
# `import` reaches all of them.
#
# Must name a file in `./themes/`. A typo is a "file not found" eval error,
# which is the failure mode this repo wants: loud, before anything is built.
"heartbox"
