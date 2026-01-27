{ config, pkgs, ... }:

{
  home.username = "daniil";
  home.homeDirectory = "/home/daniil";
  home.stateVersion = "25.11";

  home.shellAliases = {
    v = "vi";
    clear = "clear && fastfetch -l nixos_old_small";
  };

  home.packages = with pkgs; [
    ripgrep 

    nodejs
    gcc

    libreoffice-qt-fresh 
    hunspell hunspellDicts.en_US hunspellDicts.ru_RU

    qalculate-qt
  ];

  programs.bash = {
    enable = true;

    initExtra = "clear";
  };

  programs.git = {
    enable = true;

    settings = {
      user.name = "DaniilAlpha";
      user.email = "daniilmiskevich@gmail.com";
    };
  };

  programs.neovim = {
    enable= true;

    defaultEditor = true;
    vimAlias = true;
    viAlias = true;
    #vimdiffAlias = true;
    extraPackages = with pkgs; [
      nil nixpkgs-fmt
    ];
  };
  xdg.configFile."nvim".source = config.home.homeDirectory + "/.dotfiles/nvim";

  programs.qutebrowser = {
    enable = true;
  };

  programs.chromium = {
    enable=true;
  };
}
