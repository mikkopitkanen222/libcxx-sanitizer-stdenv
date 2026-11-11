{
  description = "MSan-instrumented clang+libc++ Nix stdenv";

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

      perSystem = { config, pkgs, ... }: {
        packages.default = import ./default.nix { inherit pkgs; };

        checks =
          let
            stdenv = config.packages.default;

            # Reads uninitialized heap memory through a non-inlined allocator, so the optimizer
            # can't prove the memory is uninitialized. Reading an uninitialized local is undefined
            # behaviour, which clang may delete at -O1 and above before MSan instruments it.
            uninitializedRead = ''
              [[gnu::noinline]] int* allocate() { return new int[4]; }

              int main() {
                int* values = allocate();
                int result = values[1] == 42 ? 1 : 0;
                delete[] values;
                return result;
              }
            '';

            # Must run without reports. String streams run code from the compiled libc++ library.
            # The memcpy() size is unknown at compile time, so _FORTIFY_SOURCE would turn it into
            # glibc's __memcpy_chk(). MSan doesn't intercept it, so the copy would stay marked
            # uninitialized and reading it would be reported.
            correctCode = ''
              #include <cstring>
              #include <sstream>
              #include <string>

              [[gnu::noinline]] std::size_t size(const char* s) { return std::strlen(s) + 1; }

              int main(int argc, char**) {
                std::ostringstream stream;
                stream << "hello " << argc;
                std::string text = stream.str();
                char copy[32];
                std::memcpy(copy, text.c_str(), size(text.c_str()));
                return copy[0] == 'h' ? 0 : 1;
              }
            '';

            # Compiles `source` with `optFlag`, runs it, and checks MSan's verdict.
            mkCheck =
              {
                name,
                source,
                optFlag,
                expectReport,
              }:
              stdenv.mkDerivation {
                inherit name;
                dontUnpack = true;
                buildPhase = ''
                  cp ${pkgs.writeText "test.cpp" source} test.cpp
                  $CXX -g ${optFlag} -std=c++17 test.cpp -o test

                  set +e
                  MSAN_OPTIONS="exitcode=99" ./test >output.log 2>&1
                  code=$?
                  set -e

                  fail() {
                    echo "FAIL: $1" >&2
                    cat output.log >&2
                    exit 1
                  }
                ''
                + (
                  if expectReport then
                    ''
                      [ $code -eq 99 ] || fail "expected MSan to exit 99, got $code"
                      grep -q "WARNING: MemorySanitizer: use-of-uninitialized-value$" output.log \
                        || fail "expected MSan report text wasn't found in output"
                      grep -qE "^SUMMARY: MemorySanitizer: use-of-uninitialized-value /build/test\.cpp:[0-9]+:[0-9]+ in main$" output.log \
                        || fail "expected MSan to symbolize the error location"
                    ''
                  else
                    ''
                      [ $code -eq 0 ] || fail "expected MSan to exit 0, got $code"
                      ! grep -q "MemorySanitizer" output.log || fail "unexpected MSan report"
                    ''
                );
                installPhase = "touch $out";
              };

            optLevels = {
              O0 = "-O0";
              O1 = "-O1";
              O2 = "-O2";
              O3 = "-O3";
            };
          in
          pkgs.lib.concatMapAttrs (level: optFlag: {
            "catches-uninitialized-read-${level}" = mkCheck {
              name = "libcxx-msan-stdenv-catches-uninitialized-read-${level}";
              source = uninitializedRead;
              inherit optFlag;
              expectReport = true;
            };
            "no-false-positives-${level}" = mkCheck {
              name = "libcxx-msan-stdenv-no-false-positives-${level}";
              source = correctCode;
              inherit optFlag;
              expectReport = false;
            };
          }) optLevels;

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
          };
        };
      };
    };
}
