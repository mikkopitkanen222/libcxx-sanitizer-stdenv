{
  lib,
  pkgs,
  packages,
}:
let
  mkCheck =
    {
      name,
      stdenv,
      tool,
      optionsVar,
      source,
      report,
      optFlag,
    }:
    stdenv.mkDerivation {
      inherit name;
      dontUnpack = true;
      buildPhase = ''
        cp ${pkgs.writeText "test.cpp" source} test.cpp
        $CXX -Werror=unused-command-line-argument -g ${optFlag} -std=c++17 -c test.cpp -o test.o
        $CXX -Werror=unused-command-line-argument test.o -o test

        set +e
        ${optionsVar}="exitcode=99" ./test >output.log 2>&1
        code=$?
        set -e

        fail() {
          echo "FAIL: $1" >&2
          cat output.log >&2
          exit 1
        }
      ''
      + (
        if report != null then
          ''
            [ $code -eq 99 ] || fail "expected ${tool} to exit 99, got $code"
          ''
          + lib.concatMapStrings (regex: ''
            grep -qE ${lib.escapeShellArg regex} output.log \
              || fail ${lib.escapeShellArg "expected output matching: ${regex}"}
          '') report
        else
          ''
            [ $code -eq 0 ] || fail "expected exit code 0, got $code"
            ! grep -q "${tool}" output.log || fail "unexpected ${tool} report"
          ''
      );
      installPhase = "touch $out";
    };

  optLevels = [
    "O0"
    "O1"
    "O2"
    "O3"
  ];
in
lib.concatMapAttrs (
  sanitizer: stdenv:
  let
    tests = import ./tests/${sanitizer}.nix;
  in
  lib.concatMapAttrs (
    program:
    { source, report }:
    lib.genAttrs' optLevels (
      level:
      lib.nameValuePair "${sanitizer}-${program}-${level}" (mkCheck {
        name = "libcxx-sanitizer-stdenv-${sanitizer}-${program}-${level}";
        inherit stdenv source report;
        inherit (tests) tool optionsVar;
        optFlag = "-${level}";
      })
    )
  ) tests.programs
) packages
