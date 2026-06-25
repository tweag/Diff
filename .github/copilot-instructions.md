# Copilot Instructions for the Diff-liquidhaskell package

Before starting a task, check if you have ghc 9.14.1 and cabal-install (any version) available in the PATH.
If no, install it.

## Build & Test Commands

```bash
# Build the library to run the LiquidHaskell static checks / specification 
# (requires ghc 9.14.1)

cabal build Diff-liquidhaskell

# To run the test suite and benchmark
# first add the top level package by adding “.” to the list of packages in cabal.project.
# Run the test suite
cabal test

# Run benchmarks
cabal bench
```

## Repository Architecture

### Two-package structure

| Package | Cabal file | Purpose |
|---------|-----------|---------|
| `Diff` | `Diff.cabal` | The library itself — no LH dependency. |
| `Diff-liquidhaskell` | `Diff-liquidhaskell/Diff-liquidhaskell.cabal` | Shares `Diff`'s source tree (`src/`) to compile its modules with the LH GHC plugin enabled.|

The `Diff-liquidhaskell` package exists to break the cyclic dependency
`Diff → liquidhaskell → liquidhaskell-boot → Diff`.
Source changes live in `src/`; the `Diff-liquidhaskell/` directory only has cabal metadata.

### Source modules

- `Data.Algorithm.Diff` — core Myers O(ND) diff algorithm and public API.
- `Data.Algorithm.DiffOutput` — pretty-printing utilities for regular `diff` output.
- `Data.Algorithm.DiffContext` — pretty-printing utilities for `diff -u` like output.
- `Internal.LiftedFunctions` — not always present depending on current git checkout:
   utility functions used exclusively in LH logic (lifted using `reflect` or `measure` LH directives).
