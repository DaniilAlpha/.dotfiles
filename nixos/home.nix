{ config, pkgs, ... }:

{
  home.username = "daniil";
  home.homeDirectory = "/home/daniil";
  home.stateVersion = "25.11";

  home.shellAliases = {
    vim = "nvim";
    vi = "nvim";
    v = "nvim";
  };

  programs.bash.enable = true;

  programs.git = {
    enable = true;

    settings = {
      user.name = "DaniilAlpha";
      user.email = "daniilmiskevich@gmail.com";
    };
  };
  
  home.packages = with pkgs; [
    neovim
    ripgrep
    nil
    nixpkgs-fmt

    nodejs
    gcc
  ];
}
