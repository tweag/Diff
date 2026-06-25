{
  pkgs ? import <nixpkgs> { },
}:

with pkgs;

mkShell {
  buildInputs = [
    haskell.compiler.ghc9141
    cabal-install
    haskell-language-server
    z3
  ];
}
