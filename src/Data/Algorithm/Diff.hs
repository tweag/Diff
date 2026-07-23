{-@ LIQUID "--ple" @-}
{-@ LIQUID "--etabeta" @-}
{-@ LIQUID "--higherorder" @-}
-----------------------------------------------------------------------------
-- |
-- Module      :  Data.Algorithm.Diff
-- Copyright   :  (c) Sterling Clover 2008-2011, Kevin Charter 2011
-- License     :  BSD 3 Clause
-- Maintainer  :  s.clover@gmail.com
-- Stability   :  experimental
-- Portability :  portable
--
-- This is an implementation of the diff algorithm as described in
-- [/An \( O(ND) \) Difference Algorithm and Its Variations (1986)/
-- by Eugene W. Myers](https://publications.mpi-cbg.de/Myers_1986_6330.pdf).
-- For inputs of size \( O(N) \) with the number of differences \( D \)
-- it has \( O(ND) \) time and \( O(D^2) \) space complexity.
--
-- == Algorithm overview
--
-- Finding the shortest edit script (SES) from a list \( as \) to a list \( bs \)
-- is modelled as a shortest-path search on an /edit graph/: an
-- \( (M+1) \times (N+1) \) grid of nodes \( (i, j) \),
-- where \( M \) and \( N \) are the lengths of \( as \) and \( bs \) respectively,
-- with \( i \) increasing rightward and \( j \) increasing downward.
-- Each node represents the state of having consumed \( i \) elements of \( as \)
-- and \( j \) elements of \( bs \). Three types of move are possible:
--
-- * A /rightward/ move \( (i,j) \to (i+1,j) \) represents
--   /deleting/ \( as[i] \) and costs one edit.
-- * A /downward/ move  \( (i,j) \to (i,j+1) \) represents
--   /inserting/ \( bs[j] \) and costs one edit.
-- * A /diagonal/ move  \( (i,j) \to (i+1,j+1) \) is free (zero edit cost)
--   and is only available when \( as[i] = bs[j] \).
--
-- The SES corresponds to a path from \( (0,0) \) to \( (M,N) \) that minimises
-- the number of non-diagonal moves.
--
-- Both input lists are 0-indexed, which leads to a slightly different
-- interpretation of the edit graph than in the original paper. In the paper,
-- each node represents the state of the traversal /after/ an edit, so a move
-- is the edit that /produced/ that node. Here, each node represents the state
-- /before/ an edit, so a move is the edit performed /on/ that node to yield its
-- successor. This distinction is only relevant when reading the implementation
-- alongside the paper.
--
-- === K-diagonals and the wave front
--
-- Every node \( (i,j) \) lies on the /k-diagonal/ \( k = i - j \).
-- After exactly \( D \) non-diagonal moves, every reachable node lies on one of
-- at most \( D+1 \) k-diagonals \( k \in \{-D,\,-D+2,\,\ldots,\,D-2,\,D\} \).
-- On each diagonal it suffices to track only the /furthest-reaching/ node
-- (the one with the largest \( i \)), collapsing the two-dimensional grid to a
-- one-dimensional /wave front/ indexed by \( k \).
--
-- The algorithm performs a breadth-first search over \( D = 0, 1, 2, \ldots \),
-- advancing the wave front by one edit at a time until a node reaches the goal
-- \( (M, N) \). The edit trace stored in that node is the SES, which
-- 'getDiffBy' reconstructs into a 'PolyDiff' list. The term /trace/ here
-- differs from the paper, where it denotes the sequence of k-diagonals visited
-- by the SES path; that structure is not materialised in this implementation.
-----------------------------------------------------------------------------
module Data.Algorithm.Diff
    ( Diff, PolyDiff(..)
    -- * Comparing lists for differences
    , getDiff
    , getDiffBy

    -- * Finding chunks of differences
    , getGroupedDiff
    , getGroupedDiffBy

    -- * Predicates for LiquidHaskell specifications
    , noStuttering
    , noFFSS
    , headIsFirst, headIsSecond, headIsBoth
    ) where

import Prelude hiding (pi)
import Data.Array (listArray, (!))
import Data.Bifunctor
import Data.Foldable (find)
import Internal.LiftedFunctions

-- | /Diff Instruction/ — an internal enum recording the direction of a single
-- non-diagonal edge traversed in the Myers edit graph. Every non-diagonal
-- move in the edit script is one of:
--
-- * 'F' — /First/ — a horizontal edge \( (i,j) \to (i+1,j) \), which
--   corresponds to /deleting/ the element at position \( i \) of the first input
--   sequence. The consumed element appears in the 'First' branch of the
--   resulting 'PolyDiff'.
--
-- * 'S' — /Second/ — a vertical edge \( (i,j) \to (i,j+1) \), which
--   corresponds to /inserting/ the element at position \( j \) of the second
--   input sequence. The consumed element appears in the 'Second' branch of
--   the resulting 'PolyDiff'.
--
-- Diagonal edges (free moves corresponding to equal elements) are /not/
-- recorded as 'DI' steps; they are followed implicitly by 'addsnake' and
-- produce 'Both' entries in the final output.
data DI = F | S deriving (Show, Eq)

-- | A value tagged with which of two input sequences it came from.
-- The type parameters @a@ and @b@ may differ, which is useful when comparing
-- sequences of different element types via a custom equality predicate.
--
-- Each constructor corresponds to one outcome for a position in the aligned
-- sequences:
--
-- * 'First' — the element exists only in the /first/ input (a deletion).
-- * 'Second' — the element exists only in the /second/ input (an insertion).
-- * 'Both' — the element is common to both inputs.
--   Both the left and right values are retained so that the original
--   elements can be recovered even when equality ignores some fields.
{-@ data PolyDiff a b = First a | Second b | Both a b @-}
data PolyDiff a b = First a | Second b | Both a b
    deriving (Show, Eq)

instance Functor (PolyDiff a) where
  fmap _ (First a) = First a
  fmap g (Second b) = Second (g b)
  fmap g (Both a b) = Both a (g b)

instance Bifunctor PolyDiff where
  bimap f _ (First a) = First (f a)
  bimap _ g (Second b) = Second (g b)
  bimap f g (Both a b) = Both (f a) (g b)

-- | This is 'PolyDiff' specialized so both sides are the same type.
type Diff a = PolyDiff a a

-- A valid list diff is such that any `Both` value has arguments of equal length.
{-@ type ValidListDiff a b = { d : PolyDiff [a] [b] | validListDiff d }@-}

{-@ type GroupedDiff a b = { d : ValidListDiff a b | nonEmptyDiff d } @-}

{-@
inline validListDiff
define length x = len x
@-}
-- | True when, for a 'Both' value, both sides have the same length.
-- 'First' and 'Second' trivially satisfy this.
validListDiff :: PolyDiff [a] [b] -> Bool
validListDiff (Both xs ys) = length xs == length ys
validListDiff (First _) = True
validListDiff (Second _) = True

{-@ inline nonEmptyDiff @-}
nonEmptyDiff :: PolyDiff [a] [b] -> Bool
nonEmptyDiff (First []) = False
nonEmptyDiff (Second []) = False
nonEmptyDiff (Both [] _) = False
nonEmptyDiff (Both _ []) = False
nonEmptyDiff _ = True

{-@ reflect headIsFirst @-}
{-@ reflect headIsSecond @-}
{-@ reflect headIsBoth @-}
-- | Head-constructor predicates for 'PolyDiff' lists.
-- Reflected (not measures) to avoid sort errors: measures on @[PolyDiff a b]@
-- would be attached to the polymorphic @[]@ constructor, clashing with
-- lists of other element types.
headIsFirst, headIsSecond, headIsBoth :: [PolyDiff a b] -> Bool
headIsFirst (First _ : _) = True
headIsFirst _ = False
headIsSecond (Second _ : _) = True
headIsSecond _ = False
headIsBoth (Both _ _ : _) = True
headIsBoth _ = False

{-@ reflect noStuttering @-}
-- | True if the list does not contain adjacent 'Diff's of the same type.
-- Uses head-constructor measures so PLE can work with opaque tails.
noStuttering :: [PolyDiff a b] -> Bool
noStuttering [] = True
noStuttering (First _ : xs) = not (headIsFirst xs) && noStuttering xs
noStuttering (Second _ : xs) = not (headIsSecond xs) && noStuttering xs
noStuttering (Both _ _ : xs) = not (headIsBoth xs) && noStuttering xs

{-@ reflect noFFSS @-}
-- | Like 'noStuttering' but allows Both-Both adjacencies.
-- This is the invariant preserved by @doPrefix@\/@doSuffix@ which may split
-- a single 'Both' into two consecutive 'Both' elements.
noFFSS :: [PolyDiff a b] -> Bool
noFFSS [] = True
noFFSS (First _ : xs) = not (headIsFirst xs) && noFFSS xs
noFFSS (Second _ : xs) = not (headIsSecond xs) && noFFSS xs
noFFSS (Both _ _ : xs) = noFFSS xs

-- | /D-path Location/ — a node on the wave front of the Myers O(ND) diff
-- algorithm.
--
-- Each wave front consists of one 'DL' per /k-diagonal/.  A 'DL' stores the
-- endpoint coordinates and the edit trace of a \( D \)-path, i.e. a path from the
-- origin \( (0,0) \) that uses exactly \( D \) non-diagonal edges.
{-@
data DL = DL
    { poi  :: Nat
    , poj  :: Nat
    , path :: { p : [DI] | len p <= poi + poj }
    }
@-}
data DL = DL
    { poi  :: !Int   -- ^ /Position On I/ — the @x@-coordinate of the endpoint
                     --   in the edit graph, i.e. the number of elements
                     --   consumed from the /first/ input sequence so far.
    , poj  :: !Int   -- ^ /Position On J/ — the @y@-coordinate of the endpoint
                     --   in the edit graph, i.e. the number of elements
                     --   consumed from the /second/ input sequence so far.
    , path :: [DI]   -- ^ The edit trace accumulated so far, stored in
                     --   /reverse/ order (most recent step first).  Diagonal
                     --   edges (matches) are not recorded here; only 'F' and
                     --   'S' steps are stored.
    } deriving (Show, Eq)

-- A "D-path location node" is a 'DL' value within the edit grid bounds
-- having a fixed /D-length/.
{-@ type DLN M N D = { x : DL | len (path x) = D && withinBounds M N x} @-}

{-@ inline _kdiag @-}
-- | Computes the k-diagonal of a node.
-- Used in LiquidHaskell logic as an expression.
_kdiag :: DL -> Int
_kdiag dl = poi dl - poj dl

{-@ reflect _wfDiags @-}
{-@ _wfDiags :: Int -> xs : [DL] -> Bool / [len xs] @-}
-- | Checks if succesive nodes of a wave front lie within k-diagonals
-- differing by 2 as described in the Myers algorithm.
-- Used in LiquidHaskell logic as a predicate.
_wfDiags :: Int -> [DL] -> Bool
_wfDiags _ [] = True
_wfDiags k (dl:dls) = poi dl - poj dl == k && _wfDiags (k - 2) dls

-- A wave front is a list of 'DL' nodes, all at the same edit distance @D@,
-- with k-diagonals @D@, @D−2@, …, @-D+2@, @-D@.
{-@ type WaveFront M N D = {xs : [DLN M N D] | _wfDiags (_kdiag (head xs)) xs} @-}

{-@ inline furthestReaching @-}
-- | Select the furthest-reaching candidate of two 'DL' nodes competing for the
-- same k-diagonal, as required by the Myers algorithm.
--
-- The candidate that has advanced further along the \( x \)-axis (larger 'poi')
-- is the furthest-reaching endpoint on that diagonal.
--
-- Precondition: arguments @x@ and @y@ in @furthestReaching x y@ are in the
-- same /k-diagonal/, meaning that
--
-- > poi x - poj x == poi y - poj y`
--
-- and both argument nodes are within the same wave front,
--
-- > length (path x) == length (path y)
{-@ furthestReaching ::  x : DL
                     -> {y : DL | _kdiag x = _kdiag y}
                     -> {v : DL | v = x || v = y} @-}
furthestReaching :: DL -> DL -> DL
furthestReaching x y
  | poi x >= poi y = x
  | otherwise      = y

-- * Proving the algorithm termination in LiquidHaskell
--
-- The original algorithm is known to terminate because a wave front /eventually/ reaches the 'endPoint'.
-- To prove this, both inputs lengths are threaded within phantom parameters throughout.
-- In essence, both lengths are used to encode the edit grid and its end point.

{-@ inline manhattanDistance @-}
{-@ manhattanDistance :: lena : Nat -> lenb : Nat -> {i : Nat | lena >= i} -> { j : Nat | lenb >= j} -> Nat @-}
manhattanDistance :: Int -> Int -> Int -> Int -> Int
manhattanDistance lena lenb i j  = lena - i + lenb - j

{-@ reflect _minDistanceToGoal @-}
{-@ _minDistanceToGoal :: lena : Nat -> lenb : Nat
                       -> nodes:[{dl:DL | withinBounds lena lenb dl}] -> Nat / [len nodes] @-}
_minDistanceToGoal :: Int -> Int -> [DL] -> Int
_minDistanceToGoal lena lenb [] = 0
_minDistanceToGoal lena lenb (dl:dls) = min (manhattanDistance lena lenb (poi dl) (poj dl) ) (_minDistanceToGoal lena lenb dls)

{-@ ignore _reducesDistanceToGoal @-}
-- Use to prove termination of ses
{-@ _reducesDistanceToGoal :: lena : Nat -> lenb : Nat -> wf1:[{dl:DL | withinBounds lena lenb dl}] -> wf1:[{dl:DL | withinBounds lena lenb dl}] -> Bool @-}
_reducesDistanceToGoal :: Int -> Int -> [DL] -> [DL] -> Bool
_reducesDistanceToGoal lena lenb wf1 wf2 = _minDistanceToGoal lena lenb wf2 < _minDistanceToGoal lena lenb wf1

{-@ inline withinBounds @-}
{-@ withinBounds :: lena : Nat -> lenb : Nat -> dl : DL -> {v:Bool | v <=> (poi dl <= lena && poj dl <= lenb) } @-}
withinBounds :: Int -> Int -> DL -> Bool
withinBounds lena lenb dl = poi dl <= lena && poj dl <= lenb

{-@ inline endPoint @-}
endPoint :: Int -> Int -> DL -> Bool
endPoint lena lenb dl = poi dl == lena && poj dl == lenb

{-@ type DiagPred M N = i : Nat -> j : Nat -> {b : Bool | ((i >= M || j >= N) => not b)} @-}

-- | Build a /diagonal predicate/ — a closure that tests whether position
-- @(i, j)@ in the edit graph has a diagonal edge (a /match point/ in Myers'
-- terminology).
--
-- Indices are 0-based (\( i \in [0, lena) \), \( j \in [0, lenb) \) ),
-- unlike the 1-based convention of the original paper.
--
-- The first two 'Int' parameters stand for the lengths of the input lists,
-- which are captured from the outer scope to compute them only once.
{-@
canDiag :: (a -> b -> Bool)
        -> [a]
        -> [b]
        -> lena : Int
        -> lenb : Int
        -> DiagPred lena lenb
@-}
canDiag :: (a -> b -> Bool) -- ^ Custom equality predicate
        -> [a] -- ^ First input
        -> [b] -- ^ Second input
        -> Int -- ^ First input's length
        -> Int -- ^ Second input's lenth
        -> (Int -> Int -> Bool) -- ^ Diagonal predicate on the edit grid
canDiag eq as bs lena lenb = \i j ->
  (i < lena && j < lenb) && ((arAs ! i) `eq` (arBs ! j))
  where
    -- Lists are converted into arrays to have O(1) lookups.
    arAs = listArray (0,lena - 1) as
    arBs = listArray (0,lenb - 1) bs

-- | Perform one breadth-first search expansion step, advancing every wave front
-- 'DL' node by one 'DI' edit (one non-diagonal edge) and then following
-- any available snake.
--
-- For each node the 'dstep' produces two candidate successors by adding:
--
-- * An 'F' (delete) move: 'poi' incremented by 1.
-- * An 'S' (insert) move: 'poj' incremented by 1.
--
-- The resulting candidates are merged pairwise: the vertical successor of each
-- node is paired with the horizontal successor of the next node in the wave
-- front. The 'furthestReaching' between them is extended along the available
-- sequence of matching elements using 'addsnake'.
-- When this function is iterated from a single-node seed (as in 'ses'),
-- each such pair always lies on the same diagonal: an 'F' edge advances to the
-- next higher diagonal while an 'S' edge retreats to the next lower one, so the
-- two members of each pair straddle the same diagonal from opposite sides.
--
-- Precondition: The node list must be a non-empty @WaveFront@.
--
-- Postcondition: The node list must be a non-empty @WaveFront@
-- with one more node than the input.
{-@
dstep
  :: ib : Nat
  -> jb : Nat
  -> DiagPred ib jb
  -> d : Nat
  -> {nodes : WaveFront ib jb d | len nodes > 0}
  -> {v : WaveFront ib jb (d + 1) | len v > 0}
@-}
dstep
  :: Int                  -- ^ First input's length.
  -> Int                  -- ^ Second input's length.
  -> (Int -> Int -> Bool) -- ^ Diagonal predicate
  -> Int                  -- ^ The current D-length; used for the static check of wave front invariant.
  -> [DL]                 -- ^ A non-empty wave front of nodes at edit distance D
  -> [DL]                 -- ^ A non-empty wave front of nodes at edit distance D+1
-- NOTE: @_d@ is a phantom (apparently unused) parameter required by local LiquidHaskell specifications.
-- This parameter sits at the first equation as a workaround
-- to GHC removing it when desugaring multi-equation definitions.
-- See https://github.com/ucsd-progsys/liquidhaskell/issues/2704
dstep lena lenb _ _d [] = error "dstep: Cannot perform expansion on an empty list of nodes"
dstep lena lenb cd _ (dl:dls) =
  if poi dl >= lena then stepAndMerge dl dls
  else
    addsnake lena lenb cd (hStep dl) : stepAndMerge dl dls
  where
    {-@ hStep
          :: x : DLN lena lenb _d
          -> {v : DL | len (path v) = _d + 1 && poi v = poi x + 1 && poj v = poj x} @-}
    hStep node = node {poi = poi node + 1, path = F : path node}
    {-@ vStep
          :: x : DLN lena lenb _d
          -> {v : DL | len (path v) = _d + 1 && poi v = poi x && poj v = poj x + 1} @-}
    vStep node = node {poj = poj node + 1, path = S : path node}
    -- Merge vertical step of previous node with horizontal step of next node,
    -- selecting the furthest-reaching candidate for each shared k-diagonal,
    -- and extend it along matching elements.
    {-@ stepAndMerge
          :: prev: DLN lena lenb _d
          -> rest : {xs : [DLN lena lenb _d] | _wfDiags (_kdiag prev - 2) rest}
          -> {v : [DLN lena lenb (_d + 1)] | _wfDiags (_kdiag (head v)) v
                                          && (poj prev < lenb => len v > 0)
                                          && (poi prev < lena && poj prev < lenb =>
                                               _kdiag (head v) == _kdiag prev - 1)} / [len rest] @-}
    stepAndMerge prev dls =
      -- When a node lying on the bottom boundary is found on the wave front
      -- all upcoming nodes are discarted because their in-bound childs would
      -- eventually need to cross the former's diagonal (in /more/ steps)
      -- to reach the endpoint, and thus are not SES candidates.
      if poj prev >= lenb then []
      else case dls of
        [] -> [addsnake lena lenb cd $ vStep prev]
        (next:rest) ->
            if poi next >= lena then addsnake lena lenb cd (vStep prev) : stepAndMerge next rest
            else
              addsnake lena lenb cd (furthestReaching (vStep prev) (hStep next)) : stepAndMerge next rest

{-@ lazy addsnake@-}
-- | Follow a /snake/ from the current position of a 'DL' node.
--
-- A snake is a sequence of diagonal (cost-free) edges in the edit graph,
-- i.e. a run of equal elements that can be consumed simultaneously
-- from both input sequences without counting as an edit.  Starting from
-- @(poi dl, poj dl)@, this function advances both 'poi' and 'poj' as long
-- as consecutive elements match, leaving 'path' unchanged (diagonal moves
-- are not recorded as edit steps).
{-@
addsnake :: lena : Nat
         -> lenb : Nat
         -> DiagPred lena lenb
         -> {dl : DL | withinBounds lena lenb dl}
         -> {v : DL | path v == path dl
                   && _kdiag v = _kdiag dl
                   && withinBounds lena lenb v
                   && poi v >= poi dl
                   && poj v >= poj dl}
         / [manhattanDistance lena lenb (poi dl) (poj dl)]
@-}
addsnake :: Int                  -- ^ First input's length phantom parameter for invariant checking.
         -> Int                  -- ^ Second input's length phantom parameter for invariant checking.
         -> (Int -> Int -> Bool) -- ^ Equality predicate, a.k.a. 'canDiag'
         -> DL
         -> DL
addsnake ib jb cd dl
    | cd pi pj = addsnake ib jb cd $
                 dl {poi = pi + 1, poj = pj + 1, path = path dl}
    | otherwise   = dl
    where pi = poi dl; pj = poj dl

{-@ ignore ses @-}
-- | Compute shortest edit script (SES), as the minimum sequence of 'DI' edit
-- steps that transforms @as@ into @bs@, returned in reverse order.
--
-- @ses eq as bs@ runs the Myers O(ND) diff algorithm:
--
-- 1. __Seed__: create an initial 0-path wave front @[addsnake boundary cd (DL 0 0 [])]@
--    having a single node on the tip of the longest origin-sourced snake.
-- 2. __Search__: for each wave front at edit distance \( D = 0, 1, \ldots \),
--    check whether any node has reached the goal @(lena, lenb)@. If not,
--    apply 'dstep' to advance to edit distance \( D+1 \).
-- 3. __Extract__: the first goal node's 'path' field carries the edit
--    trace in reverse order.
--
-- The search loop uses a fuel counter bounded by @lena + lenb + 1@,
-- which is the maximum number of edit distances that need to be explored
-- (the worst case is deleting all of @as@ and inserting all of @bs@).
--
-- This implementation deviates from the paper in the folowing way: rather than updating a shared
-- diagonal frontier array in place, as in the original paper, it builds a new
-- list of 'DL' nodes for each value of \( D \). This is simpler but carries a
-- larger per-node overhead: each 'DL' holds its own edit trace as a @['DI']@
-- list that structurally shares its tail with the parent node's trace (consing
-- one step reuses the existing spine), rather than the paper's
-- single-integer-per-diagonal representation. The asymptotic time
-- and space complexity — \( O(ND) \) and \( O(D^2) \) respectively — is
-- unchanged.
ses :: (a -> b -> Bool) -> [a] -> [b] -> [DI]
ses eq as bs = search 0 [addsnake lena lenb cd (DL 0 0 [])]
            where cd = canDiag eq as bs lena lenb
                  lena = length as; lenb = length bs
                  {-@ search :: d : Nat
                             -> dls : WaveFront lena lenb d
                             -> {v : [DI] | len v = d}
                             / [_minDistanceToGoal lena lenb dls] @-}
                  search :: Int -> [DL] -> [DI]
                  search _ [] = error "ses: The search must have a seed node"
                  search d wf = case findEndpoint lena lenb wf of
                      Just p  -> path p
                      Nothing -> search (d + 1) (dstep lena lenb cd d wf)
                  {-@ assume findEndpoint :: i : Nat -> j : Nat -> xs : [DL]
                                          -> { m : Maybe {dl : DL | endPoint i j dl}
                                             | m == Nothing => _minDistanceToGoal i j xs > 0} @-}
                  findEndpoint :: Int -> Int -> [DL] -> Maybe DL
                  findEndpoint i j = find (endPoint i j)

-- | Takes two lists and returns a list of differences between them. This is
-- 'getDiffBy' with '==' used as predicate.
--
-- > > getDiff ["a","b","c","d","e"] ["a","c","d","f"]
-- > [Both "a" "a",First "b",Both "c" "c",Both "d" "d",First "e",Second "f"]
-- > > getDiff "abcde" "acdf"
-- > [Both 'a' 'a',First 'b',Both 'c' 'c',Both 'd' 'd',First 'e',Second 'f']
getDiff :: (Eq a) => [a] -> [a] -> [Diff a]
getDiff = getDiffBy (==)

-- | Takes two lists and returns a list of differences between them, grouped
-- into chunks. This is 'getGroupedDiffBy' with '==' used as predicate.
--
-- > > getGroupedDiff "abcde" "acdf"
-- > [Both "a" "a",First "b",Both "cd" "cd",First "e",Second "f"]
{-@ getGroupedDiff :: Eq a => [a] -> [a]
                           -> {v:[GroupedDiff a a] | noStuttering v} @-}
getGroupedDiff :: (Eq a) => [a] -> [a] -> [Diff [a]]
getGroupedDiff = getGroupedDiffBy (==)

-- | A form of 'getDiff' with no 'Eq' constraint. Instead, an equality predicate
-- is taken as the first argument.
getDiffBy :: (a -> b -> Bool) -> [a] -> [b] -> [PolyDiff a b]
getDiffBy _ a [] = map First a
getDiffBy _ [] b = map Second b
getDiffBy eq a b = markup a b . reverse $ ses eq a b
    where markup (x:xs) (y:ys) ds
            | eq x y = Both x y : markup xs ys ds
          markup (x:xs)   ys   (F:ds) = First x  : markup xs ys ds
          markup   xs   (y:ys) (S:ds) = Second y : markup xs ys ds
          markup _ _ _ = []

-- | Like 'getGroupedDiff' but accepts a custom equality predicate.
--
-- Postcondition: the output list is guaranteed to be /chunked/. i.e. no two adjacent
-- elements share the same constructor.
{-@ getGroupedDiffBy :: (a -> b -> Bool) -> [a] -> [b]
                     -> {vs : [GroupedDiff a b] | noStuttering vs} @-}
getGroupedDiffBy :: (a -> b -> Bool) -> [a] -> [b] -> [PolyDiff [a] [b]]
getGroupedDiffBy eq a b = groupDiff $ getDiffBy eq a b

{-@ groupDiff :: xs : [PolyDiff a b]
              -> {vs : [GroupedDiff a b] | noStuttering vs
                  // The following predicates allow LiquidHaskell keep track
                  // of the head constructor in each recursive call.
                  && (headIsFirst xs  <=> headIsFirst vs)
                  && (headIsSecond xs <=> headIsSecond vs)
                  && (headIsBoth xs   <=> headIsBoth vs)} @-}
groupDiff :: [PolyDiff a b] -> [PolyDiff [a] [b]]
groupDiff (First x  : xs) = let (fs, rest) = leadingFirsts  xs
                             in First (x:fs) : groupDiff rest
groupDiff (Second x : xs) = let (sc, rest) = leadingSeconds xs
                             in Second (x:sc) : groupDiff rest
groupDiff (Both x y : xs) = let (bxs, bys, rest) = leadingBoths xs
                             in Both (x:bxs) (y:bys) : groupDiff rest
groupDiff [] = []

{-@ leadingFirsts :: xs : [PolyDiff a b]
                   -> {v : ([a], [PolyDiff a b]) | not (headIsFirst (snd v))
                       // Here and in the analogous helpers,
                       // the length comparison is needed for termination check.
                       && len (snd v) <= len xs
                       && (headIsSecond xs => headIsSecond (snd v))
                       && (headIsBoth xs   => headIsBoth (snd v))} @-}
leadingFirsts :: [PolyDiff a b] -> ([a], [PolyDiff a b])
leadingFirsts (First y : diffs) = let (firsts, rest) = leadingFirsts diffs
                                   in (y:firsts, rest)
leadingFirsts diffs = ([],diffs)

{-@ leadingSeconds :: xs : [PolyDiff a b]
                    -> {v : ([b], [PolyDiff a b]) | not (headIsSecond (snd v))
                        && len (snd v) <= len xs
                        && (headIsFirst xs => headIsFirst (snd v))
                        && (headIsBoth xs  => headIsBoth (snd v))} @-}
leadingSeconds :: [PolyDiff a b] -> ([b], [PolyDiff a b])
leadingSeconds (Second y : diffs) = let (seconds, rest) = leadingSeconds diffs
                                     in (y:seconds, rest)
leadingSeconds diffs = ([],diffs)

{-@ leadingBoths :: xs : [PolyDiff a b]
                  -> {v : ([a], [b], [PolyDiff a b]) | not (headIsBoth (thd3 v))
                      && len (thd3 v) <= len xs
                      && (headIsFirst xs  => headIsFirst (thd3 v))
                      && (headIsSecond xs => headIsSecond (thd3 v))
                      && len (fst3 v) == len (snd3 v)} @-}
leadingBoths :: [PolyDiff a b] -> ([a], [b], [PolyDiff a b])
leadingBoths (Both w z : diffs) = let (as, bs, rest) = leadingBoths diffs
                                   in (w:as, z:bs, rest)
leadingBoths diffs = ([], [], diffs)
