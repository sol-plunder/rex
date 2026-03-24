# TODO: Line massage (merge consecutive lines that fit)

## Problem

Our printer uses `PChoice` to pick between flat and vertical layouts, but
doesn't have the "greedily merge consecutive lines" optimization. This causes
output to be more spread out than necessary.

## Example

Current output:
```rex
| foo bar
              | h
            | g
          | f
        | e
      | d
    | c
  | b
| a
```

Desired output (after massage):
```rex
| foo bar     | h
            | g
          | f
        | e
      | d
    | c
  | b
| a
```

The first backstepped element `| h` can merge onto the `| foo bar` line because
its target indent (column 14) is to the right of where `| foo bar` ends (~column 10).

The subsequent elements can't merge because their indents are *less* than where
the previous line ended (the staircase goes down/left).

## When Massage Applies

This only applies to rune poems with backstep. You can't merge block forms like:

```rex
foo =
    bar
```

Into `foo = bar` without changing the syntax. The backstep pattern in rune poems
is special because the runes make the structure explicit regardless of whether
elements are on the same line or different lines.

## Implementation Strategy

Build the merge logic directly into `PBackstep` rendering in PDoc.hs.

`PBackstep` already has special rendering logic - it renders the right side
first to determine indentation. We enhance it with a merge check:

When rendering `PBackstep step left right`:
1. Render `right` first to get its layout (as currently done)
2. Determine `right`'s target indent
3. When transitioning from `left` to `right`:
   - **Current behavior**: always emit newline + indent, then render right
   - **New behavior**: if `targetIndent > currentColumn`, emit spaces to reach
     that indent (merge onto same line); otherwise emit newline + indent (break)

The check `targetIndent > currentColumn` is exactly the massage condition:
"does the next element want to start to the RIGHT of where I ended?"

This keeps the merge behavior localized to backstep contexts where it's
semantically valid, rather than being a general-purpose post-processing pass.

### Pseudocode

```haskell
renderBackstep step left right col indent width =
    let (rightResult, rightIndent) = renderRight right ...
        leftResult = renderLeft left ...
        leftEndCol = ... -- column where left's content ended
    in if rightIndent > leftEndCol
       then leftResult <> spaces (rightIndent - leftEndCol) <> rightResult  -- merge
       else leftResult <> newline <> spaces rightIndent <> rightResult       -- break
```

## Old Implementation (for reference)

The old printer's `massage` function worked as a post-processing pass:
```haskell
massage :: [(Int, RexBuilder)] -> [(Int, RexBuilder)]
massage []                 = []
massage [x]                = [x]
massage ((d,x):(e,y):more) =
    let diff = e - (d + x.width)
    in if (diff > 0) then
        massage ((d, x <> indent diff <> y) : more)
    else
        (d,x) : massage ((e,y):more)
```

Our approach achieves the same result but integrated into PDoc rendering.

## Related

- `src/hs/Rex/PrintRex.hs` - `openDoc`, `heirDoc`, `pdocBackstep`
- `src/hs/Rex/PDoc.hs` - `PBackstep` rendering logic
- `note/backstep-understanding.md` - explains the reverse staircase pattern
- `ctx/Print.hs` - `massage`, `blockLines`, `renderLines`
