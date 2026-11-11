{
  description = "Sanitizer-instrumented clang+libc++ Nix stdenvs";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    systems.url = "github:nix-systems/default-linux";
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      flake-parts,
      systems,
      treefmt-nix,
      ...
    }@inputs:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [ treefmt-nix.flakeModule ];

      systems = import systems;

      perSystem =
        { config, pkgs, ... }:
        let
          inherit (pkgs) lib;

          # The supported sanitizers: one per tests/<sanitizer>.nix.
          sanitizers = lib.pipe ./tests [
            builtins.readDir
            lib.attrNames
            (map (lib.removeSuffix ".nix"))
          ];
        in
        {
          packages = lib.genAttrs sanitizers (sanitizer: import ./default.nix { inherit pkgs sanitizer; });

          checks = import ./checks.nix {
            inherit lib pkgs;
            inherit (config) packages;
          };

          treefmt = {
            projectRootFile = "flake.nix";
            programs = {
              nixfmt = {
                enable = true;
                strict = true;
                width = 100;
              };
              yamlfmt = {
                enable = true;
                settings.formatter = {
                  type = "basic";
                  retain_line_breaks_single = true;
                  max_line_length = 100;
                  indentless_arrays = true;
                  trim_trailing_whitespace = true;
                  eof_newline = true;
                  force_array_style = "block";
                };
              };
              deadnix = {
                enable = true;
                no-underscore = true;
              };
              statix = {
                enable = true;
                disabled-lints = [ "repeated_keys" ];
              };
            };
          };
        };
    };
}
