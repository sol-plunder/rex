# Evaluation: Bernardy's "Prettiest" Algorithm vs Current PDoc

## Summary

The current PDoc system is based on Wadler's greedy algorithm, while
Bernardy's "prettiest" paper describes an optimal algorithm using Pareto
frontiers. Adopting Bernardy's approach could improve output quality for
certain cases, but would require significant work to adapt to Rex's unique
requirements.

## Current PDoc System

The current system uses:

- **Greedy `PChoice`**: When encountering `PChoice x y`, it tries `x` first
  and falls back to `y` only if `x` doesn't fit on the current line. This is
  decided locally based on `sdocFits`.

- **`PDent`**: Captures the current column as the new indentation level.

- **`PStaircase`**: A Rex-specific extension for handling rune poem alignment.
  It renders consecutive open children in a reverse-staircase pattern where
  the first child is most indented and subsequent children step back toward
  base indent.

The greedy approach means decisions are made line-by-line without considering
the global impact on output size.

## Bernardy's Approach

Key ideas from the paper:

1. **Three Principles**: Visibility (fit within page width), Legibility
   (proper structure), Frugality (minimize lines). These are prioritized in
   that order.

2. **Non-Greedy Optimization**: Instead of greedily choosing layouts, track
   all non-dominated layouts and pick the best one at the end.

3. **Pareto Frontiers**: For each document, maintain the set of layouts that
   are not dominated by any other layout. A layout `a` dominates `b` if `a`
   is better or equal in all dimensions (height, maxWidth, lastWidth).

4. **Measures**: Abstract away from actual text to just track
   `(height, lastWidth, maxWidth)`, then pair back with text at the end.

5. **Early Pruning**: Filter out invalid (too wide) layouts early, and
   continuously prune dominated layouts to keep the set small.

## What Bernardy's Approach Could Improve

### 1. Record/Config Formatting

The current output:
```rex
{title : "TOML Example" , owner : {name : "Tom Preston-Werner" , dob
                                                                 : '1979-05-27T07:32:00-08:00}
 , database : {enabled : true , ports : [8000 , 8001 , 8002]}}
```

With optimal layout, the algorithm could find that putting each field on its
own line uses fewer total lines than this awkward wrapped format:
```rex
{ title    : "TOML Example"
, owner    : { name : "Tom Preston-Werner"
             , dob  : '1979-05-27T07:32:00-08:00 }
, database : { enabled : true
             , ports   : [8000 , 8001 , 8002] } }
```

### 2. Avoiding Greedy Traps

The greedy algorithm can commit to fitting text on an early line, only to
waste vertical space later. Bernardy's example: fitting `(abcdefgh ((a` on
one line forces deep indentation that wastes space for the rest of the
document.

### 3. Better Width Utilization

When multiple layouts are possible, the optimal algorithm considers all of
them and picks the one with minimum height, rather than just trying one and
falling back.

---

## Specific Technical Challenges for Rex

### 1. PStaircase Semantics

The `PStaircase` combinator renders consecutive open children in a
reverse-staircase pattern:

```rex
- This is
      | These are
    | Staircase
  | siblings
```

All three `|` poems are children of the `- This is` OPEN. The staircase
renders the first child at the deepest indent, with each subsequent child
stepping back toward base indent.

In Bernardy's framework, documents are combined with `(<>)` which is
associative and has clean algebraic properties. The staircase pattern
requires knowing how many open siblings follow to determine the first
sibling's indentation — a dependency that doesn't fit the standard
algebraic structure.

**Current solution:** `PStaircase` is implemented as a first-class PDoc
construct that handles the entire group of open children atomically,
returning `backstep=0` to isolate its internal indentation from surrounding
context.

### 2. HEIR Rune Alignment

HEIR siblings must align based on the first child's rune length:

```rex
:= x/y
 | if y=0 !!"error"    -- | aligns at column 1 (length of ":=" minus 1)
 | if x<y 0
```

Currently handled in `heirDoc`:
```haskell
heirDoc (k:ks) =
    let runeIndent = case k of
            OPEN r _ -> length r - 1
            _        -> 0
    in PDent (PCat (heirFirst runeIndent k) (heirRest runeIndent ks))
```

This computes indentation based on **inspecting the Rex structure**, not
just the document. In Bernardy's framework, documents are abstract — you
don't inspect their structure during layout.

**Possible solutions:**
- Compute rune-based indentation during Rex→PDoc translation (current
  approach, works fine)
- Add a new primitive `PIndent Int PDoc` that adds fixed indentation

### 3. containsHeir Forcing

The current printer forces vertical layout when a child contains HEIR:

