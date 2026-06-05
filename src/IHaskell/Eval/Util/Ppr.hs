{-# LANGUAGE CPP, NoImplicitPrelude #-}

-- | Pretty-printing utilities for GHC 'SDoc' values: flags, languages, and
-- general rendering.  Extracted from 'IHaskell.Eval.Util' to reduce the CPP
-- burden in that module and to make the pretty-printer independently testable.
module IHaskell.Eval.Util.Ppr (
    pprDynFlags,
    pprLanguages,
    doc,
    ) where

import           IHaskellPrelude

#if MIN_VERSION_ghc(9,8,0)
import           GHC.Core.InstEnv (is_cls, is_tys, mkInstEnv, instEnvElts)
import           GHC.Core.Unify
import           GHC.Types.TyThing.Ppr
import           GHC.Driver.CmdLine
import           GHC.Driver.Monad (modifySession)
import           GHC.Driver.Ppr
import           GHC.Driver.Session
import           GHC.Driver.Env.Types
import           GHC.Platform.Ways
import           GHC.Runtime.Context
import           GHC.Types.Error
import           GHC.Types.Name (pprInfixName)
import           GHC.Types.Name.Set
import           GHC.Types.TyThing
import qualified GHC.Driver.Session as DynFlags
import qualified GHC.Utils.Outputable as O
import qualified GHC.Utils.Ppr as Pretty
import           GHC.Runtime.Loader
#elif MIN_VERSION_ghc(9,4,0)
import           GHC.Core.InstEnv (is_cls, is_tys, mkInstEnv, instEnvElts)
import           GHC.Core.Unify
import           GHC.Types.TyThing.Ppr
import           GHC.Driver.CmdLine
import           GHC.Driver.Monad (modifySession)
import           GHC.Driver.Ppr
import           GHC.Driver.Session
import           GHC.Driver.Env.Types
import           GHC.Platform.Ways
import           GHC.Runtime.Context
import           GHC.Types.Name (pprInfixName)
import           GHC.Types.Name.Set
import           GHC.Types.TyThing
import qualified GHC.Driver.Session as DynFlags
import qualified GHC.Utils.Outputable as O
import qualified GHC.Utils.Ppr as Pretty
import           GHC.Runtime.Loader
#elif MIN_VERSION_ghc(9,2,0)
import           GHC.Core.InstEnv (is_cls, is_tys)
import           GHC.Core.Unify
import           GHC.Types.TyThing.Ppr
import           GHC.Driver.CmdLine
import           GHC.Driver.Monad (modifySession)
import           GHC.Driver.Ppr
import           GHC.Driver.Session
import           GHC.Driver.Env.Types
import           GHC.Platform.Ways
import           GHC.Runtime.Context
import           GHC.Types.Name (pprInfixName)
import           GHC.Types.Name.Set
import           GHC.Types.TyThing
import qualified GHC.Driver.Session as DynFlags
import qualified GHC.Utils.Outputable as O
import qualified GHC.Utils.Ppr as Pretty
import           GHC.Runtime.Loader
#endif

import           GHC (DynFlags, GhcMonad, getSessionDynFlags, pprCols)

-- | Pretty-print dynamic flags (taken from 'InteractiveUI' module of @ghc-bin@)
pprDynFlags :: Bool -> DynFlags -> O.SDoc
pprDynFlags show_all dflags =
  O.vcat
    [ O.text "GHCi-specific dynamic flag settings:" O.$$
      O.nest 2 (O.vcat (map (setting opt) ghciFlags))
    , O.text "other dynamic, non-language, flag settings:" O.$$
      O.nest 2 (O.vcat (map (setting opt) others))
    , O.text "warning settings:" O.$$
      O.nest 2 (O.vcat (map (setting wopt) wFlags))
    ]
  where
    wFlags = DynFlags.wWarningFlags
    opt = gopt
    setting test flag
      | quiet = O.empty :: O.SDoc
      | is_on = fstr name :: O.SDoc
      | otherwise = fnostr name :: O.SDoc
      where
        name = flagSpecName flag
        f = flagSpecFlag flag
        is_on = test f dflags
        quiet = not show_all && test f default_dflags == is_on
#if MIN_VERSION_ghc(9,6,0)
    default_dflags = defaultDynFlags (settings dflags)
#elif MIN_VERSION_ghc(8,10,0)
    default_dflags = defaultDynFlags (settings dflags) (llvmConfig dflags)
#elif MIN_VERSION_ghc(8,6,0)
    default_dflags = defaultDynFlags (settings dflags) (llvmTargets dflags, llvmPasses dflags)
#else
    default_dflags = defaultDynFlags (settings dflags) (llvmTargets dflags)
#endif
    fstr str  = O.text "-f" O.<> O.text str
    fnostr str = O.text "-fno-" O.<> O.text str
    (ghciFlags, others) = partition (\f -> flagSpecFlag f `elem` flgs) DynFlags.fFlags
    flgs = concat [flgs1, flgs2, flgs3]
    flgs1 = [Opt_PrintExplicitForalls]
    flgs2 = [Opt_PrintExplicitKinds]

flgs3 :: [GeneralFlag]
flgs3 = [Opt_PrintBindResult, Opt_BreakOnException, Opt_BreakOnError, Opt_PrintEvldWithShow]

-- | Pretty-print the base language and active options (taken from 'InteractiveUI' module of @ghc-bin@)
pprLanguages :: Bool -> DynFlags -> O.SDoc
pprLanguages show_all dflags =
  O.vcat
    [ O.text "base language is: " O.<>
      case language dflags of
        Nothing          -> O.text "Haskell2010"
        Just Haskell98   -> O.text "Haskell98"
        Just Haskell2010 -> O.text "Haskell2010"
#if MIN_VERSION_ghc(9,4,0)
        Just GHC2021 -> O.text "GHC2021"
#else
#endif
    , (if show_all
         then O.text "all active language options:"
         else O.text "with the following modifiers:") O.$$
      O.nest 2 (O.vcat (map (setting xopt) DynFlags.xFlags))
    ]
  where
    setting test flag
      | quiet = O.empty
      | is_on = O.text "-X" O.<> O.text name
      | otherwise = O.text "-XNo" O.<> O.text name
      where
        name = flagSpecName flag
        f = flagSpecFlag flag
        is_on = test f dflags
        quiet = not show_all && test f default_dflags == is_on
    default_dflags =
#if MIN_VERSION_ghc(9,6,0)
      defaultDynFlags (settings dflags) `lang_set`
#elif MIN_VERSION_ghc(8,10,0)
      defaultDynFlags (settings dflags) (llvmConfig dflags) `lang_set`
#elif MIN_VERSION_ghc(8,6,0)
      defaultDynFlags (settings dflags) (llvmTargets dflags, llvmPasses dflags) `lang_set`
#else
      defaultDynFlags (settings dflags) (llvmTargets dflags) `lang_set`
#endif
      case language dflags of
        Nothing -> Just Haskell2010
        other   -> other

-- | Convert an 'SDoc' into a string, respecting the configured column width.
doc :: GhcMonad m => O.SDoc -> m String
doc sdoc = do
  flags <- getSessionDynFlags
#if MIN_VERSION_ghc(9,6,0)
  let unqual = O.neverQualify
#else
  unqual <- getPrintUnqual
#endif
#if MIN_VERSION_ghc(9,0,0)
  let style = O.mkUserStyle unqual O.AllTheWay
#else
  let style = O.mkUserStyle flags unqual O.AllTheWay
#endif
  let cols = pprCols flags
#if MIN_VERSION_ghc(9,2,0)
      d = O.runSDoc sdoc (initSDocContext flags style)
  return $ Pretty.fullRender (Pretty.PageMode False) cols 1.5 string_txt "" d
#else
      d = O.runSDoc sdoc (O.initSDocContext flags style)
  return $ Pretty.fullRender Pretty.PageMode cols 1.5 string_txt "" d
#endif
  where
    string_txt :: Pretty.TextDetails -> String -> String
#if MIN_VERSION_ghc(8,6,0)
    string_txt = Pretty.txtPrinter
#else
    string_txt (Pretty.Chr c) s = c : s
    string_txt (Pretty.Str s1) s2 = s1 ++ s2
    string_txt (Pretty.PStr s1) s2 = unpackFS s1 ++ s2
    string_txt (Pretty.LStr s1 _) s2 = unpackLitString s1 ++ s2
    string_txt (Pretty.ZStr s1) s2 = CBS.unpack (fastZStringToByteString s1) ++ s2
#endif
