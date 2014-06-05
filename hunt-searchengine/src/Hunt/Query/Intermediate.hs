{-# LANGUAGE FlexibleContexts  #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeFamilies      #-}

-- ----------------------------------------------------------------------------
{- |
  The intermediate query results which have to be merged for the various combinatorial operations.

  'toResult' creates the final result which includes the document (and word) hits.
-}
-- ----------------------------------------------------------------------------

module Hunt.Query.Intermediate
(
  -- * The intermediate result type.
    Intermediate
  , IntermediateContexts
  , IntermediateWords

  -- * Construction
  , empty

  -- * Query
  , null
  , size

  -- * Combine
  , union
  , merge
  , difference
  , intersection
  , unions
  , unionsDocLimited
  , merges
  , mergesDocLimited
--  , intersections1
--  , differences1

  -- * Conversion
  , fromList
  , fromListCxs
  , toResult
)
where

import           Prelude               hiding (null)
import qualified Prelude               as P

import           Control.Applicative   hiding (empty)

import qualified Data.List             as L
import           Data.Map              (Map)
import qualified Data.Map              as M
import           Data.Maybe

import           Hunt.Query.Result     hiding (null)

import           Hunt.Common
import qualified Hunt.Common.DocIdMap  as DM
import           Hunt.Common.Document  (DocumentWrapper (..), emptyDocument)
import qualified Hunt.Common.Positions as Pos

import           Hunt.DocTable         (DocTable)
import qualified Hunt.DocTable         as Dt

-- ------------------------------------------------------------

-- | The intermediate result used during query processing.

type Intermediate         = DocIdMap IntermediateContexts
type IntermediateContexts = (Map Context IntermediateWords, Boost)
type IntermediateWords    = Map Word (WordInfo, Positions)

-- ------------------------------------------------------------

-- | Create an empty intermediate result.
empty :: Intermediate
empty = DM.empty

-- | Check if the intermediate result is empty.
null :: Intermediate -> Bool
null = DM.null

-- | Returns the number of documents in the intermediate result.
size :: Intermediate -> Int
size = DM.size

-- | Merges a bunch of intermediate results into one intermediate result by unioning them.
unions :: [Intermediate] -> Intermediate
unions = L.foldl' union empty

-- | Intersect two sets of intermediate results.
intersection :: Intermediate -> Intermediate -> Intermediate
intersection = DM.intersectionWith combineContexts

{-
-- TODO: make this safe and efficient
-- foldl is inefficient because the neutral element of the intersection is >everything<

intersections1 :: [Intermediate] -> Intermediate
intersections1 = L.foldl1' intersection

-- TODO: same as for 'intersections1' but this is not commutative

differences1 :: [Intermediate] -> Intermediate
differences1 = L.foldl1' difference
-}

-- | Union two sets of intermediate results.
--   Can be used on \"query intermediates\".
--
-- /Note/: See 'merge' for a similar function.

union :: Intermediate -> Intermediate -> Intermediate
union = DM.unionWith combineContexts

-- | Merge two sets of intermediate results.
--   Search term should be the same.
--   Can be used on \"context intermediates\".
--
-- /Note/: See 'union' for a similar function.

merge :: Intermediate -> Intermediate -> Intermediate
merge = DM.unionWith mergeContexts

-- | Merges a bunch of intermediate results into one intermediate result by merging them.

merges :: [Intermediate] -> Intermediate
merges = L.foldl' merge empty

-- | Subtract two sets of intermediate results.

difference :: Intermediate -> Intermediate -> Intermediate
difference = DM.difference

-- | Create an intermediate result from a list of words and their occurrences.
--
-- The first arg is the phrase searched for split into its parts
-- all these parts are stored in the WordInfo as term
--
-- Beware! This is extremly optimized and will not work for merging arbitrary intermediate results!
-- Based on resultByDocument from Hunt.Common.RawResult
--
-- merge of list with 'head' because second argument is always a singleton
-- otherwise >> (flip $ (:) . head) [1,2] [3,4] == [3,1,2]

fromList :: Schema -> [Word] -> Context -> RawResult -> Intermediate
fromList sc ts c os
    = DM.map transform                            -- ::   DocIdMap IntermediateContexts
      $ DM.unionsWith (flip $ (:) . head)         -- ::   DocIdMap [(Word, (WordInfo, Positions))]
      $ map insertWords os                        -- :: [ DocIdMap [(Word, (WordInfo, Positions))] ]
    where
      -- O(size o)
      insertWords :: (Word, Occurrences) -> DocIdMap [(Word, (WordInfo, Positions))]
      insertWords (w, o)
          = DM.map toWordInfo o
            where
              toWordInfo o' = [(w, (WordInfo ts 0.0 , o'))] -- singleton list

      -- O(w*log w)
      transform :: [(Word, (WordInfo, Positions))] -> IntermediateContexts
      transform wl
          = ( M.singleton c (M.fromList wl)
            , weight
            )
      weight
          = fromMaybe defScore (cxWeight <$> M.lookup c sc)

