# Slug-in-HEIR Implementation Notes

This documents the implementation details of the docstring feature where slugs
can participate in HEIR forms.

## Implementation

The feature is implemented through three coordinated changes:

### Block Splitter (`Lex.hs`)

The block splitter tracks `wasSlug` alongside `wasRune`. When in `SINGLE_LN`
mode and a slug was the last content token, the block continues into `BLK` mode
rather than ending. This keeps the slug and following content in the same block.

```haskell
SINGLE_LN
  | null stk && ty t == EOL && eol == 1 ->
      if wasRune || wasSlug then ([t], BLK)
      else ([Tok EOB ...], OUTSIDE)
```

### Tree Parser (`Tree2.hs`)

When a SLUG token appears in `stepSpaced`, it starts a `CT_POEM` context at its
column, similar to how a FREE rune does:

```haskell
SLUG ->
    pushInto (mkLeaf tok) (lin tok) (off tok) (tokEnd tok)
     $ SE_CTX (mkCtx CT_POEM (lin tok) (col tok) (off tok))
     : closeClump (SE_CTX ctx : rest)
```

### Rex Extractor (`Rex.hs`)

When `convertPoem` encounters a poem starting with `N_LEAF` (a slug) rather
than `N_RUNE`, it flattens everything into a HEIR:

```haskell
convertPoem src blockOff sp pos (N_LEAF leafSp lf : rest) =
    let slug = leafToRex leafSp lf
        allNodes = rest
        flattened = concatMap (flattenHeir . convertNode src blockOff) allNodes
    in mkHeir sp (slug : flattened)
```

## Printing Considerations

### Slugs Never Collapse Inline

Slugs are line-oriented by nature. The printer wraps slug output in `pdocNoFit`
to ensure they always force vertical layout:

```haskell
SLUG | '\n' `elem` s -> pdocNoFit (formatSlugMulti cfg (lines s))
     | otherwise     -> pdocNoFit (formatSlugSingle cfg s)
```

### Consecutive Slugs Need Separators

When two SLUGs appear consecutively as HEIR siblings, printing them on adjacent
lines would cause them to be re-parsed as a single multi-line slug:

```
' First slug
' Second slug
```

This parses as ONE multi-line slug, not two separate slugs.

The printer inserts `')` (an empty note) between consecutive slugs to break the
continuation:

```haskell
sep = case (k, ks) of
    (LEAF _ SLUG _, LEAF _ SLUG _ : _) -> PCat PLine (pdocText "')")
    _ -> PEmpty
```

Result:
```
' First slug
')
' Second slug
```

This round-trips correctly as two separate SLUG nodes.
