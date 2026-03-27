# Rex Printer Implementation Reference

This document describes the implementation of the Rex pretty-printer in
`lib/Rex/PrintRex.hs` and the underlying layout engine in `lib/Rex/PDoc.hs`.

## Overview

The Rex printer transforms Rex IR (intermediate representation) back into
Rex source notation. It produces width-aware output that adapts layout
based on a configurable page width, choosing between flat (single-line)
and vertical (multi-line) layouts as appropriate.

The system has two layers:

1. **PDoc** (`Rex.PDoc`) - A document layout engine that handles the
   mechanics of fitting content within page width, indentation, and
   layout choices.

2. **PrintRex** (`Rex.PrintRex`) - The Rex-specific printer that maps
   Rex constructors to PDoc documents, encoding Rex's layout semantics.

## Rex IR Constructors

The printer handles all Rex IR constructors:

| Constructor | Description | Example |
|-------------|-------------|---------|
| `LEAF` | Atomic tokens (words, strings) | `foo`, `"text"`, `'quip` |
| `NEST` | Infix bracket forms | `(a + b)`, `{x , y}` |
| `EXPR` | Application bracket forms | `(f x)`, `[a b c]` |
| `PREF` | Tight prefix | `-x`, `:y` |
| `TYTE` | Tight infix | `x.y`, `a:b:c` |
| `JUXT` | Tight juxtaposition | `f(x)`, `a(b)[c]` |
| `OPEN` | Rune poems (layout prefix) | `+ x y z` |
| `HEIR` | Vertically-aligned siblings | `+ x`<br>`+ y` |
| `BLOC` | Block forms | `def f:`<br>`    body` |

## PDoc: The Layout Engine

### Document Type

PDoc is a pretty-printing document type inspired by Wadler's "A Pretty
Printer" algorithm, extended with constructs for Rex's unique layout
patterns.

```haskell
data PDoc
    = PEmpty                    -- empty document
    | PChar  Char               -- single character
    | PText  Int String         -- text with precomputed length
    | PSpace                    -- layout space (dropped before newlines)
    | PLine                     -- newline + current indentation
    | PCat   PDoc PDoc          -- concatenation
    | PDent  PDoc               -- set indent to current column
    | PChoice PDoc PDoc         -- try left, fallback to right
    | PNoFit PDoc               -- force PChoice to use right branch
    | PStaircase Int [PDoc]     -- reverse-staircase layout
    | PFlow Int Bool [PDoc]     -- flow layout (pack items on lines)
```

### Key Constructs

#### PChoice: Layout Decisions

`PChoice flat vertical` tries the flat layout first. If it fits within
the remaining page width, it's used. Otherwise, the vertical alternative
is rendered.

```
PChoice (text "a + b + c")        -- flat: a + b + c
        (vcat ["a", "+ b", "+ c"]) -- vertical:
                                   --   a
                                   -- + b
                                   -- + c
```

#### PDent: Indentation Capture

`PDent doc` sets the indentation level to the current column position
for the duration of `doc`. This is crucial for aligning continuation
lines:

```
"prefix: " <> PDent (multilineContent)
-- Results in:
-- prefix: first line
--         continuation aligned to column 8
```

#### PNoFit: Forcing Vertical Layout

`PNoFit doc` marks a document as "never fitting" in a PChoice. When
encountered in the left branch of a PChoice, the renderer immediately
falls back to the right branch. This is used for inherently vertical
constructs like OPEN, HEIR, and SLUG.

#### PStaircase: Reverse-Staircase Layout

`PStaircase step items` renders items in a reverse-staircase pattern
where the first item appears at the deepest indentation and each
subsequent item is dedented by `step` columns (typically 4).

```
| if cond1 result1
       | if cond2 result2
              | fallback
```

The first item may inline with spaces if it fits; subsequent items
always get newlines.

#### PFlow: Flow Layout

`PFlow maxW isFirst items` packs small items greedily onto lines,
wrapping when the line is full.

- Items within `maxW` characters that fit on the current line are
  packed with spaces between them
- Items exceeding `maxW` or containing newlines get their own line
- `isFirst` tracks whether we need a leading space

```
-- Flow layout with maxW=30, page width 50:
foo bar baz qux quux corge
grault garply waldo fred
```

### Rendering Algorithm

The renderer uses a work-list based algorithm:

1. Documents are placed on a work list with their indentation level
2. The `best` function processes the work list, accumulating rendered
   output (`SDoc`)
3. For `PChoice`, both branches are speculatively rendered and
   `sdocFits` checks if the first fits within remaining width
