<div align="center">

# libcxx-sanitizer-stdenv

**Sanitizer-instrumented clang+libc++ Nix stdenvs**

<p>
<a href="https://github.com/mikkopitkanen222/libcxx-sanitizer-stdenv/actions/workflows/checks.yml">
<img alt="GitHub master branch status" src="https://github.com/mikkopitkanen222/libcxx-sanitizer-stdenv/actions/workflows/checks.yml/badge.svg"/>
</a>
</p>

</div>

[MemorySanitizer](https://clang.llvm.org/docs/MemorySanitizer.html) (MSan) is a dynamic analysis tool used to detect uses of uninitialized memory at runtime.
In order to avoid false positives, all translation units linked into the final binary must be instrumented (compiled with MSan).
This includes libc++ (the standard library), as well.

`libcxx-sanitizer-stdenv` is a drop-in replacement Nix [stdenv](https://ryantm.github.io/nixpkgs/stdenv/stdenv/).
It's built with an MSan-instrumented libc++, and will automatically instrument any derivations built with it.

## Usage

### Stable Nix, No Flakes

```nix
let
  pkgs = import <nixpkgs> { };
  libcxx-sanitizer-stdenv = builtins.fetchTarball "https://github.com/mikkopitkanen222/libcxx-sanitizer-stdenv/archive/master.tar.gz";
  stdenv = import libcxx-sanitizer-stdenv { inherit pkgs; };
  # or with a specific LLVM version:
  # stdenv = import libcxx-sanitizer-stdenv { inherit pkgs; llvmPackages = pkgs.llvmPackages_23; };
in
# ...
```

### Flakes

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    libcxx-sanitizer-stdenv = {
      url = "github:mikkopitkanen222/libcxx-sanitizer-stdenv";
      flake = false;
    };
  };

  outputs =
    { nixpkgs, libcxx-sanitizer-stdenv, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      stdenv = import libcxx-sanitizer-stdenv { inherit pkgs; };
      # or with a specific LLVM version:
      # stdenv = import libcxx-sanitizer-stdenv { inherit pkgs; llvmPackages = pkgs.llvmPackages_23; };
    in
    { /* ... */ };
}
```

### Example

This builds `package.nix` with MSan-instrumentation, on Clang 23.
If any dependencies are linked into the final binary (e.g. `gtest`), they must also be instrumented.

```nix
# default.nix
let
  pkgs = import <nixpkgs> { };
  libcxx-sanitizer-stdenv = builtins.fetchTarball "https://github.com/mikkopitkanen222/libcxx-sanitizer-stdenv/archive/master.tar.gz";
  stdenv = import libcxx-sanitizer-stdenv { inherit pkgs; llvmPackages = pkgs.llvmPackages_23; };
in
pkgs.callPackage ./package.nix { inherit stdenv; }
```

```nix
# package.nix
{ stdenv, gtest }:
stdenv.mkDerivation {
  # ...
  buildInputs = [ (gtest.override { inherit stdenv; }) ];
  # ...
}
```

## Notes

- `fortify` hardening (`_FORTIFY_SOURCE`) is off unless a derivation sets `hardeningEnable = [ "fortify" ];`.
  It replaces calls like `memcpy()` with glibc's checking variants like `__memcpy_chk()`, which MSan doesn't fully intercept.
  Memory they write stays marked uninitialized, causing false positives in correct code.
- Optimization levels are left to the build.
  At `-O1` and above, reading an uninitialized local variable is undefined behaviour that the optimizer may delete before MSan instruments it.
  The read then goes unreported, or the enclosing function is deleted entirely and crashes without a report.
  Reads of memory the optimizer can't trace back to an uninitialized local, such as heap memory, are still reported.

## License

This project is licensed under the terms of the MIT license.
