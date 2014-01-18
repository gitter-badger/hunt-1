{-# LANGUAGE DeriveDataTypeable         #-}
{-# LANGUAGE FlexibleInstances          #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE TypeSynonymInstances       #-}

-- ----------------------------------------------------------------------------
{-
  Occurrences compression using the bzip2 library
    http://www.bzip.org/

  Haskell-Bindings
    http://hackage.haskell.org/package/bzlib
-}
-- ----------------------------------------------------------------------------

module Holumbus.Common.Occurrences.Compression.BZip
  (
  -- * Compression types
    CompressedOccurrences
  , OccCompression(..)
  )
where

import qualified Codec.Compression.BZip                  as ZIP

import           Control.Applicative                     ((<$>))
import           Control.DeepSeq

import           Data.Binary                             (Binary (..))
import qualified Data.Binary                             as B
import qualified Data.ByteString                         as BS
import qualified Data.ByteString.Lazy                    as BL
import qualified Data.ByteString.Short                   as Short
import           Data.Typeable

import qualified Holumbus.Common.DocIdMap                as DM
import           Holumbus.Common.Occurrences
import           Holumbus.Common.Occurrences.Compression

-- ----------------------------------------------------------------------------

-- TODO
--
-- The BS.ByteString is a candidate for a BS.ShortByteString available with bytestring 0.10.4,
-- then 5 machine words can be saved per value

newtype CompressedOccurrences = ComprOccs { unComprOccs :: Short.ShortByteString }
  deriving (Eq, Show, Typeable)

mkComprOccs :: Short.ShortByteString -> CompressedOccurrences
mkComprOccs b = ComprOccs $!! b

-- ----------------------------------------------------------------------------

instance NFData CompressedOccurrences where
-- use default implementation: eval to WHNF, and that's sufficient

-- ----------------------------------------------------------------------------

instance OccCompression CompressedOccurrences where
  compressOcc   = compress
  decompressOcc = decompress
  differenceWithKeySet ks = compress . (flip DM.diffWithSet) ks . decompress

-- ----------------------------------------------------------------------------

instance Binary CompressedOccurrences where
  put = put . Short.fromShort . unComprOccs
  get = mkComprOccs . Short.toShort . BS.copy <$> get

-- to avoid sharing the data with the input the ByteString is physically copied
-- before return. This should be the single place where sharing is introduced,
-- else the copy must be moved to mSBs

-- ----------------------------------------------------------------------------

--compress :: Binary a => a -> CompressedOccurrences
compress :: Occurrences -> CompressedOccurrences
compress = mkComprOccs . Short.toShort . BL.toStrict . ZIP.compress . B.encode

--decompress :: Binary a => CompressedOccurrences -> a
decompress :: CompressedOccurrences -> Occurrences
decompress = B.decode . ZIP.decompress . BL.fromStrict . Short.fromShort . unComprOccs

-- ----------------------------------------------------------------------------
