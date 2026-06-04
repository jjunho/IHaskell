{-# LANGUAGE NoImplicitPrelude #-}

-- | Pure functions for generating the Haskell source code used by
-- 'capturedEval' for stdout/stderr capture and IO redirection.
-- Extracted to this module so they can be unit-tested without a GHC session.
module IHaskell.Eval.Evaluate.Capture (
    generateVarName,
    voidpf,
    generateInitStmts,
    generatePostStmts,
    ) where

import           IHaskellPrelude

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
