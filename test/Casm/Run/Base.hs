module Casm.Run.Base where

import Base
import Data.Text.IO qualified as TIO
import Juvix.Compiler.Casm.Error
import Juvix.Compiler.Casm.Interpreter
import Juvix.Compiler.Casm.Translation.FromSource
import Juvix.Data.PPOutput
import Juvix.Parser.Error

casmRunAssertion' :: LabelInfo -> Code -> Path Abs File -> (String -> IO ()) -> Assertion
casmRunAssertion' labi instrs expectedFile step = do
  withTempDir'
    ( \dirPath -> do
        let outputFile = dirPath <//> $(mkRelFile "out.out")
        step "Interpret"
        r' <- doRun labi instrs
        case r' of
          Left err -> do
            assertFailure (show (pretty err))
          Right value' -> do
            hout <- openFile (toFilePath outputFile) WriteMode
            hPrint hout value'
            hClose hout
            actualOutput <- TIO.readFile (toFilePath outputFile)
            step "Compare expected and actual program output"
            expected <- TIO.readFile (toFilePath expectedFile)
            assertEqDiffText ("Check: RUN output = " <> toFilePath expectedFile) actualOutput expected
    )

casmRunAssertion :: Path Abs File -> Path Abs File -> (String -> IO ()) -> Assertion
casmRunAssertion mainFile expectedFile step = do
  step "Parse"
  r <- parseFile mainFile
  case r of
    Left err -> assertFailure (show (pretty err))
    Right (labi, instrs) -> casmRunAssertion' labi instrs expectedFile step

parseFile :: Path Abs File -> IO (Either MegaparsecError (LabelInfo, Code))
parseFile f = do
  let f' = toFilePath f
  s <- readFile f'
  return $ runParser f' s

doRun ::
  LabelInfo ->
  Code ->
  IO (Either CasmError Integer)
doRun labi instrs = catchRunErrorIO (runCode labi instrs)
