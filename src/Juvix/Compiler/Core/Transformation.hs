module Juvix.Compiler.Core.Transformation
  ( module Juvix.Compiler.Core.Transformation.Base,
    module Juvix.Compiler.Core.Transformation,
    module Juvix.Compiler.Core.Transformation.Eta,
    module Juvix.Compiler.Core.Transformation.LambdaLetRecLifting,
    module Juvix.Compiler.Core.Transformation.TopEtaExpand,
    module Juvix.Compiler.Core.Data.TransformationId,
  )
where

import Juvix.Compiler.Core.Data.Module
import Juvix.Compiler.Core.Data.TransformationId
import Juvix.Compiler.Core.Error
import Juvix.Compiler.Core.Options
import Juvix.Compiler.Core.Scoper (scopeCheckDebugM)
import Juvix.Compiler.Core.Transformation.Base
import Juvix.Compiler.Core.Transformation.Check.Anoma
import Juvix.Compiler.Core.Transformation.Check.Cairo
import Juvix.Compiler.Core.Transformation.Check.Exec
import Juvix.Compiler.Core.Transformation.Check.Rust
import Juvix.Compiler.Core.Transformation.Check.VampIR
import Juvix.Compiler.Core.Transformation.CombineInfoTables (combineInfoTables)
import Juvix.Compiler.Core.Transformation.ComputeCaseANF
import Juvix.Compiler.Core.Transformation.ComputeTypeInfo
import Juvix.Compiler.Core.Transformation.ConvertBuiltinTypes
import Juvix.Compiler.Core.Transformation.DetectConstantSideConditions
import Juvix.Compiler.Core.Transformation.DetectRedundantPatterns
import Juvix.Compiler.Core.Transformation.DisambiguateNames
import Juvix.Compiler.Core.Transformation.Eta
import Juvix.Compiler.Core.Transformation.FoldTypeSynonyms
import Juvix.Compiler.Core.Transformation.IdentityTrans
import Juvix.Compiler.Core.Transformation.IntToPrimInt
import Juvix.Compiler.Core.Transformation.LambdaLetRecLifting
import Juvix.Compiler.Core.Transformation.LetHoisting
import Juvix.Compiler.Core.Transformation.MatchToCase
import Juvix.Compiler.Core.Transformation.MoveApps
import Juvix.Compiler.Core.Transformation.NatToPrimInt
import Juvix.Compiler.Core.Transformation.Normalize
import Juvix.Compiler.Core.Transformation.Optimize.CaseCallLifting
import Juvix.Compiler.Core.Transformation.Optimize.CaseFolding
import Juvix.Compiler.Core.Transformation.Optimize.CasePermutation (casePermutation)
import Juvix.Compiler.Core.Transformation.Optimize.ConstantFolding
import Juvix.Compiler.Core.Transformation.Optimize.FilterUnreachable (filterUnreachable)
import Juvix.Compiler.Core.Transformation.Optimize.Inlining
import Juvix.Compiler.Core.Transformation.Optimize.LambdaFolding
import Juvix.Compiler.Core.Transformation.Optimize.LetFolding
import Juvix.Compiler.Core.Transformation.Optimize.MandatoryInlining
import Juvix.Compiler.Core.Transformation.Optimize.Phase.Eval qualified as Phase.Eval
import Juvix.Compiler.Core.Transformation.Optimize.Phase.Exec qualified as Phase.Exec
import Juvix.Compiler.Core.Transformation.Optimize.Phase.Main qualified as Phase.Main
import Juvix.Compiler.Core.Transformation.Optimize.Phase.VampIR qualified as Phase.VampIR
import Juvix.Compiler.Core.Transformation.Optimize.SimplifyComparisons (simplifyComparisons)
import Juvix.Compiler.Core.Transformation.Optimize.SimplifyIfs
import Juvix.Compiler.Core.Transformation.Optimize.SpecializeArgs
import Juvix.Compiler.Core.Transformation.RemoveTypeArgs
import Juvix.Compiler.Core.Transformation.TopEtaExpand
import Juvix.Compiler.Core.Transformation.UnrollRecursion

applyTransformations ::
  forall r.
  (Members '[Error JuvixError, Reader CoreOptions] r) =>
  [TransformationId] ->
  Module ->
  Sem r Module
applyTransformations ts tbl = foldM (flip appTransLog) tbl ts
  where
    appTransLog :: TransformationId -> Module -> Sem r Module
    appTransLog t m = do
      m' <- force <$> scopeCheckDebugM m
      traceM ("Before ApplyTrans " <> show t)
      m'' <- appTrans t m'
      res <- force <$> scopeCheckDebugM m''
      traceM ("After ApplyTrans " <> show t)
      return res

    appTrans :: TransformationId -> Module -> Sem r Module
    appTrans = \case
      LambdaLetRecLifting -> return . lambdaLetRecLifting
      LetRecLifting -> return . letRecLifting
      IdentityTrans -> return . identity
      TopEtaExpand -> return . topEtaExpand
      RemoveTypeArgs -> return . removeTypeArgs
      MoveApps -> return . moveApps
      NatToPrimInt -> return . natToPrimInt
      IntToPrimInt -> return . intToPrimInt
      ConvertBuiltinTypes -> return . convertBuiltinTypes
      ComputeTypeInfo -> return . computeTypeInfo
      ComputeCaseANF -> return . computeCaseANF
      UnrollRecursion -> unrollRecursion
      DetectConstantSideConditions -> mapError (JuvixError @CoreError) . detectConstantSideConditions
      DetectRedundantPatterns -> mapError (JuvixError @CoreError) . detectRedundantPatterns
      MatchToCase -> mapError (JuvixError @CoreError) . matchToCase
      EtaExpandApps -> return . etaExpansionApps
      DisambiguateNames -> return . disambiguateNames
      CombineInfoTables -> return . combineInfoTables
      CheckExec -> mapError (JuvixError @CoreError) . checkExec
      CheckRust -> mapError (JuvixError @CoreError) . checkRust
      CheckVampIR -> mapError (JuvixError @CoreError) . checkVampIR
      CheckAnoma -> mapError (JuvixError @CoreError) . checkAnoma
      CheckCairo -> mapError (JuvixError @CoreError) . checkCairo
      Normalize -> normalize
      LetFolding -> return . letFolding
      LambdaFolding -> return . lambdaFolding
      LetHoisting -> return . letHoisting
      Inlining -> inlining
      MandatoryInlining -> return . mandatoryInlining
      FoldTypeSynonyms -> return . foldTypeSynonyms
      CaseCallLifting -> return . caseCallLifting
      SimplifyIfs -> return . simplifyIfs
      SimplifyComparisons -> return . simplifyComparisons
      SpecializeArgs -> return . specializeArgs
      CaseFolding -> return . caseFolding
      CasePermutation -> return . casePermutation
      ConstantFolding -> constantFolding
      FilterUnreachable -> return . filterUnreachable
      OptPhaseEval -> Phase.Eval.optimize
      OptPhaseExec -> Phase.Exec.optimize
      OptPhaseVampIR -> Phase.VampIR.optimize
      OptPhaseMain -> Phase.Main.optimize
