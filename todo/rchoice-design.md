# RChoice: Multiple Rex Tree Alternatives

## Problem

The current printer makes layout decisions (flat vs vertical) for a single
Rex tree. However, the same semantic data can often have multiple valid Rex
representations. A codebase using Rex as its notation layer needs to be able
to provide these alternatives and let the printer choose the best fit.

## Current Limitation

Today, `PChoice` operates at the PDoc level, choosing between different
*renderings* of the same Rex structure:

```
PChoice (flat rendering of tree)
        (vertical rendering of tree)
```

This doesn't help when the data itself has multiple Rex representations.
For example, a function application could be written as:

```rex
-- Prefix form
| add x y

-- Tight form
add(x, y)

-- Infix form (if add is an operator)
x + y
```

These are different Rex trees, not different layouts of one tree.

## Proposed Design

Introduce `RChoice` at the Rex level:

```haskell
data Rex
    = LEAF Span LeafShape String
    | NEST Span Color String [Rex]
    | EXPR Span Color [Rex]
    | PREF Span String Rex
    | TYTE Span String [Rex]
    | BLOC Span Color String Rex [Rex]
    | OPEN Span String [Rex]
    | JUXT Span [Rex]
    | HEIR Span [Rex]
    | RCHOICE Span (NonEmpty Rex)   -- NEW: choose best-fitting alternative
```

The printer would:

1. Render each alternative
2. Select the first one that fits within page width
3. Fall back to the last alternative if none fit

## Use Cases

### 1. Compact vs Verbose Forms

```haskell
-- Upstream provides both:
RCHOICE span
    [ TYTE span "." [word "foo", word "bar", word "baz"]  -- foo.bar.baz
    , OPEN span "|" [word "get", word "foo", word "bar", word "baz"]  -- | get foo bar baz
    ]
```

### 2. Operator Precedence Choices

```haskell
-- When parens are optional due to precedence:
RCHOICE span
    [ NEST span CLEAR "+" [a, b]           -- a + b
    , NEST span PAREN "+" [a, b]           -- (a + b)
    ]
```

### 3. Record Syntax Variants

```haskell
-- JSON-style vs YAML-style:
RCHOICE span
    [ NEST span CURLY "," [...]   -- { a: 1, b: 2 }
    , OPEN span "+" [...]          -- + a: 1
                                   -- + b: 2
    ]
```

### 4. String Literal Forms

```haskell
-- Short string vs multi-line:
RCHOICE span
    [ LEAF span CORD "short text"
    , LEAF span PAGE "short text"
    ]
```

## Implementation Considerations

### Ordering Semantics

Alternatives should be ordered by preference (most compact first). The
printer tries them in order and uses the first that fits. This matches
how `PChoice` works.

### Span Handling

The `RCHOICE` span should cover all alternatives. Individual alternatives
retain their own spans for error reporting if needed.

### Interaction with PChoice

`RCHOICE` operates at tree level (which representation?), while `PChoice`
operates at layout level (how to render?). They compose:

```
RCHOICE [tree1, tree2]
        ↓
rexDoc tree1 → PChoice (flat1) (vert1)
rexDoc tree2 → PChoice (flat2) (vert2)
```

The printer would try: flat1, vert1, flat2, vert2 (or possibly flat1,
flat2, vert1, vert2 depending on desired semantics).

### Performance

Speculatively rendering multiple trees is more expensive than rendering
one tree with layout choices. Consider:

- Lazy evaluation / short-circuit on first fit
- Caching rendered widths
- Quick width estimation before full rendering

## API Surface

Upstream code would construct Rex trees with `RCHOICE`:

```haskell
-- Helper for common case of two alternatives
rexChoice2 :: Rex -> Rex -> Rex
rexChoice2 a b = RCHOICE (rexSpan a) (a :| [b])

-- General case
rexChoices :: NonEmpty Rex -> Rex
rexChoices alts = RCHOICE (rexSpan (head alts)) alts
```

## Open Questions

1. Should alternatives be `NonEmpty Rex` or `[Rex]` with implicit
   single-element handling?

2. Should the printer try all flat layouts before any vertical layouts,
   or go alternative-by-alternative?

3. How does `RCHOICE` interact with `HEIR`? Can heir siblings have
   different alternatives?

4. Should there be a way to mark an alternative as "preferred even if
   it doesn't fit" (like `PNoFit` but inverse)?
