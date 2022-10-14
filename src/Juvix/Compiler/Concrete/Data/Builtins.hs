module Juvix.Compiler.Concrete.Data.Builtins where

import Juvix.Extra.Strings qualified as Str
import Juvix.Prelude
import Juvix.Prelude.Pretty

class IsBuiltin a where
  toBuiltinPrim :: a -> BuiltinPrim

instance IsBuiltin BuiltinInductive where
  toBuiltinPrim = BuiltinsInductive

instance IsBuiltin BuiltinConstructor where
  toBuiltinPrim = BuiltinsConstructor

instance IsBuiltin BuiltinFunction where
  toBuiltinPrim = BuiltinsFunction

instance IsBuiltin BuiltinAxiom where
  toBuiltinPrim = BuiltinsAxiom

data BuiltinPrim
  = BuiltinsInductive BuiltinInductive
  | BuiltinsConstructor BuiltinConstructor
  | BuiltinsFunction BuiltinFunction
  | BuiltinsAxiom BuiltinAxiom
  deriving stock (Show, Eq, Ord, Generic)

instance Hashable BuiltinPrim

instance Pretty BuiltinPrim where
  pretty = \case
    BuiltinsInductive i -> pretty i
    BuiltinsConstructor {} -> impossible
    BuiltinsFunction f -> pretty f
    BuiltinsAxiom a -> pretty a

builtinConstructors :: BuiltinInductive -> [BuiltinConstructor]
builtinConstructors = \case
  BuiltinNat -> [BuiltinNatZero, BuiltinNatSuc]
  BuiltinBoolean -> [BuiltinBooleanTrue, BuiltinBooleanFalse]

data BuiltinInductive
  = BuiltinNat
  | BuiltinBoolean
  deriving stock (Show, Eq, Ord, Enum, Bounded, Generic)

instance Hashable BuiltinInductive

instance Pretty BuiltinInductive where
  pretty = \case
    BuiltinNat -> Str.nat
    BuiltinBoolean -> Str.boolean_

data BuiltinConstructor
  = BuiltinNatZero
  | BuiltinNatSuc
  | BuiltinBooleanTrue
  | BuiltinBooleanFalse
  deriving stock (Show, Eq, Ord, Generic)

instance Hashable BuiltinConstructor

data BuiltinFunction
  = BuiltinNatPlus
  | BuiltinBooleanIf
  deriving stock (Show, Eq, Ord, Enum, Bounded, Generic)

instance Hashable BuiltinFunction

instance Pretty BuiltinFunction where
  pretty = \case
    BuiltinNatPlus -> Str.natPlus
    BuiltinBooleanIf -> Str.booleanIf

data BuiltinAxiom
  = BuiltinNatPrint
  | BuiltinIO
  | BuiltinIOSequence
  deriving stock (Show, Eq, Ord, Enum, Bounded, Generic)

instance Hashable BuiltinAxiom

instance Pretty BuiltinAxiom where
  pretty = \case
    BuiltinNatPrint -> Str.natPrint
    BuiltinIO -> Str.io
    BuiltinIOSequence -> Str.ioSequence
