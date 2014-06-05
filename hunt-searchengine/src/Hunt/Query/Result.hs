{-# LANGUAGE StandaloneDeriving #-}

-- ----------------------------------------------------------------------------
{- |
  Module     : Hunt.Query.Result
  Copyright  : Copyright (C) 2007 Timo B. Huebel
  License    : MIT

  Maintainer : Timo B. Huebel (tbh@holumbus.org)
  Stability  : experimental
  Portability: portable

  The data type for results of Holumbus queries.

  The result of a query is defined in terms of two partial results,
  the documents containing the search terms and the words which
  are possible completions of the search terms.
-}
-- ----------------------------------------------------------------------------

module Hunt.Query.Result
  (
  -- * Result data types
  Result (..)
  , DocHits
  , DocContextHits
  , DocWordHits
  , WordHits
  , WordContextHits
  , WordDocHits
  , DocInfo (..)
  , WordInfo (..)
  , Score
  , Weight
  , Boost
  , DocBoosts

  -- * Construction
  , emptyResult

  -- * Query
  , null
  , sizeDocHits
  , sizeWordHits
  , maxScoreDocHits
  , maxScoreWordHits
  , getDocuments

  -- * Transform
  , setDocScore
  , setWordScore
  )
where

import           Prelude              hiding (null)

import qualified Data.List            as L
import           Data.Map             (Map)
import qualified Data.Map             as M
import           Data.Text            (Text)

import           Hunt.Common
import qualified Hunt.Common.DocIdMap as DM

-- ------------------------------------------------------------

-- | The combined result type for Holumbus queries.
data Result e
  = Result
    { docHits  :: DocHits e  -- ^ The documents matching the query.
    , wordHits :: WordHits   -- ^ The words which are completions of the query terms.
    }
deriving instance Show e => Show (Result e)


-- | Information about an document.
data DocInfo e
  = DocInfo
    { document :: e      -- ^ The document itself.
    , docBoost :: Weight -- ^ The document weight, init with @1.0@
    , docScore :: Score  -- ^ The score for the document (initial score for all documents is @0.0@).
    }
deriving instance Show e => Show (DocInfo e)

-- | Information about a word.
data WordInfo
  = WordInfo
    { terms     :: Terms -- ^ The search terms that led to this very word.
    , wordScore :: Score -- ^ The frequency of the word in the document for a context.
    }
    deriving (Eq, Show)

instance Monoid WordInfo where
    mempty
        = WordInfo [] noScore
    mappend (WordInfo t1 s1) (WordInfo t2 s2)
        = WordInfo (t1 `L.union` t2) (s1 <> s2)

-- XXX: a list for now - maybe useful for testing
-- | Boosting of a single document.
type Boost = Weight

-- | Document boosting.
type DocBoosts       = DocIdMap Boost

-- | A mapping from a document to it's score and the contexts where it was found.
type DocHits e       = DocIdMap (DocInfo e, DocContextHits)

-- | A mapping from a context to the words of the document that were found in this context.
type DocContextHits  = Map Context DocWordHits

-- | A mapping from a word of the document in a specific context to it's positions.
type DocWordHits     = Map Word Positions

-- | A mapping from a word to it's score and the contexts where it was found.
type WordHits        = Map Word (WordInfo, WordContextHits)

-- | A mapping from a context to the documents that contain the word that were found in this context.
type WordContextHits = Map Context WordDocHits

-- | A mapping from a document containing the word to the positions of the word.
type WordDocHits     = Occurrences

-- | The original search terms entered by the user.
type Terms           = [Text]

-- ------------------------------------------------------------

-- | Create an empty result.
emptyResult :: Result e
emptyResult = Result DM.empty M.empty

-- | Query the number of documents in a result.
sizeDocHits :: Result e -> Int
sizeDocHits = DM.size . docHits

-- | Query the number of documents in a result.
sizeWordHits :: Result e -> Int
sizeWordHits = M.size . wordHits

-- | Query the maximum score of the documents.
maxScoreDocHits :: Result e -> Score
maxScoreDocHits = DM.foldr (\(di, _) r -> max (docScore di) r) 0.0 . docHits

-- | Query the maximum score of the words.
maxScoreWordHits :: Result e -> Score
maxScoreWordHits = M.foldr (\(wi, _) r -> max (wordScore wi) r) 0.0 . wordHits

-- | Test if the result contains anything.
null :: Result e -> Bool
null = DM.null . docHits

-- | Set the score in a document info.
setDocScore :: Score -> DocInfo e -> DocInfo e
setDocScore s di@(DocInfo{}) = di { docScore = s }

-- | Set the score in a word info.
setWordScore :: Score -> WordInfo -> WordInfo
setWordScore s wi@(WordInfo{}) = wi { wordScore = s }

-- | Extract all documents from a result.
getDocuments :: Result e -> [e]
getDocuments r = map (document . fst . snd) . DM.toList $ docHits r

-- ------------------------------------------------------------
