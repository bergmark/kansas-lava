{-# LANGUAGE ScopedTypeVariables, RankNTypes, TypeFamilies, FlexibleContexts, ExistentialQuantification #-}

module Coerce where

import Language.KansasLava
import Language.KansasLava.Stream as S
import Language.KansasLava.Testing.Thunk

import Utils
import Data.Sized.Unsigned
import Data.Sized.Matrix as M hiding (length)
import Data.Sized.Signed
import Data.Sized.Arith
import Data.Sized.Ix

import Data.List as List

import Debug.Trace

tests :: TestSeq -> IO ()
tests test = do
        let t str witness arb = testUnsigned test str witness arb

        t "U1_U1" (Witness :: Witness U1) (dubSeq (arbitrary :: Gen U1))
        t "U2_U1" (Witness :: Witness U2) (dubSeq (arbitrary :: Gen U1))
        t "U3_U1" (Witness :: Witness U3) (dubSeq (arbitrary :: Gen U1))        
        t "U1_U2" (Witness :: Witness U1) (dubSeq (arbitrary :: Gen U2))
        t "U2_U2" (Witness :: Witness U2) (dubSeq (arbitrary :: Gen U2))
        t "U3_U2" (Witness :: Witness U3) (dubSeq (arbitrary :: Gen U2))        
        t "U1_U3" (Witness :: Witness U1) (dubSeq (arbitrary :: Gen U3))
        t "U2_U3" (Witness :: Witness U2) (dubSeq (arbitrary :: Gen U3))
        t "U3_U3" (Witness :: Witness U3) (dubSeq (arbitrary :: Gen U3))        
        t "U4_U8" (Witness :: Witness U4) (dubSeq (arbitrary :: Gen U8))        
        t "U8_U4" (Witness :: Witness U8) (dubSeq (arbitrary :: Gen U4))        

        t "U1_S2" (Witness :: Witness U1) (dubSeq (arbitrary :: Gen S2))
        t "U2_S2" (Witness :: Witness U2) (dubSeq (arbitrary :: Gen S2))
        t "U3_S2" (Witness :: Witness U3) (dubSeq (arbitrary :: Gen S2))        
        t "U1_S3" (Witness :: Witness U1) (dubSeq (arbitrary :: Gen S3))
        t "U2_S3" (Witness :: Witness U2) (dubSeq (arbitrary :: Gen S3))
        t "U3_S3" (Witness :: Witness U3) (dubSeq (arbitrary :: Gen S3))        
        t "U8_S4" (Witness :: Witness U8) (dubSeq (arbitrary :: Gen S4))        

        t "X2_X2" (Witness :: Witness X2) (dubSeq (arbitrary :: Gen X2))
        t "X2_X3" (Witness :: Witness X2) (dubSeq (arbitrary :: Gen X3))
        t "X2_X4" (Witness :: Witness X2) (dubSeq (arbitrary :: Gen X4))
        t "X2_X5" (Witness :: Witness X2) (dubSeq (arbitrary :: Gen X5))

        t "X3_X2" (Witness :: Witness X3) (dubSeq (arbitrary :: Gen X2))
        t "X3_X3" (Witness :: Witness X3) (dubSeq (arbitrary :: Gen X3))
        t "X3_X4" (Witness :: Witness X3) (dubSeq (arbitrary :: Gen X4))
        t "X3_X5" (Witness :: Witness X3) (dubSeq (arbitrary :: Gen X5))

        t "X4_X2" (Witness :: Witness X4) (dubSeq (arbitrary :: Gen X2))
        t "X4_X3" (Witness :: Witness X4) (dubSeq (arbitrary :: Gen X3))
        t "X4_X4" (Witness :: Witness X4) (dubSeq (arbitrary :: Gen X4))
        t "X4_X5" (Witness :: Witness X4) (dubSeq (arbitrary :: Gen X5))

        t "X5_X2" (Witness :: Witness X5) (dubSeq (arbitrary :: Gen X2))
        t "X5_X3" (Witness :: Witness X5) (dubSeq (arbitrary :: Gen X3))
        t "X5_X4" (Witness :: Witness X5) (dubSeq (arbitrary :: Gen X4))
        t "X5_X5" (Witness :: Witness X5) (dubSeq (arbitrary :: Gen X5))

        let t str witness arb = testSigned test str witness arb

        t "S2_U1" (Witness :: Witness S2) (dubSeq (arbitrary :: Gen U1))
        t "S3_U1" (Witness :: Witness S3) (dubSeq (arbitrary :: Gen U1))        
        t "S2_U2" (Witness :: Witness S2) (dubSeq (arbitrary :: Gen U2))
        t "S3_U2" (Witness :: Witness S3) (dubSeq (arbitrary :: Gen U2))        
        t "S2_U3" (Witness :: Witness S2) (dubSeq (arbitrary :: Gen U3))
        t "S3_U3" (Witness :: Witness S3) (dubSeq (arbitrary :: Gen U3))        
        t "S4_U8" (Witness :: Witness S4) (dubSeq (arbitrary :: Gen U8))        
        t "S8_U4" (Witness :: Witness S8) (dubSeq (arbitrary :: Gen U4))        

        t "S2_S2" (Witness :: Witness S2) (dubSeq (arbitrary :: Gen S2))
        t "S3_S2" (Witness :: Witness S3) (dubSeq (arbitrary :: Gen S2))        
        t "S2_S3" (Witness :: Witness S2) (dubSeq (arbitrary :: Gen S3))
        t "S3_S3" (Witness :: Witness S3) (dubSeq (arbitrary :: Gen S3))        
        t "S4_S8" (Witness :: Witness S4) (dubSeq (arbitrary :: Gen S8))        
        t "S8_S4" (Witness :: Witness S8) (dubSeq (arbitrary :: Gen S4))        

        return ()


testUnsigned :: forall w1 w2 . (Num w2, Integral w1, Integral w2, Bounded w2, Eq w1, Rep w1, Eq w2, Show w2, Rep w2) 
            => TestSeq -> String -> Witness w2 -> Gen w1 -> IO ()
testUnsigned (TestSeq test toList) tyName Witness ws = do
        let ms = toList ws
        let cir = (unsigned) :: Seq w1 -> Seq w2
        let thu = Thunk cir
                        (\ cir -> cir (toSeq ms)
                        )
            -- shallow will always pass; it *is* the semantics here
            res :: Seq w2
            res = cir $ toSeq' [ if toInteger m > toInteger (maxBound :: w2)
                                 || toInteger m < toInteger (minBound :: w2)
                                 then fail "out of bounds"
                                 else return m 
                               | m <- ms
                               ]
        test ("unsigned/" ++ tyName) (length ms) thu res
        return ()

