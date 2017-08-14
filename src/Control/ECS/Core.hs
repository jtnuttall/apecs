{-# LANGUAGE ScopedTypeVariables, FlexibleContexts, GeneralizedNewtypeDeriving, ConstraintKinds #-}
module Control.ECS.Core where

import qualified Data.IntSet as S

import Control.ECS.Storage
import Control.Monad.State
import Control.Monad.Reader

newtype Store  c = Store  {unStore  :: Storage c}
class w `Has` c where
  getStore :: Monad m => System w m (Store c)

type Valid w m c = (Has w c, Component c, SStorage m (Storage c))

newtype System w m a = System {unSystem :: ReaderT w m a} deriving (Functor, Monad, Applicative, MonadIO, MonadTrans)

newtype Slice  c = Slice  {toList   :: [Entity c]} deriving (Eq, Show)
newtype Reads  c = Reads  {unReads  :: SSafeElem (Storage c)}
newtype Writes c = Writes {unWrites :: SSafeElem (Storage c)}
newtype Elem   c = Elem   {unElem   :: SElem (Storage c)}

{-# INLINE runSystem #-}
runSystem :: System w m a -> w -> m a
runSystem sys = runReaderT (unSystem sys)

{-# INLINE runWith #-}
runWith :: w -> System w m a -> m a
runWith = flip runSystem

{-# INLINE empty #-}
empty :: SStorage m (Storage c) => m (Store c)
empty = Store <$> sEmpty

{-# INLINE slice #-}
slice :: forall w m c. Valid w m c => System w m (Slice c)
slice = do Store s :: Store c <- getStore
           fmap Slice . lift $ sSlice s

{-# INLINE isMember #-}
isMember :: forall w m c. Valid w m c => Entity c -> System w m Bool
isMember ety = do Store s :: Store c <- getStore
                  lift $ sMember s ety

{-# INLINE retrieve #-}
retrieve :: forall w m c a. Valid w m c => Entity a -> System w m (Reads c)
retrieve ety = do Store s :: Store c <- getStore
                  fmap Reads . lift $ sRetrieve s ety

{-# INLINE store #-}
store :: forall w m c a. Valid w m c => Writes c -> Entity a -> System w m ()
store (Writes w) ety = do Store s :: Store c <- getStore
                          lift $ sStore s w ety

{-# INLINE destroy #-}
destroy :: forall w m c. Valid w m c => Entity c -> System w m ()
destroy ety = do Store s :: Store c <- getStore
                 lift $ sDestroy s ety

{-# INLINE mapRW #-}
mapRW :: forall w m c. Valid w m c => (Elem c -> Elem c) -> System w m ()
mapRW f = do Store s :: Store c <- getStore
             lift $ sSlice s >>= mapM_ (\e -> do r <- sRUnsafe s e; sWUnsafe s (unElem . f $ Elem r) e)

{-# INLINE mapR #-}
mapR :: forall w m r wr. (Valid w m r, Valid w m wr) => (Elem r -> Writes wr) -> System w m ()
mapR f = do Store sr :: Store r  <- getStore
            Store sw :: Store wr <- getStore
            lift $ sSlice sr >>= mapM_
              (\e -> do r <- sRUnsafe sr e; sStore sw (unWrites . f . Elem $ r) e)

{-# INLINE union #-}
union :: Slice s1 -> Slice s2 -> Slice ()
union (Slice s1) (Slice s2) = let set1 = S.fromList . fmap unEntity $ s1
                                  set2 = S.fromList . fmap unEntity $ s2
                               in Slice . fmap Entity . S.toList $ S.intersection set1 set2

instance (w `Has` a, w `Has` b) => w `Has` (a, b) where
  {-# INLINE getStore #-}
  getStore = do Store sa :: Store a <- getStore
                Store sb :: Store b <- getStore
                return $ Store (sa, sb)