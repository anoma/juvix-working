module Juvix.Compiler.Core.Keywords
  ( module Juvix.Compiler.Core.Keywords,
    module Juvix.Data.Keyword,
    module Juvix.Data.Keyword.All,
  )
where

import Juvix.Data.Keyword
import Juvix.Data.Keyword.All
  ( delimSemicolon,
    kwAnomaDecode,
    kwAnomaEncode,
    kwAnomaSign,
    kwAnomaSignDetached,
    kwAnomaVerify,
    kwAnomaVerifyDetached,
    kwAny,
    kwAssign,
    kwBind,
    kwBottom,
    kwBuiltin,
    kwCase,
    kwColon,
    kwComma,
    kwDef,
    kwDiv,
    kwEcOp,
    kwElse,
    kwEq,
    kwFail,
    kwFieldAdd,
    kwFieldDiv,
    kwFieldMul,
    kwFieldSub,
    kwGe,
    kwGt,
    kwIf,
    kwIn,
    kwInductive,
    kwLe,
    kwLet,
    kwLetRec,
    kwLt,
    kwMatch,
    kwMinus,
    kwMod,
    kwMul,
    kwOf,
    kwPi,
    kwPlus,
    kwPoseidon,
    kwRandomEcPoint,
    kwRightArrow,
    kwSeq,
    kwSeqq,
    kwShow,
    kwStrConcat,
    kwStrToInt,
    kwThen,
    kwTrace,
    kwType,
    kwWildcard,
    kwWith,
  )
import Juvix.Prelude

allKeywordStrings :: HashSet Text
allKeywordStrings = keywordsStrings allKeywords

allKeywords :: [Keyword]
allKeywords =
  [ delimSemicolon,
    kwAssign,
    kwBottom,
    kwBuiltin,
    kwCase,
    kwColon,
    kwComma,
    kwDef,
    kwDiv,
    kwElse,
    kwEq,
    kwFieldAdd,
    kwFieldDiv,
    kwFieldMul,
    kwFieldSub,
    kwIf,
    kwIn,
    kwInductive,
    kwLet,
    kwLetRec,
    kwMatch,
    kwMinus,
    kwMod,
    kwMul,
    kwOf,
    kwPlus,
    kwRightArrow,
    kwThen,
    kwWildcard,
    kwWith,
    kwLt,
    kwLe,
    kwGt,
    kwGe,
    kwBind,
    kwSeq,
    kwSeqq,
    kwTrace,
    kwFail,
    kwAny,
    kwPi,
    kwType,
    kwPoseidon,
    kwEcOp,
    kwRandomEcPoint
  ]
