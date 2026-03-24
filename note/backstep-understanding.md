# Understanding Backstep

## What Backstep Does

When an OPEN has multiple children that are themselves OPENs, they form a
"reverse staircase" pattern where each successive OPEN sibling is indented
**less** than the previous one:

```rex
- This is
      | These are
    | Backstepped
  | siblings
```

All three `|` poems are children of the `- This is` OPEN, not nested inside
each other. The backstep mechanism positions them in this descending
staircase pattern.

Without backstep, you might get:

```rex
- This is
  | These are
  | Backstepped
  | siblings
```

Which would parse as something different (the `|` poems would be HEIRs,
siblings of each other at the same column, rather than successive children
with the staircase layout).

## How Backstep Works

The `PBackstep` combinator in PDoc renders the **later** siblings first to
determine their indentation, then uses that information to position the
**earlier** siblings further to the right. This is a right-to-left
dependency: you need to know where the last sibling lands before you can
position the first one.

From PDoc.hs:
```haskell
PBackstep !Int PDoc PDoc  -- use right's indent to inform left's indent
```

## My Misunderstanding

I initially confused backstep with HEIR alignment. I thought:

- HEIR: siblings at the same column
- Backstep: something similar, maybe also about alignment

But they're completely different:

- **HEIR**: Multiple forms at the **same** column, creating vertical siblings
- **Backstep**: Multiple OPEN children at **decreasing** indentation levels,
  creating the reverse staircase pattern

I also incorrectly gave this example:

```rex
+ a * b c
    - d e
```

And claimed `- d e` was "backstepped" relative to `* b c`. But this is wrong:
`- d e` is a **child** of `* b c`, not a sibling. The structure is nested:

```
OPEN "+"
  WORD "a"
  OPEN "*"
    WORD "b"
    WORD "c"
    OPEN "-"
      WORD "d"
      WORD "e"
```

Backstep only applies when multiple OPENs are **siblings** (children of the
same parent OPEN), not when they're nested.

## When Backstep Applies

Backstep is used in `openChildrenVertical` when rendering an OPEN's children
in vertical mode, and one of those children is itself an OPEN (or BLOC or
HEIR, per `isOpenRex`). The backstep ensures that sibling OPEN children
form the correct reverse staircase pattern rather than appearing nested.
