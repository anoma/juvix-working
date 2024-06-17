module Juvix.Compiler.Reg.Data.TransformationId where

import Juvix.Compiler.Core.Data.TransformationId.Base
import Juvix.Compiler.Reg.Data.TransformationId.Strings
import Juvix.Prelude

data TransformationId
  = IdentityTrans
  | Cleanup
  | SSA
  | InitBranchVars
  | CopyPropagation
  | ConstantPropagation
  deriving stock (Data, Bounded, Enum, Show)

data PipelineId
  = PipelineCasm
  | PipelineC
  | PipelineRust
  deriving stock (Data, Bounded, Enum)

type TransformationLikeId = TransformationLikeId' TransformationId PipelineId

-- Note: this works only because for now we mark all variables as live. Liveness
-- information needs to be re-computed after copy & constant propagation.
toCTransformations :: [TransformationId]
toCTransformations = [Cleanup, CopyPropagation, ConstantPropagation]

toRustTransformations :: [TransformationId]
toRustTransformations = [Cleanup, CopyPropagation, ConstantPropagation]

toCasmTransformations :: [TransformationId]
toCasmTransformations = [Cleanup, CopyPropagation, ConstantPropagation, SSA]

instance TransformationId' TransformationId where
  transformationText :: TransformationId -> Text
  transformationText = \case
    IdentityTrans -> strIdentity
    Cleanup -> strCleanup
    SSA -> strSSA
    InitBranchVars -> strInitBranchVars
    CopyPropagation -> strCopyPropagation
    ConstantPropagation -> strConstantPropagation

instance PipelineId' TransformationId PipelineId where
  pipelineText :: PipelineId -> Text
  pipelineText = \case
    PipelineC -> strCPipeline
    PipelineRust -> strRustPipeline
    PipelineCasm -> strCasmPipeline

  pipeline :: PipelineId -> [TransformationId]
  pipeline = \case
    PipelineC -> toCTransformations
    PipelineRust -> toRustTransformations
    PipelineCasm -> toCasmTransformations
