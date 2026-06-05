{-# LANGUAGE NoImplicitPrelude, OverloadedStrings #-}

-- | Display formatting utilities for evaluation results.
-- Separated into its own module so that both Evaluate.hs and Commands.hs
-- can use them without circular dependencies.
module IHaskell.Eval.Evaluate.Format (
    formatError,
    formatErrorWithClass,
    formatParseError,
    formatGetType,
    formatType,
    displayError,
    mono,
    ) where

import           IHaskellPrelude

import           IHaskell.Eval.Evaluate.Compat (typeCleaner)
import           IHaskell.CSS (ihaskellCSS)
import           IHaskell.Display
import           IHaskell.Eval.Parser (ErrMsg, StringLoc(..))
import           StringUtils (replace, rstrip)

formatError :: ErrMsg -> String
formatError = formatErrorWithClass "err-msg"

formatErrorWithClass :: String -> ErrMsg -> String
formatErrorWithClass cls =
  printf "<span class='%s'>%s</span>" cls .
  replace "\n" "<br/>" .
  fixDollarSigns .
  replace "<" "&lt;" .
  replace ">" "&gt;" .
  replace "&" "&amp;" .
  replace useDashV "" .
  replace "Ghci" "IHaskell" .
  replace "'interactive:" "'" .
  rstrip .
  typeCleaner
  where
    fixDollarSigns = replace "$" "<span>&dollar;</span>"
    useDashV = "\n    Use -v to see a list of the files searched for."

formatParseError :: StringLoc -> String -> ErrMsg
formatParseError (Loc ln col) =
  printf "Parse error (line %d, column %d): %s" ln col

formatGetType :: String -> String
formatGetType = printf "<span class='get-type'>%s</span>"

formatType :: String -> Display
formatType typeStr = Display [plain typeStr, html' (Just ihaskellCSS) $ formatGetType typeStr]

displayError :: ErrMsg -> Display
displayError msg = Display [plain . typeCleaner $ msg, html' (Just ihaskellCSS) $ formatError msg]

mono :: String -> String
mono = printf "<span class='mono'>%s</span>"
