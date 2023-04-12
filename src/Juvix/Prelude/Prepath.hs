module Juvix.Prelude.Prepath
  ( Prepath,
    prepath,
    mkPrepath,
    prepathToAbsDir,
    prepathToAbsFile,
  )
where

import Data.Yaml
import Juvix.Prelude.Base
import Juvix.Prelude.Path
import Juvix.Prelude.Pretty
import Juvix.Prelude.Shell
import System.Directory qualified as System

-- | A file/directory path that may contain environmental variables
newtype Prepath d = Prepath {_prepath :: String}
  deriving stock (Show, Eq, Generic)

makeLenses ''Prepath

mkPrepath :: String -> Prepath d
mkPrepath = Prepath

instance IsString (Prepath d) where
  fromString = mkPrepath

instance ToJSON (Prepath d) where
  toJSON (Prepath p) = toJSON p
  toEncoding (Prepath p) = toEncoding p

instance FromJSON (Prepath d) where
  parseJSON = fmap mkPrepath . parseJSON

instance Pretty (Prepath d) where
  pretty (Prepath p) = pretty p

prepathToAbsFile :: Path Abs Dir -> Prepath File -> IO (Path Abs File)
prepathToAbsFile root = fmap absFile . prepathToFilePath root

prepathToAbsDir :: Path Abs Dir -> Prepath Dir -> IO (Path Abs Dir)
prepathToAbsDir root = fmap absDir . prepathToFilePath root

prepathToFilePath :: Path Abs Dir -> Prepath d -> IO FilePath
prepathToFilePath root pre =
  withCurrentDir root $
    shellExpandCwd (pre ^. prepath) >>= System.canonicalizePath
