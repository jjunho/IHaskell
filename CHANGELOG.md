# Changelog

All notable changes to the Haskell-jjunho IHaskell fork are documented here.

## [Unreleased]

### Added
- `history_request` support: in-memory history storage, 500 entry limit
- `is_complete_request` support: GHC parser-based (parserModule + heuristics)
- `interrupt_request` support: SIGINT via control channel (POSIX)
- Hedgehog property tests: Display serialization roundtrip, idempotence, plain text
- Structured logging: `LogLevel` ADT (Error/Warn/Info/Debug)
- `IHaskell.Eval.Evaluate.Capture` module: pure statement generators + readChars + pollingLoop
- `IHaskell.Eval.Evaluate.Compat` module: GHC API compatibility shims
- `IHaskell.Eval.Evaluate.Format` module: formatting utilities
- `IHaskell.Eval.Evaluate.Commands` module: EvalOut, safely, doLoadModule, doReload
- `IHaskell.Eval.Util.Ppr` module: pretty-printing (pprDynFlags, pprLanguages, doc)
- 26 new tests (Capture generators + readChars + pollingLoop IO + properties)
- 4 Hoogle tests now run via conditional CPP in test-suite
- `CONTRIBUTING.md` with development guide

### Changed
- Global channels (`displayChan`, `widgetMessages`) → `IORef (TChan)` pattern
- `capturedEval` refactored: pure functions extracted, shortened 170→50 lines
- `publishResult` moved from `IHaskell.Publish` to `IHaskell.Display`
- `Publish.hs` deleted (94 lines, single function, single caller)
- `Util.hs` pretty-printing moved to `Util.Ppr`
- `publishResult` inlined into `Display.hs`
- STM replaces MVar for completion flag in capturedEval
- Evaluate.hs decomposed from 1673→1221 lines
- Kernel name: `haskell-jjunho`, display name: `Haskell-jjunho`
- Cabal version: 1.16 → 3.4 (common stanzas, proper bounds)
- cabal homepage, author, maintainer, source-repo → jjunho fork
- README.md rewritten with badges, TOC, feature tables, protocol status
- Test count: 76 → 102 (26 new, Hoogle now runs)

### Removed
- `shelly` dependency (18 ops → System.Directory/System.Process)
- `random` dependency (→ Data.Unique from base)
- `strict` dependency (unused)
- `setenv` dependency (→ System.Environment.setEnv from base)
- `Publish.hs` module (inlined into Display.hs)
- `Format.hs` shallow module (re-merged into Evaluate.hs split)

### Fixed
- MVar deadlock in kernel message loop (gcatch around takeMVar/putMVar)
- randomRs never advanced StdGen (Data.Unique instead)
- 9 `error` calls that crashed kernel (→ Either/displayError)
- GHC parser `Failure`/`Parsed` name collisions (qualified imports)
- kernelHistory unbounded growth (capped at 1000 entries)
- `raiseSignal` for Windows (guarded with #ifndef)
- `getSessionDynFlags` import only on Windows (moved outside #ifdef)
- `inputToReview` type mismatch (String, not Text)
