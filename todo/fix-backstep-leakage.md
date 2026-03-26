# Fix: PBSReset — Backstep Leakage Between Independent Groups

## The Bug

PBackstep's renderer measures backstep from its `y` argument PLUS
the entire work list continuation (`ds`). This means that when two
independent backstep groups appear in sequence, the later group's
backstep leaks into the earlier group's calculation, pushing it
too far right.

### Reproduction

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

This is an HEIR with three children: `+ foo (with 4 children)`,
`+ bar (with 4 children)`, `+ zaz`. Each OPEN's children form
their own backstep staircase.

### Current (wrong) output

```
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

The `+ a / + b` pair in the first group is pushed to indent 10
instead of 6. The backstep from `+ bar`'s children (4) leaks
backward through the heir rendering, adding extra offset to
`+ foo`'s children.

### Expected output

```
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

Both groups should have identical staircase shapes.

## Root Cause

In the PDoc renderer, `best` returns `(Int, SDoc)` where the Int
is a backstep accumulator. Almost every PDoc constructor is
transparent to this accumulator — PCat, PLine, PText, PChar all
pass through the backstep from whatever follows in the work list.

PBackstep is the only constructor that *produces* backstep, but
nothing *absorbs* it. So backstep from a later PBackstep propagates
backward through any intervening nodes into an earlier PBackstep's
calculation.

The relevant renderer code:

```haskell
PBackstep b x y ->
    let (backstep, ylist) = best n k (DLCons i y ds)
        --                                       ^^
        -- ds includes everything after this node,
        -- including later PBackstep groups
        ip = i + backstep + b
        ...
    in (backstep + b, xlist)
```

## Fix

### New PDoc constructor

```haskell
data PDoc
    = ...
    | PBSReset PDoc
    -- ^ Render contents normally, but return backstep = 0.
    -- Prevents backstep from leaking out of independent groups.
```

### Renderer additions

DLCons case:

```haskell
PBSReset x ->
    let (_, rest) = best n k (DLCons i x ds)
    in (0, rest)
```

DLSCons case:

```haskell
PBSReset x ->
    let (_, rest) = best n k (DLSCons i x bs ss)
    in (bs, rest)
```

In the DLSCons case we return `bs` (the enclosing PBackstep's
accumulator) rather than 0, because DLSCons is already inside
an outer PBackstep that manages its own accumulator.

Actually — let me reconsider. In DLSCons, when we hit PEmpty we
return `(bs, ss)`. For PBSReset, we want to prevent the inner
content's backstep from propagating, but we still need the outer
bs to flow correctly. The content `x` might itself contain
PBackstep nodes whose backstep should NOT leak out. So:

```haskell
PBSReset x ->
    best n k (DLSCons i x bs ss)
```

Wait, this doesn't reset anything. The issue is subtle in DLSCons.

