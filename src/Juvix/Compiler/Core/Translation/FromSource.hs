module Juvix.Compiler.Core.Translation.FromSource
  ( module Juvix.Compiler.Core.Translation.FromSource,
    module Juvix.Parser.Error,
  )
where

import Control.Monad.Trans.Class (lift)
import Data.HashMap.Strict qualified as HashMap
import Data.HashSet qualified as HashSet
import Data.List qualified as List
import Data.List.NonEmpty (fromList)
import Juvix.Compiler.Core.Data.InfoTable
import Juvix.Compiler.Core.Data.InfoTableBuilder
import Juvix.Compiler.Core.Extra
import Juvix.Compiler.Core.Info qualified as Info
import Juvix.Compiler.Core.Info.BinderInfo as BinderInfo
import Juvix.Compiler.Core.Info.BranchInfo as BranchInfo
import Juvix.Compiler.Core.Info.LocationInfo as LocationInfo
import Juvix.Compiler.Core.Info.NameInfo as NameInfo
import Juvix.Compiler.Core.Info.TypeInfo as TypeInfo
import Juvix.Compiler.Core.Language
import Juvix.Compiler.Core.Transformation.Eta
import Juvix.Compiler.Core.Translation.FromSource.Lexer
import Juvix.Parser.Error
import Text.Megaparsec qualified as P

parseText :: InfoTable -> Text -> Either ParserError (InfoTable, Maybe Node)
parseText = runParser "" ""

-- Note: only new symbols and tags that are not in the InfoTable already will be
-- generated during parsing, but nameIds are generated starting from 0
-- regardless of the names already in the InfoTable
runParser :: FilePath -> FilePath -> InfoTable -> Text -> Either ParserError (InfoTable, Maybe Node)
runParser root fileName tab input =
  case run $
    runInfoTableBuilder tab $
      runReader params $
        runNameIdGen $
          P.runParserT parseToplevel fileName input of
    (_, Left err) -> Left (ParserError err)
    (tbl, Right r) -> Right (tbl, r)
  where
    params =
      ParserParams
        { _parserParamsRoot = root
        }

binderNameInfo :: Name -> Info
binderNameInfo name =
  Info.singleton (BinderInfo (Info.singleton (NameInfo name)))

freshName ::
  Members '[InfoTableBuilder, NameIdGen] r =>
  NameKind ->
  Text ->
  Interval ->
  Sem r Name
freshName kind txt i = do
  nid <- freshNameId
  return $
    Name
      { _nameText = txt,
        _nameId = nid,
        _nameKind = kind,
        _namePretty = txt,
        _nameLoc = i
      }

declareBuiltinConstr ::
  Members '[InfoTableBuilder, NameIdGen] r =>
  BuiltinDataTag ->
  Text ->
  Interval ->
  Sem r ()
declareBuiltinConstr btag nameTxt i = do
  name <- freshName KNameConstructor nameTxt i
  registerConstructor
    ( ConstructorInfo
        { _constructorName = name,
          _constructorTag = BuiltinTag btag,
          _constructorType = mkDynamic',
          _constructorArgsNum = builtinConstrArgsNum btag
        }
    )

guardSymbolNotDefined ::
  Member InfoTableBuilder r =>
  Symbol ->
  ParsecS r () ->
  ParsecS r ()
guardSymbolNotDefined sym err = do
  b <- lift $ checkSymbolDefined sym
  when b err

declareBuiltins :: Members '[Reader ParserParams, InfoTableBuilder, NameIdGen] r => ParsecS r ()
declareBuiltins = do
  loc <- curLoc
  let i = mkInterval loc loc
  lift $ declareBuiltinConstr TagTrue "true" i
  lift $ declareBuiltinConstr TagFalse "false" i
  lift $ declareBuiltinConstr TagReturn "return" i
  lift $ declareBuiltinConstr TagBind "bind" i
  lift $ declareBuiltinConstr TagWrite "write" i
  lift $ declareBuiltinConstr TagReadLn "readLn" i

