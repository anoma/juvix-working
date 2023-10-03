module Juvix.Compiler.Internal.Translation.FromConcrete.NamedArguments
  ( runNamedArguments,
    NameSignatures,
  )
where

import Data.HashMap.Strict qualified as HashMap
import Data.IntMap.Strict qualified as IntMap
import Juvix.Compiler.Concrete.Data.ScopedName qualified as S
import Juvix.Compiler.Concrete.Gen qualified as Gen
import Juvix.Compiler.Concrete.Keywords
import Juvix.Compiler.Concrete.Language
import Juvix.Compiler.Concrete.Pretty
import Juvix.Compiler.Concrete.Translation.FromParsed.Analysis.Scoping.Error
import Juvix.Prelude

type NameSignatures = HashMap NameId (NameSignature 'Scoped)

data BuilderState = BuilderState
  { _stateRemainingArgs :: [ArgumentBlock 'Scoped],
    _stateRemainingNames :: [NameBlock 'Scoped]
  }

makeLenses ''BuilderState

runNamedArguments ::
  forall r.
  (Members '[NameIdGen, Error ScoperError, Reader NameSignatures] r) =>
  NamedApplication 'Scoped ->
  Sem r Expression
runNamedArguments napp = do
  iniSt <- mkIniBuilderState
  args <-
    execOutputList
      . mapError ErrNamedArgumentsError
      . execState iniSt
      $ helper (getLoc napp)
  return (foldl' mkApp (ExpressionIdentifier (napp ^. namedAppName)) args)
  where
    -- sig :: NameSignature 'Scoped = napp ^. namedAppSignature . unIrrelevant
    mkApp :: Expression -> Expression -> Expression
    mkApp a = ExpressionApplication . Application a

    mkIniBuilderState :: Sem r BuilderState
    mkIniBuilderState = do
      sig <- asks @NameSignatures (^?! at (napp ^. namedAppName . scopedIdenName . S.nameId) . _Just)
      return
        BuilderState
          { _stateRemainingArgs = toList (napp ^. namedAppArgs),
            _stateRemainingNames = sig ^. nameSignatureArgs
          }

helper ::
  forall r.
  (Members '[State BuilderState, Output Expression, NameIdGen, Error NamedArgumentsError] r) =>
  Interval ->
  Sem r ()
helper loc = do
  whenJustM nextArgumentGroup $ \(impl, args, isLastBlock) -> do
    checkRepeated args
    names <- nextNameGroup impl
    (pendingArgs, (omittedNames, argmap)) <- scanGroup impl names args
    emitArgs impl isLastBlock omittedNames argmap
    whenJust (nonEmpty pendingArgs) $ \pendingArgs' -> do
      sig <- nextNameGroup Implicit
      emitImplicit False sig mempty
      moreNames <- not . null <$> gets (^. stateRemainingNames)
      if
          | moreNames -> modify' (over stateRemainingArgs (ArgumentBlock (Irrelevant Nothing) Explicit (nonEmpty' pendingArgs) :))
          | otherwise -> throw . ErrUnexpectedArguments $ UnexpectedArguments pendingArgs'
    helper loc
  where
    nextNameGroup :: IsImplicit -> Sem r (HashMap Symbol (NameItem 'Scoped))
    nextNameGroup impl = do
      remb <- gets (^. stateRemainingNames)
      case remb of
        [] -> return mempty
        b : bs -> do
          traceM (ppTrace b)
          let implNames = b ^. nameImplicit

          modify' (set stateRemainingNames bs)
          let r = b ^. nameBlock
              matches = return r
          case (impl, implNames) of
            (Explicit, Explicit) -> matches
            (Implicit, Implicit) -> matches
            (ImplicitInstance, ImplicitInstance) -> matches
            (Explicit, Implicit) -> do
              emitImplicit False r mempty
              nextNameGroup impl
            (Explicit, ImplicitInstance) -> do
              emitImplicitInstance False r mempty
              nextNameGroup impl
            (Implicit, ImplicitInstance) -> do
              emitImplicitInstance False r mempty
              nextNameGroup impl
            (ImplicitInstance, Implicit) -> do
              emitImplicit False r mempty
              nextNameGroup impl
            (Implicit, Explicit) -> return mempty
            (ImplicitInstance, Explicit) -> return mempty

    nextArgumentGroup :: Sem r (Maybe (IsImplicit, [NamedArgument 'Scoped], Bool))
    nextArgumentGroup = do
      remb <- gets (^. stateRemainingArgs)
      case remb of
        [] -> return Nothing
        b : bs -> do
          let impl = b ^. argBlockImplicit
              (c, rem') = span ((== impl) . (^. argBlockImplicit)) bs
              isLastBlock = null rem'
          modify' (set stateRemainingArgs rem')
          return (Just (impl, concatMap (toList . (^. argBlockArgs)) (b : c), isLastBlock))

    checkRepeated :: [NamedArgument 'Scoped] -> Sem r ()
    checkRepeated args = whenJust (nonEmpty (findRepeated (map (^. namedArgName) args))) $ \reps ->
      throw . ErrDuplicateArgument $ DuplicateArgument reps

    emitArgs :: IsImplicit -> Bool -> HashMap Symbol (NameItem 'Scoped) -> IntMap Expression -> Sem r ()
    emitArgs = \case
      Implicit -> emitImplicit
      Explicit -> emitExplicit
      ImplicitInstance -> emitImplicitInstance

    -- omitting arguments is only allowed at the end
    emitExplicit :: Bool -> HashMap Symbol (NameItem 'Scoped) -> IntMap Expression -> Sem r ()
    emitExplicit lastBlock omittedArgs args = do
      if
          | lastBlock ->
              unless
                (IntMap.keys args == [0 .. IntMap.size args - 1])
                (missingErr (nonEmpty' (map fst (filterMissing (HashMap.toList omittedArgs)))))
          | otherwise -> whenJust (nonEmpty (HashMap.keys omittedArgs)) missingErr
      forM_ args output
      where
        filterMissing :: [(Symbol, NameItem 'Scoped)] -> [(Symbol, NameItem 'Scoped)]
        filterMissing = case maximumGiven of
          Nothing -> id
          Just m -> filter ((< m) . (^. nameItemIndex) . snd)
        maximumGiven :: Maybe Int
        maximumGiven = fst <$> IntMap.lookupMax args
        missingErr :: NonEmpty Symbol -> Sem r ()
        missingErr = throw . ErrMissingArguments . MissingArguments loc

    emitImplicitHelper ::
      (WithLoc Expression -> Expression) ->
      (HoleType 'Scoped -> Expression) ->
      Bool ->
      HashMap Symbol (NameItem 'Scoped) ->
      IntMap Expression ->
      Sem r ()
    emitImplicitHelper exprBraces exprHole lastBlock omittedArgs args = go 0 (IntMap.toAscList args)
      where
        go :: Int -> [(Int, Expression)] -> Sem r ()
        go n = \case
          []
            | lastBlock -> return ()
            | otherwise -> whenJust maxIx (fillUntil . succ)
          (n', e) : rest -> do
            fillUntil n'
            output (exprBraces (WithLoc (getLoc e) e))
            go (n' + 1) rest
          where
            fillUntil n' = replicateM_ (n' - n) (mkWildcard >>= output)
            mkWildcard :: (Members '[NameIdGen] r') => Sem r' Expression
            mkWildcard = exprBraces . WithLoc loc . exprHole . mkHole loc <$> freshNameId
        -- fmap (exprBraces . WithLoc loc) $ case mdefault of
        -- Nothing -> exprHole . mkHole loc <$> freshNameId
        -- -- TODO shift binders in defaultVal
        -- Just defaultVal -> return defaultVal
        maxIx :: Maybe Int
        maxIx = fmap maximum1 . nonEmpty . map (^. nameItemIndex) . toList $ omittedArgs

    emitImplicit :: Bool -> HashMap Symbol (NameItem 'Scoped) -> IntMap Expression -> Sem r ()
    emitImplicit = emitImplicitHelper ExpressionBraces ExpressionHole

    emitImplicitInstance :: Bool -> HashMap Symbol (NameItem 'Scoped) -> IntMap Expression -> Sem r ()
    emitImplicitInstance = emitImplicitHelper mkDoubleBraces ExpressionInstanceHole
      where
        mkDoubleBraces :: WithLoc Expression -> Expression
        mkDoubleBraces (WithLoc eloc e) = run . runReader eloc $ do
          l <- Gen.kw delimDoubleBraceL
          r <- Gen.kw delimDoubleBraceR
          return $
            ExpressionDoubleBraces
              DoubleBracesExpression
                { _doubleBracesExpression = e,
                  _doubleBracesDelims = Irrelevant (l, r)
                }

    scanGroup ::
      IsImplicit ->
      HashMap Symbol (NameItem 'Scoped) ->
      [NamedArgument 'Scoped] ->
      Sem r ([NamedArgument 'Scoped], (HashMap Symbol (NameItem 'Scoped), IntMap Expression))
    scanGroup impl names = runOutputList . runState names . execState mempty . mapM_ go
      where
        go ::
          (Members '[State (IntMap Expression), State (HashMap Symbol (NameItem 'Scoped)), State BuilderState, Output (NamedArgument 'Scoped), Error NamedArgumentsError] r') =>
          NamedArgument 'Scoped ->
          Sem r' ()
        go arg = do
          let sym = arg ^. namedArgName
          midx :: Maybe (NameItem 'Scoped) <- gets @(HashMap Symbol (NameItem 'Scoped)) (^. at sym)
          case midx of
            Just idx -> do
              modify' (IntMap.insert (idx ^. nameItemIndex) (arg ^. namedArgValue))
              modify' @(HashMap Symbol (NameItem 'Scoped)) (HashMap.delete sym)
            Nothing -> case impl of
              Explicit -> do
                -- the arg may belong to the next explicit group
                output arg
              Implicit ->
                throw $
                  ErrUnexpectedArguments $
                    UnexpectedArguments
                      { _unexpectedArguments = pure arg
                      }
              ImplicitInstance ->
                throw $
                  ErrUnexpectedArguments $
                    UnexpectedArguments
                      { _unexpectedArguments = pure arg
                      }
