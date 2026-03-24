# DONE: Parser S_BLOCK error on node.rex

**Status:** Fixed

## Problem

The file `src/c/ex/node.rex` failed to convert to Rex with error:
```
rex: S_BLOCK: should be consumed by enclosing context
```

## Cause

The `extractBlock` function in Rex.hs only handled S_BLOCK when it appeared
at the END of a node list. When there were multiple key-value pairs with
blocks separated by commas (like `{k1: \n items \n , k2: value}`), the
intermediate S_BLOCK nodes were not at the end, so they were passed to
`convertWith` which errored.

## Fix

Added `E_BLOCK` as a new Elem variant and implemented `mergeBlocks` to
preprocess element lists. The pattern `[E_REX head, E_RUNE rune, E_BLOCK items]`
is merged into `E_REX (BLOC CLEAR rune head items)` before normal infix
grouping occurs.

This allows S_BLOCK nodes to appear anywhere in a spaced context, not just
at the end.
