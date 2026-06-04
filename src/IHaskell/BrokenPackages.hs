{-# LANGUAGE NoImplicitPrelude, OverloadedStrings, FlexibleContexts #-}

module IHaskell.BrokenPackages (getBrokenPackages) where

import           IHaskellPrelude
import qualified Data.Text as T

import           System.Process (readProcessWithExitCode)

import           Text.Parsec
import           Text.Parsec.String

data BrokenPackage = BrokenPackage String [String]

instance Show BrokenPackage where
  show (BrokenPackage packageID _) = packageID

-- | Get a list of broken packages. This function internally shells out to @ghc-pkg@, and parses the
-- output in order to determine what packages are broken.
getBrokenPackages :: IO [String]
getBrokenPackages = do
  (_exitCode, _stdout, stderr) <- readProcessWithExitCode "ghc-pkg" ["check"] ""

  -- Get rid of extraneous things
  let rightStart str = "There are problems" `isPrefixOf` str ||
                       "  dependency" `isPrefixOf` str
      ghcPkgOutput = unlines . filter rightStart . lines $ stderr

  return $
    case parse (many check) "ghc-pkg output" ghcPkgOutput of
      Left _     -> []
      Right pkgs -> map show pkgs

check :: Parser BrokenPackage
check = string "There are problems in package "
        >> BrokenPackage <$> ident <* string ":\n" <*> many1 dependency

ident :: Parser String
ident = many (alphaNum <|> oneOf "-.")

dependency :: Parser String
dependency = string "  dependency \"" *> ident <* string "\" doesn't exist\n"
