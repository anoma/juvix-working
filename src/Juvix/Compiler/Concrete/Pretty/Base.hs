module Juvix.Compiler.Concrete.Pretty.Base
  ( module Juvix.Compiler.Concrete.Pretty.Base,
    module Juvix.Data.CodeAnn,
    module Juvix.Compiler.Concrete.Pretty.Options,
  )
where

import Data.List.NonEmpty.Extra qualified as NonEmpty
import Juvix.Compiler.Concrete.Data.InfoTable
import Juvix.Compiler.Concrete.Data.ScopedName
  ( AbsModulePath,
    IsConcrete (..),
  )
import Juvix.Compiler.Concrete.Data.ScopedName qualified as S
import Juvix.Compiler.Concrete.Keywords (delimJudocStart)
import Juvix.Compiler.Concrete.Language
import Juvix.Compiler.Concrete.Pretty.Options
import Juvix.Data.Ape
import Juvix.Data.CodeAnn
import Juvix.Extra.Strings qualified as Str
import Juvix.Prelude

doc :: (PrettyCode c) => Options -> c -> Doc Ann
doc opts =
  run
    . runReader opts
    . ppCode

class PrettyCode a where
  ppCode :: (Members '[Reader Options] r) => a -> Sem r (Doc Ann)

runPrettyCode :: (PrettyCode c) => Options -> c -> Doc Ann
runPrettyCode opts = run . runReader opts . ppCode

ppModulePathType ::
  forall t s r.
  (SingI t, SingI s, Members '[Reader Options] r) =>
  ModulePathType s t ->
  Sem r (Doc Ann)
ppModulePathType x = case sing :: SStage s of
  SParsed -> case sing :: SModuleIsTop t of
    SModuleLocal -> ppCode x
    SModuleTop -> ppCode x
  SScoped -> case sing :: SModuleIsTop t of
    SModuleLocal -> annSDef x <$> ppCode x
    SModuleTop -> annSDef x <$> ppCode x

ppUnkindedSymbol :: (Members '[Reader Options] r) => Symbol -> Sem r (Doc Ann)
ppUnkindedSymbol = fmap (annotate AnnUnkindedSym) . ppSymbol

ppSymbol :: forall s r. (SingI s, Members '[Reader Options] r) => SymbolType s -> Sem r (Doc Ann)
ppSymbol = case sing :: SStage s of
  SParsed -> ppCode
  SScoped -> ppCode

groupStatements :: forall s. SingI s => [Statement s] -> [NonEmpty (Statement s)]
groupStatements = \case
  [] -> []
  s : ss -> reverse . map NonEmpty.reverse . uncurry cons . foldl' aux (pure s, []) $ ss
  where
    aux ::
      (NonEmpty (Statement s), [NonEmpty (Statement s)]) ->
      Statement s ->
      (NonEmpty (Statement s), [NonEmpty (Statement s)])
    aux (gr@(a :| _), acc) b
      | g a b = (NonEmpty.cons b gr, acc)
      | otherwise = (pure b, gr : acc)
    -- Decides if statements a and b should be next to each other without a
    -- blank line
    g :: Statement s -> Statement s -> Bool
    g a b = case (a, b) of
      (StatementSyntax _, StatementSyntax _) -> True
      (StatementSyntax (SyntaxOperator o), s) -> definesSymbol (o ^. opSymbol) s
      (StatementImport _, StatementImport _) -> True
      (StatementImport i, StatementOpenModule o) -> case sing :: SStage s of
        SParsed -> True
        SScoped ->
          i
            ^. importModule
              . moduleRefModule
              . modulePath
              . S.nameId
            == getModuleRefNameId (o ^. openModuleName)
      (StatementImport _, _) -> False
      (StatementOpenModule {}, StatementOpenModule {}) -> True
      (StatementOpenModule {}, _) -> False
      (StatementInductive {}, _) -> False
      (StatementModule {}, _) -> False
      (StatementAxiom {}, StatementAxiom {}) -> False
      (StatementAxiom {}, _) -> False
      (StatementTypeSignature sig, StatementFunctionClause fun) ->
        case sing :: SStage s of
          SParsed -> sig ^. sigName == fun ^. clauseOwnerFunction
          SScoped -> sig ^. sigName == fun ^. clauseOwnerFunction
      (StatementTypeSignature {}, _) -> False
      (StatementFunctionClause fun1, StatementFunctionClause fun2) ->
        case sing :: SStage s of
          SParsed -> fun1 ^. clauseOwnerFunction == fun2 ^. clauseOwnerFunction
          SScoped -> fun1 ^. clauseOwnerFunction == fun2 ^. clauseOwnerFunction
      (StatementFunctionClause {}, _) -> False
    definesSymbol :: Symbol -> Statement s -> Bool
    definesSymbol n s = case s of
      StatementTypeSignature sig -> n == symbolParsed (sig ^. sigName)
      StatementInductive d -> n `elem` syms d
      StatementAxiom d -> n == symbolParsed (d ^. axiomName)
      _ -> False
      where
        symbolParsed :: SymbolType s -> Symbol
        symbolParsed sym = case sing :: SStage s of
          SParsed -> sym
          SScoped -> sym ^. S.nameConcrete

        syms :: InductiveDef s -> [Symbol]
        syms InductiveDef {..} =
          let constructors = toList _inductiveConstructors
           in case sing :: SStage s of
                SParsed -> _inductiveName : map (^. constructorName) constructors
                SScoped ->
                  _inductiveName
                    ^. S.nameConcrete
                    : map (^. constructorName . S.nameConcrete) constructors

instance PrettyCode FunctionInfo where
  ppCode f = do
    let ty = StatementTypeSignature (f ^. functionInfoType)
        cs = map StatementFunctionClause (f ^. functionInfoClauses)
    ppCode (ty : cs)

instance (SingI s) => PrettyCode [Statement s] where
  ppCode ss = vsep2 <$> mapM (fmap vsep . mapM (fmap endSemicolon . ppCode)) (groupStatements ss)

instance (SingI s) => PrettyCode (Statement s) where
  ppCode = \case
    StatementSyntax s -> ppCode s
    StatementTypeSignature sig -> ppCode sig
    StatementImport i -> ppCode i
    StatementInductive d -> ppCode d
    StatementModule m -> ppCode m
    StatementOpenModule o -> ppCode o
    StatementFunctionClause c -> ppCode c
    StatementAxiom a -> ppCode a

ppTopModulePath ::
  forall s r.
  (SingI s, Members '[Reader Options] r) =>
  ModulePathType s 'ModuleTop ->
  Sem r (Doc Ann)
ppTopModulePath = case sing :: SStage s of
  SParsed -> ppCode
  SScoped -> ppCode

instance (SingI s) => PrettyCode (InductiveParameters s) where
  ppCode InductiveParameters {..} = do
    inductiveParameterNames' <-
      forM
        _inductiveParametersNames
        (\nm -> annDef nm <$> ppSymbol nm)
    inductiveParametersType' <- case sing :: SStage s of
      SParsed -> ppCode _inductiveParametersType
      SScoped -> ppCode _inductiveParametersType
    return $ parens (hsep inductiveParameterNames' <+> kwColon <+> inductiveParametersType')

instance (SingI s) => PrettyCode [InductiveParameters s] where
  ppCode = fmap hsep . mapM ppCode

instance PrettyCode AbsModulePath where
  ppCode S.AbsModulePath {..} = do
    absLocalPath' <- mapM ppCode _absLocalPath
    absTopModulePath' <- ppCode _absTopModulePath
    return $ dotted (absTopModulePath' : absLocalPath')

ppInductiveParameters ::
  (SingI s, Members '[Reader Options] r) =>
  [InductiveParameters s] ->
  Sem r (Maybe (Doc Ann))
ppInductiveParameters ps
  | null ps = return Nothing
  | otherwise = Just <$> ppCode ps

instance (SingI s, SingI t) => PrettyCode (Module s t) where
  ppCode :: (Members '[Reader Options] r) => Module s t -> Sem r (Doc Ann)
  ppCode Module {..} = do
    moduleBody' <- localIndent <$> ppCode _moduleBody
    modulePath' <- ppModulePathType _modulePath
    moduleDoc' <- mapM ppCode _moduleDoc
    modulePragmas' <- mapM ppCode _modulePragmas
    return $
      moduleDoc'
        ?<> modulePragmas'
        ?<> kwModule
        <+> modulePath'
          <> kwSemicolon
          <> line
          <> topSpace
          <> moduleBody'
          <>? ending
    where
      topSpace :: Doc Ann
      topSpace = case sing :: SModuleIsTop t of
        SModuleLocal -> mempty
        SModuleTop -> line

      localIndent :: Doc Ann -> Doc Ann
      localIndent = case sing :: SModuleIsTop t of
        SModuleLocal -> indent'
        SModuleTop -> id

      ending :: Maybe (Doc Ann)
      ending = case sing :: SModuleIsTop t of
        SModuleLocal -> Just (line <> kwEnd)
        SModuleTop -> Nothing

instance PrettyCode Precedence where
  ppCode p = return $ case p of
    PrecMinusOmega -> pretty ("-ω" :: Text)
    PrecNat n -> pretty n
    PrecOmega -> pretty ("ω" :: Text)

instance PrettyCode Fixity where
  ppCode Fixity {..} = do
    fixityPrecedence' <- ppCode _fixityPrecedence
    fixityArity' <- ppCode _fixityArity
    return $ fixityArity' <+> fixityPrecedence'

instance PrettyCode OperatorArity where
  ppCode a = return $ case a of
    Unary {} -> kwPostfix
    Binary p -> case p of
      AssocRight -> kwInfixr
      AssocLeft -> kwInfixl
      AssocNone -> kwInfix

instance PrettyCode SyntaxDef where
  ppCode = \case
    SyntaxOperator op -> ppCode op

instance PrettyCode OperatorSyntaxDef where
  ppCode OperatorSyntaxDef {..} = do
    opSymbol' <- ppUnkindedSymbol _opSymbol
    opFixity' <- ppCode _opFixity
    return $ kwSyntax <+> opFixity' <+> opSymbol'

instance (SingI s) => PrettyCode (InductiveConstructorDef s) where
  ppCode InductiveConstructorDef {..} = do
    constructorName' <- annDef _constructorName <$> ppSymbol _constructorName
    constructorType' <- ppExpression _constructorType
    doc' <- mapM ppCode _constructorDoc
    pragmas' <- mapM ppCode _constructorPragmas
    return $ doc' ?<> pragmas' ?<> hang' (constructorName' <+> kwColon <+> constructorType')

instance PrettyCode BuiltinInductive where
  ppCode i = return (kwBuiltin <+> keyword (prettyText i))

instance PrettyCode BuiltinFunction where
  ppCode i = return (kwBuiltin <+> keyword (prettyText i))

instance PrettyCode BuiltinAxiom where
  ppCode i = return (kwBuiltin <+> keyword (prettyText i))

ppInductiveSignature :: forall r s. (SingI s, Members '[Reader Options] r) => InductiveDef s -> Sem r (Doc Ann)
ppInductiveSignature InductiveDef {..} = do
  inductivebuiltin' <- traverse ppCode _inductiveBuiltin
  inductiveName' <- annDef _inductiveName <$> ppSymbol _inductiveName
  inductiveParameters' <- ppInductiveParameters _inductiveParameters
  inductiveType' <- ppTypeType
  return $
    inductivebuiltin'
      <?+> kwInductive
      <+> inductiveName'
      <+?> inductiveParameters'
      <+?> inductiveType'
  where
    ppTypeType :: Sem r (Maybe (Doc Ann))
    ppTypeType = case _inductiveType of
      Nothing -> return Nothing
      Just e -> Just . (kwColon <+>) <$> ppExpression e

instance PrettyCode (Doc Ann) where
  ppCode d = return d

instance (SingI s) => PrettyCode (InductiveDef s) where
  ppCode :: forall r. (Members '[Reader Options] r) => InductiveDef s -> Sem r (Doc Ann)
  ppCode d@InductiveDef {..} = do
    doc' <- mapM ppCode _inductiveDoc
    pragmas' <- mapM ppCode _inductivePragmas
    sig' <- ppInductiveSignature d
    inductiveConstructors' <- ppPipeBlock _inductiveConstructors
    return $
      doc' ?<> pragmas' ?<> sig'
        <+> kwAssign
          <> line
          <> (indent' . align) inductiveConstructors'

dotted :: (Foldable f) => f (Doc Ann) -> Doc Ann
dotted = concatWith (surround kwDot)

instance PrettyCode QualifiedName where
  ppCode QualifiedName {..} = do
    let symbols = _qualifiedPath ^. pathParts NonEmpty.|> _qualifiedSymbol
    dotted <$> mapM ppSymbol symbols

ppName :: forall s r. (SingI s, Members '[Reader Options] r) => IdentifierType s -> Sem r (Doc Ann)
ppName = case sing :: SStage s of
  SParsed -> ppCode
  SScoped -> ppCode

instance PrettyCode S.NameId where
  ppCode (S.NameId k) = return (pretty k)

instance PrettyCode KeywordRef where
  ppCode p = return . annotate (kwTypeAnn (p ^. keywordRefKeyword . keywordType)) . pretty $ p

instance PrettyCode Keyword where
  ppCode p = return . annotate (kwTypeAnn (p ^. keywordType)) . pretty $ p

annDef :: forall s. SingI s => SymbolType s -> Doc Ann -> Doc Ann
annDef nm = case sing :: SStage s of
  SScoped -> annSDef nm
  SParsed -> id

annSDef :: S.Name' n -> Doc Ann -> Doc Ann
annSDef S.Name' {..} = annotate (AnnDef (_nameDefinedIn ^. S.absTopModulePath) _nameId)

instance PrettyCode TopModulePath where
  ppCode TopModulePath {..} =
    dotted <$> mapM ppSymbol (_modulePathDir ++ [_modulePathName])

instance PrettyCode Name where
  ppCode n = case n of
    NameUnqualified s -> ppSymbol s
    NameQualified s -> ppCode s

nameIdSuffix :: (Members '[Reader Options] r) => S.NameId -> Sem r (Maybe (Doc Ann))
nameIdSuffix nid = do
  showNameId <- asks (^. optShowNameIds)
  if
      | showNameId -> Just . ("@" <>) <$> ppCode nid
      | otherwise -> return Nothing

instance (PrettyCode n) => PrettyCode (S.Name' n) where
  ppCode S.Name' {..} = do
    nameConcrete' <- annotateKind _nameKind <$> ppCode _nameConcrete
    uid <- nameIdSuffix _nameId
    return $ annSRef (nameConcrete' <>? uid)
    where
      annSRef :: Doc Ann -> Doc Ann
      annSRef = annotate (AnnRef (_nameDefinedIn ^. S.absTopModulePath) _nameId)

instance PrettyCode S.AName where
  ppCode (S.AName n) =
    return (annotate (AnnKind (S.getNameKind n)) (pretty (n ^. S.nameVerbatim)))

instance PrettyCode ModuleRef where
  ppCode (ModuleRef' (t :&: ModuleRef'' {..})) = case t of
    SModuleTop -> ppCode _moduleRefName
    SModuleLocal -> ppCode _moduleRefName

instance (SingI s) => PrettyCode (OpenModule s) where
  ppCode :: forall r. (Members '[Reader Options] r) => OpenModule s -> Sem r (Doc Ann)
  ppCode OpenModule {..} = do
    openModuleName' <- case sing :: SStage s of
      SParsed -> ppCode _openModuleName
      SScoped -> ppCode _openModuleName
    openUsingHiding' <- mapM ppCode _openUsingHiding
    importkw' <- mapM ppCode _openModuleImportKw
    let openPublic' = ppPublic
    alias' <- fmap (kwAs <+>) <$> mapM ppModulePathType _openImportAsName
    return $ case importkw' of
      Nothing ->
        kwOpen
          <+> openModuleName'
          <+?> openUsingHiding'
          <+?> openPublic'
      Just importkw ->
        importkw
          <+> openModuleName'
          <+?> alias'
          <+> kwOpen
          <+?> openUsingHiding'
          <+?> openPublic'
    where
      ppPublic :: Maybe (Doc Ann)
      ppPublic = case _openPublic of
        Public -> Just kwPublic
        NoPublic -> Nothing

instance SingI s => PrettyCode (UsingHiding s) where
  ppCode :: forall r. Members '[Reader Options] r => UsingHiding s -> Sem r (Doc Ann)
  ppCode uh = do
    items' <- ppItems
    let bracedList = encloseSep kwBraceL kwBraceR (kwSemicolon <> space) (toList items')
    return $ kw' <+> bracedList
    where
      kw' = case uh of
        Using {} -> kwUsing
        Hiding {} -> kwHiding
      ppItems :: Sem r (NonEmpty (Doc Ann))
      ppItems = case uh of
        Using s -> mapM ppCode s
        Hiding s -> mapM ppSymbol s

instance SingI s => PrettyCode (UsingItem s) where
  ppCode ui = do
    kwAs' <- ppCode kwAs
    as' <- fmap (kwAs' <+>) <$> mapM ppSymbol (ui ^. usingAs)
    sym' <- ppSymbol (ui ^. usingSymbol)
    return (sym' <+?> as')

instance PrettyCode (WithSource Pragmas) where
  ppCode pragma =
    return $
      annotate AnnComment (pretty (Str.pragmasStart <> pragma ^. withSourceText <> Str.pragmasEnd)) <> line

ppJudocStart :: Members '[Reader Options] r => Sem r (Maybe (Doc Ann))
ppJudocStart = do
  i <- asks (^. optInJudocBlock)
  if
      | i -> return Nothing
      | otherwise -> Just <$> ppCode delimJudocStart

ppJudocExampleStart :: Doc Ann
ppJudocExampleStart = pretty (Str.judocExample :: Text)

instance (SingI s) => PrettyCode (Example s) where
  ppCode e = do
    e' <- ppExpression (e ^. exampleExpression)
    start' <- ppJudocStart
    return (start' <?+> ppJudocExampleStart <+> e' <> kwSemicolon)

instance SingI s => PrettyCode (JudocBlockParagraph s) where
  ppCode p = do
    start' <- ppCode (p ^. judocBlockParagraphStart)
    contents' <- inJudocBlock (vsep2 <$> mapM ppCode (p ^. judocBlockParagraphBlocks))
    end' <- ppCode (p ^. judocBlockParagraphEnd)
    return (start' <+> contents' <+> end')

instance SingI s => PrettyCode (JudocBlock s) where
  ppCode = \case
    JudocParagraphLines l -> vsep <$> mapM ppCode l
    JudocExample e -> ppCode e

instance (SingI s) => PrettyCode (JudocParagraphLine s) where
  ppCode (JudocParagraphLine atoms) = do
    start' <- ppJudocStart
    atoms' <- mconcatMap ppCode atoms
    return (start' <?+> atoms')

instance SingI s => PrettyCode (JudocGroup s) where
  ppCode :: forall r. Members '[Reader Options] r => JudocGroup s -> Sem r (Doc Ann)
  ppCode = \case
    JudocGroupLines l -> goLines l
    JudocGroupBlock l -> ppCode l
    where
      goLines :: NonEmpty (JudocBlock s) -> Sem r (Doc Ann)
      goLines blocks = do
        start' <- ppCode delimJudocStart
        let blockSep' = line <> start' <> line
        blocks' <- mapM ppCode blocks
        return (concatWith (\a b -> a <> blockSep' <> b) blocks')

instance SingI s => PrettyCode (Judoc s) where
  ppCode :: forall r. Members '[Reader Options] r => Judoc s -> Sem r (Doc Ann)
  ppCode (Judoc groups) = do
    groups' <- ppGroups groups
    return (groups' <> line)
    where
      ppGroups :: NonEmpty (JudocGroup s) -> Sem r (Doc Ann)
      ppGroups = \case
        g :| [] -> ppCode g
        g :| b : bs -> ppCode g <> groupSep <> ppGroups (b :| bs)
          where
            groupSep :: Sem r (Doc Ann)
            groupSep = (line <>) <$> extraLine
            extraLine :: Sem r (Doc Ann)
            extraLine = case (g, b) of
              (JudocGroupLines {}, JudocGroupLines {}) -> (<> line) <$> ppCode delimJudocStart
              _ -> return mempty

instance (SingI s) => PrettyCode (JudocAtom s) where
  ppCode :: forall r. (Members '[Reader Options] r) => JudocAtom s -> Sem r (Doc Ann)
  ppCode = \case
    JudocExpression e -> goExpression e
    JudocText t -> return (annotate AnnComment (pretty t))
    where
      goExpression :: ExpressionType s -> Sem r (Doc Ann)
      goExpression e = do
        e' <- ppExpression e
        return $ semiDelim e'
      semiDelim :: Doc Ann -> Doc Ann
      semiDelim = enclose1 (annotate AnnComment ";")

instance (SingI s) => PrettyCode (TypeSignature s) where
  ppCode TypeSignature {..} = do
    let sigTerminating' = if isJust _sigTerminating then kwTerminating <> line else mempty
    sigName' <- annDef _sigName <$> ppSymbol _sigName
    sigType' <- ppExpression _sigType
    builtin' <- traverse ppCode _sigBuiltin
    doc' <- mapM ppCode _sigDoc
    pragmas' <- mapM ppCode _sigPragmas
    body' :: Maybe (Doc Ann) <- fmap ((kwAssign <>) . oneLineOrNext) <$> mapM ppExpression _sigBody
    return $ doc' ?<> pragmas' ?<> builtin' <?+> sigTerminating' <> hang' (sigName' <+> kwColon <> oneLineOrNext (sigType' <+?> body'))

instance (SingI s) => PrettyCode (Function s) where
  ppCode a = case sing :: SStage s of
    SParsed -> ppCode' a
    SScoped -> apeHelper a
    where
      ppCode' :: forall r. (Members '[Reader Options] r) => Function s -> Sem r (Doc Ann)
      ppCode' Function {..} = do
        funParameter' <- ppCode _funParameters
        funReturn' <- ppRightExpression' funFixity _funReturn
        funKw' <- ppCode _funKw
        return $ funParameter' <+> funKw' <+> funReturn'
        where
          ppRightExpression' = case sing :: SStage s of
            SParsed -> ppRightExpression
            SScoped -> ppRightExpression

instance (SingI s) => PrettyCode (FunctionParameters s) where
  ppCode FunctionParameters {..} = do
    case _paramNames of
      [] -> ppLeftExpression' funFixity _paramType
      _ -> do
        paramNames' <-
          forM
            _paramNames
            ( \case
                Just n -> annDef n <$> ppSymbol n
                Nothing -> return kwWildcard
            )
        paramType' <- ppExpression _paramType
        return $ implicitDelim _paramImplicit (hsep paramNames' <+> kwColon <+> paramType')
    where
      ppLeftExpression' = case sing :: SStage s of
        SParsed -> ppLeftExpression
        SScoped -> ppLeftExpression

instance PrettyCode Universe where
  ppCode (Universe n _) = return $ kwType <+?> (pretty <$> n)

instance (SingI s) => PrettyCode (LetBlock s) where
  ppCode LetBlock {..} = do
    letClauses' <- blockIndent <$> ppBlock _letClauses
    letExpression' <- ppExpression _letExpression
    return $ kwLet <> letClauses' <> kwIn <+> letExpression'

instance (SingI s) => PrettyCode (LetClause s) where
  ppCode c = case c of
    LetTypeSig sig -> ppCode sig
    LetFunClause cl -> ppCode cl

ppBlock :: (PrettyCode a, Members '[Reader Options] r, Traversable t) => t a -> Sem r (Doc Ann)
ppBlock items = vsep <$> mapM (fmap endSemicolon . ppCode) items

ppPipeBlock :: (PrettyCode a, Members '[Reader Options] r, Traversable t) => t a -> Sem r (Doc Ann)
ppPipeBlock items = vsep <$> mapM (fmap (kwPipe <+>) . ppCode) items

instance (SingI s) => PrettyCode (LambdaClause s) where
  ppCode LambdaClause {..} = do
    lambdaParameters' <- hsep <$> mapM ppPatternAtom _lambdaParameters
    lambdaBody' <- ppExpression _lambdaBody
    return $ lambdaParameters' <+> kwAssign <> oneLineOrNext lambdaBody'

instance (SingI s) => PrettyCode (CaseBranch s) where
  ppCode CaseBranch {..} = do
    pat <- ppPatternParensType _caseBranchPattern
    e <- ppExpression _caseBranchExpression
    return $ kwPipe <+> pat <+> kwAssign <> oneLineOrNext e

instance (SingI s) => PrettyCode (Case s) where
  ppCode Case {..} = do
    exp <- ppExpression _caseExpression
    branches <- indent' . vsepHard <$> mapM ppCode _caseBranches
    return $ parensIf _caseParens (kwCase <+> exp <> hardline <> branches)

instance (SingI s) => PrettyCode (Lambda s) where
  ppCode Lambda {..} = do
    lambdaKw' <- ppCode _lambdaKw
    lambdaClauses' <- case _lambdaClauses of
      s :| [] -> braces <$> ppCode s
      _ -> bracesIndent <$> ppPipeBlock _lambdaClauses
    return $ lambdaKw' <+> lambdaClauses'

instance (SingI s) => PrettyCode (FunctionClause s) where
  ppCode FunctionClause {..} = do
    clauseOwnerFunction' <- ppSymbol _clauseOwnerFunction
    clausePatterns' <- case nonEmpty _clausePatterns of
      Nothing -> return Nothing
      Just ne -> Just . hsep <$> mapM ppPatternAtom ne
    clauseBody' <- ppExpression _clauseBody
    return $
      clauseOwnerFunction'
        <+?> clausePatterns'
        <+> kwAssign
          <> oneLineOrNext clauseBody'

instance (SingI s) => PrettyCode (AxiomDef s) where
  ppCode AxiomDef {..} = do
    axiomName' <- annDef _axiomName <$> ppSymbol _axiomName
    axiomDoc' <- mapM ppCode _axiomDoc
    axiomPragmas' <- mapM ppCode _axiomPragmas
    axiomType' <- ppExpression _axiomType
    builtin' <- traverse ppCode _axiomBuiltin
    return $ axiomDoc' ?<> axiomPragmas' ?<> builtin' <?+> hang' (kwAxiom <+> axiomName' <+> kwColon <+> axiomType')

instance SingI s => PrettyCode (Import s) where
  ppCode :: forall r. Members '[Reader Options] r => Import s -> Sem r (Doc Ann)
  ppCode i = do
    modulePath' <- ppModulePath
    qual' <- ppQual
    return $ kwImport <+> modulePath' <+?> qual'
    where
      ppQual :: Sem r (Maybe (Doc Ann))
      ppQual = case i ^. importAsName of
        Nothing -> return Nothing
        Just as -> do
          syn <- ppTopModulePath as
          return . Just $ kwAs <+> syn
      ppModulePath = case sing :: SStage s of
        SParsed -> ppCode (i ^. importModule)
        SScoped -> ppCode (i ^. importModule)

instance SingI t => PrettyCode (ModuleRef'' 'Concrete t) where
  ppCode m = case sing :: SModuleIsTop t of
    SModuleTop -> ppCode (m ^. moduleRefName)
    SModuleLocal -> ppCode (m ^. moduleRefName)

instance PrettyCode PatternScopedIden where
  ppCode = \case
    PatternScopedVar v -> ppCode v
    PatternScopedConstructor c -> ppCode c

instance PrettyCode PatternArg where
  ppCode (PatternArg i n p) = do
    n' <- traverse ppCode n
    p' <- ppCode p
    return $ (n' <&> (<> kwAt)) ?<> delimIf i (isJust n && not (isAtomic p)) p'

instance PrettyCode PatternApp where
  ppCode = apeHelper

ppPatternParensType :: forall s r. (SingI s, Member (Reader Options) r) => PatternParensType s -> Sem r (Doc Ann)
ppPatternParensType p = case sing :: SStage s of
  SParsed -> ppCode p
  SScoped -> ppCode p

instance PrettyCode PatternBinding where
  ppCode (PatternBinding n p) = do
    n' <- ppSymbol n
    p' <- ppCode p
    return $ n' <> kwAt <> p'

instance (SingI s) => PrettyCode (PatternAtom s) where
  ppCode a = case a of
    PatternAtomIden n -> case sing :: SStage s of
      SParsed -> ppCode n
      SScoped -> ppCode n
    PatternAtomWildcard {} -> return kwWildcard
    PatternAtomEmpty {} -> return $ parens mempty
    PatternAtomParens p -> parens <$> ppPatternParensType p
    PatternAtomBraces p -> braces <$> ppPatternParensType p
    PatternAtomAt p -> case sing :: SStage s of
      SParsed -> ppCode p
      SScoped -> ppCode p

instance (SingI s) => PrettyCode (PatternAtoms s) where
  ppCode (PatternAtoms ps _) = hsep <$> mapM ppCode ps

ppPattern :: forall s r. (SingI s, Members '[Reader Options] r) => PatternType s -> Sem r (Doc Ann)
ppPattern = case sing :: SStage s of
  SParsed -> ppCode
  SScoped -> ppCode

ppPatternAtom :: forall s r. (SingI s, Members '[Reader Options] r) => PatternType s -> Sem r (Doc Ann)
ppPatternAtom = case sing :: SStage s of
  SParsed -> ppCodeAtom
  SScoped -> \pat ->
    case pat ^. patternArgPattern of
      PatternVariable s | s ^. S.nameVerbatim == "=" -> parens <$> ppCodeAtom pat
      _ -> ppCodeAtom pat

instance PrettyCode Text where
  ppCode = return . pretty

instance PrettyCode InfixApplication where
  ppCode = apeHelper

instance PrettyCode PostfixApplication where
  ppCode = apeHelper

instance PrettyCode Application where
  ppCode = apeHelper

instance PrettyCode ApeLeaf where
  ppCode = \case
    ApeLeafExpression e -> ppCode e
    ApeLeafFunctionParams a -> ppCode a
    ApeLeafFunctionKw r -> return (pretty r)
    ApeLeafPattern r -> ppCode r
    ApeLeafPatternArg r -> ppCode r

apeHelper :: (IsApe a ApeLeaf, Members '[Reader Options] r) => a -> Sem r (Doc CodeAnn)
apeHelper a = do
  opts <- ask @Options
  let params :: ApeParams ApeLeaf
      params = ApeParams (run . runReader opts . ppCode)
  return $ runApe params a

instance PrettyCode Literal where
  ppCode = \case
    LitInteger n -> return $ annotate AnnLiteralInteger (pretty n)
    LitString s -> return $ ppStringLit s

instance PrettyCode AxiomRef where
  ppCode a = ppCode (a ^. axiomRefName)

instance PrettyCode InductiveRef where
  ppCode a = ppCode (a ^. inductiveRefName)

instance PrettyCode FunctionRef where
  ppCode a = ppCode (a ^. functionRefName)

instance PrettyCode ConstructorRef where
  ppCode a = ppCode (a ^. constructorRefName)

instance PrettyCode ScopedIden where
  ppCode = \case
    ScopedAxiom a -> ppCode a
    ScopedInductive i -> ppCode i
    ScopedVar n -> ppCode n
    ScopedFunction f -> ppCode f
    ScopedConstructor c -> ppCode c

instance (PrettyCode c) => PrettyCode (WithLoc c) where
  ppCode = ppCode . (^. withLocParam)

instance PrettyCode Expression where
  ppCode e = case e of
    ExpressionIdentifier n -> ppCode n
    ExpressionHole w -> ppHole w
    ExpressionParensIdentifier n -> parens <$> ppCode n
    ExpressionBraces b -> braces <$> ppCode b
    ExpressionApplication a -> ppCode a
    ExpressionInfixApplication a -> ppCode a
    ExpressionPostfixApplication a -> ppCode a
    ExpressionLambda l -> ppCode l
    ExpressionLetBlock lb -> ppCode lb
    ExpressionUniverse u -> ppCode u
    ExpressionLiteral l -> ppCode l
    ExpressionFunction f -> ppCode f
    ExpressionCase c -> ppCode c

instance PrettyCode Pattern where
  ppCode :: forall r. (Members '[Reader Options] r) => Pattern -> Sem r (Doc Ann)
  ppCode = \case
    PatternVariable v -> annDef v <$> ppCode v
    PatternApplication (PatternApp l r) -> do
      l' <- ppLeftExpression appFixity l
      r' <- ppRightExpression appFixity r
      return $ l' <+> r'
    PatternWildcard {} -> return kwWildcard
    PatternEmpty {} -> return $ parens mempty
    PatternConstructor constr -> ppCode constr
    PatternInfixApplication i -> apeHelper i
    PatternPostfixApplication i -> apeHelper i

ppPostExpression ::
  (PrettyCode a, HasAtomicity a, Member (Reader Options) r) =>
  Fixity ->
  a ->
  Sem r (Doc Ann)
ppPostExpression = ppLRExpression isPostfixAssoc

ppRightExpression ::
  (PrettyCode a, HasAtomicity a, Member (Reader Options) r) =>
  Fixity ->
  a ->
  Sem r (Doc Ann)
ppRightExpression = ppLRExpression isRightAssoc

ppLeftExpression ::
  (PrettyCode a, HasAtomicity a, Member (Reader Options) r) =>
  Fixity ->
  a ->
  Sem r (Doc Ann)
ppLeftExpression = ppLRExpression isLeftAssoc

ppLRExpression ::
  (HasAtomicity a, PrettyCode a, Member (Reader Options) r) =>
  (Fixity -> Bool) ->
  Fixity ->
  a ->
  Sem r (Doc Ann)
ppLRExpression associates fixlr e =
  parensCond (atomParens associates (atomicity e) fixlr)
    <$> ppCode e

ppCodeAtom :: (HasAtomicity c, PrettyCode c, Members '[Reader Options] r) => c -> Sem r (Doc Ann)
ppCodeAtom c = do
  p' <- ppCode c
  return $ if isAtomic c then p' else parens p'

ppHole :: forall s r. (Members '[Reader Options] r, SingI s) => HoleType s -> Sem r (Doc Ann)
ppHole w = case sing :: SStage s of
  SParsed -> return kwWildcard
  SScoped -> ppCode w

instance PrettyCode Hole where
  ppCode h = do
    suff <- nameIdSuffix (h ^. holeId)
    return (kwWildcard <>? suff)

instance (SingI s) => PrettyCode (ExpressionAtom s) where
  ppCode = \case
    AtomIdentifier n -> ppName n
    AtomLambda l -> ppCode l
    AtomLetBlock lb -> ppCode lb
    AtomCase c -> ppCode c
    AtomUniverse uni -> ppCode uni
    AtomFunction fun -> ppCode fun
    AtomLiteral lit -> ppCode lit
    AtomFunArrow a -> ppCode a
    AtomParens e -> parens <$> ppExpression e
    AtomBraces e -> braces <$> ppExpression (e ^. withLocParam)
    AtomHole w -> ppHole w

instance (SingI s) => PrettyCode (ExpressionAtoms s) where
  ppCode as = hsep <$> mapM ppCode (as ^. expressionAtoms)

ppExpression :: forall s r. (SingI s, Members '[Reader Options] r) => ExpressionType s -> Sem r (Doc Ann)
ppExpression = case sing :: SStage s of
  SScoped -> ppCode
  SParsed -> ppCode

instance PrettyCode SymbolEntry where
  ppCode ent =
    return
      ( kindWord
          <+> code (kindAnn (pretty (entryName ent ^. S.nameVerbatim)))
          <+> "defined at"
          <+> pretty (getLoc ent)
      )
    where
      pretty' :: Text -> Doc a
      pretty' = pretty
      (kindAnn :: Doc Ann -> Doc Ann, kindWord :: Doc Ann) = case ent of
        EntryAxiom {} -> (annotateKind S.KNameAxiom, pretty' Str.axiom)
        EntryInductive {} -> (annotateKind S.KNameInductive, pretty' Str.inductive)
        EntryFunction {} -> (annotateKind S.KNameFunction, pretty' Str.function)
        EntryConstructor {} -> (annotateKind S.KNameConstructor, pretty' Str.constructor)
        EntryVariable {} -> (annotateKind S.KNameLocal, pretty' Str.variable)
        EntryModule (ModuleRef' (isTop :&: _))
          | SModuleTop <- isTop -> (annotateKind S.KNameTopModule, pretty' Str.topModule)
          | SModuleLocal <- isTop -> (annotateKind S.KNameLocalModule, pretty' Str.localModule)
