{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE TypeSynonymInstances #-}

import Control.DeepSeq
import GHC.Generics
import System.Random

import Data.Algorithm.Diff

deriving instance Generic (Diff a)

instance NFData a => NFData (Diff a)


main :: IO ()
main = doBenchMarks 37

doBenchMarks :: Int -> IO ()
doBenchMarks seed =
  let rbools = randoms (mkStdGen seed) :: [Bool]
      (s1000_1, rbools1) = splitAt 10000 rbools
      (s1000_2, rbools2) = splitAt 10000 rbools1
      s500_2 = take 5000 s1000_2
      res = getDiff s1000_1 s500_2
  in s1000_1 `deepseq` s1000_2 `deepseq` s500_2 `deepseq` res  `deepseq` pure ()
