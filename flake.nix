{
  description = "Herdr Controls — native macOS session control center";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      forDarwin = nixpkgs.lib.genAttrs [ "aarch64-darwin" ];
    in
    {
      packages = forDarwin (system:
        let pkgs = import nixpkgs { inherit system; };
        in {
          default = pkgs.callPackage ./default.nix { };
          herdr-controls = self.packages.${system}.default;
        });

      checks = forDarwin (system: {
        package = self.packages.${system}.default;
      });

      devShells = forDarwin (system:
        let pkgs = import nixpkgs { inherit system; };
        in {
          default = pkgs.mkShell {
            packages = [ pkgs.swift pkgs.swiftpm pkgs.shellcheck ];
          };
        });
    };
}
