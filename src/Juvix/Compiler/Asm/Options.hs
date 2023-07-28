module Juvix.Compiler.Asm.Options
  ( module Juvix.Compiler.Asm.Options,
    module Juvix.Compiler.Backend,
  )
where

import Juvix.Compiler.Backend
import Juvix.Compiler.Pipeline.EntryPoint
import Juvix.Prelude

data Options = Options
  { _optTarget :: Target,
    _optDebug :: Bool,
    _optLimits :: Limits
  }

makeLenses ''Options

makeOptions :: Target -> Bool -> Options
makeOptions tgt debug =
  Options
    { _optTarget = tgt,
      _optDebug = debug,
      _optLimits = getLimits tgt debug
    }

getClosureSize :: Options -> Int -> Int
getClosureSize opts argsNum = opts ^. optLimits . limitsClosureHeadSize + argsNum

fromEntryPoint :: EntryPoint -> Options
fromEntryPoint EntryPoint {..} =
  Options
    { _optTarget = _entryPointTarget,
      _optDebug = _entryPointDebug,
      _optLimits = getLimits _entryPointTarget _entryPointDebug
    }
