{-# LANGUAGE NoImplicitPrelude, DoAndIfThenElse, OverloadedStrings, ExtendedDefaultRules #-}
{-# LANGUAGE CPP #-}

module IHaskell.Test.Completion (testCompletions) where

import           Prelude

import           Data.List (elemIndex)
import           Data.Maybe (fromMaybe)
import qualified Data.Text as T
import           Control.Monad (when)
import           Control.Monad.IO.Class (liftIO)
import           System.Environment (setEnv, lookupEnv)
import           System.Directory (setCurrentDirectory, getCurrentDirectory, createDirectoryIfMissing,
                                    removeDirectoryRecursive, doesDirectoryExist)
import           System.FilePath ((</>), addTrailingPathSeparator)
import           Data.Unique (newUnique, hashUnique)
import           Control.Exception (bracket)

import           GHC (setContext, parseImportDecl, InteractiveImport(..))

import           Test.Hspec

import           IHaskell.Eval.Evaluate (Interpreter, liftIO)
import           IHaskell.IPython (getSandboxPackageConf)
import           IHaskell.Eval.Completion (complete, CompletionType(..), completionType,
                                           completionTarget)
import           IHaskell.Eval.Util (initGhci)
import           IHaskell.Test.Util (replace, shouldBeAmong, ghc)

-- | @readCompletePrompt "xs*ys"@ return @(xs, i)@ where i is the location of
-- @'*'@ in the input string.
readCompletePrompt :: String -> (String, Int)
readCompletePrompt string =
  case elemIndex '*' string of
    Nothing  -> error "Expected cursor written as '*'."
    Just idx -> (replace "*" "" string, idx)

completionEvent :: String -> Interpreter (String, [String])
completionEvent string = complete newString cursorloc
  where
    (newString, cursorloc) =
      case elemIndex '*' string of
        Nothing  -> error "Expected cursor written as '*'."
        Just idx -> (replace "*" "" string, idx)

completionEventInDirectory :: String -> IO (String, [String])
completionEventInDirectory string = withHsDirectory $ const $ completionEvent string

shouldHaveCompletionsInDirectory :: String -> [String] -> IO ()
shouldHaveCompletionsInDirectory string expected = do
  (_, completions) <- completionEventInDirectory string
  expected `shouldBeAmong` completions

completionHas :: String -> [String] -> IO ()
completionHas string expected = do
  (_, completions) <- ghc $ do
                              initCompleter
                              completionEvent string
  expected `shouldBeAmong` completions

initCompleter :: Interpreter ()
initCompleter = do
  sandboxPackages <- liftIO getSandboxPackageConf
  initGhci sandboxPackages
  -- Import modules.
  imports <- mapM parseImportDecl
               [ "import Prelude"
               , "import qualified Control.Monad"
               , "import qualified Data.List as List"
               , "import IHaskell.Display"
               , "import Data.Maybe as Maybe"
               ]
  setContext $ map IIDecl imports

completes :: String -> [String] -> IO ()
completes string expected = completionTarget newString cursorloc `shouldBe` expected
  where
    (newString, cursorloc) = readCompletePrompt string

testCompletions :: Spec
testCompletions = do
  testIdentifierCompletion
  testCommandCompletion

testIdentifierCompletion :: Spec
testIdentifierCompletion = describe "Completion" $ do
    it "correctly gets the completion identifier without dots" $ do
      "hello*" `completes` ["hello"]
      "hello aa*bb goodbye" `completes` ["aa"]
      "hello aabb* goodbye" `completes` ["aabb"]
      "aacc* goodbye" `completes` ["aacc"]
      "hello *aabb goodbye" `completes` []
      "*aabb goodbye" `completes` []

    it "correctly gets the completion identifier with dots" $ do
      "hello test.aa*bb goodbye" `completes` ["test", "aa"]
      "Test.*" `completes` ["Test", ""]
      "Test.Thing*" `completes` ["Test", "Thing"]
      "Test.Thing.*" `completes` ["Test", "Thing", ""]
      "Test.Thing.*nope" `completes` ["Test", "Thing", ""]

    it "correctly gets the completion type" $ do
      completionType "import Data." 12 ["Data", ""] `shouldBe` ModuleName "Data" ""
      completionType "import Prel" 11 ["Prel"] `shouldBe` ModuleName "" "Prel"
      completionType "import D.B.M" 12 ["D", "B", "M"] `shouldBe` ModuleName "D.B" "M"
      completionType " import A." 10 ["A", ""] `shouldBe` ModuleName "A" ""
      completionType "import a.x" 10 ["a", "x"] `shouldBe` Identifier "x"
      completionType "A.x" 3 ["A", "x"] `shouldBe` Qualified "A" "x"
      completionType "a.x" 3 ["a", "x"] `shouldBe` Identifier "x"
      completionType "pri" 3 ["pri"] `shouldBe` Identifier "pri"
      completionType ":load A" 7 ["A"] `shouldBe` HsFilePath ":load A" "A"
      completionType ":! cd " 6 [""] `shouldBe` FilePath ":! cd " ""



    it "properly completes identifiers" $ do
      "pri*" `completionHas` ["print"]
      "ma*" `completionHas` ["map"]
      "hello ma*" `completionHas` ["map"]
      "print $ catMa*" `completionHas` ["catMaybes"]

    it "properly completes qualified identifiers" $ do
      "Control.Monad.liftM*" `completionHas` [ "Control.Monad.liftM"
                                             , "Control.Monad.liftM2"
                                             , "Control.Monad.liftM5"
                                             ]
      "print $ List.intercal*" `completionHas` ["List.intercalate"]
      "print $ Data.Maybe.cat*" `completionHas` []
      "print $ Maybe.catM*" `completionHas` ["Maybe.catMaybes"]

    it "properly completes imports" $ do
      "import Data.*" `completionHas` ["Data.Maybe", "Data.List"]
      "import Data.M*" `completionHas` ["Data.Maybe"]
      "import Prel*" `completionHas` ["Prelude"]


testCommandCompletion :: Spec
testCommandCompletion = describe "Completes commands" $ do
  it "properly completes haskell file paths on :load directive" $ do
    let loading xs = ":load " ++ xs
        testInDirectory start comps = loading start `shouldHaveCompletionsInDirectory` id comps
    testInDirectory ("dir" </> "file*") ["dir" </> "file2.hs", "dir" </> "file2.lhs"]
    testInDirectory ("" </> "file1*") ["" </> "file1.hs", "" </> "file1.lhs"]
    testInDirectory ("" </> "file1*") ["" </> "file1.hs", "" </> "file1.lhs"]
    testInDirectory ("" </> "." </> "*") [addTrailingPathSeparator $ "." </> "dir", "." </> "file1.hs", "." </> "file1.lhs"]
    testInDirectory ("" </> "." </> "*") [addTrailingPathSeparator $ "." </> "dir", "." </> "file1.hs", "." </> "file1.lhs"]

  it "provides path completions on empty shell cmds " $
    ":! cd *" `shouldHaveCompletionsInDirectory` id
                                                   [ addTrailingPathSeparator $ "" </> "dir"
                                                   , "" </> "file1.hs"
                                                   , "" </> "file1.lhs"
                                                   ]

  let withHsHome action = withHsDirectory $ \dirPath -> do
        home <- liftIO $ lookupEnv "HOME"
        setHomeEvent dirPath
        result <- action
        setHomeEvent (fromMaybe "" home)
        return result
      setHomeEvent path = liftIO $ setEnv "HOME" path

  it "correctly interprets ~ as the environment HOME variable" $ do
    let tildeDir = addTrailingPathSeparator $ "~" </> "dir"

        shouldHaveCompletions :: String -> [String] -> IO ()
        shouldHaveCompletions string expected = do
          (_, completions) <- withHsHome $ completionEvent string

          expected `shouldBeAmong` completions
    (":! cd ~" </> "*") `shouldHaveCompletions` [tildeDir]
    (":! ~" </> "*") `shouldHaveCompletions` [tildeDir]
    (":load ~" </> "*") `shouldHaveCompletions` [tildeDir]
    (":l ~" </> "*") `shouldHaveCompletions` [tildeDir]

  let shouldHaveMatchingText :: String -> String -> IO ()
      shouldHaveMatchingText string expected = do
        matchText <- withHsHome $ fst <$> uncurry complete (readCompletePrompt string)
        matchText `shouldBe` expected

  it "generates the correct matchingText on `:! cd ~/*` " $
    ":! cd ~/*" `shouldHaveMatchingText` ("~/" :: String)

  it "generates the correct matchingText on `:load ~/*` " $
    ":load ~/*" `shouldHaveMatchingText` ("~/" :: String)

  it "generates the correct matchingText on `:l ~/*` " $
    ":l ~/*" `shouldHaveMatchingText` ("~/" :: String)

-- | Run an Interpreter action inside a temporary directory with some files.
inDirectory :: [FilePath] -- ^ directories relative to temporary directory
            -> [FilePath] -- ^ files relative to temporary directory
            -> (FilePath -> Interpreter a)
            -> IO a
inDirectory dirs files action = do
  u <- show . hashUnique <$> newUnique
  let tmpDir = "/tmp/ihaskell-test-" ++ u
  createDirectoryIfMissing True tmpDir
  bracket
    (return tmpDir)
    (\d -> doesDirectoryExist d >>= flip when (removeDirectoryRecursive d))
    (\dirPath -> do
      setCurrentDirectory dirPath
      mapM_ (createDirectoryIfMissing True) dirs
      mapM_ (\f -> writeFile f "") files
      ghc $ wrap dirPath (action dirPath))
  where
    wrap :: FilePath -> Interpreter a -> Interpreter a
    wrap path actn = do
      initCompleter
      pwd <- IHaskell.Eval.Evaluate.liftIO getCurrentDirectory
      IHaskell.Eval.Evaluate.liftIO $ setCurrentDirectory path
      out <- actn
      IHaskell.Eval.Evaluate.liftIO $ setCurrentDirectory pwd
      return out

withHsDirectory :: (FilePath -> Interpreter a) -> IO a
withHsDirectory = inDirectory ["dir", "dir" </> "dir1"]
                    ["file1.hs", "dir" </> "file2.hs", "file1.lhs", "dir" </> "file2.lhs"]
