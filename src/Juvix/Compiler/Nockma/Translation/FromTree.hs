module Juvix.Compiler.Nockma.Translation.FromTree where

import Juvix.Compiler.Nockma.Language.Path
import Juvix.Compiler.Nockma.Pretty
import Juvix.Compiler.Nockma.Stdlib
import Juvix.Compiler.Pipeline.EntryPoint
import Juvix.Compiler.Tree.Data.InfoTable qualified as Tree
import Juvix.Compiler.Tree.Language qualified as Tree
import Juvix.Compiler.Tree.Language.Rep
import Juvix.Prelude hiding (Atom, Path)

nockmaMemRep :: MemRep -> NockmaMemRep
nockmaMemRep = \case
  MemRepTuple -> NockmaMemRepTuple
  MemRepConstr -> NockmaMemRepConstr
  MemRepTag -> NockmaMemRepConstr
  MemRepUnit -> NockmaMemRepConstr
  MemRepUnpacked {} -> NockmaMemRepConstr

data NockmaMemRepListConstr
  = NockmaMemRepListConstrNil
  | NockmaMemRepListConstrCons
  deriving stock (Eq)

data NockmaMemRep
  = NockmaMemRepConstr
  | NockmaMemRepTuple
  | NockmaMemRepList NockmaMemRepListConstr

newtype NockmaBuiltinTag
  = NockmaBuiltinBool Bool

type UserFunctionId = Symbol

data FunctionId
  = UserFunction UserFunctionId
  | BuiltinFunction BuiltinFunctionId
  deriving stock (Generic, Eq)

instance Hashable FunctionId

data BuiltinFunctionId
  = BuiltinPow2Go
  | BuiltinPow2
  | BuiltinAppendRights
  deriving stock (Eq, Enum, Bounded, Generic)

instance Hashable BuiltinFunctionId

newtype CompilerOptions = CompilerOptions
  {_compilerOptionsEnableTrace :: Bool}

fromEntryPoint :: EntryPoint -> CompilerOptions
fromEntryPoint EntryPoint {..} =
  CompilerOptions
    { _compilerOptionsEnableTrace = _entryPointDebug
    }

data FunctionInfo = FunctionInfo
  { _functionInfoPath :: Path,
    _functionInfoArity :: Natural
  }

data CompilerCtx = CompilerCtx
  { _compilerFunctionInfos :: HashMap FunctionId FunctionInfo,
    _compilerConstructorInfos :: ConstructorInfos,
    _compilerOptions :: CompilerOptions
  }

data ConstructorInfo = ConstructorInfo
  { _constructorInfoArity :: Natural,
    _constructorInfoMemRep :: NockmaMemRep
  }

type ConstructorInfos = HashMap Tree.Tag ConstructorInfo

type Offset = Natural

data CompilerFunction = CompilerFunction
  { _compilerFunctionName :: FunctionId,
    _compilerFunctionArity :: Natural,
    _compilerFunction :: Sem '[Compiler, Reader CompilerCtx] (Term Natural)
  }

data StackId
  = Args
  | TempStack
  | StandardLibrary
  | FunctionsLibrary
  deriving stock (Enum, Bounded, Eq, Show)

-- | A closure has the following structure:
-- [code totalArgsNum argsNum args], where
-- 1. code is code to run when fully applied.
-- 2. totalArgsNum is the number of arguments that the function
--     which created the closure expects.
-- 3. argsNum is the number of arguments that have been applied to the closure.
-- 4. args is the list of args that have been applied.
--    The length of the list should be argsNum.
data ClosurePathId
  = ClosureCode
  | ClosureTotalArgsNum
  | ClosureArgsNum
  | ClosureArgs
  deriving stock (Bounded, Enum)

pathFromEnum :: (Enum a) => a -> Path
pathFromEnum = indexStack . fromIntegral . fromEnum

closurePath :: ClosurePathId -> Path
closurePath = pathFromEnum

data ConstructorPathId
  = ConstructorTag
  | ConstructorArgs
  deriving stock (Bounded, Enum)

constructorPath :: ConstructorPathId -> Path
constructorPath = pathFromEnum

data ActivationFramePathId
  = ActivationFrameValueStack
  | ActivationFrameTempStack
  | ActivationFrameAuxStack
  deriving stock (Bounded, Enum)

activationFramePath :: ActivationFramePathId -> Path
activationFramePath = pathFromEnum

data FunctionPathId
  = FunctionCode
  | FunctionArgs

functionPath :: FunctionPathId -> Path
functionPath = \case
  FunctionCode -> [L]
  FunctionArgs -> [R]

numStacks :: (Integral a) => a
numStacks = fromIntegral (length (allElements @StackId))

data Compiler m a where
  Verbatim :: Term Natural -> Compiler m ()
  TraceTerm :: Term Natural -> Compiler m ()
  PushOnto :: StackId -> Term Natural -> Compiler m ()
  PopNAndPushOnto :: StackId -> Natural -> Term Natural -> Compiler m ()
  PopFromN :: Natural -> StackId -> Compiler m ()
  TestEqOn :: StackId -> Compiler m ()
  CallHelper :: Bool -> Maybe FunctionId -> Natural -> Compiler m ()
  IncrementOn :: StackId -> Compiler m ()
  Save :: Bool -> m () -> Compiler m ()
  CallStdlibOn :: StackId -> StdlibFunction -> Compiler m ()
  GetConstructorInfo :: Tree.Tag -> Compiler m ConstructorInfo
  GetFunctionArity :: FunctionId -> Compiler m Natural
  GetFunctionPath :: FunctionId -> Compiler m Path

