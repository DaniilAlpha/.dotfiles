{ config, lib, pkgs, modulesPath, ... }:

{
  imports = 
    [ (modulesPath + "/profiles/all-hardware.nix")
      /etc/nixos/hardware-configuration.nix
    ];


  # bootloader
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = false;

  # kernel
  boot.kernelPackages = pkgs.linuxPackages_latest;

  networking.hostName = "magnesium";

  # networking
  networking.networkmanager.enable = true;
  #networking.wireless.enable = true;

  time.timeZone = "Europe/Minsk";

  # locale
  i18n.defaultLocale = "en_GB.UTF-8";
  console = {
    # font = "Lat2-Terminus16";
    keyMap = "us";
    # useXkbConfig = true; # use xkb.options in tty.
  };

  environment.shellAliases = let flakePath = "/home/daniil/.dotfiles/nixos/"; in {
    q = "exit";
    nr-switch = "sudo nixos-rebuild switch --flake ${flakePath} --impure";
    nr-boot = "sudo nixos-rebuild boot --flake ${flakePath} --impure";
  };

  # Enable the X11 windowing system.
  #services.xserver = {
  #  enable = true;

  #  autoRepeatDelay = 150;
  #  autoRepeatInterval = 28;
  #  windowManager.qtile.enable = true;

  #  xkb = {
  #    layout = "us";
  #    options = "caps:escape";
  #  };
  #};

  #services.displayManager.ly.enable = true;
  services.displayManager.sddm = {
    enable = true;

    settings = {
      General.DisplayServer = "wayland";
    };
  };
  services.desktopManager.plasma6 = {
    enable = true;
  };

  # Enable CUPS to print documents.
  # services.printing.enable = true;

  # Enable sound.
  # services.pulseaudio.enable = true;
  # OR
  # services.pipewire = {
  #   enable = true;
  #   pulse.enable = true;
  # };

  # Enable touchpad support (enabled default in most desktopManager).
  # services.libinput.enable = true;

  users.users.daniil = {
    isNormalUser = true;
    extraGroups = [ "wheel" ]; 
    packages = with pkgs; [
    ];
  };

  programs.firefox.enable = true;

  programs.git = {
    enable = true;
    config.init.defaultBranch = "master";
  };

  # List packages installed in system profile.
  # You can use https://search.nixos.org/ to find more packages (and options).
  environment.systemPackages = with pkgs; [
    tree
    tmux
    wget

    mc
    btop
    alacritty

    fastfetch
    pipes

    vim
  ];

  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
  ];

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  system.stateVersion = "25.11"; # DO NOT TOUCH THIS
}

