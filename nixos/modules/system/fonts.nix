{ config, pkgs, lib, ... }:

{
  fonts = {
    enableDefaultPackages = true;

    packages = with pkgs; [
      # Nerd Fonts. On nixpkgs-unstable these are individual packages under
      # `nerd-fonts.*` (the old monolithic `nerdfonts` with `fonts = [...]`
      # was split up in 2024 — if you pin an older nixpkgs, use that instead).
      nerd-fonts.hack # ttf-hack-nerd — your kitty/foot font
      nerd-fonts.fira-code # ttf-firacode-nerd
      nerd-fonts.jetbrains-mono # ttf-jetbrains-mono-nerd
      nerd-fonts.symbols-only

      # 0xProto is used for bold/italic in your terminals (CLAUDE.md).
      _0xproto

      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-color-emoji # NOT `noto-fonts-emoji` — that name doesn't exist
      ibm-plex # ttf-ibm-plex
      liberation_ttf
      corefonts # ttf-ms-fonts (unfree)
      dejavu_fonts

      # Serif faces you have installed
      charis # ttf-bitstream-charter's packaged relative (attr is `charis`, not `charis-sil`)
      league-gothic # ttf-league-gothic

      # Icon font for the bar / shell widgets
      material-symbols
      # ttf-phosphor-icons is NOT in nixpkgs. If your Waybar config renders
      # Phosphor glyphs, drop the TTFs into ~/.local/share/fonts — fontconfig
      # picks them up with no packaging needed. (It was mainly a DMS
      # dependency, which is being dropped, so you may not need it at all.)
    ];

    fontconfig = {
      enable = true;
      antialias = true;
      hinting.enable = true;
      hinting.style = "slight";
      subpixel.rgba = "rgb";

      defaultFonts = {
        monospace = [ "Hack Nerd Font Mono" "Noto Sans Mono" ];
        sansSerif = [ "IBM Plex Sans" "Noto Sans" ];
        serif = [ "Charis SIL" "Noto Serif" ];
        emoji = [ "Noto Color Emoji" ];
      };
    };
  };

  # nerd-fonts-sf-mono (AUR) has no nixpkgs equivalent — Apple's SF Mono is
  # not redistributable. Drop it, or add the patched TTFs by hand:
  #   fonts.packages = [ (pkgs.runCommand "sf-mono-nerd" {} ''
  #     mkdir -p $out/share/fonts/truetype
  #     cp ${./../../assets/sf-mono}/*.ttf $out/share/fonts/truetype/
  #   '') ];
}
