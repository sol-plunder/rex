# Factor Out Testing and Driver Logic

## Issue
Test harness code and CLI driver logic are mixed with core implementation modules. Each file should have a single purpose.

## Current State
- `Rex.PrintRexTest` - test harness for PrintRex (this is fine, already separate)
- `Rex.Rex` has `rexMain` and `checkMain` driver functions
- `Rex.Tree2` has `treeMain` driver function
- `Rex.Lex` has `lexMain` driver function
- `Rex.PrintRex` has `prettyRexMain` driver function

## Proposed Structure
Option A: Single driver module
- `Rex.CLI` or `Rex.Main` - all CLI entry points in one place
- Core modules export only library functions

Option B: Consistent *Main pattern
- Each module with a main exports it (current approach)
- But consider moving test-related code out of core modules

## Benefits
- Core modules become pure library code
- Easier to use Rex as a library dependency
- Clearer what's API vs what's tooling