stackPath :: StackId -> Path
stackPath s = indexStack (fromIntegral (fromEnum s))

indexTuple :: Natural -> Natural -> Path
indexTuple len idx
  | idx >= len = impossible
  | otherwise =
      let lastL
            | idx == len - 1 = []
            | otherwise = [L]
       in replicate idx R ++ lastL

indexStack :: Natural -> Path
indexStack idx = replicate idx R ++ [L]

indexInPath :: Path -> Natural -> Path
indexInPath p idx = p ++ indexStack idx

topOfStack :: StackId -> Path
topOfStack s = indexInStack s 0

indexInStack :: StackId -> Natural -> Path
indexInStack s idx = stackPath s ++ indexStack idx

pathToArgumentsArea :: Path
pathToArgumentsArea = topOfStack Args

pathToArg :: Natural -> Path
pathToArg = indexInPath pathToArgumentsArea

-- | Construct a path rooted at he head of a named stack
pathInStack :: StackId -> Path -> Path
pathInStack s p = stackPath s ++ p

makeSem ''Compiler
makeLenses ''CompilerOptions
makeLenses ''CompilerFunction
makeLenses ''CompilerCtx
makeLenses ''ConstructorInfo
makeLenses ''FunctionInfo

termFromParts :: (Bounded p, Enum p) => (p -> Term Natural) -> Term Natural
termFromParts f = remakeList [f pi | pi <- allElements]

makeClosure :: (ClosurePathId -> Term Natural) -> Term Natural
makeClosure = termFromParts

makeConstructor :: (ConstructorPathId -> Term Natural) -> Term Natural
makeConstructor = termFromParts

makeActivationFrame :: (ActivationFramePathId -> Term Natural) -> Term Natural
makeActivationFrame = termFromParts

makeFunction :: (FunctionPathId -> Term Natural) -> Term Natural
makeFunction f = f FunctionCode # f FunctionArgs

