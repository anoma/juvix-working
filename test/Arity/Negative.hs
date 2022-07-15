module Arity.Negative (allTests) where

import Base
import Juvix.Pipeline
import Juvix.Syntax.MicroJuvix.ArityChecker.Error

type FailMsg = String

data NegTest = NegTest
  { _name :: String,
    _relDir :: FilePath,
    _file :: FilePath,
    _checkErr :: ArityCheckerError -> Maybe FailMsg
  }

testDescr :: NegTest -> TestDescr
testDescr NegTest {..} =
  let tRoot = root </> _relDir
   in TestDescr
        { _testName = _name,
          _testRoot = tRoot,
          _testAssertion = Single $ do
            let entryPoint = defaultEntryPoint _file
            result <- runIOEither (upToMicroJuvixArity entryPoint)
            case mapLeft fromJuvixError result of
              Left (Just tyError) -> whenJust (_checkErr tyError) assertFailure
              Left Nothing -> assertFailure "The arity checker did not find an error."
              Right _ -> assertFailure "An error ocurred but it was not in the arity checker."
        }

allTests :: TestTree
allTests =
  testGroup
    "Arity checker negative tests"
    (map (mkTest . testDescr) tests)

root :: FilePath
root = "tests/negative"

wrongError :: Maybe FailMsg
wrongError = Just "Incorrect error"

tests :: [NegTest]
tests =
  [ NegTest
      "Too many arguments in expression"
      "MicroJuvix"
      "TooManyArguments.juvix"
      $ \case
        ErrTooManyArguments {} -> Nothing
        _ -> wrongError,
    NegTest
      "Pattern match a function type"
      "MicroJuvix"
      "FunctionPattern.juvix"
      $ \case
        ErrPatternFunction {} -> Nothing
        _ -> wrongError,
    NegTest
      "Function type (* → *) application"
      "MicroJuvix"
      "FunctionApplied.juvix"
      $ \case
        ErrFunctionApplied {} -> Nothing
        _ -> wrongError,
    NegTest
      "Expected explicit pattern"
      "MicroJuvix"
      "ExpectedExplicitPattern.juvix"
      $ \case
        ErrWrongPatternIsImplicit {} -> Nothing
        _ -> wrongError,
    NegTest
      "Expected explicit argument"
      "MicroJuvix"
      "ExpectedExplicitArgument.juvix"
      $ \case
        ErrExpectedExplicitArgument {} -> Nothing
        _ -> wrongError,
    NegTest
      "Function clause with two many patterns in the lhs"
      "MicroJuvix"
      "LhsTooManyPatterns.juvix"
      $ \case
        ErrLhsTooManyPatterns {} -> Nothing
        _ -> wrongError
  ]