testSigned :: forall w1 w2 . (Num w2, Integral w1, Bounded w1, Integral w2, Bounded w2, Eq w1, Rep w1, Eq w2, Show w2, Rep w2) 
            => TestSeq -> String -> Witness w2 -> Gen w1 -> IO ()
testSigned (TestSeq test toList) tyName Witness ws = do
        let ms = toList ws
        let cir = (signed) :: Seq w1 -> Seq w2
        let thu = Thunk cir
                        (\ cir -> cir (toSeq ms)
                        )
            -- shallow will always pass; it *is* the semantics here
            res = cir $ toSeq' [ if fromIntegral m > fromIntegral (maxBound :: w2)
                                 || fromIntegral m < fromIntegral (minBound :: w2)
                                 then fail "out of bounds"
                                 else return m 
                               | m <- ms
                               ]
        test ("signed/" ++ tyName) (length ms) thu res
        return ()

{-        
        let ms = toList ws
        let cir = sum . M.toList . unpack :: Seq (M.Matrix w1 w2) -> Seq w2
        let thu = Thunk cir
                        (\ cir -> cir (toSeq ms)
                        )
            res :: Seq w2
            res = toSeq [ sum $ M.toList m | m <- ms ]
        test ("matrix/1/" ++ tyName) (length ms) thu res
-}
