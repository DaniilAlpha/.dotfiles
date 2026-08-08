{
  description = "Preconfigured shells for ESP32 and ESP8266 development";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    esp32-pkgs.url = "github:dvdvgt/nixpkgs-esp-dev/update-v6.0.1";
    esp8266-pkgs.url = "github:DaniilAlpha/nixpkgs-esp-dev-esp8266-fix";
  };

  outputs =
    {
      self,
      nixpkgs,
      esp32-pkgs,
      esp8266-pkgs,
    }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      devShells.${system} = {
        esp32 = pkgs.mkShell {
          inputsFrom = [ esp32-pkgs.devShells.${system}.esp-idf-full ];
          #buildInputs = [ pkgs.llvmPackages.clang-tools ];
        };
        esp8266 = pkgs.mkShell {
          inputsFrom = [ esp8266-pkgs.devShells.${system}.esp8266-rtos-sdk ];
          buildInputs = [ pkgs.llvmPackages.clang-tools ];
        };
      };
    };
}