checkUndeclaredIdentifiers :: Member InfoTableBuilder r => [Text] -> ParsecS r ()
checkUndeclaredIdentifiers declared = do
  let declaredSet = HashSet.fromList declared
  fwds <- lift getForwards
  let fwds' = filter (not . flip HashSet.member declaredSet . (^. forwardName)) fwds
  mapM_ (\fi -> parseFailure (fi ^. forwardOffset) ("undeclared identifier: " ++ fromText (fi ^. forwardName))) fwds'
  lift clearForwards

parseToplevel ::
  Members '[Reader ParserParams, InfoTableBuilder, NameIdGen] r =>
  ParsecS r (Maybe Node)
parseToplevel = do
  declareBuiltins
  space
  P.endBy statement kwSemicolon
  r <- optional expression
  P.eof
  return r

statement ::
  Members '[Reader ParserParams, InfoTableBuilder, NameIdGen] r =>
  ParsecS r ()
statement = statementDef <|> statementConstr

statementDef ::
  Members '[Reader ParserParams, InfoTableBuilder, NameIdGen] r =>
  ParsecS r ()
statementDef = do
  kwDef
  off <- P.getOffset
  (txt, i) <- identifierL
  r <- lift (getIdent txt)
  case r of
    Just (IdentSym sym) -> do
      guardSymbolNotDefined
        sym
        (parseFailure off ("duplicate definition of: " ++ fromText txt))
      parseDefinition sym
    Just (IdentTag {}) ->
      parseFailure off ("duplicate identifier: " ++ fromText txt)
    Just (IdentForward ForwardInfo {..}) ->
      parseFailure _forwardOffset ("undeclared identifier: " ++ fromText _forwardName)
    Nothing -> do
      sym <- lift freshSymbol
      name <- lift $ freshName KNameFunction txt i
      let info =
            IdentifierInfo
              { _identifierName = name,
                _identifierSymbol = sym,
                _identifierType = mkDynamic',
                _identifierArgsNum = 0,
                _identifierArgsInfo = [],
                _identifierIsExported = False
              }
      lift $ registerIdent info
      void $ optional (parseDefinition sym)

parseDefinition ::
  Members '[Reader ParserParams, InfoTableBuilder, NameIdGen] r =>
  Symbol ->
  ParsecS r ()
parseDefinition sym = do
  kwAssignment
  node <- expression
  lift $ registerIdentNode sym node
  let (is, _) = unfoldLambdas node
  lift $ setIdentArgsInfo sym (map toArgumentInfo is)
  where
    toArgumentInfo :: Info -> ArgumentInfo
    toArgumentInfo i =
      ArgumentInfo
        { _argumentName = getInfoName bi,
          _argumentType = getInfoType bi,
          _argumentIsImplicit = False
        }
      where
        bi = getInfoBinder i

statementConstr ::
  Members '[Reader ParserParams, InfoTableBuilder, NameIdGen] r =>
  ParsecS r ()
statementConstr = do
  kwConstr
  off <- P.getOffset
  (txt, i) <- identifierL
  (argsNum, _) <- number 0 128
  r <- lift (getIdent txt)
  case r of
    Just (IdentSym _) ->
      parseFailure off ("duplicate identifier: " ++ fromText txt)
    Just (IdentTag _) ->
      parseFailure off ("duplicate identifier: " ++ fromText txt)
    Just (IdentForward ForwardInfo {..}) ->
      parseFailure _forwardOffset ("undeclared identifier: " ++ fromText _forwardName)
    Nothing ->
      return ()
  tag <- lift freshTag
  name <- lift $ freshName KNameConstructor txt i
  let info =
        ConstructorInfo
          { _constructorName = name,
            _constructorTag = tag,
            _constructorType = mkDynamic',
            _constructorArgsNum = argsNum
          }
  lift $ registerConstructor info

