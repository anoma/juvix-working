module Juvix.Data.DependencyInfo where

import Data.Graph qualified as Graph
import Data.HashMap.Strict qualified as HashMap
import Data.HashSet qualified as HashSet
import GHC.Arr (Array, indices, (!))
import Juvix.Prelude.Base

-- DependencyInfo is polymorphic to anticipate future use with other identifier
-- types in JuvixCore and further. The graph algorithms don't depend on the
-- exact type of names (the polymorphic type n), so there is no reason to
-- specialise DependencyInfo to any particular name type
data DependencyInfo n = DependencyInfo
  { _depInfoGraph :: Graph,
    _depInfoNodeFromVertex :: Vertex -> (n, HashSet n),
    _depInfoEdgeList :: [(n, n, [n])],
    _depInfoVertexFromName :: n -> Maybe Vertex,
    _depInfoReachable :: HashSet n,
    _depInfoTopSort :: [n]
  }

makeLenses ''DependencyInfo

createDependencyInfo :: forall n. (Hashable n, Ord n) => HashMap n (HashSet n) -> HashSet n -> DependencyInfo n
createDependencyInfo edges startNames =
  DependencyInfo
    { _depInfoGraph = graph,
      _depInfoNodeFromVertex = \v -> let (_, x, y) = nodeFromVertex v in (x, HashSet.fromList y),
      _depInfoEdgeList = edgeList,
      _depInfoVertexFromName = vertexFromName,
      _depInfoReachable = reachableNames,
      _depInfoTopSort = topSortedNames
    }
  where
    graph :: Graph
    nodeFromVertex :: Vertex -> (n, n, [n])
    vertexFromName :: n -> Maybe Vertex
    (graph, nodeFromVertex, vertexFromName) = Graph.graphFromEdges edgeList
    edgeList :: [(n, n, [n])]
    edgeList = map (\(x, y) -> (x, x, HashSet.toList y)) (HashMap.toList edges)
    reachableNames :: HashSet n
    reachableNames =
      HashSet.fromList $
        map (\v -> case nodeFromVertex v of (_, x, _) -> x) $
          concatMap (Graph.reachable graph) startVertices
    startVertices :: [Vertex]
    startVertices = mapMaybe vertexFromName (HashSet.toList startNames)
    topSortedNames :: [n]
    topSortedNames = map (\v -> case nodeFromVertex v of (_, n, _) -> n) (Graph.topSort graph)

nameFromVertex :: DependencyInfo n -> Vertex -> n
nameFromVertex depInfo v = fst $ (depInfo ^. depInfoNodeFromVertex) v

isReachable :: (Hashable n) => DependencyInfo n -> n -> Bool
isReachable depInfo n = HashSet.member n (depInfo ^. depInfoReachable)

buildSCCs :: Ord n => DependencyInfo n -> [SCC n]
buildSCCs = Graph.stronglyConnComp . (^. depInfoEdgeList)

isCyclic :: DependencyInfo n -> Bool
isCyclic DependencyInfo {..} =
  run $ evalState (mempty :: HashSet Int) $ or <$> mapM (go _depInfoGraph mempty) (indices _depInfoGraph)
  where
    go :: Member (State (HashSet Int)) r => Array Int [Int] -> HashSet Int -> Int -> Sem r Bool
    go graph vars v
      | HashSet.member v vars = return True
      | otherwise = do
          s <- get
          if
              | HashSet.member v s ->
                  return False
              | otherwise -> do
                  put (HashSet.insert v s)
                  let vars' = HashSet.insert v vars
                  foldr
                    ((\v' acc -> go graph vars' v' >>= \b -> acc <&> (||) b))
                    (return False)
                    (graph ! v)
