module Commands.Dev.Termination.Calls.Options where

import CommonOptions
import Data.Text qualified as Text
import GlobalOptions
import Juvix.Compiler.Internal.Pretty.Options qualified as Internal

data CallsOptions = CallsOptions
  { _callsFunctionNameFilter :: Maybe (NonEmpty Text),
    _callsShowDecreasingArgs :: Internal.ShowDecrArgs,
    _callsInputFile :: Maybe (AppPath File)
  }
  deriving stock (Data)

makeLenses ''CallsOptions

parseCalls :: Parser CallsOptions
parseCalls = do
  _callsFunctionNameFilter <-
    fmap msum . optional $
      nonEmpty . Text.words
        <$> option
          str
          ( long "function"
              <> short 'f'
              <> metavar "fun1 fun2 ..."
              <> help "Only shows the specified functions"
          )
  _callsShowDecreasingArgs <-
    option
      (enumReader Proxy)
      ( long "show-decreasing-args"
          <> short 'd'
          <> value Internal.ArgRel
          <> helpDoc (enumHelp Internal.showDecrArgsHelp)
      )
  _callsInputFile <- optional (parseInputFile FileExtJuvix)
  pure CallsOptions {..}

instance CanonicalProjection (GlobalOptions, CallsOptions) Internal.Options where
  project (GlobalOptions {..}, CallsOptions {..}) =
    Internal.defaultOptions
      { Internal._optShowNameIds = _globalShowNameIds,
        Internal._optShowDecreasingArgs = _callsShowDecreasingArgs
      }
