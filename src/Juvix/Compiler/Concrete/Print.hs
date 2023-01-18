module Juvix.Compiler.Concrete.Print where

import Juvix.Compiler.Concrete.Print.Base
import Juvix.Data.Effect.ExactPrint
import Juvix.Compiler.Concrete.Pretty.Options
import Juvix.Data.PPOutput
import Juvix.Prelude

ppOutDefault :: (HasLoc c, PrettyPrint c) => Comments -> c -> AnsiText
ppOutDefault cs = AnsiText . PPOutput . doc defaultOptions cs

ppOut :: (CanonicalProjection a Options, PrettyPrint c, HasLoc c) => a -> Comments -> c -> AnsiText
ppOut o cs = AnsiText . PPOutput . doc (project o) cs
