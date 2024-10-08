{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs";
    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-compat.url = "github:edolstra/flake-compat";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    systems.url = "github:nix-systems/default";
    rust-overlay.url = "github:oxalica/rust-overlay";
    crane.url = "github:ipetkov/crane";
  };

  outputs =
    inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = import inputs.systems;
      imports = [
        inputs.treefmt-nix.flakeModule
      ];
      perSystem =
        {
          pkgs,
          lib,
          system,
          inputs',
          self',
          ...
        }:
        let
          rust = pkgs.rust-bin.fromRustupToolchainFile ./rust-toolchain.toml;
          craneLib = (inputs.crane.mkLib pkgs).overrideToolchain rust;
          overlays = [ inputs.rust-overlay.overlays.default ];
          src = craneLib.cleanCargoSource ./.;
          cargoArtifacts = craneLib.buildDepsOnly {
            inherit src;
          };
          serde_nix = craneLib.buildPackage {
            inherit src cargoArtifacts;
            strictDeps = true;
            doCheck = true;
          };
          cargo-clippy = craneLib.cargoClippy {
            inherit src cargoArtifacts;
            cargoClippyExtraArgs = "--verbose -- --deny warning";
          };
          cargo-doc = craneLib.cargoDoc {
            inherit src cargoArtifacts;
          };
          llvm-cov-text = craneLib.cargoLlvmCov {
            inherit cargoArtifacts src;
            cargoExtraArgs = "--locked";
            cargoLlvmCovCommand = "test";
            cargoLlvmCovExtraArgs = "--text --output-dir $out";
          };
          llvm-cov = craneLib.cargoLlvmCov {
            inherit cargoArtifacts src;
            cargoExtraArgs = "--locked";
            cargoLlvmCovCommand = "test";
            cargoLlvmCovExtraArgs = "--html --output-dir $out";
          };
        in
        {
          _module.args.pkgs = import inputs.nixpkgs {
            inherit system overlays;
          };

          treefmt = {
            projectRootFile = "flake.nix";
            programs.nixfmt.enable = true;
            programs.rustfmt.enable = true;
            programs.taplo.enable = true;
            programs.actionlint.enable = true;
            programs.mdformat.enable = true;
          };

          packages = {
            inherit llvm-cov llvm-cov-text;
            default = cargo-doc;
            doc = cargo-doc;
          };

          checks = {
            inherit
              serde_nix
              cargo-clippy
              cargo-doc
              llvm-cov
              llvm-cov-text
              ;
          };

          devShells.default = pkgs.mkShell {
            packages = [
              # Rust
              rust

              # Nix
              pkgs.nil
            ];

            shellHook = ''
              export PS1="\n[nix-shell:\w]$ "
            '';
          };
        };
    };
}
