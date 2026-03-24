# DONE: Multi-line strings need content stripping in Rex.Rex

**Status:** Completed for all string types (SLUG, TRAD, UGLY).

## Problem

Multi-line strings (UGLY, SLUG, and multi-line TRAD) are stored with their
original indentation intact. This causes incorrect output when the printer
renders them at a different indentation level.

## Example

Input:
```rex
| foo
  | bar
    - '''
      Ugly String
      '''
```

Current output:
```rex
| foo | bar - '''
      Ugly String
      '''''
```

The content lines `      Ugly String` have their original 6-space indent,
but now they follow `| foo | bar - '''` which puts the opening at a
completely different column. The result doesn't parse back correctly.

## The Three String Types Affected

### 1. UGLY strings (`'''...'''`)

```rex
- '''
  Ugly String
  Ugly String
  '''
```

Currently stored as: `"'''\n  Ugly String\n  Ugly String\n  '''''"`

Should be stored as: `"Ugly String\nUgly String"` (content only, no quotes,
leading indent stripped based on the quote line's column)

### 2. SLUG strings (`' ...` lines)

```rex
' foo
' bar
'
' zaz
```

Currently stored as: `"' foo\n' bar\n'\n' zaz"`

Should be stored as: `"foo\nbar\n\nzaz"` (content only, `' ` prefix stripped)

### 3. Multi-line TRAD strings (`"..."`)

```rex
- "trad string
   this line has no leading whitespace"
```

Currently stored as: `"\"trad string\n   this line has no leading whitespace\""`

Should be stored as: `"trad string\nthis line has no leading whitespace"`
(no quotes, continuation lines stripped of indent up to the opening quote's
column)

## Required Changes

### Phase 1: Rex.Rex - Strip content on construction

In `rexFromBlockTree` (or wherever LEAFs are created), process the raw
lexeme content:

1. **UGLY**: Remove opening/closing `'''`, strip leading whitespace from
   each line based on the column of the opening quote
2. **SLUG**: Remove `' ` prefix from each line, join into single string
3. **TRAD**: Remove quotes, strip leading whitespace from continuation
   lines based on the column of the opening quote

May need to pass column information from the lexer through to this stage.

### Phase 2: Rex.PrintRex - Re-indent on output

The printer needs to:

1. Detect multi-line LEAF content (contains `\n`)
2. Determine current output column
3. Re-indent continuation lines to align with the opening
4. Add appropriate quoting back (`'''`, `' `, or `"`)

### Invariants to Enforce

- UGLY/TRAD continuation lines must be indented >= opening quote column
- SLUG lines must all start with `'` at the same column
- Empty lines are allowed (become blank lines in the stripped content)

## Related

- `src/hs/Rex/Lex.hs` - `lexUgly`, `lexSlug` - where raw content is captured
- `src/hs/Rex/Rex.hs` - `rexFromBlockTree` - where LEAFs are created
- `src/hs/Rex/PrintRex.hs` - `rexDoc` LEAF case - where printing happens
