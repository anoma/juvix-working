module Juvix.Data.Effect.Files.Base
  ( module Juvix.Data.Effect.Files.Base,
    module Juvix.Data.Effect.Files.Error,
    module Juvix.Data.Uid,
  )
where

import Juvix.Data.Effect.Files.Error
import Juvix.Data.Uid
import Juvix.Prelude.Base
import Path

data RecursorArgs = RecursorArgs
  { _recCurDir :: Path Rel Dir,
    _recDirs :: [Path Rel Dir],
    _recFiles :: [Path Rel File]
  }

data Recurse r
  = RecurseNever
  | RecurseFilter (Path r Dir -> Bool)

makeLenses ''RecursorArgs

data Files m a where
  ReadFile' :: FilePath -> Files m Text
  ReadFileBS' :: FilePath -> Files m ByteString
  FileExists' :: FilePath -> Files m Bool
  EqualPaths' :: FilePath -> FilePath -> Files m (Maybe Bool)
  GetAbsPath :: FilePath -> Files m FilePath
  GetDirAbsPath :: Path r Dir -> Files m (Path Abs Dir)
  CanonicalizePath' :: FilePath -> Files m FilePath
  PathUid :: Path Abs b -> Files m Uid
  ListDirRel :: Path a Dir -> Files m ([Path Rel Dir], [Path Rel File])

makeSem ''Files