expression ::
  Members '[Reader ParserParams, InfoTableBuilder, NameIdGen] r =>
  ParsecS r Node
expression = do
  node <- expr 0 mempty
  checkUndeclaredIdentifiers []
  tab <- lift getInfoTable
  return $ etaExpandApps tab node

expr ::
  Members '[Reader ParserParams, InfoTableBuilder, NameIdGen] r =>
  -- current de Bruijn index, i.e., the number of binders upwards
  Index ->
  -- reverse de Bruijn indices
  HashMap Text Index ->
  ParsecS r Node
expr varsNum vars = ioExpr varsNum vars

ioExpr ::
  Members '[Reader ParserParams, InfoTableBuilder, NameIdGen] r =>
  Index ->
  HashMap Text Index ->
  ParsecS r Node
ioExpr varsNum vars = cmpExpr varsNum vars >>= ioExpr' varsNum vars

ioExpr' ::
  Members '[Reader ParserParams, InfoTableBuilder, NameIdGen] r =>
  Index ->
  HashMap Text Index ->
  Node ->
  ParsecS r Node
ioExpr' varsNum vars node = do
  bindExpr' varsNum vars node
    <|> seqExpr' varsNum vars node
    <|> return node

bindExpr' ::
  Members '[Reader ParserParams, InfoTableBuilder, NameIdGen] r =>
  Index ->
  HashMap Text Index ->
  Node ->
  ParsecS r Node
bindExpr' varsNum vars node = do
  kwBind
  node' <- cmpExpr varsNum vars
  ioExpr' varsNum vars (mkConstr Info.empty (BuiltinTag TagBind) [node, node'])

seqExpr' ::
  Members '[Reader ParserParams, InfoTableBuilder, NameIdGen] r =>
  Index ->
  HashMap Text Index ->
  Node ->
  ParsecS r Node
seqExpr' varsNum vars node = do
  ((), i) <- interval kwSeq
  node' <- cmpExpr (varsNum + 1) vars
  name <- lift $ freshName KNameLocal "_" i
  ioExpr' varsNum vars $
    mkConstr
      Info.empty
      (BuiltinTag TagBind)
      [node, mkLambda (binderNameInfo name) node']

cmpExpr ::
  Members '[Reader ParserParams, InfoTableBuilder, NameIdGen] r =>
  Index ->
  HashMap Text Index ->
  ParsecS r Node
cmpExpr varsNum vars = arithExpr varsNum vars >>= cmpExpr' varsNum vars

cmpExpr' ::
  Members '[Reader ParserParams, InfoTableBuilder, NameIdGen] r =>
  Index ->
  HashMap Text Index ->
  Node ->
  ParsecS r Node
cmpExpr' varsNum vars node =
  eqExpr' varsNum vars node
    <|> ltExpr' varsNum vars node
    <|> leExpr' varsNum vars node
    <|> gtExpr' varsNum vars node
    <|> geExpr' varsNum vars node
    <|> return node

eqExpr' ::
  Members '[Reader ParserParams, InfoTableBuilder, NameIdGen] r =>
  Index ->
  HashMap Text Index ->
  Node ->
  ParsecS r Node
eqExpr' varsNum vars node = do
  kwEq
  node' <- arithExpr varsNum vars
  return $ mkBuiltinApp' OpEq [node, node']

ltExpr' ::
  Members '[Reader ParserParams, InfoTableBuilder, NameIdGen] r =>
  Index ->
  HashMap Text Index ->
  Node ->
  ParsecS r Node
ltExpr' varsNum vars node = do
  kwLt
  node' <- arithExpr varsNum vars
  return $ mkBuiltinApp' OpIntLt [node, node']

leExpr' ::
  Members '[Reader ParserParams, InfoTableBuilder, NameIdGen] r =>
  Index ->
  HashMap Text Index ->
  Node ->
  ParsecS r Node
