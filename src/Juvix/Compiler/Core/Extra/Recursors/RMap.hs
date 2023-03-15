module Juvix.Compiler.Core.Extra.Recursors.RMap where

import Data.Functor.Identity
import Juvix.Compiler.Core.Data.BinderList qualified as BL
import Juvix.Compiler.Core.Extra.Base
import Juvix.Compiler.Core.Extra.Recursors.Base
import Juvix.Compiler.Core.Extra.Recursors.Utils

data BinderRemove = BinderRemove
  { _binderRemoveBinder :: Binder,
    _binderRemoveNode :: Node
  }

makeLenses ''BinderRemove

data BinderChange
  = -- | `BCAdd n` -- add `n` binders
    BCAdd Int
  | -- | `BCKeep b` -- keep the binder `b`
    BCKeep Binder
  | -- | `BCRemove (BinderRemove b n)` -- remove the binder `b` and replace the
    -- occurrences of the bound variable with the node `n`; the de Bruijn
    -- indices of `n` are with respect to the result
    BCRemove BinderRemove

bindersFromBinderChange :: [BinderChange] -> [Binder]
bindersFromBinderChange =
  reverse
    . foldl'
      ( \bs chg -> case chg of
          BCAdd _ -> bs
          BCKeep b -> b : bs
          BCRemove (BinderRemove b _) -> b : bs
      )
      []

bindersNumFromBinderChange :: [BinderChange] -> Int
bindersNumFromBinderChange =
  foldl'
    ( \n chg -> case chg of
        BCAdd {} -> n
        BCKeep {} -> n + 1
        BCRemove {} -> n + 1
    )
    0

rmapG ::
  forall c m.
  (Monad m) =>
  Collector (Int, [Binder]) c ->
  ((c -> [BinderChange] -> Node -> m Node) -> c -> Node -> m Node) ->
  Node ->
  m Node
rmapG coll f = go mempty 0 (coll ^. cEmpty)
  where
    -- `binders` maps input de Bruijn indices to result de Bruijn levels
    -- (adjusted by the binder shift at their occurrence) plus the replacement
    -- node; `bl` is the current binder level in the result node
    go :: BinderList (Level, Maybe Node) -> Int -> c -> Node -> m Node
    go binders bl c n = f recur c n
      where
        recur :: c -> [BinderChange] -> Node -> m Node
        recur c' changes n' =
          let ni = destruct n'
           in adjustVar . reassembleDetails ni <$> mapM goChild (ni ^. nodeChildren)
          where
            goChild :: NodeChild -> m Node
            goChild ch =
              let (bl', rbs, rbs') =
                    foldl'
                      ( \(l, bs, acc) chg -> case chg of
                          BCAdd k -> (l + k, bs, acc)
                          BCKeep b -> (l + 1, b : bs, (l, Nothing) : acc)
                          BCRemove (BinderRemove b node) -> (l, b : bs, (l, Just node) : acc)
                      )
                      (bl, [], [])
                      changes
                  cbs = map (\l -> (l, Nothing)) [bl' .. bl' + ch ^. childBindersNum - 1]
                  binders' = BL.prependRev cbs (BL.prepend rbs' binders)
               in go
                    binders'
                    (bl' + ch ^. childBindersNum)
                    ((coll ^. cCollect) (length rbs + ch ^. childBindersNum, reverse rbs ++ ch ^. childBinders) c')
                    (ch ^. childNode)

        adjustVar :: Node -> Node
        adjustVar = \case
          NVar v ->
            maybe
              (NVar v {_varIndex = getBinderIndex bl lvl})
              (shift (bl - lvl))
              mnode
            where
              (lvl, mnode) = BL.lookup (v ^. varIndex) binders
          node -> node

rmapEmbedIden :: ((([BinderChange] -> Node -> Node) -> Node -> Node)) -> (([BinderChange] -> Node -> Identity Node) -> Node -> Identity Node)
rmapEmbedIden f recur = return . f (\bcs -> runIdentity . recur bcs)

rmapEmbedIden' :: ((([BinderChange] -> Node -> Node) -> c -> Node -> Node)) -> (([BinderChange] -> Node -> Identity Node) -> c -> Node -> Identity Node)
rmapEmbedIden' f recur bl = return . f (\bcs -> runIdentity . recur bcs) bl

rmapEmbedIden'' :: (((c -> [BinderChange] -> Node -> Node) -> c -> Node -> Node)) -> ((c -> [BinderChange] -> Node -> Identity Node) -> c -> Node -> Identity Node)
rmapEmbedIden'' f recur bl = return . f (\c bcs -> runIdentity . recur c bcs) bl

rmapCEmbedIden :: (((c -> [BinderChange] -> Node -> Node) -> c -> Node -> Node)) -> ((c -> [BinderChange] -> Node -> Identity Node) -> c -> Node -> Identity Node)
rmapCEmbedIden = rmapEmbedIden''

rmapCEmbedIden' :: (((c -> [BinderChange] -> Node -> Node) -> c -> b -> Node -> Node)) -> ((c -> [BinderChange] -> Node -> Identity Node) -> c -> b -> Node -> Identity Node)
rmapCEmbedIden' f recur c b = return . f (\c' bcs -> runIdentity . recur c' bcs) c b

rmapCEmbedIden'' :: (((c -> b -> [BinderChange] -> Node -> Node) -> c -> b -> Node -> Node)) -> ((c -> b -> [BinderChange] -> Node -> Identity Node) -> c -> b -> Node -> Identity Node)
rmapCEmbedIden'' f recur c b = return . f (\c' b' bcs -> runIdentity . recur c' b' bcs) c b
