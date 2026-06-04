{-# LANGUAGE CPP, NoImplicitPrelude #-}

-- | Helpers for command evaluation: exception-safe wrappers, module loading,
-- module reloading, and the result type.
module IHaskell.Eval.Evaluate.Commands (
    EvalOut(..),
    safely,
    wrapExecution,
    doLoadModule,
    doReload,
    moduleUnloadHandler,
#ifdef USE_HOOGLE
    hoogleResults,
#endif
    ) where

import           IHaskellPrelude

import           Data.IORef (newIORef, modifyIORef', readIORef)

#if MIN_VERSION_ghc(9,4,0)
import qualified GHC.Runtime.Debugger as Debugger
import           GHC.Runtime.Eval
import           GHC.Driver.Session
import           GHC.Unit.State
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

import           GHC hiding (Stmt, TypeSig)

import           IHaskell.Eval.Evaluate.Compat
import           IHaskell.Eval.Evaluate.Format
import           IHaskell.CSS (ihaskellCSS)
import           IHaskell.Types
import           IHaskell.Display
import           IHaskell.Eval.Util
import           StringUtils (replace)

#ifdef USE_HOOGLE
import qualified IHaskell.Eval.Hoogle as Hoogle
#endif

-- | Output of a command evaluation.
data EvalOut =
       EvalOut
         { evalStatus :: ErrorOccurred
         , evalResult :: Display
         , evalState :: KernelState
         , evalPager :: [DisplayData]
         , evalMsgs :: [WidgetMsg]
         }

-- | Exception-safe evaluation wrapper.
safely :: KernelState -> Interpreter EvalOut -> Interpreter EvalOut
safely state = ghandle handler . ghandle sourceErrorHandler
  where
    handler :: SomeException -> Interpreter EvalOut
    handler exception =
      return EvalOut { evalStatus = Failure, evalResult = displayError $ show exception
                     , evalState = state, evalPager = [], evalMsgs = [] }
    sourceErrorHandler :: SourceError -> Interpreter EvalOut
    sourceErrorHandler srcerr = do
      let msgs = bagToList . getMessages $ srcErrorMessages srcerr
      errStrs <- forM msgs $ doc . getErrMsgDoc
      let fullErr = unlines errStrs
      return EvalOut { evalStatus = Failure, evalResult = displayError fullErr
                     , evalState = state, evalPager = [], evalMsgs = [] }

-- | Run a display-producing action with exception safety.
wrapExecution :: KernelState -> Interpreter Display -> Interpreter EvalOut
wrapExecution state exec = safely state $
  exec >>= \res ->
    return EvalOut { evalStatus = Success, evalResult = res
                   , evalState = state, evalPager = [], evalMsgs = [] }

#ifdef USE_HOOGLE
-- | Hoogle search results as an EvalOut.
hoogleResults :: KernelState -> [Hoogle.HoogleResult] -> EvalOut
hoogleResults state results =
  EvalOut { evalStatus = Success, evalResult = mempty, evalState = state
          , evalPager = [ plain $ unlines $ map (Hoogle.render Hoogle.Plain) results
                        , html' (Just ihaskellCSS) $ unlines $ map (Hoogle.render Hoogle.HTML) results
                        ]
          , evalMsgs = [] }
#endif

-- | Shared exception handler for module load/reload failures.
moduleUnloadHandler :: String -> [InteractiveImport] -> SomeException -> Ghc Display
moduleUnloadHandler actionName imported exception = do
  print $ show exception
  setTargets []
  _ <- load LoadAllTargets
  flags <- getSessionDynFlags
#if MIN_VERSION_ghc(9,6,0)
  _ <- setSessionDynFlags flags { backend = interpreterBackend }
#elif MIN_VERSION_ghc(9,2,0)
  _ <- setSessionDynFlags flags { backend = Interpreter }
#else
  _ <- setSessionDynFlags flags { hscTarget = HscInterpreted }
#endif
  setContext imported
  initializeItVariable
  return $ displayError $ "Failed to " ++ actionName ++ ": " ++ show exception

-- | Load a module from source and add it to the GHC context.
doLoadModule :: String -> String -> Ghc Display
doLoadModule name modName = do
  importedModules <- getContext
  flip gcatch (moduleUnloadHandler ("load module " ++ modName) importedModules) $ do
    flags <- getSessionDynFlags
    errRef <- liftIO $ newIORef []
    let logAction = \_lflags _msgclass _srcspan msg -> modifyIORef' errRef (showSDoc flags msg :)
    pushLogHookM (const logAction)
    _ <- setSessionDynFlags $ flip gopt_set Opt_BuildDynamicToo flags { backend = objTarget flags }
    target <- guessTarget name Nothing Nothing
    oldTargets <- getTargets
    addTarget target
    getTargets >>= return . nubBy ((==) `on` targetId) >>= setTargets
    result <- load LoadAllTargets
    initializeItVariable
    case result of Failed -> setTargets oldTargets; Succeeded{} -> return ()
    setContext $ case result of
                   Failed -> importedModules
                   Succeeded -> IIDecl (simpleImportDecl $ mkModuleName modName) : importedModules
    _ <- setSessionDynFlags flags
    popLogHookM
    case result of
      Succeeded -> return mempty
      Failed -> do
        errorStrs <- unlines <$> reverse <$> liftIO (readIORef errRef)
        return $ displayError $ "Failed to load module " ++ modName ++ "\n" ++ errorStrs

-- | Reload all modules.
doReload :: Ghc Display
doReload = do
  importedModules <- getContext
  flip gcatch (moduleUnloadHandler "reload" importedModules) $ do
    flags <- getSessionDynFlags
    errRef <- liftIO $ newIORef []
    let logAction = \_lflags _msgclass _srcspan msg -> modifyIORef' errRef (showSDoc flags msg :)
    _ <- setSessionDynFlags $ flip gopt_set Opt_BuildDynamicToo flags { backend = objTarget flags }
    pushLogHookM (const logAction)
    oldTargets <- getTargets
    result <- load LoadAllTargets
    popLogHookM
    initializeItVariable
    case result of Failed -> setTargets oldTargets; Succeeded{} -> return ()
    setContext importedModules
    _ <- setSessionDynFlags flags
    case result of
      Succeeded -> return mempty
      Failed -> do
        errorStrs <- unlines <$> reverse <$> liftIO (readIORef errRef)
        return $ displayError $ "Failed to reload.\n" ++ errorStrs