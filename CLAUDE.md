# Claude Code Context

## Project Overview

This is the Rex project - a universal tree notation parser and pretty printer.

## Important Notes

Before working on this codebase, review the notes in the `note/` directory:

- `note/prettiest.md` - Jean-Philippe Bernardy's paper "A Pretty But Not Greedy Printer" which describes an optimal pretty printing algorithm using Pareto frontiers. This is relevant background for understanding the PDoc system in `src/hs/Rex/PDoc.hs`.

## Key Modules

- `Rex.PDoc` - Pretty document system for width-aware layout
- `Rex.PrintRex` - Pretty printer from Rex representation (preserves HEIR structure)
- `Rex.PrintTree` - Pretty printer from Tree representation
- `Rex.Rex` - Rex data types (LEAF, NEST, EXPR, PREF, TYTE, JUXT, OPEN, HEIR, BLOC)

## Build Commands

```bash
nix develop --command cabal build
nix develop --command cabal test
nix develop --command cabal run rex -- <command>
```

Available commands: `lex`, `tree`, `rex`, `check`, `pretty`, `rex-test`
