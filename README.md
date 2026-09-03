## Diff

This is an implementation of the standard diff algorithm in Haskell.

Time complexity is O(ND) (input length * number of differences). Space complexity is O(D^2). Includes utilities for pretty printing.

### Building & testing

Build with

```shell
cabal build
```

Test with

```shell
cabal test
```

Benchmark with

```shell
cabal bench
```

### Checking Diff with LiquidHaskell

The Diff source code can we checked with [LiquidHaskell](https://ucsd-progsys.github.io/liquidhaskell/).

LiquidHaskell requires `ghc` version 9.14.1, and an SMT solver. We have tested
the checks with the [Z3](https://github.com/Z3Prover/z3) SMT solver (versions 4.16,
and 4.15.1).

```
cd Diff-liquidhaskell && cabal build
```

The `Diff-liquidhaskell` package is a device to avoid the circular dependency between
`liquidhaskell` and the `Diff` package.

``` mermaid
flowchart LR
    Diff --> liquidhaskell --> liquidhaskell-boot --> Diff
```

Contributions that update the LiquidHaskell checks are appreciated but not required at this point.

### Acknowledgments

The LiquidHaskell static checks were designed and implemented with the support of
[Tweag](https://www.tweag.io/), a part of [Modus Create](https://www.moduscreate.com/).
Learn more in this [blog post](https://www.tweag.io/blog/2026-06-11-diff-package-static-checks/).
