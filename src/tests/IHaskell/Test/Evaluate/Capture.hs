{-# LANGUAGE CPP #-}
module IHaskell.Test.Evaluate.Capture (testCapture) where

import           Prelude

import           Test.Hspec
import           Data.List (isInfixOf)

import           IHaskell.Eval.Evaluate.Capture
                   (generateVarName, voidpf, generateInitStmts, generatePostStmts,
                    readChars, PollConfig(..), defaultPollConfig, pollingLoop)

testCapture :: Spec
testCapture = describe "IHaskell.Eval.Evaluate.Capture" $ do

  describe "generateVarName" $ do
    it "appends suffix to name" $
      generateVarName "42" "file_read_var_" `shouldBe` "file_read_var_42"
    it "works with empty suffix" $
      generateVarName "" "foo" `shouldBe` "foo"
    it "works with empty name" $
      generateVarName "suffix" "" `shouldBe` "suffix"

  describe "voidpf" $ do
    it "wraps a statement with >> return ()" $
      voidpf "someAction" `shouldBe` "someAction IHaskellPrelude.>> IHaskellPrelude.return ()"
    it "works with empty string" $
      voidpf "" `shouldBe` " IHaskellPrelude.>> IHaskellPrelude.return ()"

  describe "generateInitStmts" $ do
    let posix = generateInitStmts "42" False
        win   = generateInitStmts "42" True

    it "generates 9 POSIX init statements" $
      length posix `shouldBe` 9

    it "generates 9 Windows init statements" $
      length win `shouldBe` 9

    it "uses IHaskellIO.createPipe for POSIX" $
      posix !! 1 `shouldContain` "IHaskellIO.createPipe"

    it "uses IHaskellProcess.createPipe for Windows" $
      win !! 1 `shouldContain` "IHaskellProcess.createPipe"

    it "uses dup for POSIX" $
      posix !! 2 `shouldContain` "dup"

    it "uses redirectHandle for Windows" $
      win !! 2 `shouldContain` "redirectHandle"

    it "includes it_var suffix" $ do
      head posix `shouldBe` "let it_var_42 = it"
      head win   `shouldBe` "let it_var_42 = it"

  describe "generatePostStmts" $ do
    let posix = generatePostStmts "42" False
        win   = generatePostStmts "42" True

    it "generates 7 POSIX post statements" $
      length posix `shouldBe` 7

    it "generates 7 Windows post statements" $
      length win `shouldBe` 7

    it "uses closeFd for POSIX" $
      any ("closeFd" `isInfixOf`) posix `shouldBe` True

    it "uses hClose for Windows" $
      any ("hClose" `isInfixOf`) win `shouldBe` True

    it "ends with let it = it_var" $
      last posix `shouldBe` "let it = it_var_42"
