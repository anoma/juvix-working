module Commands.Extra.Compile.Options where

import App
import CommonOptions hiding (show)
import Juvix.Compiler.Pipeline.EntryPoint
import Prelude (Show (show))

-- TODO explain why we need this on top of `Juvix.Compiler.Backend.Target`
data CompileTarget
  = AppTargetNative64
  | AppTargetWasm32Wasi
  | AppTargetGeb
  | AppTargetVampIR
  | AppTargetCore
  | AppTargetAsm
  | AppTargetReg
  | AppTargetTree
  | AppTargetAnoma
  | AppTargetCasm
  | AppTargetCairo
  deriving stock (Eq, Data, Bounded, Enum)

instance Show CompileTarget where
  show = \case
    AppTargetWasm32Wasi -> "wasi"
    AppTargetNative64 -> "native"
    AppTargetGeb -> "geb"
    AppTargetVampIR -> "vampir"
    AppTargetCore -> "core"
    AppTargetAsm -> "asm"
    AppTargetReg -> "reg"
    AppTargetTree -> "tree"
    AppTargetAnoma -> "anoma"
    AppTargetCasm -> "casm"
    AppTargetCairo -> "cairo"

-- | If the input file can be defaulted to the `main` in the `package.yaml` file, we
-- can omit the input file.
type CompileOptionsMain = CompileOptions' (Maybe (AppPath File))

type CompileOptions = CompileOptions' (AppPath File)

data CompileOptions' inputFile = CompileOptions
  { _compileDebug :: Bool,
    _compileCOutput :: Bool,
    _compilePreprocess :: Bool,
    _compileAssembly :: Bool,
    _compileTerm :: Bool,
    _compileUnsafe :: Bool,
    _compileOutputFile :: Maybe (AppPath File),
    _compileTarget :: CompileTarget,
    _compileInputFile :: inputFile,
    _compileOptimizationLevel :: Maybe Int,
    _compileInliningDepth :: Int,
    _compileNockmaUsePrettySymbols :: Bool
  }
  deriving stock (Data)

makeLenses ''CompileOptions'

fromCompileOptionsMain :: (Members '[App] r) => CompileOptionsMain -> Sem r CompileOptions
fromCompileOptionsMain = traverseOf compileInputFile getMainAppFile

compileTargetDescription :: forall str. (IsString str) => CompileTarget -> str
compileTargetDescription = \case
  AppTargetNative64 -> "Compile to native code"
  AppTargetWasm32Wasi -> "Compile to WASI (WebAssembly System Interface)"
  AppTargetAnoma -> "Compile to Anoma"
  AppTargetCairo -> "Compile to Cairo"
  AppTargetGeb -> "Compile to Geb"
  AppTargetVampIR -> "Compile to VampIR"
  AppTargetCasm -> "Compile to JuvixCasm"
  AppTargetCore -> "Compile to VampIR"
  AppTargetAsm -> "Compile to JuvixAsm"
  AppTargetReg -> "Compile to JuvixReg"
  AppTargetTree -> "Compile to JuvixTree"

type SupportedTargets = NonEmpty CompileTarget

allTargets :: [CompileTarget]
allTargets = allElements

parseCompileOptionsMain ::
  SupportedTargets ->
  Parser CompileOptionsMain
parseCompileOptionsMain supportedTargets =
  parseCompileOptions'
    supportedTargets
    (optional (parseInputFiles (FileExtJuvix :| [FileExtJuvixMarkdown])))

parseCompileOptions ::
  SupportedTargets ->
  Parser (AppPath File) ->
  Parser CompileOptions
parseCompileOptions = parseCompileOptions'

parseCompileOptions' ::
  SupportedTargets ->
  Parser a ->
  Parser (CompileOptions' a)
parseCompileOptions' supportedTargets parserFile = do
  _compileDebug <-
    switch
      ( short 'g'
          <> long "debug"
          <> help "Generate debug information and runtime assertions. Disables optimizations"
      )
  _compileCOutput <-
    switch
      ( short 'C'
          <> long "only-c"
          <> help "Produce C output only (for targets: wasm32-wasi, native)"
      )
  _compilePreprocess <-
    switch
      ( short 'E'
          <> long "only-preprocess"
          <> help "Run the C preprocessor only (for targets: wasm32-wasi, native)"
      )
  _compileAssembly <-
    switch
      ( short 'S'
          <> long "only-assemble"
          <> help "Produce assembly output only (for targets: wasm32-wasi, native)"
      )
  _compileTerm <-
    if
        | elem AppTargetGeb supportedTargets ->
            switch
              ( short 'G'
                  <> long "only-term"
                  <> help "Produce term output only (for targets: geb)"
              )
        | otherwise ->
            pure False
  _compileNockmaUsePrettySymbols <-
    switch
      ( long "nockma-pretty"
          <> help "Use names for op codes and paths in Nockma output (for target: nockma)"
      )
  _compileUnsafe <-
    if
        | elem AppTargetVampIR supportedTargets ->
            switch
              ( long "unsafe"
                  <> help "Disable range and error checking (for targets: vampir)"
              )
        | otherwise ->
            pure False
  _compileOptimizationLevel <-
    optional
      ( option
          (fromIntegral <$> naturalNumberOpt)
          ( short 'O'
              <> long "optimize"
              <> help ("Optimization level (default: " <> show defaultOptimizationLevel <> ")")
          )
      )
  _compileInliningDepth <-
    option
      (fromIntegral <$> naturalNumberOpt)
      ( long "inline"
          <> value defaultInliningDepth
          <> help ("Automatic inlining depth limit, logarithmic in the function size (default: " <> show defaultInliningDepth <> ")")
      )
  _compileTarget <- optCompileTarget supportedTargets
  _compileOutputFile <- optional parseGenericOutputFile
  _compileInputFile <- parserFile
  pure CompileOptions {..}

optCompileTarget :: SupportedTargets -> Parser CompileTarget
optCompileTarget supportedTargets =
  option
    (eitherReader parseTarget)
    ( long "target"
        <> short 't'
        <> metavar "TARGET"
        <> value (head supportedTargets)
        <> showDefault
        <> help ("select a target: " <> show listTargets)
        <> completeWith (map show listTargets)
    )
  where
    listTargets :: [CompileTarget]
    listTargets = toList supportedTargets

    parseTarget :: String -> Either String CompileTarget
    parseTarget txt =
      maybe err return $
        lookup
          (map toLower txt)
          [(Prelude.show t, t) | t <- listTargets]
      where
        err = Left $ "unrecognised target: " <> txt
