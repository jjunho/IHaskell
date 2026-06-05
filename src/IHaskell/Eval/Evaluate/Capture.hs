{-# LANGUAGE NoImplicitPrelude #-}

-- | Pure functions for generating the Haskell source code used by
-- 'capturedEval' for stdout/stderr capture and IO redirection.
-- Extracted to this module so they can be unit-tested without a GHC session.
module IHaskell.Eval.Evaluate.Capture (
    generateVarName,
    voidpf,
    generateInitStmts,
    generatePostStmts,
    readChars,
    PollConfig(..),
    defaultPollConfig,
    pollingLoop,
    ) where

import           IHaskellPrelude

import           System.IO (hGetChar)
import           Control.Exception (try)
import           Control.Concurrent (threadDelay)
import           Control.Concurrent.STM (TVar, readTVarIO)

-- | Generate a unique variable name by appending a suffix.
generateVarName :: String -> String -> String
generateVarName suffix name = name ++ suffix

-- | Wrap a statement to return () via '>>'.  The argument must NOT contain
-- printf format specifiers (@%s@, @%d@, etc.); for those use 'printf' directly.
voidpf :: String -> String
voidpf str = printf $ str ++ " IHaskellPrelude.>> IHaskellPrelude.return ()"

-- | Generate the list of initialization statements for stdout/stderr capture.
-- The 'Bool' parameter is 'True' for Windows (@mingw32_HOST_OS@),
-- 'False' for POSIX.
generateInitStmts :: String   -- ^ Unique suffix for variable names
                  -> Bool     -- ^ True = Windows, False = POSIX
                  -> [String]
generateInitStmts suffix isWindows =
  let var = generateVarName suffix
      rv  = var "file_read_var_"
      wv  = var "file_write_var_"
      iv  = var "it_var_"
      ros = var "restore_stdout_var_"
      res = var "restore_stderr_var_"
      ostd= var "old_var_stdout_"
      oerr= var "old_var_stderr_"
      voidpfRet = voidpf  -- for lines WITHOUT %s
      fmtVoid s a = printf (s ++ " IHaskellPrelude.>> IHaskellPrelude.return ()") a
  in if isWindows
     then
       [ printf "let %s = it" iv
       , printf "(%s, %s) <- IHaskellProcess.createPipe" rv wv
       , printf "%s <- IHaskellIO.redirectHandle %s IHaskellSysIO.stdout" ros wv
       , printf "%s <- IHaskellIO.redirectHandle %s IHaskellSysIO.stderr" res wv
       , voidpfRet "IHaskellSysIO.hSetBuffering IHaskellSysIO.stdout IHaskellSysIO.NoBuffering"
       , voidpfRet "IHaskellSysIO.hSetBuffering IHaskellSysIO.stderr IHaskellSysIO.NoBuffering"
       , voidpfRet "IHaskellSysIO.hSetEncoding IHaskellSysIO.stdout IHaskellSysIO.utf8"
       , voidpfRet "IHaskellSysIO.hSetEncoding IHaskellSysIO.stderr IHaskellSysIO.utf8"
       , printf "let it = %s" iv
       ]
     else
       [ printf "let %s = it" iv
       , printf "(%s, %s) <- IHaskellIO.createPipe" rv wv
       , printf "%s <- IHaskellIO.dup IHaskellIO.stdOutput" ostd
       , printf "%s <- IHaskellIO.dup IHaskellIO.stdError" oerr
       , fmtVoid "IHaskellIO.dupTo %s IHaskellIO.stdOutput" wv
       , fmtVoid "IHaskellIO.dupTo %s IHaskellIO.stdError" wv
       , voidpfRet "IHaskellSysIO.hSetBuffering IHaskellSysIO.stdout IHaskellSysIO.NoBuffering"
       , voidpfRet "IHaskellSysIO.hSetBuffering IHaskellSysIO.stderr IHaskellSysIO.NoBuffering"
       , printf "let it = %s" iv
       ]

-- | Generate the list of cleanup statements for restoring stdout/stderr.
generatePostStmts :: String   -- ^ Unique suffix for variable names
                  -> Bool     -- ^ True = Windows, False = POSIX
                  -> [String]
generatePostStmts suffix isWindows =
  let var  = generateVarName suffix
      wv   = var "file_write_var_"
      iv   = var "it_var_"
      ros  = var "restore_stdout_var_"
      res  = var "restore_stderr_var_"
      ostd = var "old_var_stdout_"
      oerr = var "old_var_stderr_"
      voidpfRet = voidpf
      fmtVoid s a = printf (s ++ " IHaskellPrelude.>> IHaskellPrelude.return ()") a
  in if isWindows
     then
       [ printf "let %s = it" iv
       , voidpfRet "IHaskellSysIO.hFlush IHaskellSysIO.stdout"
       , voidpfRet "IHaskellSysIO.hFlush IHaskellSysIO.stderr"
       , fmtVoid "%s" ros
       , fmtVoid "%s" res
       , fmtVoid "IHaskellSysIO.hClose %s" wv
       , printf "let it = %s" iv
       ]
     else
       [ printf "let %s = it" iv
       , voidpfRet "IHaskellSysIO.hFlush IHaskellSysIO.stdout"
       , voidpfRet "IHaskellSysIO.hFlush IHaskellSysIO.stderr"
       , fmtVoid "IHaskellIO.dupTo %s IHaskellIO.stdOutput" ostd
       , fmtVoid "IHaskellIO.dupTo %s IHaskellIO.stdError" oerr
       , fmtVoid "IHaskellIO.closeFd %s" wv
       , printf "let it = %s" iv
       ]

-- | Read characters from a handle, stopping at delimiters or after @n@ chars.
readChars :: Handle -> String -> Int -> IO String
readChars _ _ 0 = return []
readChars hdl delims nchars = do
  tryRead <- try $ hGetChar hdl :: IO (Either SomeException Char)
  case tryRead of
    Right ch ->
      if ch `elem` delims
        then return [ch]
        else do
          next <- readChars hdl delims (nchars - 1)
          return $ ch : next
    Left _ -> return []

-- | Configuration for the output polling loop.
data PollConfig = PollConfig
  { pollDelay   :: Int  -- ^ Microseconds between polls (default: 100ms)
  , pollMaxSize :: Int  -- ^ Maximum output size to read on completion
  , pollIncSize :: Int  -- ^ Chunk size for intermediate reads
  }

-- | Default polling config: 100ms delay, 100KB max, 100-char chunks.
defaultPollConfig :: PollConfig
defaultPollConfig = PollConfig
  { pollDelay   = 100 * 1000
  , pollMaxSize = 100 * 1000
  , pollIncSize = 100
  }

-- | Run the output polling loop.  Reads chunks from a pipe until the
-- @completed@ 'TVar' is set to 'True', then reads remaining output and
-- signals via the @finishedReading@ 'MVar'.
pollingLoop :: PollConfig
            -> Handle              -- ^ Pipe to read from
            -> (String -> IO ())   -- ^ Callback for intermediate output
            -> TVar Bool           -- ^ Set 'True' when computation is done
            -> MVar Bool           -- ^ Signal when reading is finished
            -> MVar String         -- ^ Output accumulator
            -> IO ()
pollingLoop cfg pipe output completed finishedReading outputAccum = loop
  where
    loop = do
      threadDelay (pollDelay cfg)
      computationDone <- readTVarIO completed
      if not computationDone
        then do
          nextChunk <- readChars pipe "\n" (pollIncSize cfg)
          modifyMVar_ outputAccum (return . (++ nextChunk))
          readMVar outputAccum >>= output
          loop
        else do
          nextChunk <- readChars pipe "" (pollMaxSize cfg)
          modifyMVar_ outputAccum (return . (++ nextChunk))
          putMVar finishedReading True
