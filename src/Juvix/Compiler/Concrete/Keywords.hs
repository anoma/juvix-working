module Juvix.Compiler.Concrete.Keywords
  ( module Juvix.Compiler.Concrete.Keywords,
    module Juvix.Data.Keyword,
    module Juvix.Data.Keyword.All,
  )
where

import Juvix.Data.Keyword
import Juvix.Data.Keyword.All
  ( -- delimiters
    delimBraceL,
    delimBraceR,
    delimBracketL,
    delimBracketR,
    delimDoubleBraceL,
    delimDoubleBraceR,
    delimJudocBlockEnd,
    delimJudocBlockStart,
    delimJudocExample,
    delimJudocStart,
    delimParenL,
    delimParenR,
    delimSemicolon,
    -- keywords
    kwAbove,
    kwAlias,
    kwAs,
    kwAssign,
    kwAssoc,
    kwAt,
    kwAxiom,
    kwBelow,
    kwBinary,
    kwBuiltin,
    kwCase,
    kwCoercion,
    kwColon,
    kwDeriving,
    kwDo,
    kwElse,
    kwEnd,
    kwEq,
    kwFixity,
    kwHiding,
    kwHole,
    kwIf,
    kwImport,
    kwIn,
    kwInductive,
    kwInit,
    kwInstance,
    kwIterator,
    kwLambda,
    kwLeft,
    kwLeftArrow,
    kwLet,
    kwMapsTo,
    kwModule,
    kwNone,
    kwOf,
    kwOpen,
    kwOperator,
    kwPipe,
    kwPositive,
    kwPublic,
    kwRange,
    kwRight,
    kwRightArrow,
    kwSame,
    kwSyntax,
    kwTerminating,
    kwTrait,
    kwType,
    kwUnary,
    kwUsing,
    kwWhere,
    kwWildcard,
    kwWith,
  )
import Juvix.Prelude

allKeywordStrings :: HashSet Text
allKeywordStrings = keywordsStrings reservedKeywords

reservedKeywords :: [Keyword]
reservedKeywords =
  [ delimSemicolon,
    kwAssign,
    kwDeriving,
    kwAt,
    kwAxiom,
    kwCase,
    kwColon,
    kwDo,
    kwElse,
    kwEnd,
    kwHiding,
    kwHole,
    kwIf,
    kwImport,
    kwIn,
    kwInductive,
    kwLambda,
    kwLeftArrow,
    kwLet,
    kwModule,
    kwOf,
    kwOpen,
    kwPipe,
    kwPublic,
    kwRightArrow,
    kwSyntax,
    kwType,
    kwUsing,
    kwWhere,
    kwWildcard
  ]
