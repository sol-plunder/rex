# TODO: Phrasic grouping for poem children

## Problem

Our printer treats all children of an OPEN uniformly. The old printer separates
"phrasic" (inline) elements from "open" (multi-line) elements and handles them
differently:

- Initial phrasic args go on the same line as the rune
- Middle open elements get their own indented lines
- Trailing phrasic elements go at the end

## Example

Input:
```rex
| a b c
    | nested1
    | nested2
  d e f
```

Current output (hypothetical - we'd spread everything):
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

Desired output:
```rex
| a b c
    | nested1
    | nested2
  d e f
```

## What is "phrasic"?

An element is phrasic if it doesn't need backstep alignment with siblings.
Non-phrasic elements expand vertically in a way that affects sibling positioning.

```haskell
isPhrasic :: Rex -> Bool
isPhrasic (OPEN _ _)    = False  -- needs backstep (staircase pattern)
isPhrasic (HEIR _)      = False  -- multiple lines at same column
isPhrasic (LEAF SLUG _) = False  -- can't have another slug after at same indent
isPhrasic _             = True   -- BLOC, NEST, EXPR, PREF, TYTE, JUXT, other LEAFs
```

Note: BLOC is phrasic because its contents are indented *under* it, not at the
same column as siblings. Multi-line TRAD/UGLY are also phrasic for the same
reason - they use PDent to handle their own internal alignment.

## Implementation Strategy

### Step 1: Add `PFlow` combinator to PDoc

Add a new PDoc constructor for flow layout:

```haskell
PFlow [PDoc]  -- Flow layout: items wrapped greedily onto lines
```

Semantics at render time:
- Items separated by spaces
- When next item won't fit on current line, emit newline + current indent
- Each item is atomic (no breaking within an item)

This is like "fill" layout in other pretty-printing libraries. It does greedy
packing: fit as many items as possible on each line, then wrap.

### Step 2: Update `openDoc` in PrintRex.hs

Partition children and use appropriate layout for each section:

```haskell
openDoc :: String -> [Rex] -> PDoc
openDoc r kids =
    let (initPhrasic, middle, finalPhrasic) = crushEnds kids
    in case (middle, finalPhrasic) of
        ([], []) ->
            -- All phrasic: try flat, else flow
            PChoice flat (verticalAllPhrasic initPhrasic)
        _ ->
            -- Mixed: rune + initial phrasics, then middle with backstep, then trailing
            verticalMixed r initPhrasic middle finalPhrasic

crushEnds :: [Rex] -> ([Rex], [Rex], [Rex])
crushEnds kids = (initial, middle, final)
  where
    (initial, rest) = span isPhrasic kids
    (finalRev, middleRev) = span isPhrasic (reverse rest)
    middle = reverse middleRev
    final = reverse finalRev
```

For the vertical mixed case:
1. Line 1: `rune + space + PFlow (map rexDoc initPhrasic)`
2. Middle section: each non-phrasic gets backstep, consecutive phrasics get `PFlow`
3. Trailing: `PFlow (map rexDoc finalPhrasic)`

### Step 3: Handle middle section

The middle may interleave non-phrasic and phrasic elements. Group consecutive
phrasics together:

```haskell
crushMid :: [Rex] -> [[Rex]]  -- groups of consecutive same-type
```

Then render each group appropriately:
- Non-phrasic singleton: backstep + rexDoc
- Phrasic group: PFlow of the group

## Related

- `src/hs/Rex/PrintRex.hs` - `openDoc`, `openChildrenFlat`, `openChildrenVertical`
- `src/hs/Rex/PDoc.hs` - add `PFlow` constructor
- `ctx/Print.hs` - `crushEnds`, `isPhrasic`, `toPhrases`