4. `SDoc` (rendered document) is converted to a final String, with
   trailing spaces before newlines dropped

### SDoc: Rendered Documents

```haskell
data SDoc
    = SEmpty
    | SChar  Char SDoc
    | SText  Int String SDoc
    | SSpace Int SDoc           -- layout spaces (dropped before newlines)
    | SLine  Int SDoc           -- newline with indentation level
    | SNoFit SDoc               -- marker for PChoice decisions
```

The `sdocFits` function checks if an SDoc fits within a given width:
- Returns `True` on newlines (fresh line has full width)
- Returns `False` on `SNoFit` (explicitly marked as not fitting)
- Decrements available width for characters/text

The `sdocFitsFlat` variant is stricter: it rejects newlines, used by
PFlow to verify items are truly single-line.

## PrintRex: Rex-Specific Layout

### Configuration

```haskell
data PrintConfig = PrintConfig
    { cfgColors    :: ColorScheme  -- NoColors | BoldColors
    , cfgDebug     :: Bool         -- show structural markers
    , cfgMaxFlow   :: Int          -- max item width for flow (default 30)
    , cfgMaxInline :: Int          -- max width for inlining (default 50)
    }
```

Debug mode wraps constructs with Unicode markers to show structure:
- `«»` for CLEAR nests/exprs
- `‹›` for PREF
- `⟪⟫` for TYTE and JUXT
- `⟨⟩` for OPEN and HEIR
- `⟦⟧` for BLOC head+rune

### LEAF: Atomic Tokens

Leaves are the simplest case. Single-line leaves render directly.
Multi-line leaves use special formatting:

| Shape | Single-line | Multi-line |
|-------|-------------|------------|
| WORD | `foo` | (rare) |
| QUIP | `'value` | Lines aligned to `'` position |
| CORD | `"text"` | Continuation lines aligned after `"` |
| TAPE | - | Block form with `"` delimiters |
| PAGE | - | Block form with `'''` delimiters |
| SPAN | `'''text'''` | Content aligned after `'''` |
| SLUG | `' text` | Each line prefixed with `' ` |

Multi-line string formatting uses `PDent` to capture alignment:

```haskell
-- CORD multi-line: '"' then PDent captures column for continuations
formatCordMulti cfg (l:ls) =
    PCat (cStringChar cfg '"')
         (PDent (PCat (cString cfg (escapeQuotes l))
                      (PCat (cordRest ls)
                            (cStringChar cfg '"'))))
```

In debug mode, all string types render as SLUGs to show extracted
content unambiguously.

### NEST: Infix Bracket Forms

`NEST color rune kids` represents infix expressions like `(a + b + c)`.

Layout options:
```
Flat:     (a + b + c)
Outlined: ( a
          , b
          , c
          )
```

The outlined form puts the closing bracket on its own line, aligned
with the opening bracket. Children are separated by ` rune `.

For CLEAR (unbracketed) nests like `a + b`, the rune is the separator
without brackets.

Special case: single element with trailing rune renders as `(x +)`.

### EXPR: Application Forms

`EXPR color kids` represents application forms like `(f x y)`.

Children are space-separated. The key complexity is handling OPEN
children that would collide with siblings:

```haskell
exprChildren cfg (k:ks) =
    let sep = if forcesNewline k then PLine else PChoice pdocSpace PLine
    in PCat (rexDoc cfg k) (PCat sep (exprChildren cfg ks))
  where
    forcesNewline (OPEN _ _ _)     = True
    forcesNewline (HEIR _ _)       = True
    forcesNewline (LEAF _ SLUG _)  = True
    forcesNewline _                = False
```

When an OPEN, HEIR, or SLUG is followed by siblings, a forced newline
prevents the sibling from being captured by the OPEN's layout box.

### PREF/TYTE/JUXT: Tight Forms

These forms concatenate without spaces:

- **PREF** `-x`: rune directly attached to child
- **TYTE** `x.y.z`: children joined by rune
- **JUXT** `f(x)[y]`: children concatenated directly

Complex children (OPEN, HEIR, BLOC) get wrapped in parentheses when
used in tight context via `rexDocTight`.

### OPEN: Rune Poems

`OPEN rune kids` is the heart of Rex's visual structure.

Layout strategy:
```
Flat:     RUNE child1 child2 child3
Vertical: RUNE child1
               child2
               child3
```

Children indent past the rune (rune + space). The `PDent` after
`rune + space` captures this indent for continuation lines.

#### Child Grouping

Children are grouped into "closed" (flat) and "open" (vertical) runs:

