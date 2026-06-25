{
  pkgs ? import (fetchTarball {
    url = "https://github.com/NixOS/nixpkgs/archive/a50de1b7d8a586adc18d2395c19de7d6058e6030.tar.gz";
    sha256 = "1ks8s77y6021ryqfmw2qayqhnij2yrxl81yh1lbk51cjkbd6vjds";
  }) { },
}:

let
  hsPkgs = pkgs.haskell.packages.ghc9141;
in
pkgs.mkShell {
  nativeBuildInputs = [
    hsPkgs.ghc
    pkgs.cabal-install
    pkgs.haskell-language-server
    pkgs.z3
  ];
}
