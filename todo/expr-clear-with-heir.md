# TODO: EXPR CLEAR with HEIR child prints incorrectly

## Problem

When an EXPR CLEAR contains a HEIR as one of its children, the output merges
content incorrectly onto a single line.

## Example

Input (simple.rex):
```rex
'(])
  + x
  + y
x ' Slug
  ' Slug
```

Parses as:
```
QUIP "'(])"

EXPR CLEAR
  HEIR
    OPEN "+"
      WORD "x"
    OPEN "+"
      WORD "y"
  WORD "x"
  SLUG "' Slug\n' Slug"
```

Current output:
```rex
'(])

+ x
+ y x ' Slug
' Slug
```

The `+ y x ' Slug` line is wrong - the HEIR (`+ x`, `+ y`) and the following
children (`x`, SLUG) are getting merged.

## Expected Output

```rex
'(])

+ x
+ y
x ' Slug
' Slug
```

Or possibly with proper indentation to show the EXPR structure.

## Cause

The `exprDoc` function uses `pdocIntersperseFun pdocSpaceOrLine` to join
children. When a child is a HEIR (which spans multiple lines), the
`pdocSpaceOrLine` after it may choose a space instead of a newline, merging
the next child onto the last line of the HEIR.

## Possible Fix

Similar to `nestContent`, check if a child `containsHeir` and force a newline
after it instead of using `pdocSpaceOrLine`.
