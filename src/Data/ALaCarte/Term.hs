{-# LANGUAGE EmptyDataDecls, GADTs, KindSignatures #-}

--------------------------------------------------------------------------------
-- |
-- Module      :  Data.ALaCarte.Term
-- Copyright   :  3gERP, 2010
-- License     :  AllRightsReserved
-- Maintainer  :  Tom Hvitved, Patrick Bahr, and Morten Ib Nielsen
-- Stability   :  unknown
-- Portability :  unknown
--
-- This module defines the central notion of /terms/ and its
-- generalisation contexts.
--
--------------------------------------------------------------------------------

module Data.ALaCarte.Term
    (Cxt (..),
     Hole,
     NoHole,
     Context,
     Nothing,
     Term,
     Const,
     unTerm,
     toCxt,
     simpCxt,
     constTerm,
     ) where

import Control.Applicative hiding (Const)
import Control.Monad hiding (mapM, sequence)

import Data.Traversable
import Data.Foldable

import Prelude hiding (mapM, sequence, foldl, foldl1, foldr, foldr1)


type Const f = f ()

{-| This function converts a constant to a term. This assumes that the
argument is indeed a constant, i.e. does not have a value for the
argument type of the functor f. -}

constTerm :: (Functor f) => Const f -> Term f
constTerm = Term . fmap (const undefined)

{-| This data type represents contexts over a signature. Contexts are
terms containing zero or more holes. The first type parameter is
supposed to be one of the phantom types 'Hole' and 'NoHole'. The
second parameter is the signature of the context. The third parameter
is the type of the holes. -}

data Cxt :: * -> (* -> *) -> * -> * where
            Term :: f (Cxt h f a) -> Cxt h f a
            Hole :: a -> Cxt Hole f a


{-| Phantom type that signals that a 'Cxt' might contain holes.  -}

data Hole

{-| Phantom type that signals that a 'Cxt' does not contain holes.
-}

data NoHole

type Context = Cxt Hole

simpCxt :: (Functor f) => f a -> Context f a
simpCxt = Term . fmap Hole

toCxt :: (Functor f) => Term f -> Context f a
toCxt (Term t) = Term $ fmap toCxt t

{-| Phantom type used to define 'Term'.  -}

data Nothing

instance Eq Nothing where
instance Ord Nothing where
instance Show Nothing where

{-| A term is a context with no holes.  -}

type Term f = Cxt NoHole f Nothing

{-| This function unravels the given term at the topmost layer.  -}

unTerm :: Term f -> f (Term f)
unTerm (Term t) = t

instance Functor f => Functor (Cxt h f) where
    fmap f (Hole v) = Hole (f v)
    fmap f (Term t) = Term (fmap (fmap f) t)


instance (Foldable f) => Foldable (Cxt h f) where
    foldr op e (Hole a) = a `op` e
    foldr op e (Term t) = foldr op' e t
        where op' c a = foldr op a c

    foldl op e (Hole a) = e `op` a
    foldl op e (Term t) = foldl op' e t
        where op' a c = foldl op a c

    fold (Hole a) = a
    fold (Term t) = foldMap fold t

    foldMap f (Hole a) = f a
    foldMap f (Term t) = foldMap (foldMap f) t

instance (Traversable f) => Traversable (Cxt h f) where
    traverse f (Hole a) = Hole <$> f a
    traverse f (Term t) = Term <$> traverse (traverse f) t
                          
    sequenceA (Hole a) = Hole <$> a
    sequenceA (Term t) = Term <$> traverse sequenceA t

    mapM f (Hole a) = liftM Hole $ f a
    mapM f (Term t) = liftM Term $ mapM (mapM f) t

    sequence (Hole a) = liftM Hole $ a
    sequence (Term t) = liftM Term $ mapM sequence t