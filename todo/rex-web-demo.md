# Rex Web Demo

A browser-based interactive demo for Rex parsing and pretty-printing.

## Goal

Create a web page where users can:
1. Enter Rex source text in a textarea
2. See the parsed Rex tree structure
3. See the pretty-printed output at various widths
4. Optionally see debug output with structure markers

## Technology Evaluation

### GHC JavaScript Backend

**Status: NOT RECOMMENDED**

The [GHC JavaScript backend](https://gitlab.haskell.org/ghc/ghc/-/wikis/javascript-backend)
remains a **technology preview** as of 2025:
- Not distributed in GHC release bindists
- Requires manually building GHC as a cross-compiler
- Not all Haskell features implemented
- Foreign exports not implemented (JS calling Haskell is limited)
- Bugs expected

The JS backend has received less attention than WASM since the initial merge.

### GHC WebAssembly Backend

**Status: RECOMMENDED**

The [GHC WASM backend](https://www.tweag.io/blog/2024-11-21-ghc-wasm-th-ghci/) has
made significant progress in 2024:
- Template Haskell support (as of late 2024)
- GHCi support via custom wasm dynamic linker
- JSFFI feature for seamless JS interop
- Active development and community support
- Successfully used for real projects (e.g., blog on Cloudflare Workers)

**Requirements:**
- GHC 9.10.1.20241021 or later
- cabal >= 3.15
- Nix (recommended) or manual bootstrap

### Frontend Framework: Miso

**Status: RECOMMENDED**

[Miso](https://haskell-miso.org/) is a mature Haskell web framework:
- Elm-inspired architecture (Model-View-Update)
- Virtual DOM with efficient diffing
- Native WASM support (builds directly with GHC wasm backend)
- Hot-reload development workflow with ghciwatch
- Well-documented with active community

The [miso-sampler](https://github.com/haskell-miso/miso-sampler) repository
provides a ready-to-use template with:
- Nix flake configuration
- WASM and GHCJS build targets
- Hot-reload development server
- GitHub Pages deployment workflow

Note: The older [ghc-wasm-miso-examples](https://github.com/tweag/ghc-wasm-miso-examples)
is now archived (Oct 2025) since upstream miso works directly with wasm.

## Rex Dependency Compatibility

The `directory` and `ansi-wl-pprint` dependencies are only used in the CLI
driver (`Rex.CLI`), not the core library. The core modules should compile
to WASM without changes.

| Package | WASM Compatible? | Notes |
|---------|-----------------|-------|
| base | Yes | Core library |
| extra | Yes | Pure utilities |
| filepath | Yes | Pure path manipulation |
| optics | Yes | TH splices work with GHC 9.10+ wasm |
| pretty-show | Yes | Pure pretty-printing |

**No changes required** - just don't include the CLI module in the web build.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Browser                               │
├─────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────┐ │
│  │ Input       │  │ Rex Tree    │  │ Pretty Output   │ │
│  │ Textarea    │  │ Display     │  │ Display         │ │
│  └──────┬──────┘  └──────▲──────┘  └────────▲────────┘ │
│         │                │                   │          │
│         ▼                │                   │          │
│  ┌──────────────────────────────────────────────────┐  │
│  │              Miso Application                     │  │
│  │  Model: { input :: String                        │  │
│  │         , width :: Int                           │  │
│  │         , debug :: Bool                          │  │
│  │         , parsed :: Maybe Rex                    │  │
│  │         , output :: String }                     │  │
│  └──────────────────────────────────────────────────┘  │
│                          │                              │
│                          ▼                              │
│  ┌──────────────────────────────────────────────────┐  │
│  │              Rex Core (WASM)                      │  │
│  │  - parseRex :: String -> [(String, Tree)]        │  │
│  │  - rexFromBlockTree :: String -> Tree -> Rex     │  │
│  │  - printRex :: Int -> Rex -> String              │  │
│  │  - ppRex :: Rex -> String (debug tree view)      │  │
│  └──────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

## Implementation Plan

### Phase 1: Rex Core Library

Create a minimal `rex-core` package with no IO dependencies:

```cabal
library rex-core
  exposed-modules:
      Rex.Lex
      Rex.Tree2
      Rex.Error
      Rex.String
      Rex.Rex
      Rex.PrintRex
      Rex.PDoc
  build-depends:
      base >= 4.7 && < 5
    -- Remove: directory, ansi-wl-pprint (or use pure version)
    -- Keep: extra, filepath, optics, pretty-show
```

Alternatively, use CPP to conditionally exclude IO-dependent code:

```haskell
#ifndef WASM
import System.Directory
#endif
```

### Phase 2: Miso Application

Create `rex-web` package:

```haskell
-- Model
data Model = Model
    { input   :: Text
    , width   :: Int
    , debug   :: Bool
    , result  :: Either String (Rex, String)  -- parsed Rex and output
    }

-- Actions
data Action
    = SetInput Text
    | SetWidth Int
    | ToggleDebug
    | NoOp

-- Update
updateModel :: Action -> Model -> Effect Action Model
updateModel (SetInput txt) m = noEff m
    { input = txt
    , result = processInput (debug m) (width m) txt
    }
updateModel (SetWidth w) m = noEff m
    { width = w
    , result = reprocess m { width = w }
    }
updateModel ToggleDebug m = noEff m
    { debug = not (debug m)
    , result = reprocess m { debug = not (debug m) }
    }

-- View
viewModel :: Model -> View Action
viewModel m = div_ []
    [ h1_ [] [text "Rex Demo"]
    , div_ [class_ "input-section"]
        [ textarea_
            [ onInput SetInput
            , value_ (input m)
            , rows_ "10"
            , cols_ "80"
            ] []
        ]
    , div_ [class_ "controls"]
        [ label_ [] [text "Width: "]
        , input_
            [ type_ "range"
            , min_ "40"
            , max_ "120"
            , value_ (ms $ width m)
            , onInput (SetWidth . read . ms)
            ]
        , text (ms $ width m)
        , label_ []
            [ input_ [type_ "checkbox", checked_ (debug m), onClick ToggleDebug]
            , text " Debug mode"
            ]
        ]
    , div_ [class_ "output-section"]
        [ case result m of
            Left err -> pre_ [class_ "error"] [text err]
            Right (rex, out) ->
                div_ []
                    [ h3_ [] [text "Pretty Output"]
                    , pre_ [class_ "output"] [text out]
                    , h3_ [] [text "Rex Tree"]
                    , pre_ [class_ "tree"] [text (ppRex rex)]
                    ]
        ]
    ]
```

### Phase 3: Build Configuration

Create Nix flake based on miso-sampler:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    ghc-wasm-meta.url = "gitlab:haskell-wasm/ghc-wasm-meta?host=gitlab.haskell.org";
  };

  outputs = { self, nixpkgs, flake-utils, ghc-wasm-meta }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        wasm-ghc = ghc-wasm-meta.packages.${system}.all_9_10;
      in {
        devShells.wasm = pkgs.mkShell {
          buildInputs = [ wasm-ghc pkgs.cabal-install ];
        };
      });
}
```

### Phase 4: Deployment

Options:
1. **GitHub Pages** - Static hosting, free
2. **Cloudflare Pages** - Fast CDN, free tier
3. **Self-hosted** - Embed in project documentation

The WASM output is a single `.wasm` file plus JS glue code, easily deployable
as static assets.

## Development Workflow

```bash
# Enter dev environment
nix develop .#wasm

# Build WASM
make

# Serve locally with hot-reload
make serve

# Interactive REPL (for debugging)
make repl
```

## Estimated Effort

1. **Build setup** - 1 hour
   - Copy flake.nix from miso-sampler
   - Add rex-core as dependency
   - Verify it compiles

2. **Miso application** - 1-2 hours
   - ~50-100 lines: textarea, width slider, output pane
   - Wire up parseRex/printRex

3. **Deploy** - 30 min
   - GitHub Pages or similar

**Total: 2-4 hours**

The `directory` and `ansi-wl-pprint` dependencies are only used in the CLI
driver, so the core library should compile to WASM without modification.

## References

- [GHC WASM User Guide](https://downloads.haskell.org/ghc/latest/docs/users_guide/wasm.html)
- [Miso Framework](https://haskell-miso.org/)
- [miso-sampler template](https://github.com/haskell-miso/miso-sampler)
- [GHC WASM Meta](https://gitlab.haskell.org/haskell-wasm/ghc-wasm-meta)
- [Tweag: GHC WASM TH/GHCi Support](https://www.tweag.io/blog/2024-11-21-ghc-wasm-th-ghci/)
- [Detailed GHC WASM Guide](https://finley.dev/blog/2024-08-24-ghc-wasm.html)
- [JSFFI in GHC WASM (ICFP 2024)](https://icfp24.sigplan.org/details/haskellsymp-2024-papers/11/-HIW-The-JavaScript-FFI-feature-in-GHC-Wasm-backend)
