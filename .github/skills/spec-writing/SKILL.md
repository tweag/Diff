---
name: spec-writing 
description: Liquid Haskell specification writing guidelines. Use this when asked to write or fix a Liquid Haskell specification/annotation or statically check invariants to a package/module/source-file/function.
---

# LiquidHaskell Specification Writing Guidelines

## General approach

1. Make sure the build succeeds with LiquidHaskell enabled by using
  `ignore` or `lazy` annotations in error trowing functions depending
   on the cause of the error:
   - `{-@ lazy f @-}` disables termination checking only.
   - `{-@ ignore f @-}` suppresses checking a function entirely.
   This allows to approach incrementally.
2. Analyze the source, references and documentation comments to find function invariants in the form of pre-conditions or post-conditions.
3. When writing a new specification for an existing function, begin by marking it `{-@ assume f :: T @-}`:
   - `{-@ assume f :: T @-}` skips body checking, trusting the spec.
   This lets you design the postconditions top-down — verify that callers type-check under the assumed spec before investing effort in proving the function body. Once the interface is stable, remove `assume` and prove.
4. Proving the body of a function obeys its specification, and making callers type-check with it, might require some of the following techniques:
   - Write new predicates in the form of lifted Haskell functions
   - Define refinement (predicate or type) aliases to make specs more concise.
   - Lemmas providing additional constraints in unused bindings.
   - Refactoring of the function.
   When attempting a refactoring, aim for changes that preserve existing semantics and improve code readability. Refactoring should always be the last resort.
5. Keeping check disabling annotations (like `ignore`, `lazy` and `assume`) in a codebase is a valid trade-off when the proof machinery required to remove them would disproportionately clutter the source.
6. Test your changes are correct by building the package successfully with LH enabled.

## Other guidelines

Before introducing a new specification, pick the one with the least code impact (i.e. the amount of new definitions plus the size and semantic effects of refactorings)
among two different approaches to prove it.

**Prefer lifted helper functions over source refactoring.** When a
specification requires auxiliary reasoning (e.g. an intermediate invariant),
first try to express it with a new reflected predicate rather than restructuring
the source code.  Refactoring is preferable when it simplifies spec writing
without altering semantics.

### Choosing `inline`, `measure`, or `reflect` to lift a function into the LH logic

| Annotation | What it does | When to use |
|------------|-------------|-------------|
| `inline` | Expands the definition as an SMT term (`ite`/arithmetic). Not visible inside `reflect`ed bodies. | Pure arithmetic or boolean helpers used in refinement types. Must be total and simple enough for SMT to reason about directly: they cannot be recursive and they can call other (non-recursive) inlined functions. |
| `measure` | Eagerly evaluated on constructor-applied data, attached to the type's constructors. | Single-argument functions defined by pattern matching on one ADT. |
| `reflect` | Lifts the definition into logic; PLE can unfold it at constructor-applied arguments. | The general-purpose choice for predicates and helpers used in specifications. Safe for any type, including `[SomeSpecificType]`. |

**Rule of thumb:** start with `reflect`. Switch to `measure` only when you need
eager evaluation on constructors *and* the function's domain is a standalone ADT
(not a parameterised container with mixed element types). Switch to `inline`
only for small arithmetic/boolean combinators that SMT should reason about
equationally.

## PLE and opaque terms

PLE (Proof by Logical Evaluation) unfolds reflected functions **only** at
syntactically constructor-applied arguments.  A variable — even one known to
equal a constructor via a measure — is opaque to PLE.

Key consequences:

- **Recursive call results are opaque.** In `f (x:xs) = … f xs …`, PLE can unfold `g (x:xs)` (the input) but NOT `g (f xs)` (the recursive result). Use postconditions on `f` to carry facts about `f xs` into the SMT context.

- **Opaque function parameters don't flow into SMT.** For a guard `eq x y`, where`eq` is a binary operator that evaluates to a `Bool` at runtime, LH records **no** connection between the Boolean and `eq(x,y)` in SMT. Only built-in operations like `(==)` (mapped to SMT equality) produce usable facts.

- **Measures on opaque terms stay as uninterpreted SMT terms.** `isFirst x` where `x` is constructor-applied evaluates eagerly; where `x` is a variable it becomes an uninterpreted function.  Thread the needed fact via a postcondition on the function that produces `x`.

- **Per-constructor function variants enable PLE.** When a function receives a value whose constructor is known only via a measure or a precondition, PLE cannot match the reflected definition's patterns.  Split the function into per-constructor variants (e.g. `grabGroupF`, `grabGroupS`, `grabGroupB`) that pattern-match on the constructor explicitly so PLE can unfold.

### Proving properties through recursive structures

- **Carry invariants through postconditions, not PLE unfolding.** For
  recursive functions, state the desired property of the recursive result in
  the postcondition rather than expecting PLE to derive it.  The SMT solver
  can then combine the postcondition with locally unfolded facts.

- **Biconditional head-constructor specs.** When a function transforms a list
  and the proof depends on the head element's constructor, add `<=>` (not just
  `=>`) postconditions: `headIsFirst xs <=> headIsFirst vs`.  The forward
  direction lets you prove positive properties; the backward direction
  (contrapositive) lets you prove negative ones.

- **Intermediate invariants for multi-stage pipelines.** When a pipeline involves stages that weaken and re-establish an invariant define an explicit intermediate predicate and type the stages accordingly.

### Termination

- Termination metrics are declared with `/ [expr]`.  LH adds an implicit `expr >= 0` constraint at all call sites and requires strict decrease at recursive sites.
- **Mutually recursive functions need explicit `/ [len xs]` metrics.** Without them, LH may report "decreasing parameters should be of same type" even when types match.

### Common pitfalls

- GHC may infer a polymorphic type for a local binding (e.g. a numeric literal `0`).  If the LH annotation specifies `Int`, add an explicit Haskell type signature to avoid "specified type does not refine Haskell type" errors.
