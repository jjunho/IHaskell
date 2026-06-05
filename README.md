![Haskell-jjunho](images/jupyterhaskell.svg)

# IHaskell — Haskell-jjunho Kernel

[![Build Status](https://github.com/jjunho/IHaskell/actions/workflows/stack.yml/badge.svg)](https://github.com/jjunho/IHaskell/actions/workflows/stack.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

IHaskell is a kernel for the [Jupyter project](https://jupyter.org), which allows you to use Haskell inside Jupyter frontends (console, notebook, JupyterLab). Supports GHC 8.4 through 9.14.

This fork includes bug fixes, dependency cleanup, architecture refactoring, and improved Jupyter protocol compliance.

---

## Quick Start

```bash
pip3 install jupyter
git clone https://github.com/jjunho/IHaskell
cd IHaskell
cabal build
cabal exec ihaskell install
jupyter notebook
```

Select **Haskell-jjunho** from the kernel menu.

---

## Table of Contents

- [Features](#features)
- [Installation](#installation)
- [Usage](#usage)
- [Kernel Options](#kernel-options)
- [Development](#development)
- [Project Structure](#project-structure)
- [Jupyter Protocol Status](#jupyter-protocol-status)
- [Changes From Upstream](#changes-from-upstream)
- [FAQ / Troubleshooting](#faq--troubleshooting)
- [License](#license)

---

## Features

| Capability | Details |
|-----------|---------|
| Rich output | HTML, SVG, PNG, JPG, GIF, LaTeX, Markdown, JavaScript, JSON, Vega/Vega-Lite, VDoms |
| Charts | Bar, pie, line via ihaskell-charts (Cairo) |
| Diagrams | Via ihaskell-diagrams (Cairo backend) |
| Widgets | Interactive Jupyter widgets: sliders, buttons, text, images, audio, video |
| Hoogle search | `:hoogle` queries, `:doc` fetches docs (optional, flag `use-hoogle`) |
| HLint | Integrated linting, toggled via `:option lint` |
| Tab completion | Identifiers, qualified names, modules, file paths, GHC extensions |
| Shell commands | `:! ls` runs shell commands, output captured inline |
| Module loading | `:load`, `:module`, `:reload` for multi-file projects |
| Template Haskell | Execute TH declarations inline |

---

## Installation

### Prerequisites

Install Haskell via [ghcup](https://www.haskell.org/ghcup/install/).

System dependencies:

| OS | Command |
|----|---------|
| **macOS** | `brew install python3 zeromq libmagic cairo pkg-config pango` |
| **Linux** (Debian/Ubuntu) | `sudo apt-get install -y python3-pip git libtinfo-dev libzmq3-dev libcairo2-dev libpango1.0-dev libmagic-dev libblas-dev liblapack-dev` |
| **Windows** (MSYS2 Clang64) | `pacman -S mingw-w64-clang-x86_64-zeromq mingw-w64-clang-x86_64-cairo mingw-w64-clang-x86_64-pango` |

Python:
```bash
pip3 install -r requirements.txt
```

Or manually:
```bash
pip3 install jupyter ipywidgets
```

### Cabal (recommended)

```bash
git clone https://github.com/jjunho/IHaskell
cd IHaskell
cabal build
cabal exec ihaskell install
```

Verify:
```bash
jupyter kernelspec list
# Should show: haskell-jjunho
```

### Enable Display Packages

For charts, diagrams, HTML rendering, widgets:

```bash
cabal build ihaskell-blaze      # HTML via Blaze
cabal build ihaskell-diagrams   # Diagrams (Cairo)
cabal build ihaskell-charts     # Charts (Cairo)
cabal build ihaskell-widgets    # Interactive widgets
cabal exec ihaskell install     # Re-register kernel
```

### Stack

```bash
stack install --fast
stack exec ihaskell install --stack
```

> Display packages must be listed in `stack.yaml`. Prefer Cabal for full display support.

### Docker

```bash
docker build -t ihaskell-jjunho:latest .
docker run --rm -p 8888:8888 ihaskell-jjunho:latest
```

### Nix

```bash
nix build
nix build .#ihaskell-env-display-ghc98  # with display modules
```

---

## Usage

Select **Haskell-jjunho** kernel in Jupyter.

```haskell
-- Simple expressions
3 + 5

-- Multi-line
let x = 10; y = 20 in x + y

-- Rich HTML
:extension OverloadedStrings
import IHaskell.Display
html "<b>Hello!</b>"

-- Chart
import Graphics.Rendering.Chart
import Data.Default.Class
import Control.Lens
let p (s,v,o) = pitem_value .~ v $ pitem_label .~ s $ pitem_offset .~ o $ def
toRenderable $ pie_title .~ "Data" $ pie_plot . pie_data .~ map p [(1,1,0),(2,2,0)] $ def
```

### Directives

| Command | Description |
|---------|-------------|
| `:type <expr>` | Expression type |
| `:kind <type>` | Kind |
| `:kind! <type>` | Kind + normalised type |
| `:info <name>` | Identifier info |
| `:hoogle <query>` | Search Hoogle |
| `:doc <ident>` | Hoogle documentation |
| `:set -XFlag` | GHC extension |
| `:extension <Ext>` | Shortcut for `:set -XExt` |
| `:option <opt>` | Kernel option |
| `:load <file>` | Load module |
| `:module [+/-]Mod` | Import/unimport module |
| `:reload` | Reload modules |
| `:sprint <val>` | Print without eval |
| `:! <cmd>` | Shell command |
| `:?`, `:help` | Help |

---

## Kernel Options

Set via `:option`:

| Option | Description |
|--------|-------------|
| `lint` / `no-lint` | Enable/disable HLint |
| `svg` / `no-svg` | Enable/disable SVG output |
| `show-types` / `no-show-types` | Show types of bound names |
| `show-errors` / `no-show-errors` | Show Show-instance errors |
| `pager` / `no-pager` | Use pager for `:info`/`:hoogle` |

---

## Development

### Build

```bash
cabal build             # all components
cabal build ihaskell    # executable only
cabal build -f-use-hoogle  # without network deps
```

### Test

```bash
cabal test              # 102 examples, 0 failures
```

| Module | Tests | Covers |
|--------|-------|--------|
| Test/Parser.hs | 44 | Parsing (expr, stmt, decl, import, directive, pragma, shell) |
| Test/Eval.hs | 16 | Interactive evaluation |
| Test/Completion.hs | 12 | Tab completion |
| Test/Properties.hs | 3 × 100 | Hedgehog: serialization roundtrip |
| Test/Evaluate/Capture.hs | 23 | Capture generators, readChars, pollingLoop |
| Test/Hoogle.hs | 4 | Hoogle JSON parsing |

**Total**: 102 tests (+ 3 property × 100 random runs)

### Project Structure

```
src/IHaskell/
├── Display.hs                   — Display constructors + publishResult
├── Types.hs                     — KernelState, Display, Widget, LogLevel
├── IPython.hs                   — Kernel spec installation
├── Flags.hs                     — CLI argument parsing
├── Eval/
│   ├── Evaluate.hs              — Main evaluation orchestrator
│   ├── Parser.hs                — Code block parsing (ghc-parser)
│   ├── Completion.hs            — Tab completion
│   ├── Widgets.hs               — Widget message handling
│   ├── Evaluate/Compat.hs       — GHC API compat shims
│   ├── Evaluate/Capture.hs      — Pure capture generators, readChars, pollingLoop
│   ├── Evaluate/Commands.hs     — EvalOut, safely, doLoadModule, doReload
│   ├── Evaluate/Format.hs       — displayError, formatError, formatType
│   ├── Evaluate/HTML.hs         — HTML syntax highlighting
│   ├── Util.hs                  — GHC utilities (re-exports Ppr)
│   └── Util/Ppr.hs              — Pretty-printing (pprDynFlags, doc)
ipython-kernel/
├── src/IHaskell/IPython/
│   ├── Types.hs                 — MessageType, ToJSON, FromJSON
│   ├── ZeroMQ.hs                — ZeroMQ channel interface
│   ├── Message/Parser.hs        — Message parsing
│   └── Message/UUID.hs          — UUID generation
ihaskell-display/                 — Display packages (blaze, diagrams, charts, widgets, ...)
```

---

## Jupyter Protocol Status

| Message | Status | Notes |
|---------|--------|-------|
| `kernel_info_request` | ✅ | Protocol 5.0, full language info |
| `execute_request` | ✅ | Execute + iopub (stream, display_data, error) |
| `complete_request` | ✅ | Tab completion via GHC API |
| `inspect_request` | ✅ | Type inspection |
| `is_complete_request` | ✅ | GHC parser (parserModule + heuristics) |
| `history_request` | ✅ | In-memory, 500 entries |
| `interrupt_request` | ✅ | SIGINT via control channel (POSIX) |
| `comm_info/comm_open/comm_msg/comm_close` | ✅ | Widget protocol v2.0.0 |
| `shutdown_request` | ✅ | Graceful exit |
| `debug_request` | ❌ | Jupyter debug protocol not implemented |

---

## Changes From Upstream

### Bug Fixes
- MVar deadlock prevented (gcatch around takeMVar/putMVar)
- random variable names use Data.Unique (StdGen never advanced)
- 9 `error` calls → Either/displayError (no kernel crash on bad input)
- Qualified GHC parser imports (no Failure/Parsed name collisions)

### Dependencies (4 removed, 0 added in production)
- `shelly` → System.Directory/System.Process
- `random` → Data.Unique (base)
- `strict` (unused)
- `setenv` (unused)
- `http-client`/`http-client-tls` → optional (flag `use-hoogle`)

### Architecture
- Evaluate.hs decomposed: Compat, Capture, Format, Commands modules
- Global channels (displayChan, widgetMessages) → IORef pattern
- capturedEval: pure functions + testable polling loop
- Util.Ppr extracted from 591-line Util.hs
- Publish.hs inlined into Display.hs
- STM replaces MVar for completion flag
- Structured logging (LogLevel ADT)
- Cabal 3.4 with common stanzas

### Testing
- 102 tests (up from 76 upstream)
- Hedgehog property tests
- Capture: generators, readChars, pollingLoop
- Oracle-verified across 5 review cycles

---

## FAQ / Troubleshooting

### Kernel not in kernel list?

```bash
cabal exec ihaskell install
jupyter kernelspec list
```

### Display packages not working?

Build display packages, then reinstall the kernel:
```bash
cabal build ihaskell-blaze
cabal exec ihaskell install
```

### Cairo not found?

```bash
# Linux
sudo apt-get install libcairo2-dev libpango1.0-dev
# macOS
brew install cairo pango
```

### Stack vs Cabal?

Cabal is preferred. Stack needs display packages in `stack.yaml`. Without `--stack`, kernel runs standalone.

---

## License

MIT — see [LICENSE](./LICENSE).

Upstream IHaskell by Andrew Gibiansky. This fork by [jjunho](https://github.com/jjunho).