```haskell
nestContent c r (k:ks)
    | containsHeir k = PCat (rexDoc k) (PCat PLine ...)  -- force newline
    | otherwise      = PCat (rexDoc k) (nestSep c r ks)  -- try flat first
```

This is a **structural inspection** of the Rex tree to decide layout
strategy. In Bernardy's framework, you'd instead offer both layouts as
choices and let the optimizer pick.

**Challenge:** If you offer `flat <|> vertical` for every NEST child, you
get exponential blowup in the number of layouts to consider. The
`containsHeir` check is a pruning heuristic that prevents this.

**Possible solutions:**
- Keep the `containsHeir` check as a pre-filtering step before building
  documents
- Trust the Pareto frontier pruning to handle the combinatorial explosion
  (may be slow)
- Add a "must be vertical" document combinator that constrains rather than
  chooses

### 4. Round-Trip Constraint

Rex printing must produce output that parses back to the same tree. Some
layout choices that look valid from a pretty-printing perspective may
produce different parse trees.

Example: The trailing rune for single-element NEST:
```rex
(foo ,)   -- parses as NEST with trailing comma
(foo)     -- parses as EXPR, different tree!
```

Currently we handle this with special cases:
```haskell
nestDoc c r kids = case kids of
    [k] -> PCat (rexDoc k) (PCat pdocSpace (pdocText r))  -- force trailing rune
    _   -> nestContent c r kids
```

**In Bernardy's framework:** These aren't layout choices — they're semantic
requirements. The solution is to not offer invalid layouts in the first
place, which is what we already do.

### 5. The Measure Type Extension

Bernardy uses `M = (height, lastWidth, maxWidth)`. For Rex we may need:

```haskell
data M = M
    { height      :: Int
    , lastWidth   :: Int
    , maxWidth    :: Int
    , staircaseN  :: Int    -- NEW: number of items in staircase group
    , runeIndent  :: Int    -- NEW: if this is an OPEN, the rune length - 1
    }
```

The domination relation becomes more complex:
```haskell
m1 ≺ m2 = height m1 <= height m2
       && maxWidth m1 <= maxWidth m2
       && lastWidth m1 <= lastWidth m2
       && staircaseN m1 == staircaseN m2   -- must be equal, not less
       && runeIndent m1 == runeIndent m2   -- must be equal
```

This may cause larger Pareto frontiers (more non-dominated layouts to track).

### 6. Performance Implications

Bernardy reports ~10x slowdown vs Wadler-Leijen. For Rex:

- **Poem structures** create many choice points (flat vs vertical for each
  OPEN)
- **Deeply nested records** create combinatorial layouts
- **HEIR chains** don't have choices (always vertical) so don't add overhead

Estimated: For typical Rex code, the slowdown is acceptable. For large
generated code or deeply nested configs, it could be noticeable.

---

## Implementation Roadmap

### Phase 1: Measure-Based Layout (without full Pareto)

1. Define `RexMeasure` type with Rex-specific fields
2. Implement measure computation for each Rex constructor
3. Keep greedy choice but use measures to make smarter decisions

This gives some benefits without full complexity.

### Phase 2: Pareto Frontier for Choice

1. Implement `pareto :: [RexMeasure] -> [RexMeasure]`
2. Change `PChoice` handling to track frontier instead of greedy pick
3. Add early pruning for invalid layouts

### Phase 3: Staircase in Pareto Framework

1. Ensure `PStaircase` works correctly with measure computation
2. May require treating staircase groups as atomic units in the frontier
3. Test extensively with staircase poem patterns

### Phase 4: Text Pairing

1. Pair measures with actual text output
2. Ensure round-trip property is preserved
3. Benchmark against current implementation

---

## Recommendation

The Bernardy approach could meaningfully improve output for:
- Nested records/configuration
- Deeply nested expressions where greedy choices lead to poor layouts

However, the implementation effort is substantial due to Rex-specific
constructs. A pragmatic path:

1. **Short term**: Improve the greedy algorithm's heuristics for specific
   Rex constructs (records, tuples with poems). This can be done within the
   current PDoc framework.

2. **Medium term**: Implement Phase 1 (measures) to enable smarter greedy
   decisions.

3. **Long term**: Consider full Pareto implementation if the above aren't
   sufficient.

**Key insight:** The `PStaircase` combinator is already designed to be
self-contained (returns backstep=0), which helps with composability. The
main challenge is integrating staircase groups into the measure/frontier
computation.

## References

- Bernardy's implementation: https://hackage.haskell.org/package/pretty-compact
- Paper: "A Pretty But Not Greedy Printer" (PACM Progr. Lang. 2017)
