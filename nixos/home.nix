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
    nodejs
    gcc
    libclang

    telegram-desktop

    qalculate-qt

    libreoffice-qt-fresh
    hunspell
    hunspellDicts.en_US
    hunspellDicts.ru_RU

    gimp
    imagemagick

  ];

  xdg.enable = true;

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
    enable = true;

    defaultEditor = true;
    vimAlias = true;
    viAlias = true;
    #vimdiffAlias = true;
    extraPackages = with pkgs; [
      nil
      nixpkgs-fmt
    ];
  };
  xdg.configFile."nvim".source = config.lib.file.mkOutOfStoreSymlink (
    config.home.homeDirectory + "/.dotfiles/nvim"
  );

  programs.qutebrowser = {
    enable = true;
  };

  programs.chromium = {
    enable = true;
  };
}
