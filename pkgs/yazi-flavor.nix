# yazi's flavour, written from the palette. docs/adr/0041.
#
# A flavour is 220 lines of colour and nothing else, which is why it stops
# being a fetch: the four schemes here were served by four unrelated upstreams
# (`stepbrobd/nord.yazi`, `bennyyip/gruvbox-dark.yazi`, …) that agree on the
# schema and on nothing else, and a scheme with no flavour published could not
# be adopted at all.
#
# Consumed as `programs.yazi.flavors.scheme` — a `.yazi` package directory
# whose entry point is this file.
#
# The role assignments reproduce what the four flavours had, with three
# exceptions marked below where upstream's pick was not a role at all.
#
# EVERY GLYPH IS A `\uXXXX` ESCAPE, none is a literal character. A lone
# backslash is not an escape in a Nix indented string, so the text reaches the
# TOML unchanged and TOML resolves it — which is how upstream spells its
# separators too. This is the narrow exception to CLAUDE.md's "glyphs must be
# literal UTF-8": that rule is about consumers with no escape syntax, and TOML
# has one.
#
# The rule exists because both attempts at typing a glyph here lost it. The
# powerline separators went first and were caught; `which.separator` (U+EA9C)
# went too and was NOT — it renders blank in a terminal without the font, so
# two spaces looked like a faithful copy, and it shipped. checks/static.sh now
# asserts this file's codepoints rather than trusting either the eye or the
# diff.
p: ''
  # GENERATED from modules/home/palette.nix by pkgs/yazi-flavor.nix.
  # docs/adr/0041. Edit the theme file, then rebuild.
  # vim:fileencoding=utf-8:foldmethod=marker

  [mgr]
  cwd = { fg = "#${p.brBlue}" }

  find_keyword  = { fg = "#${p.brGreen}", bold = true, italic = true, underline = true }
  find_position = { fg = "#${p.accent}", bg = "reset", bold = true, italic = true }

  symlink_target = { italic = true }

  marker_copied   = { fg = "#${p.brCyan}", bg = "#${p.brCyan}" }
  marker_cut      = { fg = "#${p.brMagenta}", bg = "#${p.brMagenta}" }
  marker_marked   = { fg = "#${p.brBlue}", bg = "#${p.brBlue}" }
  marker_selected = { fg = "#${p.fg0}", bg = "#${p.fg0}" }

  count_copied   = { fg = "#${p.bg0}", bg = "#${p.brCyan}" }
  count_cut      = { fg = "#${p.bg0}", bg = "#${p.brMagenta}" }
  count_selected = { fg = "#${p.bg0}", bg = "#${p.fg0}" }

  border_symbol = "\u2502"
  border_style  = { fg = "#${p.bg3}" }

  [tabs]
  active   = { fg = "#${p.bg0}", bg = "#${p.fg4}" }
  inactive = { fg = "#${p.fg4}", bg = "#${p.bg2}" }

  sep_inner = { open = "", close = "" }
  sep_outer = { open = "", close = "" }

  [mode]
  normal_main = { fg = "#${p.bg0}", bg = "#${p.fg4}", bold = true }
  normal_alt  = { fg = "#${p.fg4}", bg = "#${p.bg2}" }

  select_main = { fg = "#${p.bg0}", bg = "#${p.accent}", bold = true }
  select_alt  = { fg = "#${p.fg4}", bg = "#${p.bg2}" }

  unset_main = { fg = "#${p.bg0}", bg = "#${p.brGreen}", bold = true }
  unset_alt  = { fg = "#${p.fg4}", bg = "#${p.bg2}" }

  [indicator]
  parent  = { reversed = true }
  current = { reversed = true }
  preview = { underline = true }
  padding = { open = "\u2588", close = "\u2588" }

  [status]
  overall = { }
  sep_left  = { open = "\ue0be", close = "\ue0b8" }
  sep_right = { open = "\ue0be", close = "\ue0b8" }

  perm_sep   = { fg = "#${p.bg3}" }
  perm_type  = { fg = "#${p.bg2}" }
  perm_read  = { fg = "#${p.brGreen}" }
  perm_write = { fg = "#${p.brRed}" }
  perm_exec  = { fg = "#${p.brGreen}" }

  progress_label  = { fg = "#${p.fg1}", bold = true }
  progress_normal = { fg = "#${p.bg2}", bg = "#${p.bg1}" }
  progress_error  = { fg = "#${p.brRed}", bg = "#${p.bg1}" }

  [which]
  cols            = 3
  mask            = { bg = "#${p.bg1}" }
  cand            = { fg = "#${p.brBlue}" }
  rest            = { fg = "#${p.comment}" }
  desc            = { fg = "#${p.accent}" }
  separator       = " \uea9c "
  separator_style = { fg = "#${p.bg2}" }

  [confirm]
  border     = { fg = "#${p.fg4}" }
  title      = { fg = "#${p.brBlue}" }
  body       = { fg = "#${p.fg0}" }
  list       = { fg = "#${p.fg1}" }
  btn_yes    = { reversed = true, fg = "#${p.fg1}" }
  btn_no     = {}
  btn_labels = [ "  [Y]es  ", "  (N)o  " ]

  [spot]
  border   = { fg = "#${p.brBlue}" }
  title    = { fg = "#${p.brBlue}" }
  tbl_col  = { fg = "#${p.brBlue}" }
  tbl_cell = { fg = "#${p.brYellow}", reversed = true }

  # The three that are roles here and were not upstream: gruvbox put `fg0` on
  # the WARNING title and its pink on the ERROR one, which reads as neither.
  [notify]
  title_info  = { fg = "#${p.okColor}" }
  title_warn  = { fg = "#${p.warnColor}" }
  title_error = { fg = "#${p.errColor}" }

  [pick]
  border   = { fg = "#${p.blue}" }
  active   = { fg = "#${p.brMagenta}", bold = true }
  inactive = {}

  [input]
  border   = { fg = "#${p.fg1}" }
  title    = {}
  value    = {}
  selected = { reversed = true }

  [cmp]
  border   = { fg = "#${p.fg4}" }
  active   = { reversed = true, fg = "#${p.brBlue}" }
  inactive = { fg = "#${p.fg1}" }

  [tasks]
  border  = { fg = "#${p.bg2}" }
  title   = {}
  hovered = { underline = true }

  [help]
  on      = { fg = "#${p.brBlue}" }
  run     = { fg = "#${p.brMagenta}" }
  desc    = {}
  hovered = { reversed = true, bold = true }
  footer  = { fg = "#${p.bg1}", bg = "#${p.fg4}" }

  [filetype]
  rules = [
    { mime = "image/*", fg = "#${p.brMagenta}" },
    { mime = "{audio,video}/*", fg = "#${p.brYellow}" },
    { mime = "application/*zip", fg = "#${p.brRed}" },
    { mime = "application/x-{tar,bzip*,7z-compressed,xz,rar}", fg = "#${p.brRed}" },
    { mime = "application/{pdf,doc,rtf,vnd.*}", fg = "#${p.cyan}" },
    { url = "*", fg = "#${p.fg1}" },
    { url = "*/", fg = "#${p.brBlue}" },
  ]
''
