# Staircase Layout

## What Staircase Layout Does

When an OPEN has multiple children that are themselves OPENs (or HEIRs or
BLOCs), they form a "reverse staircase" pattern where each successive sibling
is indented **less** than the previous one:

```rex
- This is
      | These are
    | Staircase
  | siblings
```

All three `|` poems are children of the `- This is` OPEN, not nested inside
each other. The staircase mechanism positions them in this descending pattern.

Without staircase layout, you would get:

```rex
- This is
  | These are
  | Staircase
  | siblings
```

Which would parse differently (the `|` poems would be HEIRs, siblings of each
other at the same column, rather than successive children with the staircase
layout).


## Staircase vs HEIR

These are complementary but different concepts:

- **HEIR**: Multiple forms at the **same** column, creating vertical siblings
- **Staircase**: Multiple OPEN children at **decreasing** indentation levels

A HEIR groups items that share a column. Staircase layout positions items at
different columns to show they're children of a common parent, not siblings
in a HEIR.


## When Staircase Applies

Staircase layout is used when rendering an OPEN's children in vertical mode,
and multiple consecutive children are "open" forms (OPEN, HEIR, or BLOC per
`isOpenRex`). The staircase ensures these sibling children form the correct
reverse staircase pattern.


## Implementation in PDoc

The staircase pattern is implemented via `PStaircase` in `Rex.PDoc`:

```haskell
| PStaircase !Int [PDoc]    -- reverse-staircase layout for open children
                            -- Int = step size (typically 4)
```

### Rendering Logic

`PStaircase step items` renders items with the first item at the deepest
indentation and the last at the base indentation:

- For N items with step size S, the first item is at `base + (N-1)*S`
- Each subsequent item is S columns less indented
- The last item is at `base + 0`

Each item is preceded by a newline at its computed indent:

```haskell
PStaircase step items ->
    let totalSteps = (length items - 1) * step
        buildDoc [] _depth = best n k ds
        buildDoc [item] _depth =
            best n k (DLCons i (PCat PLine item) ds)
        buildDoc (item:rest) depth =
            let itemIndent = i + depth
                (_, restSDoc) = buildDoc rest (depth - step)
            in best n k (DLCons itemIndent (PCat PLine item)
                          (DLSCons i PEmpty 0 restSDoc))
    in (0, snd (buildDoc items totalSteps))
```

Key aspects:

1. **Inside-out rendering**: Later items are rendered first (recursively),
   building up an `SDoc` continuation. Earlier items are then prepended.

2. **Returns backstep=0**: The staircase returns `(0, ...)` to prevent its
   internal indentation from "leaking" to outer contexts. This is critical
   for composability.

3. **DLSCons for continuation**: Uses `DLSCons` to carry the precomputed
   continuation from later items, so earlier items can be prepended correctly.


### Why Backstep Isolation Matters

Without isolation, multiple staircases would interfere with each other:

```rex
+ foo
      + a
      + b
  + c
  + d
+ bar
      + p
      + q
  + r
  + s
+ zaz
```

Here `+ foo` and `+ bar` each have their own staircase children. If the
staircase from `+ bar` leaked its indentation backward, it would push
`+ foo`'s children too far right. By returning backstep=0, each staircase
is self-contained.


## Implementation in PrintRex

`openChildrenVertical` groups children into consecutive "closed" and "open"
runs, then renders each run appropriately:

```haskell
openChildrenVertical cfg kids = renderGroups (groupChildren kids)
  where
    groupChildren xs =
        let (closed, rest1) = span (not . isOpenRex) xs
            (open,   rest2) = span isOpenRex rest1
        in case (closed, open) of
            ([], []) -> []
            (cs, []) -> [ClosedGroup cs]
            ([], os) -> OpenGroup os : groupChildren rest2
            (cs, os) -> ClosedGroup cs : OpenGroup os : groupChildren rest2

    renderGroup (ClosedGroup cs) =
        pdocIntersperseFun (\x y -> PCat x (PCat PLine y)) (map (rexDoc cfg) cs)
    renderGroup (OpenGroup os) =
        pdocStaircase (map (rexDoc cfg) os)
```

- **ClosedGroup**: Items separated by newlines at the same indent
- **OpenGroup**: Items rendered via `pdocStaircase` in reverse-staircase


## Historical Note

The original implementation used `PBackstep`, a combinator that rendered the
right argument first to determine indentation, then positioned the left
argument relative to that. This worked but had a composability issue: backstep
from one group could "leak" into another.

`PStaircase` replaced `PBackstep` with a cleaner design where the staircase
is a self-contained first-class concept that explicitly isolates its
indentation effects.
