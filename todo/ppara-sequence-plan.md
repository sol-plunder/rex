# Generic Sequence Printing with PPara

Depends on: PBSReset fix (fix-backstep-leakage.md)

## Summary

Add `PPara` to PDoc for paragraph-flow layout, then build a generic
`seqDoc` in PrintRex that handles all child sequences uniformly:
paragraph flow for closed items, backstep for open items. Replace
all bespoke sequence logic with `seqDoc`.


## Part 1: PPara in PDoc

### Constructor

```haskell
data PDoc
    = ...
    | PPara !Int [PDoc]
    -- ^ Paragraph flow layout.
    -- Int = max item width for inlining.
    -- Items that render flat within the limit share lines.
    -- Items that exceed it get their own line.
```

### sdocFitsFlat

A stricter variant of `sdocFits` that returns False on newlines.
Used by PPara to check whether an item is truly single-line:

```haskell
sdocFitsFlat :: Int -> SDoc -> Bool
sdocFitsFlat w _ | w < 0       = False
sdocFitsFlat _ SEmpty           = True
sdocFitsFlat w (SChar _ x)      = sdocFitsFlat (w - 1) x
sdocFitsFlat w (SText l _ x)    = sdocFitsFlat (w - l) x
sdocFitsFlat _ (SLine _ _)      = False
sdocFitsFlat _ (SNoFit _)       = False
```

### Renderer logic

PPara processes items one at a time, deciding per-item whether to
place it on the current line or start a new one.

Three tiers of item:
- **Small**: renders flat within the item width limit. Participates
  in paragraph flow, can share lines with other small items.
- **Medium**: closed but exceeds item limit. Gets its own line,
  rendered flat.
- **Large**: goes vertical (contains newlines). Gets its own line,
  rendered with full layout.

Per-item decision (k = current column, i = indent):

```
1. Render item speculatively
2. IS_SMALL = sdocFitsFlat maxW rendered
   FITS_HERE = sdocFitsFlat (w - k - 1) rendered
              (room for space + item on current line)

3. If IS_SMALL and FITS_HERE and not first item:
     → emit space + item, continue on same line

4. If IS_SMALL and at line start (k == i):
     → emit item (no leading space), continue

5. If not at line start:
     → emit newline, retry from step 3

6. At line start, not small:
     → emit item as-is (may go vertical)
     → emit newline before next item
```

In `best`:

```haskell
-- DLCons case:
PPara maxW [] ->
    best n k ds

PPara maxW (item:rest) ->
    let (_, rendered) = best n k (DLCons i item DLNil)
        isSmall = sdocFitsFlat maxW rendered
        fitsHere = k == i || sdocFitsFlat (w - k - 1) rendered
        atStart = k == i
    in if isSmall && fitsHere
       then if atStart
            then -- first on line, no space
                 best n k (DLCons i item (DLCons i (PPara maxW rest) ds))
            else -- append with space
                 best n k (DLCons i pdocSpace
                            (DLCons i item
                              (DLCons i (PPara maxW rest) ds)))
       else if not atStart
            then -- wrap to new line, retry
                 let (bs, r) = best i i (DLCons i (PPara maxW (item:rest)) ds)
                 in (bs, SLine i r)
            else -- at start, item is big, emit as-is
                 -- next item needs a new line
                 best n k (DLCons i item
                            (DLCons i PLine
                              (DLCons i (PPara maxW rest) ds)))
```

Note: DLSCons case mirrors DLCons with appropriate bs/ss handling.

### Double rendering cost

Each item is rendered speculatively then potentially rendered again
as part of the real output. This is acceptable because:
- Small items (the common case in PPara) are cheap to render
- Large items fail sdocFitsFlat quickly (hit SLine early)
- PPara lists are typically short (children of one Rex node)


## Part 2: seqDoc in PrintRex

### Classification

```haskell
isOpenSeq :: Rex -> Bool
isOpenSeq (OPEN _ _ _)     = True
isOpenSeq (HEIR _ _)       = True
isOpenSeq (LEAF _ SLUG _)  = True
isOpenSeq _                = False
```

BLOC is NOT open — its items are indented under it, siblings can't
be captured by its parsing box.

### Config

```haskell
data PrintConfig = PrintConfig
    { cfgColors    :: ColorScheme
    , cfgDebug     :: Bool
    , cfgMaxInline :: Int
    }

defaultConfig = PrintConfig NoColors False 20
```

### The generic sequence builder

```haskell
seqDoc :: PrintConfig -> [Rex] -> PDoc
seqDoc cfg items = go items
  where
    maxW = cfgMaxInline cfg

    go [] = PEmpty
    go xs =
        let (closed, rest1) = span (not . isOpenSeq) xs
            (open,   rest2) = span isOpenSeq rest1
        in case (closed, open) of
            ([], []) -> PEmpty
            (cs, []) -> PPara maxW (map (rexDoc cfg) cs)
            ([], os) -> PBSReset (openChain os (plineThen (go rest2)))
            (cs, os) -> PCat (PPara maxW (map (rexDoc cfg) cs))
                             (PBSReset (openChain os (plineThen (go rest2))))

    openChain []     tail = tail
    openChain [k]    PEmpty = PCat PLine (rexDoc cfg k)
    openChain [k]    tail = pdocBackstep (rexDoc cfg k) tail
    openChain (k:ks) tail = pdocBackstep (rexDoc cfg k) (openChain ks tail)

    plineThen PEmpty = PEmpty
    plineThen doc    = PCat PLine doc
```

### Worked example

