module Juvix.Compiler.Tree.Evaluator where

import Control.Exception qualified as Exception
import GHC.IO (unsafePerformIO)
import GHC.Show qualified as S
import Juvix.Compiler.Core.Data.BinderList qualified as BL
import Juvix.Compiler.Tree.Data.InfoTable
import Juvix.Compiler.Tree.Error
import Juvix.Compiler.Tree.Evaluator.Builtins
import Juvix.Compiler.Tree.Extra.Base
import Juvix.Compiler.Tree.Language
import Juvix.Compiler.Tree.Language.Value
import Juvix.Compiler.Tree.Pretty

data EvalError = EvalError
  { _evalErrorLocation :: Maybe Location,
    _evalErrorMsg :: Text
  }

makeLenses ''EvalError

instance Show EvalError where
  show :: EvalError -> String
  show EvalError {..} =
    "evaluation error: "
      ++ fromText _evalErrorMsg

instance Exception.Exception EvalError

eval :: InfoTable -> Node -> Value
eval = hEval stdout

hEval :: Handle -> InfoTable -> Node -> Value
hEval hout tab = eval' [] mempty
  where
    eval' :: [Value] -> BL.BinderList Value -> Node -> Value
    eval' args temps node = case node of
      Binop x -> goBinop x
      Unop x -> goUnop x
      Anoma {} -> evalError "unsupported: Anoma builtin"
      Cairo {} -> evalError "unsupported: Cairo builtin"
      Constant c -> goConstant c
      MemRef x -> goMemRef x
      AllocConstr x -> goAllocConstr x
      AllocClosure x -> goAllocClosure x
      ExtendClosure x -> goExtendClosure x
      Call x -> goCall x
      CallClosures x -> goCallClosures x
      Branch x -> goBranch x
      Case x -> goCase x
      Save x -> goSave x
      where
        evalError :: Text -> a
        evalError msg =
          Exception.throw (EvalError (getNodeLocation node) msg)

        eitherToError :: Either Text Value -> Value
        eitherToError = \case
          Left err -> evalError err
          Right v -> v

        goBinop :: NodeBinop -> Value
        goBinop NodeBinop {..} =
          -- keeping the lets separate ensures that `arg1` is evaluated before `arg2`
          let !arg1 = eval' args temps _nodeBinopArg1
           in let !arg2 = eval' args temps _nodeBinopArg2
               in case _nodeBinopOpcode of
                    PrimBinop op -> eitherToError $ evalBinop op arg1 arg2
                    OpSeq -> arg2

        goUnop :: NodeUnop -> Value
        goUnop NodeUnop {..} =
          let !v = eval' args temps _nodeUnopArg
           in case _nodeUnopOpcode of
                PrimUnop op -> eitherToError $ evalUnop tab op v
                OpTrace -> goTrace v
                OpFail -> goFail v

        goFail :: Value -> Value
        goFail v = evalError ("failure: " <> printValue tab v)

        goTrace :: Value -> Value
        goTrace v = unsafePerformIO (hPutStrLn hout (printValue tab v) >> return v)

        goConstant :: NodeConstant -> Value
        goConstant NodeConstant {..} = constantToValue _nodeConstant

        goMemRef :: NodeMemRef -> Value
        goMemRef NodeMemRef {..} = case _nodeMemRef of
          DRef r -> goDirectRef r
          ConstrRef r -> goField r

        goDirectRef :: DirectRef -> Value
        goDirectRef = \case
          ArgRef OffsetRef {..} ->
            args !! _offsetRefOffset
          TempRef RefTemp {_refTempOffsetRef = OffsetRef {..}} ->
            BL.lookupLevel _offsetRefOffset temps

        goField :: Field -> Value
        goField Field {..} = case goDirectRef _fieldRef of
          ValConstr Constr {..} -> _constrArgs !! _fieldOffset
          _ -> evalError "expected a constructor"

        goAllocConstr :: NodeAllocConstr -> Value
        goAllocConstr NodeAllocConstr {..} =
          let !vs = map' (eval' args temps) _nodeAllocConstrArgs
           in ValConstr
                Constr
                  { _constrTag = _nodeAllocConstrTag,
                    _constrArgs = vs
                  }

        goAllocClosure :: NodeAllocClosure -> Value
        goAllocClosure NodeAllocClosure {..} =
          let !vs = map' (eval' args temps) _nodeAllocClosureArgs
           in ValClosure
                Closure
                  { _closureSymbol = _nodeAllocClosureFunSymbol,
                    _closureArgs = vs
                  }

        goExtendClosure :: NodeExtendClosure -> Value
        goExtendClosure NodeExtendClosure {..} =
          case eval' args temps _nodeExtendClosureFun of
            ValClosure Closure {..} ->
              let !vs = map' (eval' args temps) (toList _nodeExtendClosureArgs)
               in ValClosure
                    Closure
                      { _closureSymbol,
                        _closureArgs = _closureArgs ++ vs
                      }
            _ -> evalError "expected a closure"

        goCall :: NodeCall -> Value
        goCall NodeCall {..} = case _nodeCallType of
          CallFun sym -> doCall sym [] _nodeCallArgs
          CallClosure cl -> doCallClosure cl _nodeCallArgs

        doCall :: Symbol -> [Value] -> [Node] -> Value
        doCall sym vs0 as =
          let !vs = map' (eval' args temps) as
              fi = lookupFunInfo tab sym
              vs' = vs0 ++ vs
           in if
                  | length vs' == fi ^. functionArgsNum ->
                      eval' vs' mempty (fi ^. functionCode)
                  | otherwise ->
                      evalError "wrong number of arguments"

        doCallClosure :: Node -> [Node] -> Value
        doCallClosure cl cargs = case eval' args temps cl of
          ValClosure Closure {..} ->
            doCall _closureSymbol _closureArgs cargs
          _ ->
            evalError "expected a closure"

        goCallClosures :: NodeCallClosures -> Value
        goCallClosures NodeCallClosures {..} =
          let !vs = map' (eval' args temps) (toList _nodeCallClosuresArgs)
           in go (eval' args temps _nodeCallClosuresFun) vs
          where
            go :: Value -> [Value] -> Value
            go cl vs = case cl of
              ValClosure Closure {..}
                | argsNum == n ->
                    eval' vs' mempty body
                | argsNum < n ->
                    go (eval' (take argsNum vs') mempty body) (drop argsNum vs')
                | otherwise ->
                    ValClosure
                      Closure
                        { _closureSymbol,
                          _closureArgs = vs'
                        }
                where
                  fi = lookupFunInfo tab _closureSymbol
                  argsNum = fi ^. functionArgsNum
                  vs' = _closureArgs ++ vs
                  n = length vs'
                  body = fi ^. functionCode
              _ ->
                evalError "expected a closure"

        goBranch :: NodeBranch -> Value
        goBranch NodeBranch {..} =
          case eval' args temps _nodeBranchArg of
            ValBool True -> eval' args temps _nodeBranchTrue
            ValBool False -> eval' args temps _nodeBranchFalse
            _ -> evalError "expected a boolean"

        goCase :: NodeCase -> Value
        goCase NodeCase {..} =
          case eval' args temps _nodeCaseArg of
            v@(ValConstr Constr {..}) ->
              case find (\CaseBranch {..} -> _caseBranchTag == _constrTag) _nodeCaseBranches of
                Just CaseBranch {..} -> goCaseBranch v _caseBranchSave _caseBranchBody
                Nothing -> goCaseBranch v False (fromMaybe (evalError "no matching branch") _nodeCaseDefault)
            _ ->
              evalError "expected a constructor"

        goCaseBranch :: Value -> Bool -> Node -> Value
        goCaseBranch v bSave body
          | bSave = eval' args (BL.cons v temps) body
          | otherwise = eval' args temps body

        goSave :: NodeSave -> Value
        goSave NodeSave {..} =
          let !v = eval' args temps _nodeSaveArg
           in eval' args (BL.cons v temps) _nodeSaveBody

valueToNode :: Value -> Node
valueToNode = \case
  ValInteger i -> mkConst $ ConstInt i
  ValField f -> mkConst $ ConstField f
  ValBool b -> mkConst $ ConstBool b
  ValString s -> mkConst $ ConstString s
  ValUnit -> mkConst ConstUnit
  ValVoid -> mkConst ConstVoid
  ValConstr Constr {..} ->
    AllocConstr
      NodeAllocConstr
        { _nodeAllocConstrInfo = mempty,
          _nodeAllocConstrTag = _constrTag,
          _nodeAllocConstrArgs = map valueToNode _constrArgs
        }
  ValClosure Closure {..} ->
    AllocClosure
      NodeAllocClosure
        { _nodeAllocClosureInfo = mempty,
          _nodeAllocClosureFunSymbol = _closureSymbol,
          _nodeAllocClosureArgs = map valueToNode _closureArgs
        }

hEvalIO :: (MonadIO m) => Handle -> Handle -> InfoTable -> FunctionInfo -> m Value
hEvalIO hin hout infoTable funInfo = do
  let !v = hEval hout infoTable (funInfo ^. functionCode)
  hRunIO hin hout infoTable v

-- | Interpret IO actions.
hRunIO :: (MonadIO m) => Handle -> Handle -> InfoTable -> Value -> m Value
hRunIO hin hout infoTable = \case
  ValConstr (Constr (BuiltinTag TagReturn) [x]) -> return x
  ValConstr (Constr (BuiltinTag TagBind) [x, f]) -> do
    x' <- hRunIO hin hout infoTable x
    let code =
          CallClosures
            NodeCallClosures
              { _nodeCallClosuresInfo = mempty,
                _nodeCallClosuresFun = valueToNode f,
                _nodeCallClosuresArgs = valueToNode x' :| []
              }
        !x'' = hEval hout infoTable code
    hRunIO hin hout infoTable x''
  ValConstr (Constr (BuiltinTag TagWrite) [ValString s]) -> do
    hPutStr hout s
    return ValVoid
  ValConstr (Constr (BuiltinTag TagWrite) [arg]) -> do
    hPutStr hout (ppPrint infoTable arg)
    return ValVoid
  ValConstr (Constr (BuiltinTag TagReadLn) []) -> do
    liftIO $ hFlush hout
    s <- liftIO $ hGetLine hin
    return (ValString s)
  val ->
    return val

-- | Catch EvalError and convert it to TreeError.
catchEvalErrorIO :: IO a -> IO (Either TreeError a)
catchEvalErrorIO ma =
  Exception.catch
    (Exception.evaluate ma >>= \ma' -> Right <$> ma')
    (\(ex :: EvalError) -> return (Left (toTreeError ex)))

toTreeError :: EvalError -> TreeError
toTreeError EvalError {..} =
  TreeError
    { _treeErrorMsg = "evaluation error: " <> _evalErrorMsg,
      _treeErrorLoc = _evalErrorLocation
    }
