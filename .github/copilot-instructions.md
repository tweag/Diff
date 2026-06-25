# Copilot Instructions for the Diff Repository

Before starting a task, check if you have ghc 9.14.1 available in the PATH.
If no, install it.

## Build & Test Commands

```bash
# Build the library (no LiquidHaskell)

cabal build

# Build the library with LiquidHaskell to run the static checks
# (requires ghc 9.14.1)
cd Diff-liquidhaskell && cabal build

# Run the QuickCheck test suite
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
