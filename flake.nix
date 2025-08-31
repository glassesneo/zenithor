{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    zig-overlay = {
      url = "github:mitchellh/zig-overlay";
      inputs = {
        nixpkgs.follows = "nixpkgs";
      };
    };
    zls-overlay.url = "github:zigtools/zls/0.15.0";
    zon2nix = {
      url = "github:jcollie/zon2nix";
      inputs = {
        nixpkgs.follows = "nixpkgs";
      };
    };
  };

  outputs = {
    nixpkgs,
    zig-overlay,
    zls-overlay,
    ...
  } @ inputs: let
    allSystems = [
      "aarch64-darwin"
      "x86_64-darwin"
      "aarch64-linux"
      "x86_64-linux"
    ];
    forAllSystems = fn: nixpkgs.lib.genAttrs allSystems (system: fn system nixpkgs.legacyPackages.${system});
  in {
    devShell = forAllSystems (
      system: pkgs: let
        zig = zig-overlay.packages.${system}."0.15.1";
        zls = zls-overlay.packages.${system}.zls.overrideAttrs (old: {
          nativeBuildInputs = [zig];
        });
        zon2nix = inputs.zon2nix.packages.${system}.zon2nix;
      in
        pkgs.mkShell {
          packages = [
            zig
            zls
            zon2nix
          ];

          buildInputs = [
            pkgs.apple-sdk_15
            pkgs.cups
          ];

          shellHook = ''
            unset NIX_CFLAGS_COMPILE
            unset NIX_LDFLAGS
            unset SDKROOT
            unset SDKROOT_FOR_BUILD
          '';
          CUPS_INCLUDE_DIR = "${pkgs.cups.dev}/include";
        }
    );
  };
}
