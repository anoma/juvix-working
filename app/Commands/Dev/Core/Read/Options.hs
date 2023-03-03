module Commands.Dev.Core.Read.Options where

import Commands.Dev.Core.Eval.Options qualified as Eval
import CommonOptions
import Evaluator qualified
import Juvix.Compiler.Core.Data.TransformationId
import Juvix.Compiler.Core.Pretty.Options qualified as Core

data CoreReadOptions = CoreReadOptions
  { _coreReadTransformations :: [TransformationId],
    _coreReadShowDeBruijn :: Bool,
    _coreReadShowIdentIds :: Bool,
    _coreReadNoDisambiguate :: Bool,
    _coreReadEval :: Bool,
    _coreReadNoPrint :: Bool,
    _coreReadInputFile :: AppPath File
  }
  deriving stock (Data)

makeLenses ''CoreReadOptions

instance CanonicalProjection CoreReadOptions Core.Options where
  project c =
    Core.defaultOptions
      { Core._optShowDeBruijnIndices = c ^. coreReadShowDeBruijn,
        Core._optShowIdentIds = c ^. coreReadShowIdentIds
      }

instance CanonicalProjection CoreReadOptions Eval.CoreEvalOptions where
  project c =
    Eval.CoreEvalOptions
      { _coreEvalNoIO = False,
        _coreEvalInputFile = c ^. coreReadInputFile,
        _coreEvalShowDeBruijn = c ^. coreReadShowDeBruijn,
        _coreEvalShowIdentIds = c ^. coreReadShowIdentIds,
        _coreEvalNoDisambiguate = c ^. coreReadNoDisambiguate
      }

instance CanonicalProjection CoreReadOptions Evaluator.EvalOptions where
  project x =
    Evaluator.EvalOptions
      { _evalNoIO = False,
        _evalNoDisambiguate = x ^. coreReadNoDisambiguate,
        _evalInputFile = x ^. coreReadInputFile
      }

parseCoreReadOptions :: Parser CoreReadOptions
parseCoreReadOptions = do
  _coreReadShowDeBruijn <- optDeBruijn
  _coreReadShowIdentIds <- optIdentIds
  _coreReadNoDisambiguate <- optNoDisambiguate
  _coreReadNoPrint <-
    switch
      ( long "no-print"
          <> help "do not print the transformed code"
      )
  _coreReadEval <-
    switch
      ( long "eval"
          <> help "evaluate after the transformation"
      )
  _coreReadTransformations <- optTransformationIds
  _coreReadInputFile <- parseInputJuvixCoreFile
  pure CoreReadOptions {..}