leExpr' varsNum vars node = do
  kwLe
  node' <- arithExpr varsNum vars
  return $ mkBuiltinApp' OpIntLe [node, node']

gtExpr' ::
  Members '[Reader ParserParams, InfoTableBuilder, NameIdGen] r =>
  Index ->
  HashMap Text Index ->
  Node ->
  ParsecS r Node
gtExpr' varsNum vars node = do
  kwGt
  node' <- arithExpr varsNum vars
  return $ mkBuiltinApp' OpIntLt [node', node]

geExpr' ::
  Members '[Reader ParserParams, InfoTableBuilder, NameIdGen] r =>
  Index ->
  HashMap Text Index ->
  Node ->
  ParsecS r Node
geExpr' varsNum vars node = do
  kwGe
  node' <- arithExpr varsNum vars
  return $ mkBuiltinApp' OpIntLe [node', node]

arithExpr ::
  Members '[Reader ParserParams, InfoTableBuilder, NameIdGen] r =>
  Index ->
  HashMap Text Index ->
  ParsecS r Node
arithExpr varsNum vars = factorExpr varsNum vars >>= arithExpr' varsNum vars

arithExpr' ::
  Members '[Reader ParserParams, InfoTableBuilder, NameIdGen] r =>
  Index ->
  HashMap Text Index ->
  Node ->
  ParsecS r Node
arithExpr' varsNum vars node =
  plusExpr' varsNum vars node
    <|> minusExpr' varsNum vars node
    <|> return node

plusExpr' ::
  Members '[Reader ParserParams, InfoTableBuilder, NameIdGen] r =>
  Index ->
  HashMap Text Index ->
  Node ->
  ParsecS r Node
