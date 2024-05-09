module Juvix.Compiler.Nockma.Encoding where

import Data.Bit
import Data.Bits
import Data.Vector.Unboxed qualified as U
import Juvix.Compiler.Nockma.Language
import Juvix.Prelude.Base
import VectorBuilder.Builder as Builder
import VectorBuilder.Vector

integerToVectorBits :: Integer -> U.Vector Bit
integerToVectorBits = build . integerToBuilder

integerToBuilder :: (Integral a) => a -> Builder Bit
integerToBuilder x
  | x == 0 = Builder.singleton (Bit False)
  | x < 0 = error "integerToVectorBits: negative integers are not supported in this implementation"
  | otherwise = unfoldBits (fromIntegral x)
  where
    unfoldBits :: Integer -> Builder Bit
    unfoldBits n
      | n == 0 = Builder.empty
      | otherwise = Builder.singleton (Bit (testBit n 0)) <> unfoldBits (n `shiftR` 1)

bitLength :: forall a. (Integral a) => a -> Int
bitLength = \case
  0 -> 0
  n -> go (fromIntegral n) 0
    where
      go :: Integer -> Int -> Int
      go 0 acc = acc
      go x acc = go (x `shiftR` 1) (acc + 1)

vectorBitsToInteger :: U.Vector Bit -> Integer
vectorBitsToInteger = U.ifoldl' go 0
  where
    go :: Integer -> Int -> Bit -> Integer
    go acc idx (Bit b)
      | b = setBit acc idx
      | otherwise = acc

data JamState = JamState
  { _jamStateCache :: HashMap (Term Natural) Int,
    _jamStateBuilder :: Builder Bit
  }

initJamState :: JamState
initJamState =
  JamState
    { _jamStateCache = mempty,
      _jamStateBuilder = mempty
    }

makeLenses ''JamState

writeBit :: (Member (State JamState) r) => Bit -> Sem r ()
writeBit b = modify appendByte
  where
    appendByte :: JamState -> JamState
    appendByte = over jamStateBuilder (<> Builder.singleton b)

writeOne :: (Member (State JamState) r) => Sem r ()
writeOne = writeBit (Bit True)

writeZero :: (Member (State JamState) r) => Sem r ()
writeZero = writeBit (Bit False)

writeIntegral :: (Integral a, Member (State JamState) r) => a -> Sem r ()
writeIntegral i = modify updateBuilder
  where
    iBuilder :: Builder Bit
    iBuilder = integerToBuilder i

    updateBuilder :: JamState -> JamState
    updateBuilder = over jamStateBuilder (<> iBuilder)

writeLength :: forall r. (Member (State JamState) r) => Int -> Sem r ()
writeLength len = do
  let lenOfLen = finiteBitSize len - countLeadingZeros len
  replicateM_ lenOfLen writeZero
  writeOne
  unless (lenOfLen == 0) (go len)
  where
    go :: Int -> Sem r ()
    go l = unless (l == 1) $ do
      writeBit (Bit ((l .&. 1) /= 0))
      go (l `shiftR` 1)

writeAtom :: forall r a. (Integral a, Member (State JamState) r) => Atom a -> Sem r ()
writeAtom a = do
  writeZero
  writeLength (bitLength (a ^. atom))
  writeIntegral (a ^. atom)

cacheTerm :: (Member (State JamState) r) => Term Natural -> Sem r ()
cacheTerm t = do
  pos <- Builder.size <$> gets (^. jamStateBuilder)
  modify (set (jamStateCache . at t) (Just pos))

lookupCache :: (Member (State JamState) r) => Term Natural -> Sem r (Maybe Int)
lookupCache t = gets (^. jamStateCache . at t)

writeCell :: forall r. (Member (State JamState) r) => Cell Natural -> Sem r ()
writeCell c = do
  writeOne
  writeZero
  jamSem (c ^. cellLeft)
  jamSem (c ^. cellRight)

jamSem :: forall r. (Member (State JamState) r) => Term Natural -> Sem r ()
jamSem t = do
  ct <- lookupCache t
  case ct of
    Just idx -> case t of
      TermAtom a -> do
        let idxBitLength = finiteBitSize idx - countLeadingZeros idx
            atomBitLength = bitLength (a ^. atom)
        if
            | atomBitLength <= idxBitLength -> writeAtom a
            | otherwise -> backref idx
      TermCell {} -> backref idx
    Nothing -> do
      cacheTerm t
      case t of
        TermAtom a -> writeAtom a
        TermCell c -> writeCell c
  where
    backref :: Int -> Sem r ()
    backref idx = do
      writeOne
      writeOne
      writeLength (bitLength idx)
      writeIntegral idx

evalJamStateBuilder :: JamState -> Sem '[State JamState] a -> Builder Bit
evalJamStateBuilder st = (^. jamStateBuilder) . run . execState st

evalJamState :: JamState -> Sem '[State JamState] a -> U.Vector Bit
evalJamState st = build . evalJamStateBuilder st

jamToBuilder :: Term Natural -> Builder Bit
jamToBuilder = evalJamStateBuilder initJamState . jamSem

jamToVector :: Term Natural -> U.Vector Bit
jamToVector = build . jamToBuilder

jam :: Term Natural -> Atom Natural
jam = (\i -> Atom @Natural i emptyAtomInfo) . fromInteger . vectorBitsToInteger . jamToVector

cueToVector :: Atom Natural -> U.Vector Bit
cueToVector = integerToVectorBits . fromIntegral . (^. atom)

cueFromBits :: U.Vector Bit -> Term Natural
cueFromBits = undefined

cue :: Atom Natural -> Term Natural
cue = cueFromBits . cueToVector
