{-# LANGUAGE NoImplicitPrelude, CPP #-}

-- | GHC API compatibility shims.  All CPP-gated version adaptations are
-- collected here so that the rest of the codebase can import a stable
-- interface regardless of the GHC version being used.
module IHaskell.Eval.Evaluate.Compat (
    showSDocUnqual,
    gcatch,
    gtry,
    gfinally,
    ghandle,
    throw,
    packageIdString',
    getPackageConfigs,
    getErrMsgDoc,
    objTarget,
    ghcVerbosity,
    hiddenPackageNames,
    requiredGlobalImports,
    ihaskellGlobalImports,
    ignoreTypePrefixes,
    typeCleaner,
    ) where

import           IHaskellPrelude

import           Data.Foldable (foldMap)
import qualified Data.Set as Set
import           Data.Char as Char

-- GHC API imports — version-gated
#if MIN_VERSION_ghc(9,4,0)
import qualified GHC.Runtime.Debugger as Debugger
import           GHC.Runtime.Eval
import           GHC.Driver.Session
import           GHC.Unit.State
import           Control.Monad.Catch as MC
import           GHC.Utils.Outputable hiding ((<>))
import           GHC.Data.Bag
import           GHC.Driver.Backend
import           GHC.Driver.Env
import           GHC.Driver.Ppr
import           GHC.Runtime.Context
import           GHC.Types.Error
import           GHC.Types.SourceError
import           GHC.Unit.Types (UnitId)
import qualified GHC.Utils.Error as ErrUtils
#elif MIN_VERSION_ghc(9,2,0)
import qualified GHC.Runtime.Debugger as Debugger
import           GHC.Runtime.Eval
import           GHC.Driver.Session
import           GHC.Unit.State
import           Control.Monad.Catch as MC
import           GHC.Utils.Outputable hiding ((<>))
import           GHC.Data.Bag
import           GHC.Driver.Backend
import           GHC.Driver.Ppr
import           GHC.Runtime.Context
import           GHC.Types.SourceError
import           GHC.Unit.Types (UnitId)
import qualified GHC.Utils.Error as ErrUtils
#elif MIN_VERSION_ghc(9,0,0)
import qualified GHC.Runtime.Debugger as Debugger
import           GHC.Runtime.Eval
import           GHC.Driver.Session
import           GHC.Driver.Types
import           GHC.Unit.State
import           Control.Monad.Catch as MC
import           GHC.Utils.Outputable hiding ((<>))
import           GHC.Data.Bag
import           GHC.Unit.Types (UnitId)
import qualified GHC.Utils.Error as ErrUtils
#else
import qualified Debugger
import           Bag
import           DynFlags
import           HscTypes
import           InteractiveEval
import           Exception hiding (evaluate)
import           GhcMonad (liftIO)
import           Outputable hiding ((<>))
import           Packages
import qualified ErrUtils
#endif

import qualified GHC.Paths
import           GHC hiding (Stmt, TypeSig)

#if MIN_VERSION_ghc(9,0,0)
import           GHC.Data.FastString
#else
import           FastString (unpackFS)
#endif

import           StringUtils (replace)

#if MIN_VERSION_ghc(9,2,0)
showSDocUnqual :: DynFlags -> SDoc -> String
showSDocUnqual = showSDoc
#endif

#if MIN_VERSION_ghc(9,0,0)
gcatch :: Ghc a -> (SomeException -> Ghc a) -> Ghc a
gcatch = MC.catch

gtry :: IO a -> IO (Either SomeException a)
gtry = MC.try

gfinally :: Ghc a -> Ghc b -> Ghc a
gfinally = MC.finally

ghandle :: (MonadCatch m, Exception e) => (e -> m a) -> m a -> m a
ghandle = MC.handle

throw :: SomeException -> Ghc a
throw = MC.throwM
#endif

-- | Set GHC's verbosity for debugging
ghcVerbosity :: Maybe Int
ghcVerbosity = Nothing -- Just 5

ignoreTypePrefixes :: [String]
ignoreTypePrefixes = [ "GHC.Types"
                     , "GHC.Base"
                     , "GHC.Show"
                     , "System.IO"
                     , "GHC.Float"
                     , ":Interactive"
                     , "GHC.Num"
                     , "GHC.IO"
                     , "GHC.Integer.Type"
                     ]

typeCleaner :: String -> String
typeCleaner = useStringType . foldl' (.) id (map (`replace` "") fullPrefixes)
  where
    fullPrefixes = map (++ ".") ignoreTypePrefixes
    useStringType = replace "[Char]" "String"

requiredGlobalImports :: [String]
requiredGlobalImports =
  [ "import qualified Prelude as IHaskellPrelude"
  , "import qualified System.Directory as IHaskellDirectory"
#ifdef mingw32_HOST_OS
  , "import qualified System.Process as IHaskellProcess"
#else
  , "import qualified System.Posix.IO as IHaskellIO"
#endif
  , "import qualified System.IO as IHaskellSysIO"
  , "import qualified Language.Haskell.TH as IHaskellTH"
  ]

ihaskellGlobalImports :: [String]
ihaskellGlobalImports =
  [ "import IHaskell.Display()"
  , "import qualified IHaskell.Display"
  , "import qualified IHaskell.IPython.Stdin"
  , "import qualified IHaskell.Eval.Widgets"
#ifdef mingw32_HOST_OS
  , "import qualified IHaskell.Windows.IO as IHaskellIO"
#endif
  ]

hiddenPackageNames :: Set.Set String
hiddenPackageNames = Set.fromList ["ghc-lib", "ghc-lib-parser"]

#if MIN_VERSION_ghc(9,4,0)
packageIdString' :: UnitState -> UnitInfo -> String
packageIdString' unitState pkg_cfg =
    case (lookupUnit unitState $ mkUnit pkg_cfg) of
      Nothing -> "(unknown)"
      Just cfg -> let
        PackageName name = unitPackageName cfg
        in unpackFS name
#elif MIN_VERSION_ghc(9,2,0)
packageIdString' :: UnitState -> UnitInfo -> String
packageIdString' unitState pkg_cfg =
    case (lookupUnit unitState $ mkUnit pkg_cfg) of
      Nothing -> "(unknown)"
      Just cfg -> let
        PackageName name = unitPackageName cfg
        in unpackFS name
#elif MIN_VERSION_ghc(9,0,0)
packageIdString' :: DynFlags -> UnitInfo -> String
packageIdString' dflags pkg_cfg =
    case (lookupUnit (unitState dflags) $ mkUnit pkg_cfg) of
      Nothing -> "(unknown)"
      Just cfg -> let
        PackageName name = unitPackageName cfg
        in unpackFS name
#else
packageIdString' :: DynFlags -> PackageConfig -> String
packageIdString' dflags pkg_cfg =
    case (lookupPackage dflags $ packageConfigId pkg_cfg) of
      Nothing -> "(unknown)"
      Just cfg -> let
        PackageName name = packageName cfg
        in unpackFS name
#endif

#if MIN_VERSION_ghc(9,4,0)
getPackageConfigs :: Logger -> DynFlags -> HscEnv -> IO ([GenUnitInfo UnitId], UnitState)
getPackageConfigs logger dflags hsc_env = do
    (pkgDb, unitState, _, _) <- initUnits logger dflags Nothing (hsc_all_home_unit_ids hsc_env)
    pure (foldMap unitDatabaseUnits pkgDb, unitState)
#elif MIN_VERSION_ghc(9,2,0)
getPackageConfigs :: Logger -> DynFlags -> IO ([GenUnitInfo UnitId], UnitState)
getPackageConfigs logger dflags = do
    (pkgDb, unitState, _, _) <- initUnits logger dflags Nothing
    pure (foldMap unitDatabaseUnits pkgDb, unitState)
#elif MIN_VERSION_ghc(9,0,0)
getPackageConfigs :: DynFlags -> [GenUnitInfo UnitId]
getPackageConfigs dflags =
    foldMap unitDatabaseUnits pkgDb
  where
    Just pkgDb = unitDatabases dflags
#else
getPackageConfigs :: DynFlags -> [PackageConfig]
getPackageConfigs dflags =
    foldMap snd pkgDb
  where
    Just pkgDb = pkgDatabase dflags
#endif

#if MIN_VERSION_ghc(9,6,0)
getErrMsgDoc :: ErrUtils.Diagnostic e => ErrUtils.MsgEnvelope e -> SDoc
getErrMsgDoc = ErrUtils.pprLocMsgEnvelopeDefault
#elif MIN_VERSION_ghc(9,4,0)
getErrMsgDoc :: ErrUtils.Diagnostic e => ErrUtils.MsgEnvelope e -> SDoc
getErrMsgDoc = ErrUtils.pprLocMsgEnvelope
#elif MIN_VERSION_ghc(9,2,0)
getErrMsgDoc :: ErrUtils.WarnMsg -> SDoc
getErrMsgDoc = ErrUtils.pprLocMsgEnvelope
#else
getErrMsgDoc :: ErrUtils.ErrMsg -> SDoc
getErrMsgDoc = ErrUtils.pprLocErrMsg
#endif

#if MIN_VERSION_ghc(9,2,0)
objTarget :: DynFlags -> Backend
objTarget = platformDefaultBackend . targetPlatform
#elif MIN_VERSION_ghc(8,10,0)
objTarget :: DynFlags -> HscTarget
objTarget = defaultObjectTarget
#else
objTarget :: DynFlags -> HscTarget
objTarget flags = defaultObjectTarget $ targetPlatform flags
#endif
