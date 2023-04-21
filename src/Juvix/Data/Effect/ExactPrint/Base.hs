module Juvix.Data.Effect.ExactPrint.Base
  ( module Juvix.Data.Effect.ExactPrint.Base,
    module Juvix.Data.Loc,
    module Juvix.Data.Comment,
  )
where

import Juvix.Data.CodeAnn hiding (line')
import Juvix.Data.Comment
import Juvix.Data.Loc
import Juvix.Prelude.Base
import Prettyprinter qualified as P

data ExactPrint m a where
  NoLoc :: Doc Ann -> ExactPrint m ()
  Morpheme :: Interval -> Doc Ann -> ExactPrint m ()
  PrintCommentsUntil :: Interval -> ExactPrint m (Maybe SpaceSpan)
  EmptyLine :: ExactPrint m ()
  IgnoreTrailingEmpty :: ExactPrint m ()
  Region :: (Doc Ann -> Doc Ann) -> m b -> ExactPrint m b
  End :: ExactPrint m ()

makeSem ''ExactPrint

data Builder = Builder
  { -- | comments sorted by starting location
    _builderComments :: [SpaceSpan],
    _builderDoc :: Doc Ann,
    _builderPendingEmptyLine :: Bool,
    _builderIgnoreTrailingEmpty :: Bool,
    _builderEnd :: FileLoc
  }

makeLenses ''Builder

runExactPrint :: Maybe FileComments -> Sem (ExactPrint ': r) x -> Sem r (Doc Ann, x)
runExactPrint cs = fmap (first (^. builderDoc)) . runState ini . re
  where
    ini :: Builder
    ini =
      Builder
        { _builderComments = fromMaybe [] (cs ^? _Just . fileCommentsSorted),
          _builderDoc = mempty,
          _builderPendingEmptyLine = False,
          _builderIgnoreTrailingEmpty = False,
          _builderEnd = FileLoc 0 0 0
        }

execExactPrint :: Maybe FileComments -> Sem (ExactPrint ': r) x -> Sem r (Doc Ann)
execExactPrint cs = fmap fst . runExactPrint cs

re :: forall r a. Sem (ExactPrint ': r) a -> Sem (State Builder ': r) a
re = reinterpretH h
  where
    h ::
      forall rInitial x.
      ExactPrint (Sem rInitial) x ->
      Tactical ExactPrint (Sem rInitial) (State Builder ': r) x
    h = \case
      NoLoc p -> append' p >>= pureT
      EmptyLine -> modify' (set builderPendingEmptyLine True) >>= pureT
      IgnoreTrailingEmpty -> modify' (set builderIgnoreTrailingEmpty True) >>= pureT
      Morpheme l p -> morpheme' l p >>= pureT
      End -> end' >>= pureT
      PrintCommentsUntil l -> printCommentsUntil' l >>= pureT
      Region f m -> do
        st0 :: Builder <- set builderDoc mempty <$> get
        m' <- runT m
        (st' :: Builder, fx) <- raise (evalExactPrint' st0 m')

        modify (over builderDoc (<> f (st' ^. builderDoc)))
        modify (set builderComments (st' ^. builderComments))
        modify (set builderEnd (st' ^. builderEnd))

        return fx

evalExactPrint' :: Builder -> Sem (ExactPrint ': r) a -> Sem r (Builder, a)
evalExactPrint' b = runState b . re

append' :: forall r. Members '[State Builder] r => Doc Ann -> Sem r ()
append' d = modify (over builderDoc (<> d))

line' :: forall r. Members '[State Builder] r => Sem r ()
line' = append' P.line

-- | It prints all remaining comments
end' :: forall r. Members '[State Builder] r => Sem r ()
end' = do
  cs <- gets (^. builderComments)
  case cs of
    [] -> return ()
    [x] -> printSpaceSpan x
    _ -> impossible
  modify' (set builderComments [])

printSpaceSpan :: forall r. Members '[State Builder] r => SpaceSpan -> Sem r ()
printSpaceSpan = mapM_ printSpaceSection . (^. spaceSpan)
  where
    printSpaceSection :: SpaceSection -> Sem r ()
    printSpaceSection = \case
      SpaceComment c -> printComment c
      SpaceLines l ->
        -- append' (pretty $ getLoc l) >>
        line'

printComment :: Members '[State Builder] r => Comment -> Sem r ()
printComment c = do
  append' (annotate AnnComment (P.pretty c))
  line'

printCommentsUntil' :: forall r. Members '[State Builder] r => Interval -> Sem r (Maybe SpaceSpan)
printCommentsUntil' loc = do
  forceLine <- popPendingLine
  g <- popSpaceSpan
  let noSpaceLines = fromMaybe True $ do
        g' <- (^. spaceSpan) <$> g
        return (not (any (has _SpaceLines) g'))
  -- when (forceLine && noSpaceLines) line'
  whenJust g printSpaceSpan
  return g
  where
    cmp :: SpaceSpan -> Bool
    cmp c = getLoc c ^. intervalStart < loc ^. intervalStart

    popPendingLine :: Sem r Bool
    popPendingLine = do
      b <- gets (^. builderPendingEmptyLine)
      modify' (set builderPendingEmptyLine False)
      return b

    popSpaceSpan :: Sem r (Maybe SpaceSpan)
    popSpaceSpan = do
      cs <- gets (^. builderComments)
      case cs of
        h : hs
          | cmp h -> do
              modify' (set builderComments hs)
              return (Just h)
        _ -> return Nothing

morpheme' :: forall r. Members '[State Builder] r => Interval -> Doc Ann -> Sem r ()
morpheme' loc doc = do
  void (printCommentsUntil' loc)
  append' doc
