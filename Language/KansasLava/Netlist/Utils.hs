{-# LANGUAGE TypeSynonymInstances #-}
module Language.KansasLava.Netlist.Utils where

import Language.KansasLava.Types
import Language.Netlist.AST hiding (U)
-- import Language.KansasLava.Entity
import Language.KansasLava.Shallow


import Data.Reify.Graph (Unique)

import Data.List(find,mapAccumL)

-- There are three type "classes" in our generated VHDL.
--  1. std_logic_vector
--  2. signed/unsigned
--  3. integer, as used to index into arrays, etc.


-- Turn a signal of std_logic[_vector], and
-- turn it into a Typed logic Expr. (signed, unsigned, or as is)
-- based on the given type.

class ToTypedExpr v where
	-- Turning a 'v' of (typically a std_logic_[vector] signal var) to a *typed* Expr,
	-- that is we use signed and unsigned for our S and U.
	toTypedExpr :: Type -> v -> Expr

instance (Integral a) => ToTypedExpr (Driver a) where
	-- From a std_logic* into a typed Expr
	toTypedExpr ty (Lit n)           = toTypedExpr ty n
	toTypedExpr ty (Generic n)       = toTypedExpr ty n
	toTypedExpr ty (Port (v) n)      = toTypedExpr ty (sigName v (fromIntegral n))
	toTypedExpr ty (Pad (OVar _ nm)) = toTypedExpr ty nm

instance ToTypedExpr String where
	-- From a std_logic* into a typed Expr
	toTypedExpr B      nm = 		       ExprVar $ nm -- ExprBinary Equals (ExprVar nm) (ExprBit 1)
	toTypedExpr ClkTy  nm = 		       ExprVar $ nm
	toTypedExpr (V _)  nm = 	   	       ExprVar $ nm
	toTypedExpr (S _)  nm = 	signed $       ExprVar $ nm
	toTypedExpr (U _)  nm = 	unsigned $     ExprVar $ nm
	toTypedExpr (TupleTy _) nm =		       ExprVar $ nm
	toTypedExpr (MatrixTy _ _) nm =		       ExprVar $ nm
	toTypedExpr (SampledTy {}) nm =		       ExprVar $ nm
	toTypedExpr _other nm = error $ (show ("toTypedExpr",_other,nm))

instance ToTypedExpr Integer where
	-- From a literal into a typed Expr
	toTypedExpr = fromIntegerToExpr

-- Integer is untyped.
fromIntegerToExpr :: Type -> Integer -> Expr
fromIntegerToExpr t i =
	case toStdLogicTy t of
	     B   -> ExprLit (Just 1) (ExprBit (b (fromInteger i)))
	     V n -> ExprLit (Just n) (ExprNum i)
	     GenericTy   -> ExprLit Nothing  (ExprNum i)
	     _ -> error "fromIntegerToExpr: was expecting B or V from normalized number"
  where b :: Int -> Bit
        b 0 = F
        b 1 = T


instance ToTypedExpr RepValue where
	-- From a literal into a typed Expr
	-- NOTE: We use Integer here as a natural, and assume overflow
	toTypedExpr t r = toTypedExpr t (fromRepToInteger r)


class ToStdLogicExpr v where
	-- Turn a 'v' into a std_logic[_vector] Expr.
	toStdLogicExpr :: Type -> v -> Expr

instance (Integral a) => ToStdLogicExpr (Driver a) where
	-- From a std_logic* (because you are a driver) into a std_logic.
        toStdLogicExpr ty _
                | typeWidth ty == 0        = ExprVar $ "\"\""
	toStdLogicExpr ty (Lit n)          = toStdLogicExpr ty n
	toStdLogicExpr ty (Generic n)      = toStdLogicExpr ty n
	toStdLogicExpr _ (Port (v) n)     = ExprVar $ sigName v (fromIntegral n)
	toStdLogicExpr _ (Pad (OVar _ v)) = ExprVar $ v
	toStdLogicExpr _ other		   = error $ show other

instance ToStdLogicExpr Integer where
	-- From a literal into a StdLogic Expr
	toStdLogicExpr = fromIntegerToExpr

instance ToStdLogicExpr RepValue where
	toStdLogicExpr t r = toTypedExpr t (fromRepToInteger r)

instance ToStdLogicExpr Expr where
	-- Convert from a typed expression (as noted by the type) back into a std_logic*
	--
	toStdLogicExpr B      e =      		     e
	toStdLogicExpr ClkTy  e = 		     e
	toStdLogicExpr (V _)  e = 	   	     e
	toStdLogicExpr (TupleTy _) e = 		     e
	toStdLogicExpr (MatrixTy _ _) e =	     e
	toStdLogicExpr (S _)  e = std_logic_vector $ e
	toStdLogicExpr (U _)  e = std_logic_vector $ e
	toStdLogicExpr(SampledTy {}) e =	     e
	toStdLogicExpr _other e = error $ show ("toStdLogicExpr", _other,e)

class ToIntegerExpr v where
	toIntegerExpr :: Type -> v -> Expr

instance (Integral i) => ToIntegerExpr (Driver i) where
	toIntegerExpr ty (Lit v) = toStdLogicExpr ty v
	toIntegerExpr GenericTy other = (toTypedExpr GenericTy other) -- HACK
	toIntegerExpr ty other        = to_integer (toTypedExpr ty other)

-- NEVER USED
{-
toStdLogicVectorExpr :: (Integral a) => Type -> Driver a -> Expr
toStdLogicVectorExpr ty dr =
	case toStdLogicTy ty of
	   B   -> singleton $ toStdLogicExpr B dr
	   V n -> toStdLogicExpr (V n) dr
-}

-- Turn a Kansas Lava type into its std_logic[_vector] type (in KL format)
-- There are three possible results (V n, B, MatrixTy n (V m))
-- Note this function does not have an inverse.
toStdLogicTy :: Type -> Type
toStdLogicTy B               = B
toStdLogicTy ClkTy           = B
toStdLogicTy (V n)           = V n
toStdLogicTy GenericTy       = GenericTy
toStdLogicTy (MatrixTy i ty) = MatrixTy i (V $ fromIntegral size)
  where size = typeWidth ty
toStdLogicTy ty              = V $ fromIntegral size
  where size = typeWidth ty
--

-- Name a signal
-- TODO: consider Var -> Unique -> String
sigName :: String -> Unique -> String
sigName v d = "sig_" ++  show d ++ "_" ++ v

-- figure out the size of a type.
sizedRange :: Type -> Maybe Range
sizedRange ty = case toStdLogicTy ty of
		  B -> Nothing
		  V n -> Just $ Range high low
                    where high = ExprLit Nothing (ExprNum (fromIntegral n - 1))
                          low = ExprLit Nothing (ExprNum 0)
                  MatrixTy _ _ -> error "sizedRange: does not support matrix types"

-- like sizedRange, but allowing 2^n elements (for building memories)
memRange :: Type -> Maybe Range
memRange ty = case toStdLogicTy ty of
		  B -> Nothing
		  V n -> Just $ Range high low
                    where high = ExprLit Nothing
                                 (ExprNum (2^(fromIntegral n :: Integer) - 1))
                          low = ExprLit Nothing (ExprNum 0)

-- VHDL "macros"
active_high :: Expr -> Expr
active_high d      = ExprCond d  (ExprLit Nothing (ExprBit T)) (ExprLit Nothing (ExprBit F))

std_logic_vector :: Expr -> Expr
std_logic_vector d = ExprFunCall "std_logic_vector" [d]

to_unsigned :: Expr -> Expr -> Expr
to_unsigned x w    = ExprFunCall "to_unsigned" [x, w]		-- is this used now?

unsigned :: Expr -> Expr
unsigned x         = ExprFunCall "unsigned" [x]

to_signed :: Expr -> Expr -> Expr
to_signed x w      = ExprFunCall "to_signed" [x, w]		-- is this used now?

signed :: Expr -> Expr
signed x           = ExprFunCall "signed" [x]

to_integer :: Expr -> Expr
to_integer e       = ExprFunCall "to_integer" [e]

--singleton x 	   = ExprFunCall "singleton" [x]
-- Others

isHigh :: Expr -> Expr
isHigh d = (ExprBinary Equals d (ExprLit Nothing (ExprBit T)))

isLow :: Expr -> Expr
isLow d = (ExprBinary Equals d (ExprLit Nothing (ExprBit F)))

allLow :: Type -> Expr
allLow ty = ExprLit (Just (typeWidth ty)) (ExprNum 0)

zeros :: Expr
zeros = ExprString "(others => '0')" -- HACK

toMemIndex :: Integral t => Type -> Driver t -> Expr
toMemIndex ty _ | typeWidth ty == 0 = ExprLit Nothing (ExprNum 0)
toMemIndex _ (Lit n) = ExprLit Nothing $ ExprNum $ fromRepToInteger n
toMemIndex ty dr = to_integer $ unsigned $ toStdLogicExpr ty dr

-- Both of these are hacks for memories, that do not use arrays of Bools.
memToStdLogic :: Type -> Expr -> Expr
memToStdLogic B e = ExprFunCall "lava_to_std_logic" [e]
memToStdLogic _ e = e

stdLogicToMem :: Type -> Expr -> Expr
stdLogicToMem B e = ExprConcat [ExprLit Nothing $ ExprBitVector [],e]
stdLogicToMem _ e = e


---------------------------------------------------------------------------------------------------
-- Other utils

-- The Type here goes from left to right, but we use it right to left.
-- So [B,U4] => <XXXX:4 to 1><X:0>, because of the convension ordering in our generated VHDL.
-- Notice the result list is in the same order as the argument list.
-- The result is written out as a std_logic[_vector].
-- We assume that the input is *not* a constant (would cause lava-compile-time crash)

prodSlices :: Driver Unique -> [Type] -> [Expr]
prodSlices d tys = reverse $ snd $ mapAccumL f size $ reverse tys
  where size = fromIntegral $ sum (map typeWidth tys) - 1

	nm = case d of
		Port (v) n -> sigName v n
		Pad (OVar _ v) -> v
		Lit {} -> error "projecting into a literal (not implemented yet!)"

	f :: Integer -> Type -> (Integer,Expr)
        f i B = (i-1,ExprIndex nm (ExprLit Nothing (ExprNum i)))
        f i ty = let w = fromIntegral $ typeWidth ty
                     nextIdx = i - w
                 in (nextIdx, ExprSlice nm (ExprLit Nothing (ExprNum i))
                                        (ExprLit Nothing (ExprNum (nextIdx + 1))))

-- Find some specific (named) input inside the entity.
lookupInput :: (Show b) => String -> Entity b -> Driver b
lookupInput i (Entity _ _ inps) = case find (\(v,_,_) -> v == i) inps of
                                      Just (_,_,d) -> d
                                      Nothing -> error $ "lookupInput: Can't find input" ++ show (i,inps)

-- Find some specific (named) input's type inside the entity.
lookupInputType :: String -> Entity t -> Type
lookupInputType i (Entity _ _ inps) = case find (\(v,_,_) -> v == i) inps of
                                          Just (_,ty,_) -> ty
                                          Nothing -> error "lookupInputType: Can't find input"

-- TODO: should ty be GenericTy only here?
addNum :: Integer -> [(String,Type,Driver Unique)] -> [(String,Type,Driver Unique)]
addNum i [("i0",ty,d)] = [("i0",GenericTy,Generic i),("i1",ty,d)]
addNum _ _ = error "addNum"

------------------------------------------------------------------------

{-
-- GONE
data NetlistOption
		= LoadEnable 			-- add an enable signal to the entity, and each gate.
		| AsynchResets
--		| ReifyOptions [ReifyOption]
		deriving (Eq, Show, Ord)
type NetlistOptions = [NetlistOption]

addEnabled opts = LoadEnable `elem` opts
asynchResets opts = AsynchResets `elem` opts
-}

------------------------------------------------------------------------------

class AddNext s where
   next :: s -> s

instance AddNext String where
   next nm = nm ++ "_next"

instance AddNext (Driver i) where
   next (Port v i) = Port (next v) i
   next other = other

------------------------------------------------------------------------------
-- Turn a name into something VHDL could use

sanitizeName :: String -> String
sanitizeName "+"         = "add"
sanitizeName "-"         = "sub"
sanitizeName "*"         = "mul"
sanitizeName ".>."       = "gt"
sanitizeName ".<."       = "lt"
sanitizeName ".<=."      = "ge"
sanitizeName ".>=."      = "le"
-- TODO: Add check for symbols
sanitizeName other       = other

------------------------------------------------------------------------------------

-- Grab all of the synchronous elements (listed in 'nms') and return a map keyed
-- on clk input, with the value including a list of associated entities.
-- TODO: What is going on here!!

-- only works for a single clock domain, for now.
getSynchs :: [String]
	  -> [(Unique,Entity Unique)]
	  -> [((Driver Unique, Driver Unique, Driver Unique),[(Unique, Entity Unique)])]
getSynchs nms ents =
	[ ((clk_dr,rst_dr,en_dr),
	    [ e | e@(_,Entity (Prim n) _ _) <- ents,  n `elem` nms ]
           )
	| (_,Entity (Prim "Env") _ [("clk_en",B,en_dr),("clk",ClkTy,clk_dr),("rst",B,rst_dr)]) <- ents
	]
{-
  where
        synchs = [((getInput "clk" is,getInput "rst" is,getInput "en" is),[e])
		 | e@(i,Entity (Name "Memory" n) _ is _) <- ents,
		    n `elem` nms]
        getInput nm is = case find (\(c,_,_) -> c == nm) is of
                      Just (_,_,d) -> d
                      Nothing -> error $ "getSynchs: Can't find a signal " ++ show (nm,is,ents)
-}
---------------------------------------------------------------------------------

-- Entities that never result in code generation
isVirtualEntity :: [Id]
isVirtualEntity =
        [ Prim "write"  -- write (to an array) requires a counterpart read.
                        -- the read generates the entire operation, cloning
                        -- the write node if needed.
        ]


-- We sometimes store std_logic's as singleton std_logic_vectors.
--boolTrick :: [String] -> Entity a -> Entity a
boolTrick :: [[Char]] -> Entity s -> Entity s
boolTrick nms (Entity (External nm) outs ins) =
        Entity (External nm)
               [ (trick n,t) | (n,t) <- outs ]
               [ (trick n,t,d) | (n,t,d) <- ins ]
   where
           trick n | n `elem` nms = n ++ "(0)"
                   | otherwise    = n

boolTrick _ _ = error "applying bool Trick to non-external entity"