```haskell
data ChildGroup
    = ClosedGroup [Rex]  -- consecutive closed children
    | OpenGroup   [Rex]  -- consecutive open children
```

- **ClosedGroup**: rendered with `pdocFlow`, packing items on lines
- **OpenGroup**: rendered with `pdocStaircase`, reverse-indent pattern

This grouping prevents backstep from leaking between independent
poem chains.

#### Staircase Layout

When OPEN children are nested, they form a staircase:

```
| if cond1 result1
       | if cond2 result2
              | fallback
```

The first child of a staircase may inline with spaces if it fits:

```
| foo | bar baz     -- bar inlines with spaces
           | qux    -- qux on newline, dedented
```

#### Heir Collision Detection

```haskell
hasOpenThenMore :: [Rex] -> Bool
hasOpenThenMore (x:xs) = forcesVertical x || hasOpenThenMore xs
```

If any non-final child forces vertical layout, the entire OPEN goes
vertical to prevent heir collision (where a sibling would be captured
by an inner OPEN's scope).

### HEIR: Vertically-Aligned Siblings

`HEIR kids` represents siblings that must appear at the same column,
aligned by their rune's last character.

```
:= x/y
 | if y=0 !!error
 | if x<y 0
 | #(1 + (x-y / y))
```

The first element sets the rune length baseline. Subsequent elements
are padded to align their runes:

```haskell
heirRest cfg firstRuneLen (k:ks) =
    let currentRuneLen = case k of
            OPEN _ r _ -> length r
            _          -> 1
        padding = max 0 (firstRuneLen - currentRuneLen)
```

Special handling: consecutive SLUGs get `')` separator to prevent
re-parsing as a single multi-line slug.

### BLOC: Block Forms

`BLOC color rune head items` represents block forms with trailing
rune opening a block:

```
def foo(x):
    body1
    body2
```

The head and rune stay on one line, items are indented 4 spaces on
subsequent lines.

## Flat vs. Vertical Decision Flow

1. **rexDoc**: Full layout with PChoice between flat/vertical
2. **rexDocFlat**: Flat-only rendering for use inside flat contexts

When rendering the flat branch of a PChoice, `rexDocFlat` is used for
children. This ensures nested structures don't unexpectedly go vertical
(which would cause the outer flat form to span multiple lines, defeating
the "fits" check).

Inherently vertical constructs (OPEN, HEIR, BLOC, SLUG) are wrapped in
`pdocNoFit` in flat mode, forcing PChoice to select the vertical
alternative.

## Width Calculations

`rexMinWidth` computes the minimum flat width of a Rex without
rendering, used to make quick inline/vertical decisions:

```haskell
rexMinWidth (LEAF _ shape s) = leafWidth shape s
rexMinWidth (NEST _ _ r kids) = 2 + length r + 1 + childrenWidth kids
rexMinWidth (OPEN _ r kids) = length r + 1 + childrenWidth kids
-- etc.
```

This O(n) traversal avoids expensive speculative rendering for
obviously-too-large expressions.

## Color Support

ANSI color codes are supported via `ColorScheme`:

- **Runes**: Yellow (bold for light runes `-`, `` ` ``, `.`)
- **Brackets**: Bold magenta
- **Strings**: Green
- **Quips**: Cyan

Color text uses `PText` with the visible width (not including escape
sequences):

```haskell
colorText BoldColors code s = PText (length s) (esc code ++ s ++ esc "0")
```

## Entry Points

```haskell
-- Basic rendering
printRex :: Int -> Rex -> String
printRex width = render width . rexDoc defaultConfig

-- With colors
printRexColor :: ColorScheme -> Int -> Rex -> String

-- Full configuration
printRexWith :: PrintConfig -> Int -> Rex -> String

-- Get PDoc for custom rendering
rexDoc :: PrintConfig -> Rex -> PDoc
```

## Design Principles

1. **Width-awareness**: All layout decisions respect page width
2. **Structure preservation**: Round-trip parsing produces identical
   trees (modulo normalization)
3. **Visual hierarchy**: Indentation reflects nesting depth
4. **Greedy but bounded**: Flow layout packs items greedily within
   limits
5. **Explicit vertical**: OPEN/HEIR/BLOC are inherently vertical;
   flat layout is a special case when everything fits

## Limitations and Future Work

The current implementation is a straightforward recursive descent that
makes local layout decisions. A more sophisticated approach would use
Pareto frontiers (as in Bernardy's "A Pretty But Not Greedy Printer")
to find globally optimal layouts. This is documented as potential
future work in `note/prettiest.md`.
