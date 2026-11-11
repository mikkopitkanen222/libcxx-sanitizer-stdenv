{
  pkgs ? import <nixpkgs> { },
  llvmPackages ? pkgs.llvmPackages,
  ...
}:
let
  lib = pkgs.lib;

  libcxx-msan = llvmPackages.libcxx.overrideAttrs (oldAttrs: {
    pname = oldAttrs.pname + "-msan";
    cmakeFlags =
      let
        sharedFlags = lib.concatStringsSep " " [
          # Put sanitizer headers on the include path.
          "-isystem ${lib.getDev llvmPackages.compiler-rt-libc}/include"
          # Silence unused "-rtlib=compiler-rt" (a link-only flag) compiler warnings.
          "-Wno-unused-command-line-argument"
        ];
      in
      (oldAttrs.cmakeFlags or [ ])
      ++ (lib.mapAttrsToList lib.cmakeFeature {
        LLVM_USE_SANITIZER = "MemoryWithOrigins";
        CMAKE_C_FLAGS = sharedFlags;
        CMAKE_CXX_FLAGS = sharedFlags;
      });
  });

  # Remove fortify from default hardening flags. Derivations can opt back in with hardeningEnable.
  # _FORTIFY_SOURCE replaces e.g. memcpy() with glibc's __memcpy_chk(), which MSan doesn't fully
  # intercept, so the copied memory stays marked uninitialized, producing false positives.
  bintools-msan = llvmPackages.bintools.override {
    defaultHardeningFlags = lib.subtractLists [
      "fortify"
      "fortify3"
    ] llvmPackages.bintools.defaultHardeningFlags;
  };

  cc-msan = pkgs.wrapCCWith {
    name = "clang-msan-wrapper";
    cc = llvmPackages.clang-unwrapped;
    libcxx = libcxx-msan;
    # bintools ships symbolizer; Symbolizer turns reported addresses to file:line locations.
    bintools = bintools-msan;
    # compiler-rt ships sanitizer headers (sanitizer/msan_interface.h).
    extraPackages = [ llvmPackages.compiler-rt ];
    # clang-unwrapped only ships its builtin headers.
    # compiler-rt ships the sanitizer runtime archives (libclang_rt.msan*.a).
    extraBuildCommands =
      let
        cc = llvmPackages.clang-unwrapped;
        clangMajorVersion = lib.versions.major llvmPackages.release_version;
      in
      ''
        rsrc="$out/resource-root"
        mkdir "$rsrc"
        ln -s "${lib.getLib cc}/lib/clang/${clangMajorVersion}/include" "$rsrc/include"
        ln -s "${llvmPackages.compiler-rt}/lib" "$rsrc/lib"
        ln -s "${llvmPackages.compiler-rt}/share" "$rsrc/share"
        echo "-resource-dir=$rsrc" >> $out/nix-support/cc-cflags
      '';
    # MSan requires every translation unit linked into the final binary to be instrumented.
    # Baking the flags into the wrapper itself makes every derivation built with this stdenv
    # automatically instrumented.
    nixSupport.cc-cflags = [
      "-fsanitize=memory"
      "-fno-omit-frame-pointer"
      "-fsanitize-memory-track-origins=2"
    ];
  };
in
pkgs.overrideCC llvmPackages.libcxxStdenv cc-msan
