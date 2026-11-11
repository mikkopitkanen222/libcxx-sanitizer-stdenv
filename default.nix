{
  pkgs ? import <nixpkgs> { },
  llvmPackages ? pkgs.llvmPackages,
  sanitizer,
}:
let
  inherit (pkgs) lib;

  # DFSan's ABI lists name the functions that aren't instrumented. Clang adds LLVM's bundled list
  # (share/dfsan_abilist.txt in the resource directory) by itself. The supplement adds glibc
  # functions missing from it (see dfsan_abilist_supplement.txt).
  dfsanSupplementFlags = [
    "--start-no-unused-arguments"
    "-mllvm"
    "-dfsan-abilist=${./dfsan_abilist_supplement.txt}"
    "--end-no-unused-arguments"
  ];

  sanitizers = {
    memory = {
      short = "msan";
      llvmUseSanitizer = "MemoryWithOrigins";
      cflags = [
        "-fsanitize=memory"
        "-fno-omit-frame-pointer"
        "-fsanitize-memory-track-origins=2"
      ];
      libcxxCflags = [
        # Put sanitizer headers on the include path.
        "-isystem ${lib.getDev llvmPackages.compiler-rt-libc}/include"
      ];
    };
    thread = {
      short = "tsan";
      llvmUseSanitizer = "Thread";
      cflags = [ "-fsanitize=thread" ];
    };
    dataflow = {
      short = "dfsan";
      llvmUseSanitizer = "DataFlow";
      cflags = [ "-fsanitize=dataflow" ] ++ dfsanSupplementFlags;
      libcxxCflags = [
        # Add LLVM's bundled ABI list, which libc++'s clang doesn't find by itself.
        "-mllvm"
        "-dfsan-abilist=${llvmPackages.compiler-rt}/share/dfsan_abilist.txt"
      ]
      ++ dfsanSupplementFlags;
    };
  };

  settings =
    sanitizers.${sanitizer} or (throw (
      "libcxx-sanitizer-stdenv: unsupported sanitizer \"${sanitizer}\"; "
      + "supported: ${lib.concatStringsSep ", " (lib.attrNames sanitizers)}"
    ));

  libcxx-sanitized = llvmPackages.libcxx.overrideAttrs (oldAttrs: {
    pname = "${oldAttrs.pname}-${settings.short}";
    cmakeFlags =
      let
        sharedFlags = lib.concatStringsSep " " (
          [
            # Silence unused "-rtlib=compiler-rt" (a link-only flag) compiler warnings.
            "-Wno-unused-command-line-argument"
          ]
          ++ settings.libcxxCflags or [ ]
        );
      in
      (oldAttrs.cmakeFlags or [ ])
      ++ (lib.mapAttrsToList lib.cmakeFeature {
        LLVM_USE_SANITIZER = settings.llvmUseSanitizer;
        CMAKE_C_FLAGS = sharedFlags;
        CMAKE_CXX_FLAGS = sharedFlags;
      });
  });

  # Remove fortify from default hardening flags. Derivations can opt back in with hardeningEnable.
  bintools-sanitized = llvmPackages.bintools.override {
    defaultHardeningFlags = lib.subtractLists [
      "fortify"
      "fortify3"
    ] llvmPackages.bintools.defaultHardeningFlags;
  };

  cc-sanitized = pkgs.wrapCCWith {
    name = "clang-${settings.short}-wrapper";
    cc = llvmPackages.clang-unwrapped;
    libcxx = libcxx-sanitized;
    # bintools ships llvm-symbolizer, which turns reported addresses into file:line locations.
    bintools = bintools-sanitized;
    # compiler-rt ships sanitizer headers (sanitizer/*_interface.h).
    extraPackages = [ llvmPackages.compiler-rt ];
    # clang-unwrapped only ships its builtin headers.
    # compiler-rt ships the sanitizer runtime archives (libclang_rt.*.a) and default
    # ignore and ABI lists (share/).
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
    # The sanitizer requires every translation unit linked into the final binary to be instrumented.
    # Baking the flags into the wrapper itself makes every derivation built with this stdenv
    # automatically instrumented.
    nixSupport.cc-cflags = settings.cflags;
  };
in
pkgs.overrideCC llvmPackages.libcxxStdenv cc-sanitized
