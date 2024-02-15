module PureScript.CoreFn.Analyser where

import Prelude

import Data.Array (fold, foldMap)
import Data.Array as Array
import Data.Maybe (Maybe(..))
import Data.String as Str
import Data.String.Regex as Re
import Data.Tuple (Tuple)
import Data.Tuple.Nested (type (/\), (/\))
import PureScript.CoreFn (propValue)
import PureScript.CoreFn as CF
import PureScript.CoreFn.Utils (typeClassConstructorRegex)

type TypeclassInstance =
  { typeclass :: CF.Qualified CF.Ident
  , members :: Array (CF.Ident /\ CF.Expr CF.Ann)
  }

classify
  :: Array (CF.Bind CF.Ann)
  -> { normal :: Array (Tuple CF.Ident (CF.Expr CF.Ann))
     , constructors :: Array (Tuple CF.Ident (CF.Expr CF.Ann))
     , newtypeConstructors :: Array (Tuple CF.Ident (CF.Expr CF.Ann))
     , typeclassConstructors :: Array (Tuple CF.Ident (CF.Expr CF.Ann))
     , typeclassInstances :: Array (Tuple CF.Ident (CF.Expr CF.Ann))
     }
classify = foldMap (go1 initial)
  where
  initial =
    { normal: []
    , constructors: []
    , newtypeConstructors: []
    , typeclassConstructors: []
    , typeclassInstances: []
    }

  go1 accu = case _ of
    CF.NonRec binding -> go2 accu binding
    CF.Rec bindings -> foldMap (go2 accu) bindings

  go2 accu (CF.Binding ann ident@(CF.Ident id) expr) = case expr of
    CF.ExprConstructor _ _ _ _ -> accu { constructors = Array.cons (ident /\ expr) accu.constructors }
    CF.ExprAbs ann' _ _
      | CF.Ann { meta: Just CF.IsNewtype } <- ann' ->
          if Re.test typeClassConstructorRegex id then accu { typeclassConstructors = Array.cons (ident /\ expr) accu.typeclassConstructors }
          else accu { newtypeConstructors = Array.cons (ident /\ expr) accu.newtypeConstructors }
    CF.ExprApp _ abs _
      | CF.ExprVar (CF.Ann { meta: Just CF.IsNewtype }) var <- abs
      , CF.Qualified qual (CF.Ident name) <- var
      , Re.test typeClassConstructorRegex name ->
          accu { typeclassInstances = Array.cons (ident /\ expr) accu.typeclassInstances }
    _ -> accu

typeclassInstanceOfExpr :: CF.Expr CF.Ann -> Maybe TypeclassInstance
typeclassInstanceOfExpr = case _ of
  CF.ExprApp _ abs arg
    | CF.ExprVar (CF.Ann { meta: Just CF.IsNewtype }) absVar <- abs
    , CF.Qualified (Just moduleName) (CF.Ident typeclassDict) <- absVar
    , Re.test typeClassConstructorRegex typeclassDict
    , CF.ExprLit _ (CF.LitRecord props) <- arg ->
        let
          clsName = Str.replace (Str.Pattern "$Dict") (Str.Replacement "") typeclassDict
        in
          Just
            { typeclass: CF.Qualified (Just moduleName) (CF.Ident clsName)
            , members: props <#> \(CF.Prop id exp) -> CF.Ident id /\ exp
            }
  _ -> Nothing

freeVars :: CF.Expr CF.Ann -> Array CF.Ident
freeVars = case _ of
  CF.ExprVar _ (CF.Qualified Nothing var) -> [ var ]
  CF.ExprAbs _ arg body -> Array.filter (_ /= arg) (freeVars body)
  CF.ExprApp _ func arg -> fold [ freeVars func, freeVars arg ]
  CF.ExprLet _ binds body ->
    let
      boundVars = fold $ binds <#> case _ of
        CF.NonRec (CF.Binding _ id _) -> [ id ]
        CF.Rec bindings -> map CF.bindingIdent bindings
    in
      Array.filter (not <<< (_ `Array.elem` boundVars)) $ freeVars body
  CF.ExprAccessor _ e _ -> freeVars e
  CF.ExprUpdate _ e ups -> fold [ freeVars e, foldMap (freeVars <<< propValue) ups ]
  CF.ExprCase _ caseHeads caseAlts ->
    let
      freeVarsInHeads = foldMap freeVars caseHeads
      freeVarsInGuard (CF.Guard gur exp) = freeVars gur <> freeVars exp
      freeVarsInCaseAlts = join $ caseAlts
        <#> \(CF.CaseAlternative _ act) -> case act of
          CF.Unconditional exp -> freeVars exp
          CF.Guarded gs -> foldMap freeVarsInGuard gs
    in
      freeVarsInHeads <> freeVarsInCaseAlts
  _ -> []
