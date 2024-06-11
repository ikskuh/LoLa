{pkgs ? import <nixpkgs> {}}:
pkgs.mkShell {
  nativeBuildInputs = [
    pkgs.zig_master
    pkgs.llvmPackages_16.bintools
    pkgs.pkgsCross.avr.buildPackages.gcc
  ];
}
