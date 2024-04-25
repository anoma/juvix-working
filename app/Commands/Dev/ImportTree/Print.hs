module Commands.Dev.ImportTree.Print where

import Commands.Base
import Commands.Dev.ImportTree.Print.Options
import Juvix.Compiler.Concrete.Print
import Juvix.Compiler.Concrete.Translation.FromParsed.Analysis.Scoping.Error
import Juvix.Compiler.Pipeline.Loader.PathResolver
import Juvix.Compiler.Pipeline.Setup

runCommand :: (Members '[EmbedIO, App, TaggedLock] r) => PrintOptions -> Sem r ()
runCommand PrintOptions =
  runPipelineSetup $ do
    entrySetup defaultDependenciesConfig
    tree <- mapError (JuvixError @ScoperError) mkImportTree
    renderStdOut (ppOutDefaultNoComments tree)
