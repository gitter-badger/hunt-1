{-# LANGUAGE ConstraintKinds       #-}
{-# LANGUAGE DataKinds             #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE KindSignatures        #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverlappingInstances  #-}
{-# LANGUAGE TypeFamilies          #-}
{-# LANGUAGE UndecidableInstances  #-}
-- {-# LANGUAGE Rank2Types            #-}
-- {-# LANGUAGE EmptyDataDecls        #-}
-- {-# LANGUAGE TypeSynonymInstances  #-}
-- {-# LANGUAGE OverloadedStrings     #-}
-- {-# LANGUAGE GADTs                 #-}
-- {-# LANGUAGE StandaloneDeriving    #-}

module AssocTypes2 where

import           Control.Applicative ((<$>))
import           Control.Arrow       (first, second)
import           GHC.Exts            (Constraint)

-- ----------------------------------------

class Index i where
    type IKey i v :: *
    type IVal i v :: *
    type IToL i v :: *
    type ICon i v :: Constraint
    type ICon i v = ()

    insert   :: ICon i v => IKey i v -> IVal i v -> i v -> i v
    delete   :: ICon i v => IKey i v             -> i v -> i v
    empty    :: ICon i v =>                         i v
    fromList :: ICon i v => IToL i v             -> i v
    toList   :: ICon i v =>                         i v -> IToL i v
    search   :: ICon i v => IKey i v             -> i v -> IToL i v
                                                               -- nicht Maybe (IVal i), zu speziell
                                                               -- Key-Value liste erlaubt auch
                                                               -- unscharfes Suchen

-- ----------------------------------------
--
-- functor class with the possibility to constrain the element arg and result type

class CFunctor f where
    type Cx f a :: Constraint
    type Cx f a = ()		-- default constraint: empty

    cmap :: (Cx f a, Cx f b) => (a -> b) -> f a -> f b

-- see http://stackoverflow.com/questions/9016521/associated-types-and-container-elements/9016783
-- answer 2

-- ----------------------------------------

type Map k v = [(k, v)]         -- dummy for Data.Map

insertXS :: Eq k => k -> v -> Map k v -> Map k v
insertXS k v xs = (k, v) : deleteXS k xs

deleteXS :: Eq k => k -> Map k v -> Map k v
deleteXS k xs = filter ((/= k) . fst) xs

updateXS :: Eq k => (v -> v -> v) -> k -> v -> Map k v -> Map k v
updateXS op k v xs =
    case lookup k xs of
      Nothing -> (k, v) : xs
      Just v1 -> insertXS k (v `op` v1) xs

changeXS :: Eq k => k -> (v -> v) -> Map k v -> Map k v
changeXS k f xs =
    case lookup k xs of
      Nothing -> error "changeXS: Nothing found"
      Just v1 -> insertXS k (f v1) xs

mapXS :: (v -> w) -> Map k v -> Map k w
mapXS f xs = map (second f) xs

emptyXS :: Map k v
emptyXS = []

searchXS :: Eq k => k -> Map k v -> [(k, v)]
searchXS k xs = maybe [] (\ v -> [(k, v)]) $ lookup k xs

-- ----------------------------------------

newtype StringMap v = SM (Map String v)
    deriving (Show)

instance Index StringMap where
    type IKey StringMap v = String
    type IVal StringMap v = v
    type IToL StringMap v = [(String, v)]

    insert k v (SM m) = SM $ insertXS k v m
    delete k   (SM m) = SM $ deleteXS k   m
    empty             = SM emptyXS
    fromList xs       = SM xs
    search k   (SM m) = searchXS k m
    toList     (SM m) = m

instance Functor StringMap where
    fmap f (SM m) = SM $ mapXS f m

instance CFunctor StringMap where
    cmap = fmap

-- ----------------------------------------

newtype Text = T String         -- dummy for Data.Text

type ISO' a b = (a -> b, b -> a)

isoTextString :: ISO' Text String
isoTextString = (\ (T s) -> s, T)

unpack :: Text -> String
unpack = fst isoTextString

pack :: String -> Text
pack   = snd isoTextString

newtype TextMap v = TM (StringMap v)
    deriving (Show)

instance Index TextMap where
    type IKey TextMap v = Text
    type IVal TextMap v = v
    type IToL TextMap v = [(Text, v)]

    insert k v (TM m) = TM $ insert (unpack k) v m
    delete k   (TM m) = TM $ delete (unpack k)   m
    empty             = TM empty
    fromList xs       = TM $ fromList $ map (first unpack) xs
    search k   (TM m) = first pack <$> search (unpack k) m
    toList     (TM m) = first pack <$> toList m

instance Functor TextMap where
    fmap f (TM m) = TM $ fmap f m

instance CFunctor TextMap where
    cmap = fmap

-- ----------------------------------------
--
-- example: value of a map is transformed into something else

newtype ByteString = BS String          -- dummy for ByteString
    deriving (Show)

class Compression a where               -- dummy for serialisation and compression
    compress   :: a -> ByteString
    decompress :: ByteString -> a

newtype CompStrMap v = CM (StringMap ByteString)
    deriving (Show)

instance Index CompStrMap where
    type IKey CompStrMap v = String
    type IVal CompStrMap v = v
    type IToL CompStrMap v = [(String, v)]
    type ICon CompStrMap v = Compression v

    insert k v (CM m) = CM $ insert k (compress v) m
    delete k   (CM m) = CM $ delete k              m
    empty             = CM $ empty
    fromList xs       = CM $ fromList $ map (second compress) xs
    search k   (CM m) = second decompress <$> search k m
    toList     (CM m) = second decompress <$> toList m

instance CFunctor CompStrMap where
    type Cx CompStrMap v = (Compression v)

    cmap f (CM m) = CM $ cmap (compress . f . decompress) m

-- ----------------------------------------

newtype ContextWordMap impl v = CWM (Map String (impl v))
    deriving (Show)

-- here {-# LANGUAGE UndecidableInstances #-} is needed

instance Index (ContextWordMap impl) where

    type IKey (ContextWordMap impl) v = (Maybe String, Maybe (IKey impl v))
                                                                        -- zusammengesetzte Schluessel
									-- (cx, w) mit Maybe fuer
									-- fehlende Kontext/Wort Teile
    type IVal (ContextWordMap impl) v = v
    type IToL (ContextWordMap impl) v = [(String, IToL impl v)]         -- geschachtelte Listen
									-- [(cx1,[(w1,v1),...]),...]
    type ICon (ContextWordMap impl) v = (Index impl, v ~ IVal impl v, ICon impl (IVal impl v))

    insert k v (CWM m)
        = case k of
            (Just c,  Nothing) -> CWM $ updateXS (const id) c empty m   -- neuen Kontext c erzeugen, falls noch nicht da
            (Just c,  Just w)  -> CWM $ changeXS c (insert w v)         -- Wort w in Kontext c einfuegen
                                      $ updateXS (const id) c empty m
            (Nothing, Nothing) -> CWM m                                 -- noop
            (Nothing, Just w)  -> CWM $ mapXS (insert w v) m            -- Wort in alle Kontexte einfuegen

    delete k (CWM m)
        = case k of
            (Nothing, Nothing) -> empty                                 -- alles loeschen
            (Nothing, Just w)  -> CWM $ mapXS (delete w) m              -- in allen Kontexten w loeschen
            (Just c,  Nothing) -> CWM $ deleteXS c m                    -- einen Context c loeschen
            (Just c,  Just w)  -> CWM $ changeXS c (delete w) $ updateXS (const id) c empty m
                                                                        -- ein Wort w in einem Kontext c loeschen
    empty = CWM $ emptyXS

    fromList xs
        = CWM $ foldr ins emptyXS xs
          where
            ins (c, ws) m = insertXS c (fromList ws) m

    toList (CWM m)
--      = [(c, toList im) | (c, im) <- m]
        = mapXS toList m

    search k (CWM m)
        = case k of
            (Just c,  Just w)  -> let r = searchXS c m                  -- Suche in einem Wort-Index
                                  in [(cx, search w im) | (cx, im) <- r]
            (Nothing, Just w)  -> -- [(cx, search w im) | (cx, im) <- m]
                                  mapXS (search w) m                    -- Suche in allen Wort-Indexen
            _                  -> []

instance (Functor impl) => Functor (ContextWordMap impl) where
    fmap f (CWM m) = CWM $ mapXS (fmap f) m

instance CFunctor (ContextWordMap impl) where
    type Cx (ContextWordMap impl) v = (CFunctor impl, Cx impl v)

    cmap f (CWM m) = CWM $ mapXS (cmap f) m

-- ----------------------------------------
--
-- values

instance Compression Int where
    compress          = BS . show
    decompress (BS s) = read s

xs1, xs2 :: [(String, Int)]
xs1 = [("abc", 1), ("xyz", 2), ("123", 3)]
xs2 = [("aaa", 1), ("xxx", 2), ("zzz", 3)]


sm1 :: StringMap Int
sm1 = fromList xs1

tm1 :: TextMap Int
tm1 = fromList $ map (first pack) xs1

cm1 :: CompStrMap Int
cm1 = fromList xs1

type ContextIndex  = ContextWordMap StringMap  Int
type ContextIndex' = ContextWordMap CompStrMap Int

cx1, cx2, cx3, cx4, cx5, cx6, cx7, cx8 :: ContextIndex'  -- ' oder nicht ', geht beides

cx1 = fromList [("A",xs1),("B",xs2)]
cx2 = insert (Just "C", Just "111") 42 cx1
cx3 = insert (Just "A", Just "111") 43 cx2
cx4 = insert (Nothing, Just "ddd") 99 cx3
cx5 = delete (Nothing, Just "ddd") cx4
cx6 = delete (Just "A", Just "abc") cx5
cx7 = delete (Just "A", Nothing) cx6
cx8 = delete (Nothing, Nothing) cx7

-- ----------------------------------------
-- -}
