# The case of the `ses` check

After the "Verify Diff with Liquid Haskell" project,[^post]
several invariants are statically checked using Liquid Haskell specs,[^branch]
but the `ses` function
-- the entry point to the diff algorithm, standing for "shortest edit script" --
might remain unchecked under an `ignore` annotation,
even though I have a working solution.

[^post]: Read the write-up [here](https://www.tweag.io/blog/2026-06-11-diff-package-static-checks/)
[^branch]: The static checks are still being improved and revised on the [`static-checks` branch](https://github.com/tweag/Diff/tree/static-checks) of our `Diff` fork.

`Diff` defines it as follows:

```haskell
ses :: (a -> b -> Bool) -> [a] -> [b] -> [DI]
ses eq as bs = path . head . dropWhile (\dl -> poi dl /= lena || poj dl /= lenb) .
            concat . iterate (dstep cd) . (:[]) . addsnake cd $
            DL {poi=0,poj=0,path=[]}
            where cd = canDiag eq as bs lena lenb
                  lena = length as; lenb = length bs
```

The first complain LH has of the `ses` function is lacking _means_ to assert that `head` receives a non-empty list,
which in this context translates in `dropWhile` terminating.
So all that's left do is proving _there is always one element with coordinates `(lena, lenb)` in the node stream_.
To see why this is the case and why it is difficult to verify with LH
I'll go into some details about the relation between the paper's algorithm and this implementation.

## Implementation vs paper specification

The `ses` function implements Myers diff algorithm following a five stage pipeline,
as documented in the function haddock:

```haskell
-- 1. __Seed__: create an initial 0-path wave front @[addsnake cd (DL 0 0 [])]@
--    having a single node on the tip of the longest origin-sourced snake.
-- 2. __Iterate__: apply 'dstep' repeatedly via 'iterate', producing an
--    infinite list of wave fronts (one per edit distance D = 0, 1, 2, …).
-- 3. __Flatten__: 'concat' all wave fronts into a single stream of 'DL' nodes.
-- 4. __Find__: 'dropWhile' skips nodes until one reaches @(lena, lenb)@ — the
--    bottom-right corner of the edit graph — which is the terminal node of a
--    shortest edit script.
-- 5. __Extract__: 'head' returns that node; its 'path' field carries the edit
--    trace in reverse order.
```

In what follows I'll show how the notion of a _wave front_ relates this implementation with the algorithm specification.
This requires me to introduce some of the concepts that underlie the paper specification,
which translate _almost_ identically.

## Prerequisites

TODO: Edith graph, nodes, k-diagonals

- A `k-diagonal` is a diagonal on the _edit grid_. 
  A node with coordinates `(x,y)` lies on the k-diagonal with $k = x - y$.

## Wave front

A wave front is represented in LH logic as a list of _nodes_ at the same edit distance on a specific set of _k-diagonals_
using a refinement type alias.

```haskell
-- A wave front is a list of 'DL' nodes, all at the same edit distance @D@,
-- with k-diagonals @K@, @K−2@, @K−4@, …
{-@ type WaveFront D K = {xs : [DLN D] | wfDiags K xs} @-}

-- This refinement type alias represents a 'DL' value with a fixed /D-length/,
-- which we call a "D-path location node".
{-@ type DLN D = { x : DL | len (path x) = D } @-}

{-@ wfDiags :: Int -> xs : [DL] -> Bool / [len xs] @-}
-- | Checks if succesive nodes of a wave front lie within k-diagonals
-- differing by 2 as described in the Myers algorithm.
wfDiags :: Int -> [DL] -> Bool
wfDiags _ [] = True
wfDiags k (dl:dls) = poi dl - poj dl == k && wfDiags (k - 2) dls
```

Wave fronts essentially reify the iterative steps of the original Myers algorithm,
which uses the fact that successive iterations of its inner loop produce nodes on disjoint diagonals to optimize space by writing to a single vector containing the furthest reaching node along each diagonal.
In contrast, `dstep` implements the inner loop logic with a separate list as output for each run of the outer loop,
and thus incurring in some space overhead.

```haskell
dstep
  :: (Int -> Int -> Bool) -- ^ Diagonal predicate
  -> [DL]                 -- ^ A non-empty wave front of nodes at edit distance D
  -> [DL]                 -- ^ A non-empty wave front of nodes at edit distance D+1
```

So the correspondence is:
if the n-th iteration of the the Myers algorithm outer loop returns the minimal edit distance,
then the wave front produced by nth `dstep` iteration must contain a node with coordinates `(lena, lenb)`.

This is the case because:

1. Both specification and algorithm start by extending on `(0,0)`by a snake.
2. Successive iterations produce nodes con complementary diagonals:
   this is shown by lemma x in the paper, and is statically check by the `dstep` spec:
   ```haskell
   {-@
   dstep
     :: (Nat -> Nat -> Bool)
     -> d : Nat
     -> k : Int
     -> {nodes : WaveFront d k | len nodes > 0}
     -> {v : WaveFront (d + 1) (k + 1) | len v = len nodes + 1}
   @-}
   ```
   where the current iteration `n` is equal the current edit trace length `d`
   and the higher diagonal on the wave front `k`; they redundancy comes from
   using them to check different properties, and thus having different types.

In the paper, termination is argued on the basis of the existance of a worst case edit script:
delete each line from the input, and insert each line of the output.
The algorithm must find a script shorter or equal to this.
Termination is expressed as the upper bound of the outer loop, as the sum of both inputs lengths.

By comparison, `ses` can be refactored to use a `worstCaseEdits` parameter to bound the recursion in a similar way

```haskell
ses :: (a -> b -> Bool) -> [a] -> [b] -> [DI]
ses eq as bs = search (worstCaseEdits + 1) 0 0 [addsnake worstCaseEdits cd (DL 0 0 [])]
            where cd = canDiag eq as bs lena lenb
                  lena = length as; lenb = length bs
                  worstCaseEdits = lena + lenb
                  {-@ search :: fuel : Nat
                             -> d : Nat
                             -> k : Int
                             -> {dls : WaveFront d k | len dls > 0}
                             -> [DI] / [fuel] @-}
                  search :: Int -> Int -> Int -> [DL] -> [DI]
                  search 0 _ _ _ = error "search: unreachable because the trivial edit script is at iteration with fuel = 1"
                  search fuel _ _ [] = error "ses: The search must have a seed node"
                  search fuel currentD k wf = case findGoal wf of
                      Just p  -> p
                      Nothing -> search (fuel - 1) (currentD + 1) (k + 1) (dstep worstCaseEdits cd currentD k wf)
                  findGoal [] = Nothing
                  findGoal (dl:dls)
                      | poi dl == lena && poj dl == lenb = Just (path dl)
                      | otherwise = findGoal dls
```