foldTerms :: NonEmpty (Term Natural) -> Term Natural
foldTerms = foldr1 (#)

allConstructors :: Tree.InfoTable -> Tree.ConstructorInfo -> NonEmpty Tree.ConstructorInfo
allConstructors Tree.InfoTable {..} ci =
  let indInfo = getInductiveInfo (ci ^. Tree.constructorInductive)
   in nonEmpty' (getConstructorInfo'' <$> indInfo ^. Tree.inductiveConstructors)
  where
    getInductiveInfo :: Symbol -> Tree.InductiveInfo
    getInductiveInfo s = _infoInductives ^?! at s . _Just

    getConstructorInfo'' :: Tree.Tag -> Tree.ConstructorInfo
    getConstructorInfo'' t = _infoConstrs ^?! at t . _Just

supportsListNockmaRep :: Tree.InfoTable -> Tree.ConstructorInfo -> Maybe NockmaMemRepListConstr
supportsListNockmaRep tab ci = case allConstructors tab ci of
  c1 :| [c2]
    | [0, 2] `elem` permutations ((^. Tree.constructorArgsNum) <$> [c1, c2]) -> Just $ case ci ^. Tree.constructorArgsNum of
        0 -> NockmaMemRepListConstrNil
        2 -> NockmaMemRepListConstrCons
        _ -> impossible
    | otherwise -> Nothing
  _ -> Nothing

-- | Use `Tree.toNockma` before calling this function
fromTreeTable :: (Members '[Error JuvixError, Reader CompilerOptions] r) => Tree.InfoTable -> Sem r (Cell Natural)
fromTreeTable t = case t ^. Tree.infoMainFunction of
  Just mainFun -> do
    opts <- ask
    return (fromTree opts mainFun t)
  Nothing -> throw @JuvixError (error "TODO missing main")
  where
    fromTree :: CompilerOptions -> Tree.Symbol -> Tree.InfoTable -> Cell Natural
    fromTree opts mainSym tab@Tree.InfoTable {..} =
      let funs = map compileFunction allFunctions
          mkConstructorInfo :: Tree.ConstructorInfo -> ConstructorInfo
          mkConstructorInfo ci@Tree.ConstructorInfo {..} =
            ConstructorInfo
              { _constructorInfoArity = fromIntegral _constructorArgsNum,
                _constructorInfoMemRep = rep
              }
            where
              rep :: NockmaMemRep
              rep = maybe r NockmaMemRepList (supportsListNockmaRep tab ci)
                where
                  r = nockmaMemRep (memRep ci (getInductiveInfo (ci ^. Tree.constructorInductive)))

          constrs :: ConstructorInfos
          constrs = mkConstructorInfo <$> _infoConstrs

          getInductiveInfo :: Symbol -> Tree.InductiveInfo
          getInductiveInfo s = _infoInductives ^?! at s . _Just
       in runCompilerWith opts constrs funs mainFun
      where
        mainFun :: CompilerFunction
        mainFun =
          CompilerFunction
            { _compilerFunctionName = UserFunction mainSym,
              _compilerFunctionArity = 0,
              _compilerFunction = compile mainCode
            }

        mainCode :: Tree.Node
        mainCode = _infoFunctions ^?! at mainSym . _Just . Tree.functionCode

        allFunctions :: [Tree.FunctionInfo]
        allFunctions = filter notMain (toList _infoFunctions)
          where
            notMain :: Tree.FunctionInfo -> Bool
            notMain Tree.FunctionInfo {..} = _functionSymbol /= mainSym

        compileFunction :: Tree.FunctionInfo -> CompilerFunction
        compileFunction Tree.FunctionInfo {..} =
          CompilerFunction
            { _compilerFunctionName = UserFunction _functionSymbol,
              _compilerFunctionArity = fromIntegral _functionArgsNum,
              _compilerFunction = compile _functionCode
            }

        memRep :: Tree.ConstructorInfo -> Tree.InductiveInfo -> Tree.MemRep
        memRep ci ind
          | numArgs >= 1 && numConstrs == 1 = MemRepTuple
          | otherwise = MemRepConstr
          where
            numConstrs = length (ind ^. Tree.inductiveConstructors)
            numArgs = ci ^. Tree.constructorArgsNum

fromOffsetRef :: Tree.OffsetRef -> Natural
fromOffsetRef = fromIntegral . (^. Tree.offsetRefOffset)

compile :: forall r. (Members '[Compiler] r) => Tree.Node -> Sem r (Term Natural)
compile = \case
  Tree.Binop b -> goBinop b
  Tree.Unop b -> goUnop b
  Tree.Const c -> return (goConst c)
  Tree.MemRef c -> goMemRef c
  Tree.AllocConstr c -> goAllocConstr c
  Tree.AllocClosure c -> goAllocClosure c
  Tree.ExtendClosure c -> goExtendClosure c
  Tree.Call c -> goCall c
  Tree.Branch b -> goBranch b
  Tree.Case c -> goCase c
  Tree.Save s -> goSave s
  Tree.CallClosures {} -> impossible
  where
    goAllocConstr :: Tree.NodeAllocConstr -> Sem r (Term Natural)
    goAllocConstr Tree.NodeAllocConstr {..} = do
      args <- mapM compile _nodeAllocConstrArgs
      return $ case _nodeAllocConstrTag of
        Tree.UserTag tag ->
          makeConstructor $ \case
            ConstructorTag -> OpQuote # (fromIntegral (tag ^. Tree.tagUserWord) :: Natural)
            ConstructorArgs -> remakeList args
        Tree.BuiltinTag tag -> case nockmaBuiltinTag tag of
          NockmaBuiltinBool b -> nockBoolLiteral b

    goMemRef :: Tree.MemRef -> Sem r (Term Natural)
    goMemRef = \case
      Tree.DRef d -> goDirectRef d
      Tree.ConstrRef {} -> error "TODO"
      where
        goDirectRef :: Tree.DirectRef -> Sem r (Term Natural)
        goDirectRef = \case
          Tree.ArgRef {} -> error "TODO"
          Tree.TempRef {} -> error "TODO"

    goConst :: Tree.Constant -> Term Natural
    goConst = \case
      Tree.ConstInt i
        | i < 0 -> error "negative integer"
        | otherwise -> toNock @Natural (fromIntegral i)
      Tree.ConstBool i -> nockBoolLiteral i
      Tree.ConstString {} -> stringsErr
      Tree.ConstUnit -> constUnit
      Tree.ConstVoid -> constVoid

    goSave :: Tree.NodeSave -> Sem r (Term Natural)
    goSave Tree.NodeSave {..} = do
      arg <- compile _nodeSaveArg
      body <- compile _nodeSaveBody
      return (withTemp arg body)

    goCase :: Tree.NodeCase -> Sem r (Term Natural)
    goCase c = do
      def <- mapM compile (c ^. Tree.nodeCaseDefault)
      branches <-
        sequence
          [ do
              body' <- compile (b ^. Tree.caseBranchBody)
              return (b ^. Tree.caseBranchTag, body')
            | b <- c ^. Tree.nodeCaseBranches
          ]
      arg <- compile (c ^. Tree.nodeCaseArg)
      caseCmd arg def branches

    goBranch :: Tree.NodeBranch -> Sem r (Term Natural)
    goBranch Tree.NodeBranch {..} = do
      arg <- compile _nodeBranchArg
      iftrue <- compile _nodeBranchTrue
      iffalse <- compile _nodeBranchFalse
      return (branch arg iftrue iffalse)

    goUnop :: Tree.NodeUnop -> Sem r (Term Natural)
    goUnop Tree.NodeUnop {..} = goUnaryOpcode _nodeUnopOpcode
      where
        goUnaryOpcode :: Tree.UnaryOpcode -> Sem r (Term Natural)
        goUnaryOpcode = \case
          Tree.OpShow -> stringsErr
          Tree.OpStrToInt -> stringsErr
          Tree.OpFail -> return crash
          Tree.OpTrace -> error "TODO"
          Tree.OpArgsNum -> error "TODO"

    goBinop :: Tree.NodeBinop -> Sem r (Term Natural)
    goBinop Tree.NodeBinop {..} = do
      arg1 <- compile _nodeBinopArg1
      arg2 <- compile _nodeBinopArg2
      let args = [arg1, arg2]
      case _nodeBinopOpcode of
        Tree.IntAdd -> return (callStdlib StdlibAdd args)
        Tree.IntSub -> return (callStdlib StdlibSub args)
        Tree.IntMul -> return (callStdlib StdlibMul args)
        Tree.IntDiv -> return (callStdlib StdlibDiv args)
        Tree.IntMod -> return (callStdlib StdlibMod args)
        Tree.IntLt -> return (callStdlib StdlibLt args)
        Tree.IntLe -> return (callStdlib StdlibLe args)
        Tree.OpSeq -> error "TODO"
        Tree.ValEq -> testEq _nodeBinopArg1 _nodeBinopArg2
        Tree.StrConcat -> stringsErr

    goAllocClosure :: Tree.NodeAllocClosure -> Sem r (Term Natural)
    goAllocClosure = error "TODO"

    goExtendClosure :: Tree.NodeExtendClosure -> Sem r (Term Natural)
    goExtendClosure = extendClosure

    goCallHelper :: Bool -> Tree.NodeCall -> Sem r (Term Natural)
    goCallHelper _isTail Tree.NodeCall {..} = do
      args <- mapM compile _nodeCallArgs
      case _nodeCallType of
        Tree.CallFun fun -> callFun (UserFunction fun) args
        Tree.CallClosure f -> do
          f' <- compile f
          let argsNum = getClosureField ClosureArgsNum f'
              oldArgs = getClosureField ClosureArgs f'
              fcode = getClosureField ClosureCode f'
          posOfArgsNil <- appendRights (toNock emptyPath) argsNum
          let allArgs = replaceSubterm' oldArgs posOfArgsNil (remakeList args)
          return (replaceArgsWithTerm allArgs >># fcode)

    goCall :: Tree.NodeCall -> Sem r (Term Natural)
    goCall = goCallHelper False

-- | arg order: push path >> push n
appendRights ::
  (Members '[Compiler] r) =>
  Term Natural ->
  Term Natural ->
  Sem r (Term Natural)
appendRights path n = callFun (BuiltinFunction BuiltinAppendRights) [path, n]

pushTemp :: Term Natural -> Term Natural
pushTemp toBePushed =
  remakeList
    [ let p = OpAddress # stackPath s
       in if
              | TempStack == s -> toBePushed # p
              | otherwise -> p
      | s <- allElements
    ]

withTemp :: Term Natural -> Term Natural -> Term Natural
withTemp toBePushed body =
  OpSequence # pushTemp toBePushed # body

testEq :: (Members '[Compiler] r) => Tree.Node -> Tree.Node -> Sem r (Term Natural)
testEq a b = do
  a' <- compile a
  b' <- compile b
  return (OpEq # a' # b')

nockIntegralLiteral :: (Integral a) => a -> Term Natural
nockIntegralLiteral = (OpQuote #) . toNock @Natural . fromIntegral

extendClosure ::
  (Members '[Compiler] r) =>
  Tree.NodeExtendClosure ->
  Sem r (Term Natural)
extendClosure Tree.NodeExtendClosure {..} = do
  args <- mapM compile _nodeExtendClosureArgs
  closure <- compile _nodeExtendClosureFun
  let argsNum = getClosureField ClosureArgsNum closure
      oldArgs = getClosureField ClosureArgs closure
      fcode = getClosureField ClosureCode closure
  posOfArgsNil <- appendRights (toNock emptyPath) argsNum
  let allArgs = replaceSubterm' oldArgs posOfArgsNil (remakeList args)
  let newArgsNum = add argsNum (nockIntegralLiteral (length _nodeExtendClosureArgs))
  return . makeClosure $ \case
    ClosureCode -> fcode
    ClosureTotalArgsNum -> getClosureField ClosureTotalArgsNum closure
    ClosureArgsNum -> newArgsNum
    ClosureArgs -> allArgs

callStdlib :: StdlibFunction -> [Term Natural] -> Term Natural
callStdlib fun args =
  let fPath = stdlibPath fun
      getFunCode = OpCall # fPath # (OpAddress # stackPath StandardLibrary)
      adjustArgs = case nonEmpty args of
        Just args' -> OpReplace # ([R, L] # foldTerms args')
        Nothing -> OpAddress # emptyPath
      callFn = OpCall # [L] # adjustArgs
      callCell = set cellCall (Just meta) (OpPush #. (getFunCode # callFn))
      meta =
        StdlibCall
          { _stdlibCallArgs = case nonEmpty args of
              Just args' -> OpQuote # foldTerms args'
              Nothing -> nockNil',
            _stdlibCallFunction = fun
          }
   in TermCell callCell

constUnit :: Term Natural
constUnit = constVoid

constVoid :: Term Natural
constVoid = makeConstructor $ \case
  ConstructorTag -> OpQuote # toNock (0 :: Natural)
  ConstructorArgs -> remakeList []

pushConstructorFieldOnto ::
  (Members '[Compiler] r) =>
  StackId ->
  Tree.Tag ->
  Tree.DirectRef ->
  Natural ->
  Sem r ()
pushConstructorFieldOnto s tag refToConstr argIx = do
  info <- getConstructorInfo tag
  let memrep = info ^. constructorInfoMemRep
      arity = info ^. constructorInfoArity
      path = case memrep of
        NockmaMemRepConstr ->
          directRefPath refToConstr
            ++ constructorPath ConstructorArgs
            ++ indexStack argIx
        NockmaMemRepTuple ->
          directRefPath refToConstr
            ++ indexTuple arity argIx
        NockmaMemRepList constr -> case constr of
          NockmaMemRepListConstrNil -> impossible
          NockmaMemRepListConstrCons -> directRefPath refToConstr ++ indexTuple 2 argIx
  pushOnto s (OpAddress # path)

directRefPath :: Tree.DirectRef -> Path
directRefPath = \case
  Tree.ArgRef a -> pathToArg (fromOffsetRef a)
  Tree.TempRef Tree.RefTemp {..} -> tempRefPath (fromIntegral (fromJust _refTempTempHeight)) (fromOffsetRef _refTempOffsetRef)

tempRefPath :: Natural -> Natural -> Path
tempRefPath tempHeight off = indexInStack TempStack (tempHeight - off - 1)

allocClosure :: Tree.NodeAllocClosure -> Sem r ()
allocClosure = error "TODO"

closureArgsNum :: Sem r ()
closureArgsNum = error "TODO"

nockmaBuiltinTag :: Tree.BuiltinDataTag -> NockmaBuiltinTag
nockmaBuiltinTag = \case
  Tree.TagTrue -> NockmaBuiltinBool True
  Tree.TagFalse -> NockmaBuiltinBool False
  Tree.TagReturn -> impossible
  Tree.TagBind -> impossible
  Tree.TagWrite -> impossible
  Tree.TagReadLn -> impossible

-- | Generic constructors are encoded as [tag args], where args is a
-- nil terminated list.
goConstructor :: NockmaMemRep -> Tree.Tag -> [Term Natural] -> Term Natural
goConstructor mr t args = case t of
  Tree.BuiltinTag b -> case nockmaBuiltinTag b of
    NockmaBuiltinBool v -> nockBoolLiteral v
  Tree.UserTag tag -> case mr of
    NockmaMemRepConstr ->
      makeConstructor $ \case
        ConstructorTag -> OpQuote # (fromIntegral (tag ^. Tree.tagUserWord) :: Natural)
        ConstructorArgs -> remakeList args
    NockmaMemRepTuple -> foldTerms (nonEmpty' args)
    NockmaMemRepList constr -> case constr of
      NockmaMemRepListConstrNil
        | null args -> remakeList []
        | otherwise -> impossible
      NockmaMemRepListConstrCons -> case args of
        [l, r] -> TCell l r
        _ -> impossible

allocConstr :: Tree.NodeAllocConstr -> Sem r ()
allocConstr = error "TODO"

copyTopFromTo :: (Members '[Compiler] r) => StackId -> StackId -> Sem r ()
copyTopFromTo from toStack = pushOnto toStack (OpAddress # topOfStack from)

moveTopFromTo :: (Members '[Compiler] r) => StackId -> StackId -> Sem r ()
moveTopFromTo from toStack = do
  pushOnto toStack (OpAddress # topOfStack from)
  popFrom from

unsupported :: Text -> a
unsupported thing = error ("The Nockma backend does not support " <> thing)

stringsErr :: a
stringsErr = unsupported "strings"

-- | Computes a - b
sub :: Term Natural -> Term Natural -> Sem r () -> Sem r ()
sub _a _b _aux = error "TODO"

seqTerms :: [Term Natural] -> Term Natural
seqTerms = foldl' (flip (>>#)) (OpAddress # emptyPath) . reverse

makeEmptyList :: Term Natural
makeEmptyList = makeList []

makeList :: [Term Natural] -> Term Natural
makeList ts = foldTerms (ts `prependList` pure (TermAtom nockNil))

remakeList :: (Foldable l) => l (Term Natural) -> Term Natural
remakeList ts = foldTerms (toList ts `prependList` pure (OpQuote # nockNil'))

nockNil' :: Term Natural
nockNil' = TermAtom nockNil

initStack :: [Term Natural] -> Term Natural
initStack defs = makeList (initSubStack <$> allElements)
  where
    initSubStack :: StackId -> Term Natural
    initSubStack = \case
      Args -> nockNil'
      TempStack -> nockNil'
      StandardLibrary -> stdlib
      FunctionsLibrary -> makeList defs

dupOnto :: (Members '[Compiler] r) => StackId -> Sem r ()
dupOnto stackId = pushOnto stackId (OpAddress # topOfStack stackId)

execCompilerList :: (Member (Reader CompilerCtx) r) => Sem (Compiler ': r) a -> Sem r [Term Natural]
execCompilerList = fmap fst . runCompilerList

runCompilerList :: (Member (Reader CompilerCtx) r) => Sem (Compiler ': r) a -> Sem r ([Term Natural], a)
runCompilerList sem = do
  (ts, a) <- runOutputList (re sem)
  return (ts, a)

execCompiler :: (Member (Reader CompilerCtx) r) => Sem (Compiler ': r) a -> Sem r (Term Natural)
execCompiler = fmap fst . runCompiler

runCompiler :: (Member (Reader CompilerCtx) r) => Sem (Compiler ': r) a -> Sem r (Term Natural, a)
runCompiler sem = do
  (ts, a) <- runOutputList (re sem)
  return (seqTerms ts, a)

runCompilerWith :: CompilerOptions -> ConstructorInfos -> [CompilerFunction] -> CompilerFunction -> Cell Natural
runCompilerWith opts constrs libFuns mainFun =
  let entryCommand :: (Members '[Compiler] r) => Sem r (Term Natural)
      entryCommand = callFun (mainFun ^. compilerFunctionName) []
      entryTerm =
        seqTerms
          . run
          . runReader compilerCtx
          . execOutputList
          . re
          $ entryCommand
      compiledFuns :: NonEmpty (Term Natural)
      compiledFuns =
        makeFunction'
          <$> ( run
                  . runReader compilerCtx
                  . mapM (execCompiler . (^. compilerFunction))
                  $ allFuns
              )
      makeFunction' :: Term Natural -> Term Natural
      makeFunction' c = makeFunction $ \case
        FunctionCode -> c
        FunctionArgs -> nockNil'
   in Cell (initStack (toList compiledFuns)) entryTerm
  where
    allFuns :: NonEmpty CompilerFunction
    allFuns = mainFun :| libFuns ++ (builtinFunction <$> allElements)

    compilerCtx :: CompilerCtx
    compilerCtx =
      CompilerCtx
        { _compilerFunctionInfos = functionInfos,
          _compilerConstructorInfos = constrs,
          _compilerOptions = opts
        }

    functionInfos :: HashMap FunctionId FunctionInfo
    functionInfos = hashMap (run (runInputNaturals (toList <$> userFunctions)))

    userFunctions :: (Members '[Input Natural] r) => Sem r (NonEmpty (FunctionId, FunctionInfo))
    userFunctions = forM allFuns $ \CompilerFunction {..} -> do
      i <- input
      return
        ( _compilerFunctionName,
          FunctionInfo
            { _functionInfoPath = indexInStack FunctionsLibrary i,
              _functionInfoArity = _compilerFunctionArity
            }
        )

asmReturn :: Sem r ()
asmReturn = return ()

builtinFunction :: BuiltinFunctionId -> CompilerFunction
builtinFunction = \case
  BuiltinAppendRights ->
    CompilerFunction
      { _compilerFunctionName = BuiltinFunction BuiltinAppendRights,
        _compilerFunctionArity = 2, -- args: n pos
        _compilerFunction = error "TODO"
      }
  BuiltinPow2 ->
    CompilerFunction
      { _compilerFunctionName = BuiltinFunction BuiltinPow2,
        _compilerFunctionArity = 1,
        _compilerFunction = error "TODO"
      }
  BuiltinPow2Go ->
    CompilerFunction
      { _compilerFunctionName = BuiltinFunction BuiltinPow2Go,
        _compilerFunctionArity = 2, -- args: n acc
        _compilerFunction = error "TODO"
      }

-- callEnum :: (Enum funId, Members '[Compiler] r) => funId -> Natural -> Sem r ()
-- callEnum = callFun . UserFunction . Tree.defaultSymbol . fromIntegral . fromEnum

callFun ::
  (Members '[Compiler] r) =>
  FunctionId ->
  [Term Natural] ->
  Sem r (Term Natural)
callFun fun args = do
  fpath <- getFunctionPath fun
  return (OpCall # fpath # replaceArgs args)

replaceArgsWithTerm :: Term Natural -> Term Natural
replaceArgsWithTerm term =
  remakeList
    [ if
          | Args == s -> term
          | otherwise -> OpAddress # stackPath s
      | s <- allElements
    ]

replaceArgs :: [Term Natural] -> Term Natural
replaceArgs args =
  remakeList
    [ if
          | Args == s -> remakeList args
          | otherwise -> OpAddress # stackPath s
      | s <- allElements
    ]

tcallFun :: (Members '[Compiler] r) => FunctionId -> Natural -> Sem r ()
tcallFun = callHelper True . Just

getFunctionPath' :: (Members '[Reader CompilerCtx] r) => FunctionId -> Sem r Path
getFunctionPath' funName = asks (^?! compilerFunctionInfos . at funName . _Just . functionInfoPath)

-- | obj[relPath] := newVal
-- relPath is relative to obj
replaceSubterm :: Term Natural -> Path -> Term Natural -> Term Natural
replaceSubterm obj relPath newVal = OpReplace # (relPath # newVal) # obj

evaluated :: Term Natural -> Term Natural
evaluated t = OpApply # (OpAddress # emptyPath) # t

-- | The same as replaceSubterm but the path is a cell that is evaluated.
-- i.e. replaceSubterm a p b = replaceSubterm' a (quote p) b
replaceSubterm' :: Term Natural -> Term Natural -> Term Natural -> Term Natural
replaceSubterm' obj relPath newVal =
  evaluated $ (OpQuote # OpReplace) # ((relPath # (OpQuote # newVal)) # (OpQuote # obj))

sre :: (Members '[Output (Term Natural), Reader CompilerCtx] r) => Sem (Compiler ': r) x -> Sem r x
sre = subsume . re

-- | funName is Nothing when we call a closure at the top of the stack
callHelper' ::
  Bool ->
  Maybe FunctionId ->
  Natural ->
  Sem r ()
callHelper' _isTail _funName _funArgsNum = error "TODO"

asmReturn' :: Sem r ()
asmReturn' = error "TODO"

testEqOn' :: (Members '[Output (Term Natural)] r) => StackId -> Sem r ()
testEqOn' s = output (replaceOnStackN 2 s (OpEq # stackSliceAsCell s 0 1))

dumpStack :: (Members '[Compiler] r) => StackId -> Sem r ()
dumpStack t = traceTerm (OpAddress # stackPath t)

traceTerm' :: (Members '[Output (Term Natural)] r) => Term Natural -> Sem r ()
traceTerm' t =
  let iden = OpAddress # ([] :: Path)
   in output (OpTrace # t # iden)

incrementOn' :: (Members '[Output (Term Natural)] r) => StackId -> Sem r ()
incrementOn' s = output (replaceOnStack s (OpInc # stackSliceAsCell s 0 0))

callStdlibOn' :: (Members '[Output (Term Natural)] r) => StackId -> StdlibFunction -> Sem r ()
callStdlibOn' s f = do
  let fNumArgs = stdlibNumArgs f
      fPath = stdlibPath f
      decodeFn = OpCall # (fPath # (OpAddress # stackPath StandardLibrary))
      preargs = stdlibStackTake s fNumArgs
      arguments = OpSequence # (OpAddress # [R]) # preargs
      extractResult = (OpAddress # [L]) # (OpAddress # [R, R])
      callFn = OpPush # (OpCall # [L] # (OpReplace # ([R, L] # arguments) # (OpAddress # [L]))) # extractResult
      meta =
        StdlibCall
          { _stdlibCallArgs = preargs,
            _stdlibCallFunction = f
          }

      callCell = set cellCall (Just meta) (OpPush #. (decodeFn # callFn))

  output (toNock callCell)
  output (replaceTopStackN fNumArgs s)
  where
    stdlibStackTake :: StackId -> Natural -> Term Natural
    stdlibStackTake sn n =
      foldTerms
        ( nonEmpty'
            (take (fromIntegral n) [OpAddress # indexInStack sn i | i <- [0 ..]])
        )

save' ::
  Bool ->
  m () ->
  Sem (WithTactics Compiler f m r) (f ())
save' _isTail = error "TODO"

builtinTagToTerm :: NockmaBuiltinTag -> Term Natural
builtinTagToTerm = \case
  NockmaBuiltinBool v -> nockBoolLiteral v

constructorTagToTerm :: Tree.Tag -> Term Natural
constructorTagToTerm = \case
  Tree.UserTag t -> OpQuote # toNock (fromIntegral (t ^. Tree.tagUserWord) :: Natural)
  Tree.BuiltinTag b -> builtinTagToTerm (nockmaBuiltinTag b)

caseCmd ::
  forall r.
  (Members '[Compiler] r) =>
  Term Natural ->
  Maybe (Term Natural) ->
  [(Tree.Tag, Term Natural)] ->
  Sem r (Term Natural)
caseCmd arg defaultBranch = \case
  [] -> return (fromJust defaultBranch)
  (tag, b) : bs -> case tag of
    Tree.BuiltinTag t -> case nockmaBuiltinTag t of
      NockmaBuiltinBool v -> return (goBoolTag v b bs)
    Tree.UserTag {} -> do
      rep <- getConstructorMemRep tag
      case rep of
        NockmaMemRepConstr -> goRepConstr tag b bs
        NockmaMemRepTuple
          | null bs, isNothing defaultBranch -> return b
          | otherwise -> error "redundant branch. Impossible?"
        NockmaMemRepList constr -> do
          bs' <- mapM (firstM asNockmaMemRepListConstr) bs
          goRepList ((constr, b) :| bs')
  where
    goRepConstr ::
      Tree.Tag ->
      Term Natural ->
      [(Tree.Tag, Term Natural)] ->
      Sem r (Term Natural)
    goRepConstr tag b bs = do
      let cond :: Term Natural =
            OpEq
              # constructorTagToTerm tag
              # (getConstructorField ConstructorTag arg)
      elseBr <- caseCmd arg defaultBranch bs
      return (branch cond b elseBr)

    asNockmaMemRepListConstr :: Tree.Tag -> Sem r NockmaMemRepListConstr
    asNockmaMemRepListConstr tag = case tag of
      Tree.UserTag {} -> do
        rep <- getConstructorMemRep tag
        case rep of
          NockmaMemRepList constr -> return constr
          _ -> impossible
      Tree.BuiltinTag {} -> impossible

    goBoolTag ::
      Bool ->
      Term Natural ->
      [(Tree.Tag, Term Natural)] ->
      (Term Natural)
    goBoolTag v b bs =
      let otherBranch = fromJust (firstJust f bs <|> defaultBranch)
       in if
              | v -> branch arg b otherBranch
              | otherwise -> branch arg otherBranch b
      where
        f :: (Tree.Tag, Term Natural) -> Maybe (Term Natural)
        f (tag', br) = case tag' of
          Tree.UserTag {} -> impossible
          Tree.BuiltinTag tag -> case nockmaBuiltinTag tag of
            NockmaBuiltinBool v' -> guard (v /= v') $> br

    goRepList :: NonEmpty (NockmaMemRepListConstr, Term Natural) -> Sem r (Term Natural)
    goRepList ((_c, _b) :| _bs) = error "TODO"

branch ::
  Term Natural ->
  Term Natural ->
  Term Natural ->
  Term Natural
branch cond t f = OpIf # cond # t # f

getFunctionArity' :: (Members '[Reader CompilerCtx] r) => FunctionId -> Sem r Natural
getFunctionArity' s = asks (^?! compilerFunctionInfos . at s . _Just . functionInfoArity)

getConstructorInfo' :: (Members '[Reader CompilerCtx] r) => Tree.Tag -> Sem r ConstructorInfo
getConstructorInfo' tag = asks (^?! compilerConstructorInfos . at tag . _Just)

getClosureField :: ClosurePathId -> Term Natural -> Term Natural
getClosureField = getField

getConstructorField :: ConstructorPathId -> Term Natural -> Term Natural
getConstructorField = getField

getField :: (Enum field) => field -> Term Natural -> Term Natural
getField field t = (OpQuote # t) >># (OpAddress # pathFromEnum field)

getConstructorMemRep :: (Members '[Compiler] r) => Tree.Tag -> Sem r NockmaMemRep
getConstructorMemRep tag = (^. constructorInfoMemRep) <$> getConstructorInfo tag

getConstructorArity :: (Members '[Compiler] r) => Tree.Tag -> Sem r Natural
getConstructorArity tag = (^. constructorInfoArity) <$> getConstructorInfo tag

re :: (Member (Reader CompilerCtx) r) => Sem (Compiler ': r) a -> Sem (Output (Term Natural) ': r) a
re = reinterpretH $ \case
  PushOnto s n -> pushOntoH s n
  PopFromN n s -> popFromNH n s
  PopNAndPushOnto s n t -> popNAndPushOnto' s n t >>= pureT
  Verbatim s -> outputT s
  TraceTerm s -> whenM (asks (^. compilerOptions . compilerOptionsEnableTrace)) (traceTerm' s) >>= pureT
  CallHelper isTail funName funArgsNum -> callHelper' isTail funName funArgsNum >>= pureT
  IncrementOn s -> incrementOn' s >>= pureT
  Save isTail m -> save' isTail m
  CallStdlibOn s f -> callStdlibOn' s f >>= pureT
  TestEqOn s -> testEqOn' s >>= pureT
  GetConstructorInfo s -> getConstructorInfo' s >>= pureT
  GetFunctionArity s -> getFunctionArity' s >>= pureT
  GetFunctionPath s -> getFunctionPath' s >>= pureT

crash :: Term Natural
crash = (OpAddress # OpAddress # OpAddress)

outputT :: (Functor f, Member (Output (Term Natural)) r) => Term Natural -> Sem (WithTactics e f m r) (f ())
outputT = output >=> pureT

pushOntoH ::
  (Functor f, Member (Output (Term Natural)) r) =>
  StackId ->
  Term Natural ->
  Sem (WithTactics e f m r) (f ())
pushOntoH s n = outputT (pushOnStack s n)

popFromH ::
  (Functor f, Member (Output (Term Natural)) r) =>
  StackId ->
  Sem (WithTactics e f m r) (f ())
popFromH s = outputT (popStack s)

popFromNH ::
  (Functor f, Member (Output (Term Natural)) r) =>
  Natural ->
  StackId ->
  Sem (WithTactics e f m r) (f ())
popFromNH n s = outputT (popStackN n s)

mul :: Sem r ()
mul = error "TODO"

mulOn :: (Members '[Compiler] r) => StackId -> Sem r ()
mulOn s = callStdlibOn s StdlibMul

addOn :: (Members '[Compiler] r) => StackId -> Sem r ()
addOn s = callStdlibOn s StdlibAdd

pow2 :: (Members '[Compiler] r) => Term Natural -> Sem r (Term Natural)
pow2 = callFun (BuiltinFunction BuiltinPow2) . pure

add :: Term Natural -> Term Natural -> Term Natural
add a b = callStdlib StdlibAdd [a, b]

dec :: Term Natural -> Term Natural
dec = callStdlib StdlibDec . pure

increment :: Sem r ()
increment = error "TODO"

popFrom :: (Members '[Compiler] r) => StackId -> Sem r ()
popFrom = popFromN 1

popN :: Natural -> Sem r ()
popN = error "TODO"

pop :: Sem r ()
pop = error "TODO"

stackPop :: StackId -> Natural -> Term Natural
stackPop s n = OpAddress # pathInStack s (replicate n R)

stackTake :: StackId -> Natural -> Term Natural
stackTake sn n = remakeList (take (fromIntegral n) [OpAddress # indexInStack sn i | i <- [0 ..]])

stackSliceHelper :: StackId -> Natural -> Natural -> NonEmpty (Term Natural)
stackSliceHelper sn fromIx toIx = fromMaybe err (nonEmpty [OpAddress # indexInStack sn i | i <- indices])
  where
    err :: a
    err = error "impossible: empty slice"
    indices
      | fromIx <= toIx = [fromIx .. toIx]
      | otherwise = impossible

stackSliceAsCell :: StackId -> Natural -> Natural -> Term Natural
stackSliceAsCell sn a b = foldTerms (stackSliceHelper sn a b)

-- | Takes a slice of a stack. Both indices are inclusive
stackSliceAsList :: StackId -> Natural -> Natural -> Term Natural
stackSliceAsList sn fromIx toIx = remakeList (stackSliceHelper sn fromIx toIx)

pushOnStack :: StackId -> Term Natural -> Term Natural
pushOnStack sn t = OpPush # t # moveTopToStack
  where
    moveTopToStack :: Term Natural
    moveTopToStack =
      remakeList
        [ let p = OpAddress # (R : stackPath s)
           in if
                  | sn == s -> (OpAddress # indexStack 0) # p
                  | otherwise -> p
          | s <- allElements
        ]

popNAndPushOnto' :: (Member (Output (Term Natural)) r) => StackId -> Natural -> Term Natural -> Sem r ()
popNAndPushOnto' s num t = output (replaceOnStackN num s t)

replaceOnStackN :: Natural -> StackId -> Term Natural -> Term Natural
replaceOnStackN numToReplace s t = OpPush # t # replaceTopStackN numToReplace s

replaceOnStack :: StackId -> Term Natural -> Term Natural
replaceOnStack = replaceOnStackN 1

popStack :: StackId -> Term Natural
popStack = popStackN 1

popStackN :: Natural -> StackId -> Term Natural
popStackN n sn =
  remakeList
    [ let p = stackPath s
          a
            | sn == s = p ++ replicate n R
            | otherwise = p
       in OpAddress # a
      | s <- allElements
    ]

replaceStack :: StackId -> Term Natural -> Term Natural
replaceStack sn t =
  remakeList
    [ if
          | sn == s -> t
          | otherwise -> OpAddress # (stackPath s)
      | s <- allElements
    ]

resetStack :: StackId -> Term Natural
resetStack sn = replaceStack sn (OpQuote # nockNil')

replaceTopStackN :: Natural -> StackId -> Term Natural
replaceTopStackN n sn =
  remakeList
    [ let p = R : stackPath s
       in if
              | sn == s -> (OpAddress # indexStack 0) # (OpAddress # p ++ replicate n R)
              | otherwise -> OpAddress # p
      | s <- allElements
    ]

replaceTopStack :: StackId -> Term Natural
replaceTopStack = replaceTopStackN 1

pushNat :: Natural -> Sem r ()
pushNat = error "TODO"

pushNatOnto :: (Member Compiler r) => StackId -> Natural -> Sem r ()
pushNatOnto s n = pushOnto s (OpQuote # toNock n)
