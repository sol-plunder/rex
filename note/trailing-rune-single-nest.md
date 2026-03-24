# Trailing Rune for Single-Element NEST

## The Problem

A NEST with a single element must print with a trailing rune, otherwise it
parses back as an EXPR (different tree):

```rex
(foo ,)   -- NEST PAREN "," with one child "foo"
(foo)     -- EXPR PAREN with one child "foo" -- DIFFERENT!
```

Without the trailing rune, round-trip fails.

## The Fix

In `nestDoc`, we special-case single-element NESTs to add the trailing rune:

```haskell
nestDoc c r kids =
    let (open, close) = bracketChars c
        content = case kids of
            [k] -> PCat (rexDoc k) (PCat pdocSpace (pdocText r))  -- trailing rune
            _   -> nestContent c r kids
    in case c of
        CLEAR -> PDent content
        _     -> PCat (PChar open) (PCat (PDent content) (PChar close))
```

For a single child `k`, we output: `child SPACE rune`

Examples:
- `(foo ,)` - single element with comma
- `(bar +)` - single element with plus
- `{x |}` - single element with bar in curlies

## Test Cases

Added in `nests.tests`:
```
=== trailing comma | 80
(foo ,)

=== trailing plus | 80
(bar +)
```
