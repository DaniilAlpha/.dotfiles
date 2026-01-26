{ config, pkgs, ... }:

{
  home.username = "daniil";
  home.homeDirectory = "/home/daniil";
  home.stateVersion = "25.11";

  home.shellAliases = {
    vim = "nvim";
    vi = "nvim";
    v = "nvim";
    clear = "fastfetch -l small && clear";
  };

  home.packages = with pkgs; [
    neovim
    ripgrep
    nil
    nixpkgs-fmt

    nodejs
    gcc
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

  programs.qutebrowser = {
    enable = true;
  };
}