-- XXX: optimize if necessary, see comments below
-- | Create an intermediate result from a list of words and their occurrences
--   with their associated context.

fromListCxs :: Schema -> [Word] -> [(Context, RawResult)] -> Intermediate
fromListCxs sc ts rs = merges $ map (uncurry (fromList sc ts)) rs

-- | Convert to a @Result@ by generating the 'WordHits' structure.
toResult :: (Applicative m, Monad m, DocTable d, e ~ Dt.DValue d) =>
            d -> Intermediate -> m (Result e)
toResult d im = do
    dh <- createDocHits d im
    return $ Result dh (createWordHits im)


-- XXX: IntMap.size is O(n) :(
-- | Union 'Intermediate's until a certain number of documents is reached/surpassed.

unionsDocLimited :: Int -> [Intermediate] -> Intermediate
unionsDocLimited n = takeOne ((>= n) . size) . scanl union empty
  where
  takeOne b (x:xs) = if P.null xs || b x then x else takeOne b xs
  takeOne _ _      = error "takeOne with empty list"


-- | Create the doc hits structure from an intermediate result.
createDocHits :: (Applicative m, Monad m, DocTable d, e ~ Dt.DValue d) =>
                 d -> Intermediate -> m (DocHits e)
createDocHits d = DM.traverseWithKey transformDocs
  where
  transformDocs did (ic,db)
    = let doc   = fromMaybe dummy <$> (Dt.lookup did d)
          dummy = wrap emptyDocument
      in (\doc' -> (DocInfo doc' db 0.0, M.map (M.map snd) ic)) <$> doc

-- | Create the word hits structure from an intermediate result.
--
-- the schema is used for the context weights
createWordHits :: Intermediate -> WordHits
createWordHits
    = DM.foldrWithKey transformDoc M.empty
    where
      -- XXX: boosting not used in wordhits
      transformDoc d (ic, _db) wh
          = M.foldrWithKey transformContext wh ic
          where
            transformContext c iw wh'
                = M.foldrWithKey insertWord wh' iw
                where
                  insertWord w (wi, pos) wh''
                      = if terms wi == [""]
                        then wh''
                        else M.insertWith combineWordHits
                             w
                             (wi, M.singleton c (DM.singleton d pos))
                             wh''

-- | Combine two tuples with score and context hits.
combineWordHits :: (WordInfo, WordContextHits) -> (WordInfo, WordContextHits)
                -> (WordInfo, WordContextHits)
combineWordHits (i1, c1) (i2, c2)
  = ( i1 <> i2
    , M.unionWith (DM.unionWith Pos.union) c1 c2
    )

-- XXX: 'combineContexts' is used in 'union' and 'intersection'.
--      maybe it should include the merge op as a parameter.
--      there is a difference in merging "query intermediates" and "context intermediates".
--        docboosts merge:
--          - on context merge: should be always the same since the query introduces it
--          - on query merge: default merge
--      merging "context intermediates" seems inefficient - maybe not because of hedge-union?

-- XXX: db merge is skewed on a context merge - include merge op?
-- | Combine two tuples with score and context hits.

combineContexts :: IntermediateContexts -> IntermediateContexts -> IntermediateContexts
combineContexts (ic1,db1) (ic2,db2)
    = (M.unionWith (M.unionWith merge') ic1 ic2, db1 * db2)
    where
      merge' (i1, p1) (i2, p2)
          = ( i1 <> i2
            , Pos.union p1 p2
            )

mergeContexts :: IntermediateContexts -> IntermediateContexts -> IntermediateContexts
mergeContexts cx1 (ic2,_db2)
    = combineContexts cx1 (ic2, defScore)


-- XXX: IntMap.size is O(n) :(
-- | Merge 'Intermediate's until a certain number of documents is reached/surpassed.

mergesDocLimited :: Int -> [Intermediate] -> Intermediate
mergesDocLimited n = takeOne ((>= n) . size) . scanl merge empty
  where
  takeOne b (x:xs) = if P.null xs || b x then x else takeOne b xs
  takeOne _ _      = error "takeOne with empty list"

-- ------------------------------------------------------------
