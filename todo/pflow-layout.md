# PFlow: Paragraph Flow Layout

## Problem

The current printer chooses between two extremes:
- **Flat**: Everything on one line
- **Vertical**: One item per line

This produces unnecessarily verbose output. A definition that could fit in 8
lines spans 100+ because each small item gets its own line.

Example - current vertical output:
```rex
| a
  b
  c
  | nested1
  | nested2
  d
  e
  f
```

Desired output with flow layout:
```rex
| a b c
    | nested1
    | nested2
  d e f
```

The small items `a b c` and `d e f` should flow together on lines, while the
open items `| nested1` and `| nested2` get their staircase treatment.


## Solution

Add `PFlow` to PDoc for greedy line-packing of items, then use it in
`openChildrenVertical` for closed item groups.


## Part 1: PFlow in PDoc

### Constructor

```haskell
data PDoc
    = ...
    | PFlow !Int [PDoc]
    -- ^ Flow layout: pack items greedily onto lines.
    -- Int = max item width for flow participation.
    -- Items that fit the limit are packed with spaces between them.
    -- Items exceeding the limit get their own line.
```

### Helper: sdocFitsFlat

A stricter variant of `sdocFits` that rejects newlines:

```haskell
sdocFitsFlat :: Int -> SDoc -> Bool
sdocFitsFlat w _ | w < 0       = False
sdocFitsFlat _ SEmpty           = True
sdocFitsFlat w (SChar _ x)      = sdocFitsFlat (w - 1) x
sdocFitsFlat w (SText l _ x)    = sdocFitsFlat (w - l) x
sdocFitsFlat _ (SLine _ _)      = False
sdocFitsFlat _ (SNoFit _)       = False
```

### Renderer Logic

PFlow processes items one at a time, greedily packing onto the current line:

```haskell
PFlow maxW [] ->
    best n k ds

PFlow maxW (item:rest) ->
    let (_, rendered) = best n k (DLCons i item DLNil)
        isSmall = sdocFitsFlat maxW rendered
        fitsHere = sdocFitsFlat (w - k - 1) rendered  -- room for space + item
        atStart = k == i
    in if isSmall && fitsHere
       then if atStart
            then -- first on line, no leading space
                 best n k (DLCons i item (DLCons i (PFlow maxW rest) ds))
            else -- append with space
                 best n k (DLCons i pdocSpace
                            (DLCons i item
                              (DLCons i (PFlow maxW rest) ds)))
       else if not atStart
            then -- wrap to new line, retry
                 let (bs, r) = best i i (DLCons i (PFlow maxW (item:rest)) ds)
                 in (bs, SLine i r)
            else -- at line start, item is big, emit as-is
                 best n k (DLCons i item
                            (DLCons i PLine
                              (DLCons i (PFlow maxW rest) ds)))
```

DLSCons case mirrors this with appropriate bs/ss handling.

### Behavior Summary

- **Small item fits on current line**: emit space (if not first) + item
- **Small item doesn't fit**: wrap to new line, retry
- **Large item (has newlines or exceeds maxW)**: gets its own line


## Part 2: Update PrintRex

### Add config field

```haskell
data PrintConfig = PrintConfig
    { cfgColors    :: ColorScheme
    , cfgDebug     :: Bool
    , cfgMaxFlow   :: Int   -- max item width for flow layout
    }

defaultConfig = PrintConfig NoColors False 24
```

### Update openChildrenVertical

Change `ClosedGroup` rendering from PLine-separated to PFlow:

```haskell
renderGroup :: ChildGroup -> PDoc
renderGroup (ClosedGroup cs) =
    PFlow (cfgMaxFlow cfg) (map (rexDoc cfg) cs)
renderGroup (OpenGroup os) =
    pdocStaircase (map (rexDoc cfg) os)
```

That's it. The existing grouping logic (`groupChildren`, `renderGroups`)
handles partitioning correctly. We just change how closed groups render.

### Export pdocFlow combinator

```haskell
pdocFlow :: Int -> [PDoc] -> PDoc
pdocFlow _    []    = PEmpty
pdocFlow _    [x]   = x
pdocFlow maxW items = PFlow maxW items
```


## Part 3: Test Cases

### New test file: flow.tests

```
=== flow packs small items | 30
(a b c d e f g h i j k l)
---
(a b c d e f g h i j k
 l)

=== flow with open items | 40
| a b c | nested d e f
---
| a b c
    | nested
  d e f

=== large item gets own line | 30
(x y (longFunctionName a b) z w)
---
(x y
 (longFunctionName a b)
 z w)

=== mixed groups | 40
| p q r | step1 | step2 x y z
---
| p q r
      | step1
  | step2
  x y z

=== all small stays flat if fits | 80
| a b c d e
```

### Regressions

All existing tests must pass. The change only affects vertical layout of
closed groups - they now flow instead of one-per-line.


## Implementation Checklist

1. Add `sdocFitsFlat` helper to PDoc.hs
2. Add `PFlow` constructor to PDoc
3. Add renderer cases for PFlow in both DLCons and DLSCons
4. Add `pdocFlow` combinator and export it
5. Add `cfgMaxFlow` to PrintConfig
6. Update `renderGroup (ClosedGroup ...)` to use PFlow
7. Add flow.tests
8. Run full test suite


## Future Work

This handles the common case of closed items in OPEN children. Other contexts
that could benefit from flow layout:

- EXPR children (currently uses pdocSpaceOrLine)
- NEST content for CLEAR color
- Anywhere we currently use pdocIntersperse with space/line choice

These can be addressed incrementally. The PFlow infrastructure enables them.


## Relationship to Other Todos

- **phrasic-grouping.md**: Describes same problem, proposes same solution.
  This plan supersedes it.
- **ppara-sequence-plan.md**: More ambitious plan with seqDoc unification.
  PFlow is the subset we're implementing first.

After PFlow is working, evaluate whether seqDoc unification is still wanted
or if the current structure with PFlow is sufficient.
