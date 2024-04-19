module Juvix.Compiler.Tree.Language.Builtins where

import Juvix.Prelude

data BinaryOp
  = OpIntAdd
  | OpIntSub
  | OpIntMul
  | OpIntDiv
  | OpIntMod
  | OpIntLt
  | OpIntLe
  | OpFieldAdd
  | OpFieldSub
  | OpFieldMul
  | OpFieldDiv
  | OpEq
  | OpStrConcat
  deriving stock (Eq)

data UnaryOp
  = -- | Convert the argument to a string. JV* opcode: `show`.
    OpShow
  | -- | Convert a string to an integer. JV* opcode: `atoi`.
    OpStrToInt
  | -- | Convert an integer to a field element. JV* opcode: `itof`.
    OpIntToField
  | -- | Convert a field element to an integer. JV* opcode: `ftoi`.
    OpFieldToInt
  | -- | Compute the number of expected arguments for the given closure. JV*
    -- opcode: `argsnum`.
    OpArgsNum
  deriving stock (Eq)

-- | Builtin Cairo operations. Implemented only in the Cairo backend.
data CairoOp
  = -- | Cairo Poseidon hash builtin (hades permutation).
    OpCairoPoseidon
  | -- | Cairo Elliptic Curve operation.
    OpCairoEc
  | -- | Cairo random elliptic curve point generation.
    OpCairoRandomEcPoint
  deriving stock (Eq)

cairoOpArgsNum :: CairoOp -> Int
cairoOpArgsNum = \case
  OpCairoPoseidon -> 1
  OpCairoEc -> 3
  OpCairoRandomEcPoint -> 0
