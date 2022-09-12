module Juvix.Compiler.Asm.Extra.Base where

import Data.HashMap.Strict qualified as HashMap
import Juvix.Compiler.Asm.Data.InfoTable
import Juvix.Compiler.Asm.Language

mkInstr :: Instruction -> Command
mkInstr = Instr . CmdInstr emptyInfo

getFunInfo :: InfoTable -> Symbol -> FunctionInfo
getFunInfo infoTable sym = fromMaybe (error "invalid function symbol") (HashMap.lookup sym (infoTable ^. infoFunctions))

getConstrInfo :: InfoTable -> Tag -> ConstructorInfo
getConstrInfo infoTable tag = fromMaybe (error "invalid constructor tag") (HashMap.lookup tag (infoTable ^. infoConstrs))

isFinalInstr :: Instruction -> Bool
isFinalInstr = \case
  Return -> True
  TailCall {} -> True
  TailCallClosures {} -> True
  _ -> False
