{-# LANGUAGE RankNTypes, MultiParamTypeClasses, FlexibleInstances,
  FlexibleContexts, UndecidableInstances, TemplateHaskell, TypeOperators,
  ImplicitParams, GADTs #-}
--------------------------------------------------------------------------------
-- |
-- Module      :  Examples.GTermHom
-- Copyright   :  (c) 2010-2011 Patrick Bahr
-- License     :  BSD3
-- Maintainer  :  Patrick Bahr <paba@diku.dk>
-- Stability   :  experimental
-- Portability :  non-portable (GHC Extensions)
--
--
--------------------------------------------------------------------------------

module Examples.GTermHom where

import Data.Comp
import Data.Comp.Show ()
import Data.Map (Map)
import Data.Maybe
import qualified Data.Map as Map
import Control.Monad
import Data.Comp.Derive


-- | This type represents generalised term homomorphisms. Generalised
-- term homomorphisms have access to a state that is provided
-- (separately) by a DUTA or a DDTA (or both).
type GTermHom q f g = forall a . (?below :: a -> q, ?above :: q) => f a -> Context g a


class Functor f => Zippable f where
    fzip :: f a -> [b] -> Maybe (f (a,b))
    fzip = fzipWith (\ x y -> (x,y))
    fzipWith :: (a -> b -> c) -> f a -> [b] -> Maybe (f c)
    fzipWith f s l = fmap (fmap $ uncurry f) (fzip s l)

-- | This type represents transition functions of deterministic
-- bottom-up tree transducers (DUTTs).

type UpTrans q f g = forall a. f (q,a) -> (q, Context g a)


-- | This type represents transition functions of deterministic
-- bottom-up tree acceptors (DUTAs).
type UpState f q = Alg f q

-- | This function transforms DUTT transition function into an
-- algebra.

upAlg :: (Functor g)  => UpTrans q f g -> Alg f (q, Term g)
upAlg trans = fmap appCxt . trans 

-- | This function runs the given DUTT on the given term.

runUpTrans :: (Functor f, Functor g) => UpTrans q f g -> Term f -> (q, Term g)
runUpTrans = cata . upAlg

-- | This function generalises 'runUpTrans' to contexts. Therefore,
-- additionally, a transition function for the holes is needed.
runUpTrans' :: (Functor f, Functor g) => (a -> q) -> UpTrans q f g -> Context f a -> (q, Context g a)
runUpTrans' st trans = run where
    run (Hole a) = (st a, Hole a)
    run (Term t) = fmap appCxt $ trans $ fmap run t

-- | This function composes two DUTTs.
compUpTrans :: (Functor f, Functor g, Functor h)
               => UpTrans q2 g h -> UpTrans q1 f g -> UpTrans (q1,q2) f h
compUpTrans t2 t1 x = ((q1,q2), fmap snd c2) where
    (q1, c1) = t1 $ fmap (\((q1,q2),a) -> (q1,(q2,a))) x
    (q2, c2) = runUpTrans' fst t2 c1

-- | This function turns constructs a DUTT from a given generalised
-- term homomorphism with the state propagated by the given DUTA.
toUpTrans :: (Functor f, Functor g) => UpState f q -> GTermHom q f g -> UpTrans q f g
toUpTrans alg f t = (q, c)
    where q = alg $ fmap fst t
          c =  fmap snd $ (let ?below = fst; ?above = q in f t)

-- | This function applies a given generalised term homomorphism with
-- a state space propagated by the given DUTA to a term.
upTermHom :: (Functor f, Functor g) => UpState f q -> GTermHom q f g -> Term f -> (q,Term g)
upTermHom alg h = runUpTrans (toUpTrans alg h)

-- | This function generalised 'upTermHom' to contexts. To this end
-- also a transition function for holes is required.
upTermHom' :: (Functor f, Functor g) => (a -> q) -> UpState f q -> GTermHom q f g -> Context f a -> (q, Context g a)
upTermHom' st alg h = runUpTrans' st (toUpTrans alg h)


-- | This type represents transition functions of deterministic
-- top-down tree transducers (DDTTs).

type DownTrans q f g = forall a. (q, f a) -> Context g (q,a)

-- | This function runs the given DDTT on the given tree.
runDownTrans :: (Functor f, Functor g) => DownTrans q f g -> q -> Cxt h f a -> (Cxt h g a)
runDownTrans tr q t = run (q,t) where
    run (q,Term t) = appCxt $ fmap run $  tr (q, t)
    run (_,Hole a)      = Hole a


-- | This type represents transition functions of deterministic
-- top-down tree acceptors (DDTAs).
type DownState f q = forall a. Ord a => (q, f a) -> Map a q

-- | This type is used for applying a DDTAs.
newtype Numbered a = Numbered (a, Int)

instance Eq (Numbered a) where
    Numbered (_,i) == Numbered (_,j) = i == j

instance Ord (Numbered a) where
    compare (Numbered (_,i))  (Numbered (_,j)) = i `compare` j

-- | This function constructs a DDTT from a given generalised term
-- homomorphism with the state propagated by the given DDTA.
toDownTrans :: Zippable f => DownState f q -> GTermHom q f g -> DownTrans q f g
toDownTrans st f (q, s) = c
    where s' = fromJust $ fzipWith (curry Numbered) s [0 ..]
          qmap = st (q,s')
          qfun = \ k@(Numbered (a,_)) -> (Map.findWithDefault q k qmap ,a)
          s'' = fmap qfun s'
          c   = (let ?above = q; ?below = fst in f) s''


-- | This function applies a given generalised term homomorphism with
-- a state space propagated by the given DUTA to a term.
downTermHom :: (Zippable f, Functor g)
            => q -> DownState f q -> GTermHom q f g -> Term f -> Term g
downTermHom q st h = runDownTrans (toDownTrans st h) q


-- | This type represents the transition functions of deterministic
-- bidirectional tree transducers (DBTT), i.e. tree transducers with a
-- two state spaces. One is propagated bottom-up like in a DUTT, the
-- other is propagated top-down like in a DDTT.
type BiTrans u d f g = forall a .  (d, f (u,a)) -> (u, Context g (d, a))
          
-------------
-- Example --
-------------

data Str a = Str
data Base a = Char | List a

type Typ = Str :+: Base

$(derive [instanceFunctor,smartConstructors, instanceShowF] [''Str,''Base])

class StringType f g where
    strTypeHom :: GTermHom Bool f g

$(derive [liftSum] [''StringType])

strType :: (Base :<: f, Functor f, Functor g, StringType f g)
        => Term f -> Term g
strType = snd . upTermHom isCharAlg strTypeHom

isCharAlg :: (Base :<: f) => Alg f Bool
isCharAlg t = case proj t of
                Just Char -> True
                _ -> False
    
instance (Str :<: f, Functor f) =>  StringType Str f where
    strTypeHom = simpCxt . inj

instance (Str :<:  f, Base :<: f, Functor f) =>  StringType Base f where
    strTypeHom Char = iChar
    strTypeHom (List t)
               | ?below t  = iStr 
               | otherwise = iList $ Hole t


ex1 :: Term Typ
ex1 = iList iChar

runEx1 :: Term Typ
runEx1 = strType ex1