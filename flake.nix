{
  description = "ClaudeBar — cross-platform Claude.ai desktop usage indicator";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
      in
      {
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            # Rust
            cargo
            rustc
            rustfmt
            clippy

            # Node.js / TypeScript
            nodejs
            esbuild

            # Python
            (python3.withPackages (ps: with ps; [ pillow pyyaml ]))

            # Build tooling
            meson
            ninja
            cmake
            vala
            gettext

            # Cargo dependencies
            pkg-config
            openssl
          ];
        };
      });
}
