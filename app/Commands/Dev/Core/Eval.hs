module Commands.Dev.Core.Eval where

import Commands.Base
import Commands.Dev.Core.Eval.Options
import Juvix.Compiler.Core.Data.InfoTable qualified as Core
import Juvix.Compiler.Core.Error qualified as Core
import Juvix.Compiler.Core.Evaluator qualified as Core
import Juvix.Compiler.Core.Extra.Base qualified as Core
import Juvix.Compiler.Core.Info qualified as Info
import Juvix.Compiler.Core.Info.NoDisplayInfo qualified as Info
import Juvix.Compiler.Core.Language qualified as Core
import Juvix.Compiler.Core.Pretty qualified as Core
import Juvix.Compiler.Core.Translation.FromSource qualified as Core
import Text.Megaparsec.Pos qualified as M

doEval ::
  forall r.
  Members '[Embed IO, App] r =>
  Bool ->
  Interval ->
  Core.InfoTable ->
  Core.Node ->
  Sem r (Either Core.CoreError Core.Node)
doEval noIO loc tab node
  | noIO = embed $ Core.catchEvalError loc (Core.eval (tab ^. Core.identContext) [] node)
  | otherwise = embed $ Core.catchEvalErrorIO loc (Core.evalIO (tab ^. Core.identContext) [] node)

evalNode ::
  forall r a.
  (Members '[Embed IO, App] r, CanonicalProjection a Core.Options) =>
  a ->
  Bool ->
  Path ->
  Core.InfoTable ->
  Core.Node ->
  Sem r ()
evalNode opts noIO p tab node = do
  r <- doEval noIO defaultLoc tab node
  case r of
    Left err -> exitJuvixError (JuvixError err)
    Right node'
      | Info.member Info.kNoDisplayInfo (Core.getInfo node') ->
          return ()
    Right node' -> do
      renderStdOut (Core.ppOut docOpts node')
      embed (putStrLn "")
  where
    defaultLoc :: Interval
    defaultLoc = singletonInterval (mkLoc f 0 (M.initialPos f))
    f :: FilePath
    f = p ^. pathPath
    docOpts :: Core.Options
    docOpts = Core.defaultOptions

runCommand :: forall r. Members '[Embed IO, App] r => CoreEvalOptions -> Sem r ()
runCommand opts = do
  s <- embed (readFile f)
  case Core.runParser "" f Core.emptyInfoTable s of
    Left err -> exitJuvixError (JuvixError err)
    Right (tab, Just node) -> evalNode opts (opts ^. coreEvalNoIO) (opts ^. coreEvalInputFile) tab node
    Right (_, Nothing) -> return ()
  where
    f :: FilePath
    f = opts ^. coreEvalInputFile . pathPath
