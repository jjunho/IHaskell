{-# LANGUAGE NoImplicitPrelude, DoAndIfThenElse, OverloadedStrings, ExtendedDefaultRules #-}

-- | Description : Shell scripting wrapper for the @notebook@ and @console@
--                 commands.  Uses standard @base@ libraries (@System.Directory@,
--                 @System.Process@, @System.Environment@) instead of @Shelly@.
module IHaskell.IPython (
    replaceIPythonKernelspec,
    defaultConfFile,
    getIHaskellDir,
    getSandboxPackageConf,
    subHome,
    KernelSpecOptions(..),
    defaultKernelSpecOptions,
    installLabextension,
    ) where

import qualified Data.Text as T
import qualified Data.Text.Lazy as LT
import           IHaskellPrelude

import qualified System.IO as IO
import qualified System.FilePath as FP
import           System.Directory
import           System.Environment (getExecutablePath, lookupEnv)
import           System.Directory (findExecutable)
import           System.Exit (exitFailure, ExitCode(..))
import           System.Process (readProcess, readProcessWithExitCode)
import           System.IO (hPutStrLn)
import           Data.Aeson (toJSON)
import           Data.Aeson.Text (encodeToTextBuilder)
import           Data.Text.Lazy.Builder (toLazyText)
import           Data.Unique (newUnique, hashUnique)

import qualified Paths_ihaskell as Paths

import qualified GHC.Paths
import           IHaskell.Types

import           Control.Exception (bracket)
import           System.Directory (getTemporaryDirectory)
import           StringUtils (replace, split)

data KernelSpecOptions =
       KernelSpecOptions
         { kernelSpecGhcLibdir :: String                  -- ^ GHC libdir.
         , kernelSpecRTSOptions :: [String]               -- ^ Runtime options to use.
         , kernelSpecDebug :: Bool                        -- ^ Spew debugging output?
         , kernelSpecCodeMirror :: String                 -- ^ CodeMirror mode
         , kernelSpecHtmlCodeWrapperClass :: Maybe String -- ^ HTML output: class name for wrapper div
         , kernelSpecHtmlCodeTokenPrefix :: String        -- ^ HTML output: class name prefix for token spans
         , kernelSpecConfFile :: IO (Maybe String)        -- ^ Filename of profile JSON file.
         , kernelSpecInstallPrefix :: Maybe String
         , kernelSpecUseStack :: Bool                     -- ^ Whether to use @stack@ environments.
         , kernelSpecStackFlags :: [String]               -- ^ Extra flags to pass to @stack@.
         , kernelSpecEnvFile :: Maybe FilePath
         , kernelSpecKernelName :: String                 -- ^ The IPython kernel name
         , kernelSpecDisplayName :: String                -- ^ The IPython kernel display name
         }

defaultKernelSpecOptions :: KernelSpecOptions
defaultKernelSpecOptions = KernelSpecOptions
  { kernelSpecGhcLibdir = GHC.Paths.libdir
  , kernelSpecRTSOptions = ["-M3g", "-N2"]  -- Memory cap 3 GiB,
                                            -- multithreading on two processors.
  , kernelSpecDebug = False
  , kernelSpecCodeMirror = "ihaskell"
  , kernelSpecHtmlCodeWrapperClass = Just "CodeMirror cm-s-jupyter cm-s-ipython"
  , kernelSpecHtmlCodeTokenPrefix = "cm-"
  , kernelSpecConfFile = defaultConfFile
  , kernelSpecInstallPrefix = Nothing
  , kernelSpecUseStack = False
  , kernelSpecStackFlags = []
  , kernelSpecEnvFile = Nothing
  , kernelSpecKernelName = "haskell-jjunho"
  , kernelSpecDisplayName = "Haskell-jjunho"
  }

-- | Resolve the Jupyter binary, falling back to IPython.
locateJupyter :: IO FilePath
locateJupyter = do
  jupyterMay <- findExecutable "jupyter"
  case jupyterMay of
    Just j  -> return j
    Nothing -> do
      ipythonMay <- findExecutable "ipython"
      case ipythonMay of
        Just j  -> return j
        Nothing -> do
          hPutStrLn IO.stderr "No Jupyter / IPython detected -- install Jupyter 3.0+ before using IHaskell."
          exitFailure

-- | Verify that a proper version of IPython is installed and accessible.
verifyIPythonVersion :: IO ()
verifyIPythonVersion = void locateJupyter

-- | Create the directory and return it.
ensure :: FilePath -> IO FilePath
ensure dir = do
  createDirectoryIfMissing True dir
  return dir

-- | Return the data directory for IHaskell.
ihaskellDir :: IO FilePath
ihaskellDir = do
  home <- maybe (error "$HOME not defined.") id <$> lookupEnv "HOME"
  ensure (home FP.</> ".ihaskell")

getIHaskellDir :: IO String
getIHaskellDir = ihaskellDir

defaultConfFile :: IO (Maybe String)
defaultConfFile = do
  dir <- ihaskellDir
  let filename = dir FP.</> "rc.hs"
  exists <- doesFileExist filename
  return $ if exists then Just filename else Nothing

replaceIPythonKernelspec :: KernelSpecOptions -> IO ()
replaceIPythonKernelspec kernelSpecOpts = do
  verifyIPythonVersion
  installKernelspec True kernelSpecOpts

-- | Install an IHaskell kernelspec into the right location. The right location is determined by
-- using `ipython kernelspec install --user`.
installKernelspec :: Bool -> KernelSpecOptions -> IO ()
installKernelspec repl opts = do
  ihaskellPath <- getIHaskellPath
  confFile <- kernelSpecConfFile opts

  let kernelName = kernelSpecKernelName opts

  let kernelFlags :: [String]
      kernelFlags =
        ["--debug" | kernelSpecDebug opts] ++
        (case confFile of
           Nothing   -> []
           Just file -> ["--conf", file])
        ++ ["--ghclib", kernelSpecGhcLibdir opts]
        ++ (case kernelSpecRTSOptions opts of
             [] -> []
             _ -> "+RTS" : kernelSpecRTSOptions opts ++ ["-RTS"])
           ++ ["--stack" | kernelSpecUseStack opts]
           ++ mconcat [["--stack-flag", f] | f <- kernelSpecStackFlags opts]

  let kernelSpec = KernelSpec
        { kernelDisplayName = kernelSpecDisplayName opts
        , kernelLanguage = kernelName
        , kernelCommand = [ihaskellPath, "kernel", "{connection_file}"] ++ kernelFlags
        }

  -- Create a temporary directory. Use this temporary directory to make a kernelspec directory; then,
  -- shell out to IPython to install this kernelspec directory.
  withTempDir $ \tmp -> do
    let kernelDir = tmp FP.</> kernelName
    let jsonFile = kernelDir FP.</> "kernel.json"

    createDirectoryIfMissing True kernelDir
    writeFile jsonFile $ T.unpack $ LT.toStrict $ toLazyText $ encodeToTextBuilder $ toJSON kernelSpec
    let files = ["kernel.js", "logo-64x64.svg"]
    forM_ files $ \file -> do
      src <- Paths.getDataFileName $ "html/" ++ file
      copyFile src (kernelDir FP.</> file)

    let replaceFlag = if repl then ["--replace"] else []
        installPrefixFlag = maybe ["--user"] (\prefix -> ["--prefix", prefix]) (kernelSpecInstallPrefix opts)
        cmd = concat [["kernelspec", "install"], installPrefixFlag, [kernelDir], replaceFlag]

    jupyter <- locateJupyter
    (exitCode, stdout, stderr) <- readProcessWithExitCode jupyter cmd ""
    when (kernelSpecDebug opts) $ hPutStrLn IO.stdout (stdout ++ stderr)
    case exitCode of
      ExitSuccess -> return ()
      ExitFailure _ -> hPutStrLn IO.stderr $ jupyter ++ " kernelspec install failed: " ++ stderr

installLabextension :: Bool -> IO ()
installLabextension debug = do
  -- Find the prebuilt extension directory
  ihaskellDataDir <- Paths.getDataDir
  let labextensionDataDir = ihaskellDataDir
        FP.</> "jupyterlab-ihaskell"
        FP.</> "labextension"

  -- Find the $(jupyter --data-dir)/labextensions/jupyterlab-ihaskell directory
  jupyter <- locateJupyter
  jupyterDataDir <- T.strip . T.pack <$> readProcess jupyter ["--data-dir"] ""
  let jupyterlabIHaskellDir = T.unpack jupyterDataDir
        FP.</> "labextensions"
        FP.</> "jupyterlab-ihaskell"

  when debug (putStrLn $ "Installing kernel in folder: " ++ show jupyterlabIHaskellDir)
  -- Remove the extension directory with extreme prejudice if it already exists
  dirExists <- doesDirectoryExist jupyterlabIHaskellDir
  when dirExists $ removeDirectoryRecursive jupyterlabIHaskellDir
  -- Create an empty 'jupyterlab-ihaskell' directory to install our extension in
  createDirectoryIfMissing True jupyterlabIHaskellDir
  -- Copy the prebuilt extension files over
  extensionContents <- listDirectory labextensionDataDir
  forM_ extensionContents $ \entry ->
    cpRecursive (labextensionDataDir FP.</> entry) (jupyterlabIHaskellDir FP.</> entry)

-- | Replace "~" with $HOME if $HOME is defined. Otherwise, do nothing.
subHome :: String -> IO String
subHome path = do
  home <- fromMaybe "~" <$> lookupEnv "HOME"
  return $ replace "~" home path

-- | Get the absolute path to this IHaskell executable.
getIHaskellPath :: IO FilePath
getIHaskellPath = do
  -- Get the absolute filepath to the argument.
  f <- getExecutablePath

  -- If we have an absolute path, that's the IHaskell we're interested in.
  if FP.isAbsolute f
    then return f
    else
    -- Check whether this is a relative path, or just 'IHaskell' with $PATH resolution done by
    -- the shell. If it's just 'IHaskell', use the $PATH variable to find where IHaskell lives.
    if FP.takeFileName f == f
      then do
        ihaskellPath <- findExecutable "ihaskell"
        case ihaskellPath of
          Nothing   -> error "ihaskell not on $PATH and not referenced relative to directory."
          Just path -> return path
      else makeAbsolute f

getSandboxPackageConf :: IO (Maybe String)
getSandboxPackageConf = do
  myPath <- getIHaskellPath
  let sandboxName = ".cabal-sandbox"
  if not $ sandboxName `isInfixOf` myPath
    then return Nothing
    else do
      let pieces = split "/" myPath
          sandboxDir = intercalate "/" $ takeWhile (/= sandboxName) pieces ++ [sandboxName]
      subdirs <- filter (isSuffixOf ("packages.conf.d" :: String)) <$> listDirectory sandboxDir
      case subdirs of
        [] -> return Nothing
        dir:_ -> return $ Just dir

-- | Copy a file or directory recursively (replaces @shelly@'s @cp_r@).
cpRecursive :: FilePath -> FilePath -> IO ()
cpRecursive src dst = do
  isDir <- doesDirectoryExist src
  if isDir
    then do
      createDirectoryIfMissing True dst
      entries <- listDirectory src
      forM_ entries $ \entry ->
        cpRecursive (src FP.</> entry) (dst FP.</> entry)
    else copyFile src dst

-- | Create a temporary directory with a unique name and run an action with it.
-- The directory is removed after the action completes (or on exception).
-- Uses 'bracket' for exception safety, so no temp directories leak.
withTempDir :: (FilePath -> IO a) -> IO a
withTempDir action = do
  tmpRoot <- getTemporaryDirectory
  u <- show . hashUnique <$> newUnique
  let tmpDir = tmpRoot FP.</> "ihaskell-" ++ u
  createDirectory tmpDir
  bracket
    (return tmpDir)
    (\d -> doesDirectoryExist d >>= flip when (removeDirectoryRecursive d))
    action
