{-# LANGUAGE ScopedTypeVariables, FlexibleContexts, TypeFamilies, ParallelListComp, TypeSynonymInstances, FlexibleInstances, GADTs, RankNTypes, UndecidableInstances #-}
-- | This module provides abstractions for working with RAMs and ROMs.
module Language.KansasLava.Protocols.Memory where

import Language.KansasLava.Rep
import Language.KansasLava.Signal
import Language.KansasLava.Stream as Stream
import Language.KansasLava.Types
import Language.KansasLava.Utils
import Language.KansasLava.Protocols.Enabled

import Data.Sized.Matrix as M
import Control.Applicative hiding (empty)
import Data.Maybe  as Maybe
import Control.Monad

import Prelude hiding (tail, lookup)

-- | A Pipe combines an address, data, and an Enabled control line.
type Pipe a d = Enabled (a,d)

-- | A Memory takes in a sequence of addresses, and returns a sequence of data at that address.
type Memory clk a d = Signal clk a -> Signal clk d

-- | Given a Seq of addresses for reads and a memory structure, this produces a Pipe that's the memory output.
memoryToPipe ::  forall a d clk . (Rep a, Rep d, Clock clk) =>  Signal clk (Enabled a) -> Memory clk a d -> Signal clk (Pipe a d)
memoryToPipe enA mem = pack (delay en,pack (delay a,mem a))
   where
	(en,a) = unpack enA

-- | Given a Seq of address/data pairs as a pipe, write the data to the memory
-- at the corresponding address, and return the value at the address that is the
-- second argument.
pipeToMemory :: forall a d clk1 . (Size a, Clock clk1, Rep a, Rep d)
	=> Signal clk1 (Pipe a d)
	-> Memory clk1 a d
pipeToMemory pipe addr2 = syncRead (writeMemory (delay pipe)) addr2

-- Later, we will have a two clock version.

-- Does not work for two clocks, *YET*
-- call writeMemory
-- | Write the input pipe to memory, return a circuit that does reads.
writeMemory :: forall a d clk1 sig . (Clock clk1, sig ~ Signal clk1, Size a, Rep a, Rep d)
	=> sig (Pipe a d)
	-> sig (a -> d)
writeMemory pipe = res
  where
	-- Adding a 1 cycle delay, to keep the Xilinx tools happy and working.
	-- TODO: figure this out, and fix it properly
	(wEn,pipe') = unpack  {- register (pureS Nothing) $ -} pipe
	(addr,dat) = unpack pipe'

    	res :: Signal clk1 (a -> d)
    	res = Signal shallowRes (D $ Port "o0" $ E entity)

	shallowRes :: Stream (X (a -> d))
        shallowRes = pure (\ m -> XFunction $ \ ix ->
                        case getValidRepValue (toRep (optX (Just ix))) of
                               Nothing -> optX Nothing
                               Just a' -> case lookup a' m of
                                            Nothing -> optX Nothing
                                            Just v -> optX (Just v)
                          )
			<*> mem -- (emptyMEM :~ mem)
--			    <*> ({- optX Nothing :~ -} shallowS addr2)

	-- This could have more fidelity, and allow you
	-- to say only a single location is undefined
	updates :: Stream (Maybe (Maybe (a,d)))
	updates = stepifyStream (\ a -> case a of
					Nothing -> ()
					Just b -> case b of
						   Nothing -> ()
						   Just (c,d) -> eval c `seq` eval d `seq` ()
			        )
		$ pure (\ e a b ->
			   do en'   <- unX e
			      if not en'
				     then return Nothing
				     else do
			      		addr' <- unX a
			      		dat'  <- unX b
			      		return $ Just (addr',dat')
		       ) <*> shallowS wEn
			 <*> shallowS addr
			 <*> shallowS dat

	-- mem
{-
	mem :: Stream (Map [Bool] d)
	mem = id -- stepify
	    $ Map.empty :~ Stream.fromList
		[ case u of
		    Nothing           -> Map.empty	-- unknown again
		    Just Nothing      -> m
		    Just (Just (a,d)) -> ((Map.insert $! (M.toList $! (fromWireRep a :: Matrix (WIDTH a) Bool))) $!) d $! m
		| u <- Stream.toList updates
		| m <- Stream.toList mem
		]
-}
	mem :: Stream (Radix d)
	mem = stepifyStream (\ a -> a `seq` ())
	    $ Cons empty $ Stream.fromList
		[ case u of
		    Nothing           -> empty	-- unknown again
		    Just Nothing      -> m
		    Just (Just (a,d)) ->
			case getValidRepValue (toRep (optX (Just a))) of
			  Just bs -> ((insert $! bs) $! d) $! m
                          Nothing -> error "mem: can't get a valid rep value"
		| u <- Stream.toList updates
		| m <- Stream.toList mem
		]

    	entity :: Entity E
    	entity =
		Entity (Prim "write")
			[ ("o0",typeOfS res)]
			[ ("clk",ClkTy, Pad "clk")
   		        , ("rst",B,     Pad "rst")
			, ("wEn",typeOfS wEn,unD $ deepS wEn)
			, ("wAddr",typeOfS addr,unD $ deepS addr)
			, ("wData",typeOfS dat,unD $ deepS dat)
                        , ("element_count"
                          , GenericTy
                          , Generic (fromIntegral (M.size (error "witness" :: a)))
                          )
			]
{-
readMemory :: forall a d sig clk . (Clock clk, sig ~ Signal clk, Size a, Rep a, Rep d)
	=> sig (a -> d) -> sig a -> sig d
readMemory mem addr = unpack mem addr
-}

-- This is an alias (TODO: remove)
-- | Read a series of addresses.
readMemory :: forall a d sig clk . (Clock clk, sig ~ Signal clk, Size a, Rep a, Rep d)
	=> sig (a -> d) -> sig a -> sig d
readMemory mem addr = asyncRead mem addr

-- | Read a series of addresses. Respect the latency of Xilinx BRAMs.
syncRead :: forall a d sig clk . (Clock clk, sig ~ Signal clk, Size a, Rep a, Rep d)
	=> sig (a -> d) -> sig a -> sig d
syncRead mem addr = delay (asyncRead mem addr)

-- | Read a series of addresses.
asyncRead :: forall a d sig clk . (Clock clk, sig ~ Signal clk, Size a, Rep a, Rep d)
	=> sig (a -> d) -> sig a -> sig d
asyncRead = primXS2 fn "asyncRead"
   where fn (XFunction f) a = 
           -- We need to case of XFunction, rather than use unX,
           -- because the function may not be total.
           case unX a of
                Just a' -> f a'
                Nothing -> optX Nothing

-- | memoryToMatrix should be used with caution/simulation  only,
-- because this actually clones the memory to allow this to work,
-- generating lots of LUTs and BRAMS.
memoryToMatrix ::  (Integral a, Size a, Rep a, Rep d, Clock clk, sig ~ Signal clk)
	=> sig (a -> d) -> sig (Matrix a d)
memoryToMatrix mem = pack (forAll $ \ x -> asyncRead mem (pureS x))

-- | Apply a function to the Enabled input signal producing a Pipe.
enabledToPipe :: (Rep x, Rep y, Rep z, sig ~ Signal clk) => (forall j . Signal j x -> Signal j (y,z)) -> sig (Enabled x) -> sig (Pipe y z)
enabledToPipe f se = pack (en, f x)
   where (en,x) = unpack se


{-
-- to move into a counters module
-- Count the number of ticks on a signal. Notice that we start at zero (no ticks),
-- and bump the counter at each sighting.
countTicks :: forall clk x . (Rep x) => x -> (Comb x -> Comb x) ->  Signal clk Bool -> Signal clk (Enabled x)
countTicks init succ sysEnv enable = packEnabled enable ctr
   where
        ctr :: Signal clk x
        ctr = register sysEnv (pureS init) val

        val :: Signal clk x
        val = mux2 enable (liftS1 succ ctr,ctr)


-- compare with my previous value
cmp :: (Wire a) =>  (Comb a -> Comb a -> Comb b) -> Signal clk a -> Signal clk b
cmp env f inp = liftS2 f (delay env inp) inp

-}
-- Apply a function to the data output of a Pipe.
--mapPipe :: (sig ~ Signal clk, Rep a, Rep b, Rep x) => (Comb a -> Comb b) -> sig (Pipe x a) -> sig (Pipe x b)
--mapPipe f = mapEnabled (mapPacked $ \ (a0,b0) -> (a0,f b0))


{-
-- | only combines pipes when both inputs are enabled, and *assumes* the
-- x addresses are the same.
zipPipe :: (sig ~ Signal clk, Rep a, Rep b, Rep c, Rep x) => (Comb a -> Comb b -> Comb c) -> sig (Pipe x a) -> sig (Pipe x b) -> sig (Pipe x c)
zipPipe f = zipEnabled (zipPacked $ \ (a0,b0) (a1,b1) -> (a0 `phi` a1,f b0 b1))
-}


--------------------------------------------------


-- The order here has the function *last*, because it allows
-- for a idiomatic way of writing things
--
--  res = rom inp $ \ a -> ....
--
-- | Generate a read-only memory.
rom :: (Rep a, Rep b, Clock clk) => Signal clk a -> (a -> Maybe b) -> Signal clk b
rom inp fn = delay $ funMap fn inp

---------------------------------


-- | Stepify allows us to make a stream element-strict.
class Stepify a where
  stepify :: a -> a

--class Rep a => Eval a where

--instance (Rep a) => Stepify (Seq a) where
--  stepify (Seq a d) = Seq (stepify a) d

-- one step behind, to allow knot tying.
--instance (Rep a) => Stepify (Stream a) where
--  stepify (a :~ r) = a :~ (eval a `seq` stepify r)
-- | Strictly apply a function to each element of a Stream.
stepifyStream :: (a -> ()) -> Stream a -> Stream a
stepifyStream f (Cons a r) = Cons a (f a `seq` stepifyStream f r)

--instance Wire (Map [Bool] d) where {}

-- instance Rep (Map (M.Matrix x Bool) d) where {}


{-

instance Eval (WireVal a) where
    eval WireUnknown = ()
    eval (WireVal a) = a `seq` ()

instance (Eval a) => Eval (Maybe a) where
    eval (Just a)  = eval a
    eval (Nothing) = ()

instance (Eval a, Eval b) => Eval (a,b) where
	eval (a,b) = eval a `seq` eval b `seq` ()
-}



-- | A 'Radix' is a trie indexed by bitvectors.
data Radix a
  = Res !a -- ^ A value stored in the tree
  | NoRes -- ^ Non-present value
  -- | A split-node, left corresponds to 'True' key bit, right corresponds to 'False' key bit.
  | Choose !(Radix a) !(Radix a)
	deriving Show

-- | The empty tree
empty :: Radix a
empty = NoRes

-- | Add a value (keyed by the list of bools) into a tree
insert :: [Bool] -> a -> Radix a -> Radix a
insert []    y (Res _) = Res $! y
insert []    y NoRes   = Res $! y
insert []    _ (Choose _ _) = error "inserting with short key"
insert xs     y NoRes   = insert xs y (Choose NoRes NoRes)
insert _  _ (Res _) = error "inserting with too long a key"
insert (True:a) y (Choose l r) = Choose (insert a y l) r
insert (False:a) y (Choose l r) = Choose l (insert a y r)


-- | Find a value in a radix tree
lookup :: [Bool] -> Radix a -> Maybe a
lookup [] (Res v) = Just v
lookup [] NoRes   = Nothing
lookup [] _       = error "lookup error with short key"
lookup (_:_) (Res _) = error "lookup error with long key"
lookup (_:_) NoRes   = Nothing
lookup (True:a) (Choose l _) = lookup a l
lookup (False:a) (Choose _ r) = lookup a r


