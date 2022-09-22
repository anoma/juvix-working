module Juvix.Compiler.Asm.Extra.Memory where

import Data.HashMap.Strict qualified as HashMap
import Juvix.Compiler.Asm.Data.InfoTable
import Juvix.Compiler.Asm.Data.Stack (Stack)
import Juvix.Compiler.Asm.Data.Stack qualified as Stack
import Juvix.Compiler.Asm.Error
import Juvix.Compiler.Asm.Extra.Base
import Juvix.Compiler.Asm.Extra.Type
import Juvix.Compiler.Asm.Language
import Juvix.Compiler.Asm.Language.Type
import Juvix.Compiler.Asm.Pretty
import Safe (atMay)

type Arguments = HashMap Offset Type

-- | A static representation of JuvixAsm memory providing type information for
-- memory locations.
data Memory = Memory
  { _memoryValueStack :: Stack Type,
    _memoryTempStack :: Stack Type,
    _memoryArgumentArea :: Arguments,
    _memoryArgsNum :: Int
  }

makeLenses ''Memory

mkMemory :: Arguments -> Memory
mkMemory args =
  Memory
    { _memoryValueStack = Stack.empty,
      _memoryTempStack = Stack.empty,
      _memoryArgumentArea = args,
      _memoryArgsNum = HashMap.size args
    }

pushValueStack :: Type -> Memory -> Memory
pushValueStack ty = over memoryValueStack (Stack.push ty)

popValueStack :: Int -> Memory -> Memory
popValueStack n = foldr (.) id (replicate n (over memoryValueStack Stack.pop))

pushTempStack :: Type -> Memory -> Memory
pushTempStack ty = over memoryTempStack (Stack.push ty)

popTempStack :: Int -> Memory -> Memory
popTempStack n = foldr (.) id (replicate n (over memoryTempStack Stack.pop))

-- | Read value stack at index `n` from the top.
topValueStack :: Int -> Memory -> Maybe Type
topValueStack n mem = Stack.nthFromTop n (mem ^. memoryValueStack)

topValueStack' :: Int -> Memory -> Type
topValueStack' n mem =
  fromMaybe (error "invalid value stack access") $
    topValueStack n mem

-- | Values from top of the value stack, in order from top to bottom.
topValuesFromValueStack :: Int -> Memory -> Maybe [Type]
topValuesFromValueStack n mem = Stack.topValues n (mem ^. memoryValueStack)

-- | Values from top of the value stack, in order from top to bottom.
topValuesFromValueStack' :: Int -> Memory -> [Type]
topValuesFromValueStack' n mem =
  fromMaybe (error "invalid value stack access") $
    Stack.topValues n (mem ^. memoryValueStack)

-- | Read temporary stack at index `n` from the bottom.
bottomTempStack :: Int -> Memory -> Maybe Type
bottomTempStack n mem = Stack.nthFromBottom n (mem ^. memoryTempStack)

bottomTempStack' :: Int -> Memory -> Type
bottomTempStack' n mem =
  fromMaybe (error "invalid temporary stack access") $
    bottomTempStack n mem

getArgumentType :: Offset -> Memory -> Maybe Type
getArgumentType off mem = HashMap.lookup off (mem ^. memoryArgumentArea)

getMemValueType :: InfoTable -> MemValue -> Memory -> Maybe Type
getMemValueType tab val mem = case val of
  DRef dr -> getDirectRefType dr mem
  ConstrRef fld ->
    let ci = getConstrInfo tab (fld ^. fieldTag)
        tyargs = typeArgs (ci ^. constructorType)
     in atMay tyargs (fld ^. fieldOffset)

getDirectRefType :: DirectRef -> Memory -> Maybe Type
getDirectRefType dr mem = case dr of
  StackRef ->
    topValueStack 0 mem
  ArgRef off ->
    getArgumentType off mem
  TempRef off ->
    bottomTempStack off mem

getValueType' :: Member (Error AsmError) r => Maybe Location -> InfoTable -> Memory -> Value -> Sem r Type
getValueType' loc tab mem = \case
  ConstInt _ -> return mkTypeInteger
  ConstBool _ -> return mkTypeBool
  ConstString _ -> return TyString
  ConstUnit -> return TyUnit
  ConstVoid -> return TyUnit
  Ref val -> case getMemValueType tab val mem of
    Just ty -> return ty
    Nothing -> throw $ AsmError loc "invalid memory reference"

getValueType :: InfoTable -> Memory -> Value -> Maybe Type
getValueType tab mem val =
  case run (runError ty0) of
    Left _ -> Nothing
    Right ty -> Just ty
  where
    ty0 :: Sem '[Error AsmError] Type
    ty0 = getValueType' Nothing tab mem val

-- | Check if the value stack has at least the given height
checkValueStackHeight' :: Member (Error AsmError) r => Maybe Location -> Int -> Memory -> Sem r ()
checkValueStackHeight' loc n mem = do
  unless (length (mem ^. memoryValueStack) >= n) $
    throw $
      AsmError
        loc
        ( fromString $
            "wrong value stack height: expected at least "
              ++ show n
              ++ ", but the height is "
              ++ show (length (mem ^. memoryValueStack))
        )

-- | Check if the values on top of the value stack have the given types (the
-- first element of the list corresponds to the top of the stack)
checkValueStack' :: Member (Error AsmError) r => Maybe Location -> InfoTable -> [Type] -> Memory -> Sem r ()
checkValueStack' loc tab tys mem = do
  checkValueStackHeight' loc (length tys) mem
  mapM_
    ( \(ty, idx) -> do
        let ty' = fromJust $ topValueStack idx mem
        unless (isSubtype ty' ty) $
          throw $
            AsmError loc $
              "type mismatch on value stack cell "
                `mappend` show idx
                `mappend` " from top: expected "
                `mappend` ppTrace tab ty
                `mappend` " but got "
                `mappend` ppTrace tab ty'
    )
    (zip tys [0 ..])

unifyMemory' :: Member (Error AsmError) r => Maybe Location -> InfoTable -> Memory -> Memory -> Sem r Memory
unifyMemory' loc tab mem1 mem2 = do
  unless (length (mem1 ^. memoryValueStack) == length (mem2 ^. memoryValueStack)) $
    throw $
      AsmError loc "value stack height mismatch"
  vs <- zipWithM (unifyTypes' loc tab) (toList (mem1 ^. memoryValueStack)) (toList (mem2 ^. memoryValueStack))
  unless (length (mem1 ^. memoryTempStack) == length (mem2 ^. memoryTempStack)) $
    throw $
      AsmError loc "temporary stack height mismatch"
  ts <- zipWithM (unifyTypes' loc tab) (toList (mem1 ^. memoryTempStack)) (toList (mem2 ^. memoryTempStack))
  unless
    ( length (mem1 ^. memoryArgumentArea) == length (mem2 ^. memoryArgumentArea)
        && mem1 ^. memoryArgsNum == mem2 ^. memoryArgsNum
    )
    $ throw
    $ AsmError loc "argument area size mismatch"
  let n = mem1 ^. memoryArgsNum
  args <-
    mapM
      ( \off ->
          unifyTypes'
            loc
            tab
            (fromJust $ HashMap.lookup off (mem1 ^. memoryArgumentArea))
            (fromJust $ HashMap.lookup off (mem1 ^. memoryArgumentArea))
      )
      [0 .. n - 1]
  return $
    Memory
      { _memoryValueStack = Stack.fromList vs,
        _memoryTempStack = Stack.fromList ts,
        _memoryArgumentArea = HashMap.fromList (zipExact [0 .. n - 1] args),
        _memoryArgsNum = n
      }
