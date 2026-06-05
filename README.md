![IHaskell](https://i.imgur.com/qhXXFbA.png)

# IHaskell — Haskell-jjunho Kernel

IHaskell is a kernel for the [Jupyter project](https://jupyter.org), which allows you to use Haskell inside Jupyter frontends (including the console and notebook). It currently supports GHC 8.4 through 9.14 (inclusive).

This is a fork with extensive improvements — bug fixes, dependency cleanup, architecture refactoring, Jupyter protocol compliance, and SOTA Haskell practices.

## Features

- **Rich output**: Display HTML, SVG, PNG, JPG, GIF, LaTeX, Markdown, JavaScript, JSON, Vega/Vega-Lite, VDoms
- **Charts & Diagrams**: Via `ihaskell-charts`, `ihaskell-diagrams`, `ihaskell-gnuplot`, `ihaskell-plot`
- **Widgets**: Interactive Jupyter widgets via `ihaskell-widgets`
- **Hoogle**: Online type/documentation search (`:hoogle`, `:doc`)
- **HLint**: Integrated linting (`:lint`)
- **Tab completion**: Identifiers, modules, file paths, GHC extensions
- **Jupyter Protocol v5.0**: Full support for execute, complete, inspect, history, is_complete, comm, interrupt
- **Structured logging**: Configurable log levels (`--debug`, `LogLevel`)

## Kernel Identity

- **Kernel name**: `haskell-jjunho`
- **Display name**: `Haskell-jjunho`
- **Protocol version**: 5.0

## Installation

### Prerequisites

Install Haskell via [ghcup](https://www.haskell.org/ghcup/install/).

System dependencies:
| OS | Command |
|----|---------|
| **macOS** | `brew install python3 zeromq libmagic cairo pkg-config pango` |
| **Linux** | `sudo apt-get install -y python3-pip git libtinfo-dev libzmq3-dev libcairo2-dev libpango1.0-dev libmagic-dev libblas-dev liblapack-dev` |
| **Windows** (MSYS2) | `pacman -S mingw-w64-clang-x86_64-zeromq mingw-w64-clang-x86_64-cairo mingw-w64-clang-x86_64-pango` |

Python:
```bash
pip3 install jupyter
```

### Cabal (recommended)

```bash
git clone https://github.com/jjunho/IHaskell
cd IHaskell
cabal build
cabal exec ihaskell install
```

Then start Jupyter:
```bash
jupyter notebook
# or
jupyter-lab
```

The kernel "Haskell-jjunho" will appear in the kernel selector.

### Building Display Packages (optional, for rich output)

```bash
cabal build ihaskell-blaze    # HTML rendering via Blaze
cabal build ihaskell-diagrams # Diagrams (Cairo backend)
cabal build ihaskell-charts   # Charts (Cairo backend)
cabal build ihaskell-widgets  # Interactive widgets
```

### Stack

```bash
stack install --fast
stack exec ihaskell install --stack
jupyter notebook
```

> Note: Display packages require the `stack.yaml` to list them. Prefer cabal for full display support.

### Docker

```bash
docker build -t ihaskell:latest .
docker run --rm -p 8888:8888 ihaskell:latest
```

Or use the [Docker Hub image](https://hub.docker.com/r/gibiansky/ihaskell):
```bash
docker run --rm -p 8888:8888 gibiansky/ihaskell
```

### Nix

```bash
nix build
# or with display modules:
nix build .#ihaskell-env-display-ghc98
```

## Usage

Start Jupyter and select the "Haskell-jjunho" kernel. Enter Haskell code in cells:

```haskell
-- Simple expressions
3 + 5

-- Multi-line
let x = 10
    y = 20
in x + y

-- Rich display
:extension OverloadedStrings
import IHaskell.Display
html "<b>Hello!</b>"
```

### Directives

| Command | Description |
|---------|-------------|
| `:type <expr>` | Show expression type |
| `:kind <type>` | Show kind |
| `:info <name>` | Show identifier info |
| `:hoogle <query>` | Search Hoogle online |
| `:doc <ident>` | Get Hoogle documentation |
| `:set -XFlag` | Enable GHC extension |
| `:extension <Ext>` | Shortcut for `:set -XExt` |
| `:option <opt>` | Set kernel option (lint/svg/pager) |
| `:load <file>` | Load Haskell module |
| `:module [+/-]Mod` | Import/unimport module |
| `:reload` | Reload modules |
| `:sprint <val>` | Print without evaluation |
| `:! <cmd>` | Execute shell command |
| `:?`, `:help` | Show help |

### Kernel Options

Set via `:option`:

| Option | Description |
|--------|-------------|
| `lint` / `no-lint` | Enable/disable HLint |
| `svg` / `no-svg` | Enable/disable SVG output |
| `show-types` / `no-show-types` | Show types of bound names |
| `pager` / `no-pager` | Use pager for `:info`/`:hoogle` |

## Development

### Build

```bash
cabal build           # build all
cabal test            # run tests (99 test cases)
cabal build ihaskell  # build executable only
```

### Test Suite

| Module | Tests | What it covers |
|--------|-------|----------------|
| `Test/Parser.hs` | 44 | Code block parsing (expr, stmt, decl, import, directive, pragma) |
| `Test/Eval.hs` | 16 | Haskell evaluation (expressions, types, kinds, directives) |
| `Test/Completion.hs` | 12 | Tab completion (identifiers, qualified, modules, file paths) |
| `Test/Properties.hs` | 3 × 100 | Hedgehog property tests (serialization roundtrip) |
| `Test/Evaluate/Capture.hs` | 23 | Capture functions, readChars, polling loop |
| `Test/Hoogle.hs` | 4 | Hoogle JSON response parsing |

### Project Structure

```
src/IHaskell/
├── Display.hs               — Display constructors + publishResult
├── Types.hs                 — Core types (KernelState, Display, Widget, LogLevel)
├── IPython.hs               — Kernel spec installation
├── Flags.hs                 — CLI argument parsing
├── Eval/
│   ├── Evaluate.hs          — Main evaluation orchestrator
│   ├── Evaluate/
│   │   ├── Compat.hs        — GHC API compatibility shims
│   │   ├── Capture.hs       — Pure capture functions (readChars, pollingLoop)
│   │   ├── Commands.hs      — Command evaluation helpers
│   │   ├── Format.hs        — Display formatting
│   │   └── HTML.hs          — HTML syntax highlighting
│   ├── Parser.hs            — Code block parsing
│   ├── Completion.hs        — Tab completion
│   ├── Util.hs              — GHC utilities
│   ├── Util/Ppr.hs          — Pretty-printing (pprDynFlags, pprLanguages, doc)
│   └── Widgets.hs           — Widget message handling
├── Publish.hs               — (removed, inlined into Display.hs)
└── ...
```

### Jupyter Protocol Status

| Message | Status |
|---------|--------|
| `kernel_info_request` | ✅ Complete |
| `execute_request` | ✅ Complete |
| `complete_request` | ✅ Complete |
| `inspect_request` | ✅ Complete |
| `is_complete_request` | ✅ GHC parser-based |
| `history_request` | ✅ In-memory (500 entries) |
| `comm_info_request` | ✅ Complete |
| `comm_open/msg/close` | ✅ Complete |
| `shutdown_request` | ✅ Complete |
| `interrupt_request` | ✅ Via SIGINT |
| `debug_request` | ❌ Not implemented |

## Improvements Over Upstream

### Bug Fixes
- **MVar deadlock**: Kernel no longer deadlocks on exception during evaluation
- **Random variable names**: Uses `Data.Unique` instead of `System.Random` (StdGen never advanced)
- **`error` calls**: 9 crash-causing `error` calls replaced with `Either`/`displayError`
- **`ghc-parser` types**: Qualified imports prevent name collisions

### Dependencies Removed
- `shelly` — replaced with `System.Directory`/`System.Process`
- `random` — replaced with `Data.Unique`
- `strict` — was unused except as re-export
- `setenv` — already in `base`

### Architecture
- **Evaluate.hs** decomposed into Compat, Capture, Format, Commands modules
- **Global channels** (`displayChan`, `widgetMessages`) replaced with `IORef` pattern
- **capturedEval** refactored into testable pure functions + polling loop
- **`Util.hs`** pretty-printing extracted into `Util/Ppr.hs`
- **`Publish.hs`** inlined into `Display.hs`
- **STM** replaces MVar for completion flag in IO capture
- **Structured logging** with `LogLevel` (Error/Warn/Info/Debug)
- **Cabal 3.4** with common stanzas

### Testing
- 99 test cases (up from 76)
- New property tests: Display serialization roundtrip, idempotence, plain text
- New tests for capture functions: `generateInitStmts`, `generatePostStmts`, `readChars`, `pollingLoop`

## License

MIT — see [LICENSE](./LICENSE).