plusExpr' varsNum vars node = do
  kwPlus
  node' <- factorExpr varsNum vars
  arithExpr' varsNum vars (mkBuiltinApp' OpIntAdd [node, node'])

minusExpr' ::
  Members '[Reader ParserParams, InfoTableBuilder, NameIdGen] r =>
  Index ->
  HashMap Text Index ->
  Node ->
  ParsecS r Node
minusExpr' varsNum vars node = do
  kwMinus
  node' <- factorExpr varsNum vars
  arithExpr' varsNum vars (mkBuiltinApp' OpIntSub [node, node'])

factorExpr ::
  Members '[Reader ParserParams, InfoTableBuilder, NameIdGen] r =>
  Index ->
  HashMap Text Index ->
  ParsecS r Node
factorExpr varsNum vars = appExpr varsNum vars >>= factorExpr' varsNum vars

factorExpr' ::
  Members '[Reader ParserParams, InfoTableBuilder, NameIdGen] r =>
  Index ->
  HashMap Text Index ->
  Node ->
  ParsecS r Node
factorExpr' varsNum vars node =
  mulExpr' varsNum vars node
    <|> divExpr' varsNum vars node
    <|> modExpr' varsNum vars node
    <|> return node

mulExpr' ::
  Members '[Reader ParserParams, InfoTableBuilder, NameIdGen] r =>
  Index ->
  HashMap Text Index ->
  Node ->
  ParsecS r Node
mulExpr' varsNum vars node = do
  kwMul
  node' <- appExpr varsNum vars
  factorExpr' varsNum vars (mkBuiltinApp' OpIntMul [node, node'])

divExpr' ::
  Members '[Reader ParserParams, InfoTableBuilder, NameIdGen] r =>
  Index ->
  HashMap Text Index ->
  Node ->
  ParsecS r Node
divExpr' varsNum vars node = do
  kwDiv
  node' <- appExpr varsNum vars
  factorExpr' varsNum vars (mkBuiltinApp' OpIntDiv [node, node'])

modExpr' ::
  Members '[Reader ParserParams, InfoTableBuilder, NameIdGen] r =>
  Index ->
  HashMap Text Index ->
  Node ->
  ParsecS r Node
modExpr' varsNum vars node = do
  kwMod
  node' <- appExpr varsNum vars
  factorExpr' varsNum vars (mkBuiltinApp' OpIntMod [node, node'])

appExpr ::
  Members '[Reader ParserParams, InfoTableBuilder, NameIdGen] r =>
  Index ->
  HashMap Text Index ->
  ParsecS r Node
appExpr varsNum vars = builtinAppExpr varsNum vars <|> atoms varsNum vars

builtinAppExpr ::
  Members '[Reader ParserParams, InfoTableBuilder, NameIdGen] r =>
  Index ->
  HashMap Text Index ->
  ParsecS r Node
builtinAppExpr varsNum vars = do
  op <-
    (kwEq >> return OpEq)
      <|> (kwLt >> return OpIntLt)
      <|> (kwLe >> return OpIntLe)
      <|> (kwPlus >> return OpIntAdd)
      <|> (kwMinus >> return OpIntSub)
      <|> (kwDiv >> return OpIntDiv)
      <|> (kwMul >> return OpIntMul)
      <|> (kwTrace >> return OpTrace)
      <|> (kwFail >> return OpFail)
  args <- P.many (atom varsNum vars)
  return $ mkBuiltinApp' op args

atoms ::
  Members '[Reader ParserParams, InfoTableBuilder, NameIdGen] r =>
  Index ->
  HashMap Text Index ->
  ParsecS r Node
atoms varsNum vars = do
  es <- P.some (atom varsNum vars)
  return $ mkApps' (List.head es) (List.tail es)

atom ::
  Members '[Reader ParserParams, InfoTableBuilder, NameIdGen] r =>
  Index ->
  HashMap Text Index ->
  ParsecS r Node
atom varsNum vars =
  exprNamed varsNum vars
    <|> exprConstInt
    <|> exprConstString
    <|> exprLambda varsNum vars
    <|> exprLetRec varsNum vars
    <|> exprLet varsNum vars
    <|> exprCase varsNum vars
    <|> exprIf varsNum vars
    <|> parens (expr varsNum vars)
    <|> braces (expr varsNum vars)

exprNamed ::
  Members '[Reader ParserParams, InfoTableBuilder, NameIdGen] r =>
  Index ->
  HashMap Text Index ->
  ParsecS r Node
exprNamed varsNum vars = do
  off <- P.getOffset
  (txt, i) <- identifierL
  case HashMap.lookup txt vars of
    Just k -> do
      name <- lift $ freshName KNameLocal txt i
      return $ mkVar (Info.singleton (NameInfo name)) (varsNum - k - 1)
    Nothing -> do
      r <- lift (getIdent txt)
      case r of
        Just (IdentSym sym) -> do
          name <- lift $ freshName KNameFunction txt i
          return $ mkIdent (Info.singleton (NameInfo name)) sym
        Just (IdentTag tag) -> do
          name <- lift $ freshName KNameConstructor txt i
          return $ mkConstr (Info.singleton (NameInfo name)) tag []
        Just (IdentForward ForwardInfo {..}) ->
          return $ mkIdent' _forwardSymbol
        Nothing -> do
          sym <- lift freshSymbol
          lift $
            registerForward $
              ForwardInfo
                { _forwardName = txt,
                  _forwardOffset = off,
                  _forwardSymbol = sym
                }
          return $ mkIdent' sym

exprConstInt ::
  Members '[Reader ParserParams, InfoTableBuilder, NameIdGen] r =>
  ParsecS r Node
exprConstInt = P.try $ do
  (n, i) <- integer
  return $ mkConstant (Info.singleton (LocationInfo i)) (ConstInteger n)

exprConstString ::
  Members '[Reader ParserParams, InfoTableBuilder, NameIdGen] r =>
  ParsecS r Node
exprConstString = P.try $ do
  (s, i) <- string
  return $ mkConstant (Info.singleton (LocationInfo i)) (ConstString s)

parseLocalName ::
  forall r.
  Members '[Reader ParserParams, InfoTableBuilder, NameIdGen] r =>
  ParsecS r Name
parseLocalName = parseWildcardName <|> parseIdentName
  where
    parseWildcardName :: ParsecS r Name
    parseWildcardName = do
      ((), i) <- interval kwWildcard
      lift $ freshName KNameLocal "_" i

    parseIdentName :: ParsecS r Name
    parseIdentName = do
      (txt, i) <- identifierL
      lift $ freshName KNameLocal txt i

exprLambda ::
  Members '[Reader ParserParams, InfoTableBuilder, NameIdGen] r =>
  Index ->
  HashMap Text Index ->
  ParsecS r Node
exprLambda varsNum vars = do
  kwLambda
  name <- parseLocalName
  let vars' = HashMap.insert (name ^. nameText) varsNum vars
  body <- expr (varsNum + 1) vars'
  return $ mkLambda (binderNameInfo name) body

exprLet ::
  Members '[Reader ParserParams, InfoTableBuilder, NameIdGen] r =>
  Index ->
  HashMap Text Index ->
  ParsecS r Node
exprLet varsNum vars = do
  kwLet
  name <- parseLocalName
  kwAssignment
  value <- expr varsNum vars
  kwIn
  let vars' = HashMap.insert (name ^. nameText) varsNum vars
  body <- expr (varsNum + 1) vars'
  return $ mkLet (binderNameInfo name) value body

exprLetRec ::
  Members '[Reader ParserParams, InfoTableBuilder, NameIdGen] r =>
  Index ->
  HashMap Text Index ->
  ParsecS r Node
exprLetRec varsNum vars = do
  off <- P.getOffset
  kwLetRec
  defs <-
    braces (exprLetRecDefs varsNum vars)
      <|> exprLetRecDefs varsNum vars
  kwIn
  when (null defs) $
    parseFailure off "letrec block must contain at least one definition"
  let defNames = map ((^. nameText) . fst) defs
  let (vars', _) = foldl' (\(vs, k) txt -> (HashMap.insert txt k vs, k + 1)) (vars, varsNum) defNames
  body <- expr (varsNum + length defs) vars'
  checkUndeclaredIdentifiers defNames
  syms <-
    mapM
      ( \txt -> do
          r <- lift $ getIdent txt
          case r of
            Just (IdentSym sym) -> return sym
            Just (IdentForward ForwardInfo {..}) -> return _forwardSymbol
            _ -> lift freshSymbol
      )
      defNames
  let infos = map (Info.singleton . NameInfo . fst) defs
  let fwdMap = HashMap.fromList $ zip (reverse syms) (zip [0 ..] (reverse infos))
  let values = map (umapN (go fwdMap) . shift (length defs) . snd) defs
  return $ mkLetRec (Info.singleton (BindersInfo infos)) (fromList values) body
  where
    go :: HashMap Symbol (Index, Info) -> Int -> Node -> Node
    go fwdMap k = \case
      NIdt (Ident {..})
        | Just (idx, info) <- HashMap.lookup _identSymbol fwdMap ->
            mkVar info (idx + k)
      node -> node

exprLetRecDefs ::
  Members '[Reader ParserParams, InfoTableBuilder, NameIdGen] r =>
  Index ->
  HashMap Text Index ->
  ParsecS r [(Name, Node)]
exprLetRecDefs varsNum vars = P.sepEndBy (exprLetRecDef varsNum vars) kwSemicolon

exprLetRecDef ::
  Members '[Reader ParserParams, InfoTableBuilder, NameIdGen] r =>
  Index ->
  HashMap Text Index ->
  ParsecS r (Name, Node)
exprLetRecDef varsNum vars = do
  (txt, i) <- identifierL
  name <- lift $ freshName KNameLocal txt i
  kwAssignment
  v <- expr varsNum vars
  return (name, v)

exprCase ::
  Members '[Reader ParserParams, InfoTableBuilder, NameIdGen] r =>
  Index ->
  HashMap Text Index ->
  ParsecS r Node
exprCase varsNum vars = do
  off <- P.getOffset
  kwCase
  value <- expr varsNum vars
  kwOf
  braces (exprCase' off value varsNum vars)
    <|> exprCase' off value varsNum vars

exprCase' ::
  Members '[Reader ParserParams, InfoTableBuilder, NameIdGen] r =>
  Int ->
  Node ->
  Index ->
  HashMap Text Index ->
  ParsecS r Node
exprCase' off value varsNum vars = do
  bs <- P.sepEndBy (caseBranchP varsNum vars) kwSemicolon
  let bs' = map fromLeft' $ filter isLeft bs
  let bss = map fst bs'
  let bsns = map snd bs'
  let def' = map fromRight' $ filter isRight bs
  let bi = CaseBinderInfo $ map (map (Info.singleton . NameInfo)) bsns
  bri <-
    CaseBranchInfo
      <$> mapM
        ( \(CaseBranch tag _ _) -> do
            ci <- lift $ getConstructorInfo tag
            return $ BranchInfo (ci ^. constructorName)
        )
        bss
  let info = Info.insert bri (Info.singleton bi)
  case def' of
    [def] ->
      return $ mkCase info value bss (Just def)
    [] ->
      return $ mkCase info value bss Nothing
    _ ->
      parseFailure off "multiple default branches"

caseBranchP ::
  Members '[Reader ParserParams, InfoTableBuilder, NameIdGen] r =>
  Index ->
  HashMap Text Index ->
  ParsecS r (Either (CaseBranch, [Name]) Node)
caseBranchP varsNum vars =
  (defaultBranch varsNum vars <&> Right)
    <|> (matchingBranch varsNum vars <&> Left)

defaultBranch ::
  Members '[Reader ParserParams, InfoTableBuilder, NameIdGen] r =>
  Index ->
  HashMap Text Index ->
  ParsecS r Node
defaultBranch varsNum vars = do
  kwWildcard
  kwMapsTo
  expr varsNum vars

matchingBranch ::
  Members '[Reader ParserParams, InfoTableBuilder, NameIdGen] r =>
  Index ->
  HashMap Text Index ->
  ParsecS r (CaseBranch, [Name])
matchingBranch varsNum vars = do
  off <- P.getOffset
  txt <- identifier
  r <- lift (getIdent txt)
  case r of
    Just (IdentSym {}) ->
      parseFailure off ("not a constructor: " ++ fromText txt)
    Just (IdentForward {}) ->
      parseFailure off ("not a constructor: " ++ fromText txt)
    Just (IdentTag tag) -> do
      ns <- P.many parseLocalName
      let bindersNum = length ns
      ci <- lift $ getConstructorInfo tag
      when
        (ci ^. constructorArgsNum /= bindersNum)
        (parseFailure off "wrong number of constructor arguments")
      kwMapsTo
      let vars' =
            fst $
              foldl'
                ( \(vs, k) name ->
                    (HashMap.insert (name ^. nameText) k vs, k + 1)
                )
                (vars, varsNum)
                ns
      br <- expr (varsNum + bindersNum) vars'
      return (CaseBranch tag bindersNum br, ns)
    Nothing ->
      parseFailure off ("undeclared identifier: " ++ fromText txt)

exprIf ::
  Members '[Reader ParserParams, InfoTableBuilder, NameIdGen] r =>
  Index ->
  HashMap Text Index ->
  ParsecS r Node
exprIf varsNum vars = do
  kwIf
  value <- expr varsNum vars
  kwThen
  br1 <- expr varsNum vars
  kwElse
  br2 <- expr varsNum vars
  return $ mkIf Info.empty value br1 br2
