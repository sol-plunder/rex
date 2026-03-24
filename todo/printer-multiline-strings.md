# DONE: Printer must re-indent multi-line strings

**Status:** Completed for all string types (SLUG, TRAD, UGLY).

## Dependency

This depends on `multiline-string-stripping.md` being completed first.
The Rex representation must store stripped content before the printer
can re-indent it.

## Problem

Once multi-line string content is stripped of its original indentation,
the printer must re-add appropriate indentation based on where the string
appears in the output.

## Example

If we have a LEAF containing:
```
Ugly String
Ugly String
```

And it appears after `| foo | bar - ` (column 15), the printer must output:
```rex
| foo | bar - '''
              Ugly String
              Ugly String
              '''
```

Each continuation line needs 14 spaces (to align under the `'` after the
space following `'''`).

## Required Changes to PrintRex.hs

### 1. Detect multi-line content

```haskell
rexDoc = \case
    LEAF shape s
        | '\n' `elem` s -> multiLineLeafDoc shape s
        | otherwise     -> pdocText (formatLeaf shape s)
    ...
```

### 2. Implement multiLineLeafDoc

For each string type:

**UGLY:**
```haskell
-- Input content: "line1\nline2\nline3"
-- Output: '''\n  line1\n  line2\n  line3\n  '''
-- Where indentation is current column + 2 (or based on PDent)
```

**SLUG:**
```haskell
-- Input content: "line1\nline2\n\nline4"
-- Output: ' line1\n' line2\n'\n' line4
-- Each line prefixed with "' " at current column
```

**TRAD:**
```haskell
-- Input content: "line1\nline2"
-- Output: "line1\n  line2"
-- Continuation lines indented to opening quote column + 1
```

### 3. Track column for indentation

May need to use `PDent` to capture the column where the string starts,
then use that for continuation line indentation.

Alternatively, could use a combinator that inserts proper indentation
after each newline in the content.

## Challenges

- Need to know the current output column to compute indentation
- PDoc doesn't directly expose current column; it's computed during rendering
- May need a new PDoc primitive or a different approach

## Possible Approaches

1. **Pre-process in rexDoc**: Convert multi-line content to a PDoc that
   explicitly handles each line, using PDent to capture alignment

2. **New PDoc combinator**: `PIndentedText String` that renders a string
   with all embedded newlines followed by current-column indentation

3. **Post-process**: Render to string, then fix up indentation (hacky)

Approach 1 seems cleanest - treat multi-line strings as multiple PDoc
fragments joined by PLine.
