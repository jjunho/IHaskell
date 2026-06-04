{-# LANGUAGE CPP #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

module IHaskell.Test.Properties (testProperties) where

import           Prelude

import           Test.Hspec
import           Test.Hspec.Core.Spec (Spec)

import           Data.Binary (Binary, encode, decode)
import qualified Data.Text as T

import qualified Hedgehog
import qualified Hedgehog.Gen as Gen
import qualified Hedgehog.Range as Range

import           IHaskell.Types (Display(..), DisplayData(..), MimeType(..))
import           IHaskell.Display (plain, html, latex, markdown, javascript, json, svg)

-- | Generators for IHaskell types.

-- | Generate a random MimeType.
genMimeType :: Hedgehog.Gen MimeType
genMimeType =
  Hedgehog.Gen.element
    [ PlainText, MimeHtml, MimeSvg, MimeLatex, MimeMarkdown
    , MimeJavascript, MimeJson, MimeVega, MimeVegalite, MimeVdom
    , MimePng 64 64, MimeJpg 64 64, MimeGif 64 64, MimeBmp 64 64
    ]

-- | Generate a random non-empty Text string.
genTextContent :: Hedgehog.Gen T.Text
genTextContent =
  Gen.text (Range.linear 1 200) Gen.latin1

-- | Generate a random DisplayData.
genDisplayData :: Hedgehog.Gen DisplayData
genDisplayData = do
  mime <- genMimeType
  content <- genTextContent
  return $ DisplayData mime content

-- | Generate a random Display (either simple or many).
genDisplay :: Hedgehog.Gen Display
genDisplay =
  Gen.recursive Gen.choice
    [ Display <$> Gen.list (Range.linear 0 5) genDisplayData ]
    [ ManyDisplay <$> Gen.list (Range.linear 0 3) genDisplay ]

-- | Property: Display serialization roundtrip.
prop_display_roundtrip :: Hedgehog.Property
prop_display_roundtrip = Hedgehog.property $ do
  display <- Hedgehog.forAll genDisplay
  let encoded = encode display
      decoded :: Display
      decoded = decode encoded
  decoded Hedgehog.=== display

-- | Property: Display serialization is idempotent.
prop_display_idempotent :: Hedgehog.Property
prop_display_idempotent = Hedgehog.property $ do
  display <- Hedgehog.forAll genDisplay
  let once  = encode display
      twice = encode (decode once :: Display)
  once Hedgehog.=== twice

-- | Property: Plain text DisplayData preserves content.
prop_plain_roundtrip :: Hedgehog.Property
prop_plain_roundtrip = Hedgehog.property $ do
  content <- Hedgehog.forAll $ Gen.text (Range.linear 0 500) Gen.latin1
  let dd = plain (T.unpack content)
      DisplayData PlainText t = dd
  t Hedgehog.=== content

-- | Register all property tests with Hspec.
testProperties :: Spec
testProperties = do
  describe "Property-based tests" $ do
    describe "Display serialization" $ do
      it "roundtrips through Binary encoding" $
        Hedgehog.property prop_display_roundtrip
      it "is idempotent" $
        Hedgehog.property prop_display_idempotent
    describe "Display constructors" $ do
      it "plain text preserves content" $
        Hedgehog.property prop_plain_roundtrip