Let me think about when PBSReset appears inside a DLSCons context.
This happens when PBSReset is inside the `x` (left) branch of an
outer PBackstep. In that case, the PBSReset is rendering content
that will be placed at a backstep-computed indent. The backstep
from within PBSReset shouldn't affect the outer PBackstep's
accumulator — but in DLSCons, the outer accumulator `bs` is
already fixed (it was computed from the outer PBackstep's `y`).
DLSCons always returns `(bs, ss)` at PEmpty, regardless of what
happened inside. So PBSReset in DLSCons doesn't need special
handling — the backstep is already isolated by DLSCons itself.

```haskell
-- DLSCons case: just render normally, DLSCons handles isolation
PBSReset x ->
    best n k (DLSCons i x bs ss)
```

### Where to insert PBSReset

Anywhere an independent backstep group is built. Currently, the
only place backstep groups are built is `openChildrenVertical` /
`openRestAfterOpen` in PrintRex.hs.

The fix: when `openChildrenVertical` encounters an open child and
calls `pdocBackstep`, the result should be wrapped in PBSReset so
the backstep doesn't leak into whatever precedes it.

But wait — the staircase WITHIN a single group needs backstep to
propagate between its PBackstep nodes. PBSReset should wrap the
entire group, not individual steps.

The structure for a poem with children `[a, +b, +c, d]`:

```
rexDoc a
PLine
PBSReset (pdocBackstep (+b) (pdocBackstep (+c) (PLine (rexDoc d))))
```

Or for `[+b, +c, +d]` (all open):

```
PBSReset (pdocBackstep (+b) (pdocBackstep (+c) (PLine (rexDoc +d))))
```

The PBSReset wraps the entire chain so its backstep doesn't leak
into preceding content or into an enclosing PBackstep from a
parent poem.

### Concrete code change in PrintRex.hs

Current:

```haskell
openChildrenVertical cfg (k:ks)
    | isOpenRex k = pdocBackstep (rexDoc cfg k) (openRestAfterOpen cfg ks)
    | otherwise   = PCat (rexDoc cfg k) (PCat PLine (openChildrenVertical cfg ks))
```

Changed:

```haskell
openChildrenVertical cfg (k:ks)
    | isOpenRex k = PBSReset (pdocBackstep (rexDoc cfg k) (openRestAfterOpen cfg ks))
    | otherwise   = PCat (rexDoc cfg k) (PCat PLine (openChildrenVertical cfg ks))
```

Wait — this wraps each backstep call individually. If we have
`[+a, +b, x, +c, +d]`, the first `isOpenRex` hit produces:

```
PBSReset (pdocBackstep (+a) (openRestAfterOpen [+b, x, +c, +d]))
```

And `openRestAfterOpen` continues building the chain. `+b` is open,
so it does `pdocBackstep (+b) (openRestAfterOpen [x, +c, +d])`.
Then `x` is closed: `PCat PLine (PCat (rexDoc x) (openRestAfterOpen [+c, +d]))`.
Then `+c` is open: `pdocBackstep (+c) (openRestAfterOpen [+d])`.
Then `+d` is open: wait, there's only one, so `PCat PLine (rexDoc +d)`.

So the whole thing is:

```
PBSReset
  (pdocBackstep (+a)
    (pdocBackstep (+b)
      (PCat PLine (PCat x
        (pdocBackstep (+c)
          (PCat PLine (rexDoc +d)))))))
```

The `+c/+d` backstep leaks into `+a/+b`'s calculation! PBSReset
only wraps the outermost level — it doesn't help with the inner
boundary at `x`.

The fix needs to be: wrap PBSReset around each INDEPENDENT backstep
group. Two backstep groups are independent when they're separated
by a non-open child.

So `openRestAfterOpen` needs to detect the transition from
open→closed→open and insert PBSReset at each boundary:

```haskell
openRestAfterOpen :: PrintConfig -> [Rex] -> PDoc
openRestAfterOpen _   []     = PEmpty
openRestAfterOpen cfg [k]    = PCat PLine (rexDoc cfg k)
openRestAfterOpen cfg (k:ks)
    | isOpenRex k = pdocBackstep (rexDoc cfg k) (openRestAfterOpen cfg ks)
    | otherwise   = PCat PLine (PCat (rexDoc cfg k) (openRestRestart cfg ks))

-- After a closed child interrupts a backstep chain, start a new
-- independent group
openRestRestart :: PrintConfig -> [Rex] -> PDoc
openRestRestart _   []     = PEmpty
openRestRestart cfg [k]    = PCat PLine (rexDoc cfg k)
openRestRestart cfg (k:ks)
    | isOpenRex k = PBSReset (pdocBackstep (rexDoc cfg k) (openRestAfterOpen cfg ks))
    | otherwise   = PCat PLine (PCat (rexDoc cfg k) (openRestRestart cfg ks))
```

Hmm, but this still has the problem. The `openRestAfterOpen` for
the first group continues into the closed child and then into
`openRestRestart`. The backstep from `openRestRestart` (which
contains the second group) is still inside the first group's
pdocBackstep tail.

Let me restructure differently. Group the children first, then
render each group independently:

```haskell
openChildrenVertical :: PrintConfig -> [Rex] -> PDoc
openChildrenVertical _   []     = PEmpty
openChildrenVertical cfg [k]    = rexDoc cfg k
openChildrenVertical cfg kids   = renderGroups cfg (groupChildren kids)

data ChildGroup
    = ClosedGroup [Rex]      -- consecutive closed children
    | OpenGroup   [Rex]      -- consecutive open children

groupChildren :: [Rex] -> [ChildGroup]
groupChildren [] = []
groupChildren xs =
    let (closed, rest1) = span (not . isOpenRex) xs
        (open,   rest2) = span isOpenRex rest1
    in case (closed, open) of
        ([], []) -> []
        (cs, []) -> [ClosedGroup cs]
        ([], os) -> OpenGroup os : groupChildren rest2
        (cs, os) -> ClosedGroup cs : OpenGroup os : groupChildren rest2

renderGroups :: PrintConfig -> [ChildGroup] -> PDoc
renderGroups _   [] = PEmpty
renderGroups cfg [g] = renderGroup cfg g
renderGroups cfg (g:gs) =
    PCat (renderGroup cfg g) (PCat PLine (renderGroups cfg gs))

renderGroup :: PrintConfig -> ChildGroup -> PDoc
renderGroup cfg (ClosedGroup kids) =
    pdocIntersperseFun (\x y -> PCat x (PCat PLine y))
                       (map (rexDoc cfg) kids)
renderGroup cfg (OpenGroup kids) =
    PBSReset (renderOpenGroup cfg kids)

renderOpenGroup :: PrintConfig -> [Rex] -> PDoc
renderOpenGroup _   []     = PEmpty
renderOpenGroup cfg [k]    = rexDoc cfg k
renderOpenGroup cfg (k:ks) =
    pdocBackstep (rexDoc cfg k) (renderOpenGroupRest cfg ks)

renderOpenGroupRest :: PrintConfig -> [Rex] -> PDoc
renderOpenGroupRest _   []     = PEmpty
renderOpenGroupRest cfg [k]    = PCat PLine (rexDoc cfg k)
renderOpenGroupRest cfg (k:ks) =
    pdocBackstep (rexDoc cfg k) (renderOpenGroupRest cfg ks)
```

Now each OpenGroup is wrapped in PBSReset, and the groups are
joined with PCat + PLine. The backstep from one OpenGroup can't
leak into another because PBSReset absorbs it.

But wait — there's still the issue that renderGroups uses PCat to
join groups. The second group (wrapped in PBSReset) is in the `ds`
continuation when the first group renders. But the first group's
PBSReset returns backstep=0, so... the first group's internal
PBackstep sees backstep from `ds` which includes the next group.

No — PBSReset wraps the ENTIRE first open group. The PBackstep
nodes inside PBSReset render, and PBSReset returns 0. The PCat
after PBSReset doesn't see the internal backstep.

But the PBackstep INSIDE the PBSReset — when it renders its y,
the `ds` includes everything after PBSReset (the rest of the
groups). Hmm.

OK let me trace very carefully. Structure:

```
PCat (PBSReset (PBackstep 4 A (PBackstep 4 B PEmpty)))
     (PBSReset (PBackstep 4 C (PBackstep 4 D PEmpty)))
```

Work list: `PBSReset(...), PBSReset(...), ds_outer`

Processing first PBSReset:

```haskell
PBSReset x ->
    let (_, rest) = best n k (DLCons i x ds)
    in (0, rest)
```

Where `ds` = `DLCons i (PBSReset(PBackstep C D)) ds_outer`.

So it renders `x` = `PBackstep 4 A (PBackstep 4 B PEmpty)` with
ds = `[PBSReset(CD group), ds_outer]`.

The outer PBackstep (A) renders its y = `PBackstep 4 B PEmpty`
with ds = `[PBSReset(CD group), ds_outer]`.

The inner PBackstep (B) renders its y = `PEmpty` with
ds = `[PBSReset(CD group), ds_outer]`.

PEmpty in DLCons moves to ds: processes `PBSReset(CD group)`.
PBSReset returns (0, rendered_CD). backstep = 0!

So PBackstep B sees backstep = 0. B at indent i+0+4 = 4. Returns 4.
PBackstep A sees backstep = 4. A at indent i+4+4 = 8. Returns 8.

PBSReset absorbs: returns (0, ...).

Then the second PBSReset... but it was already rendered as part of
the first PBSReset's continuation! The PEmpty inside PBackstep B
fell through to ds, which rendered the second PBSReset.

So the second PBSReset is rendered inside the first PBSReset's
`best` call. Its backstep (0) is what PBackstep B sees. That's
correct!

And the first PBSReset returns 0 to whatever is outside. Correct.

**It works!** The key insight: when PBackstep B's PEmpty falls
through to ds and hits the second PBSReset, that PBSReset returns
backstep=0, which is what B sees. So B is positioned correctly.
Then A sees B's backstep (4) and is positioned correctly. The
entire first group is correct, independent of the second group.

## Test Cases

Add to the existing test suite:

```
=== independent backstep groups in heir | 80
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

=== backstep groups separated by closed children | 80
+ foo
      + a
  + b
  x
      + c
  + d

=== single backstep group unchanged | 80
+     + a
  + b
```

## Summary of Changes

### PDoc.hs

1. Add `PBSReset PDoc` constructor to `PDoc` data type
2. Add rendering case in `best` for DLCons:
   ```haskell
   PBSReset x ->
       let (_, rest) = best n k (DLCons i x ds)
       in (0, rest)
   ```
3. Add rendering case in `best` for DLSCons:
   ```haskell
   PBSReset x ->
       best n k (DLSCons i x bs ss)
   ```
4. Export `PBSReset` (or a smart constructor `pdocBSReset`)

### PrintRex.hs

Refactor `openChildrenVertical` and `openRestAfterOpen` to:
1. Group children into runs of closed and open
2. Wrap each open run in PBSReset
3. Join groups with PLine

This can be done with the groupChildren / renderGroups approach
shown above, or by inserting PBSReset at the right points in the
existing recursive structure.