Sequence: `a b c (+ foo) (+ bar) x y z (+ baz) p q r`
Width: 40, maxW: 20, indent: 2

`go` splits:
- closed = `[a, b, c]`, open = `[+ foo, + bar]`, rest = `[x,y,z,+ baz,p,q,r]`

```
PCat (PPara 20 [a, b, c])
     (PBSReset
       (pdocBackstep (+ foo)
         (pdocBackstep (+ bar)
           (PCat PLine (go [x,y,z,+ baz,p,q,r])))))
```

Inner `go [x,y,z,+ baz,p,q,r]`:
- closed = `[x, y, z]`, open = `[+ baz]`, rest = `[p, q, r]`

```
PCat (PPara 20 [x, y, z])
     (PBSReset
       (pdocBackstep (+ baz)
         (PCat PLine (PPara 20 [p, q, r]))))
```

Full structure:

```
PCat
  (PPara 20 [a, b, c])
  (PBSReset
    (pdocBackstep (+ foo)
      (pdocBackstep (+ bar)
        (PCat PLine
          (PCat
            (PPara 20 [x, y, z])
            (PBSReset
              (pdocBackstep (+ baz)
                (PCat PLine
                  (PPara 20 [p, q, r])))))))))
```

Rendering at indent 2:

PPara [a,b,c] → `a b c`

PBSReset group 1:
- Inner PBSReset (+baz) renders: +baz at indent 2+0+4=6, backstep=4.
  PBSReset returns 0.
- PPara [x,y,z] renders: `x y z`
- PLine: newline
- pdocBackstep (+bar): sees backstep=0 (from PBSReset), +bar at 2+0+4=6, backstep=4
- pdocBackstep (+foo): sees backstep=4, +foo at 2+4+4=10, backstep=8
- Outer PBSReset returns 0

Output:

```
  a b c
          + foo
      + bar
  x y z
      + baz
  p q r
```

Correct!


## Part 3: Updating Call Sites

### openDoc

```haskell
openDoc cfg r kids =
    let runeD = cRune cfg r
        flat = PCat runeD (PCat pdocSpace (openChildrenFlat cfg kids))
        vertical = PCat runeD (PCat pdocSpace (PDent (seqDoc cfg kids)))
    in if any isOpenSeq kids
       then vertical   -- must go vertical, seqDoc handles backstep
       else PChoice flat vertical
```

The flat branch is unchanged (uses rexDocFlat). The vertical branch
uses seqDoc instead of openChildrenVertical.

### exprDoc

```haskell
exprDoc cfg c kids =
    let (open, close) = bracketChars c
        flat = ... -- unchanged, uses rexDocFlat
        vertical = PCat (cBracket cfg open)
                        (PCat (PDent (seqDoc cfg kids))
                              (cBracket cfg close))
    in case c of
        CLEAR -> seqDoc cfg kids   -- no brackets, just the sequence
        _ -> if any isOpenSeq kids
             then vertical
             else PChoice flat vertical
```

### nestContentClear

Replace with `seqDoc cfg kids`. It IS a sequence.

### nestContentOutlined

Keep as-is. The rune separators are structural to the nest form
and don't follow the generic sequence pattern. Each slot between
runes is a single child, and that child's own rexDoc handles its
internal layout.

### blocItemsSep

Keep as-is. Block items are independent top-level forms separated
by PLine. Each item's rexDoc handles its internal layout.

### heirDoc

The heir renderer lays out siblings that are each independently
rendered. Each sibling may contain backstep groups internally
(via its own rexDoc → openDoc → seqDoc). Since heirDoc joins
siblings with PLine and they're independent forms, it doesn't
need seqDoc. Keep as-is.

### Remove

- `openChildrenVertical` — replaced by seqDoc
- `openRestAfterOpen` — replaced by seqDoc


## Part 4: Test Cases

### New test file: sequence-flow.tests

```
=== paragraph flow small items | 20
(a b c d e f g h i j)
---
(a b c d e f g
 h i j)

=== big closed gets own line | 30
(x y (abcdefghijklmnop u v) z)
---
(x y
 (abcdefghijklmnop u v)
 z)

=== poem in expr | 30
+ x + a + b c d
---
+ x
      + a
  + b
  c d

=== alternating groups | 40
a b c + step + step x y z + more p q r
---
a b c
      + step
  + step
x y z
    + more
p q r

=== clear expr with poems | 40
+ x
+ y x y z
---
+ x
+ y
x y z
```

### Regressions

All existing tests must pass. Key risk areas:
- Poem tests: staircase shapes must be identical
- Heir tests: independent backstep groups must be correct
- Expr tests: flat layout unchanged, vertical layout may improve
- Nest tests: outlined form unchanged
- Block tests: unchanged


## Open Questions

1. **maxW default value.** Start with 20, tune from there.

2. **Slug handling.** Slugs are open (need backstep), but a trailing
   slug could potentially share a line with preceding items. Future
   optimization.

3. **PPara first-item space.** The first item in a PPara at the
   start of a line should not get a leading space. The renderer
   logic handles this via the `atStart` check.

4. **PPara inside PDent.** When PPara appears inside
   `PDent (seqDoc ...)` in openDoc, items wrap to the indent set
   by PDent (after rune+space). PLine inside PPara renders at the
   current indent, which is correct.

5. **CLEAR EXPR as top-level.** A CLEAR expr at the top level has
   no framing — seqDoc produces the sequence directly. This
   replaces the current pdocSpaceOrLine-based exprDoc for CLEAR.
