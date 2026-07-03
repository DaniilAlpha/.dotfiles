{
	description = "Preconfigured shells for ESP32 and ESP8266 development";

	inputs = {
		nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
		esp-dev-pkgs.url = "github:mirrexagon/nixpkgs-esp-dev";
	};

	outputs = { self, nixpkgs, esp-dev-pkgs }:
		let
			system = "x86_64-linux";
			pkgs = nixpkgs.legacyPackages.${system};
		in {
			devShells.${system} = {
				esp32 = pkgs.mkShell {
					inputsFrom = [ esp-dev-pkgs.devShells.${system}.esp-idf-full ];
					buildinputs = [ pkgs.llvmPackages.clang-tools ];
				};
				esp8266 = pkgs.mkShell {
					inputsFrom = [ esp-dev-pkgs.devShells.${system}.esp8266-rtos-sdk ];
					buildinputs = [ pkgs.llvmPackages.clang-tools ];
				};
			};
		};
}
