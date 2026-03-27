# Rune Poem Printing in Rex

## What Is a Rune Poem?

A rune poem is Rex's primary mechanism for vertical structure. A
free-floating rune (followed by a space) opens a poem, and children
are gathered by indentation — everything indented more than the
rune's column belongs to the poem:

    + a
      b
      c

This parses as `(+ a b c)`. The rune `+` is at column 0. Its
children `a`, `b`, `c` are at column 2 (after `+ `). Everything
to the right and below belongs to the poem until something appears
at the poem's column or to its left.

## The Parsing Box

This is the critical concept for understanding poem printing. A rune
poem claims a rectangular region: from its starting column, extending
rightward to infinity and downward until a token appears at a column
less than the poem's starting position. We call this the poem's
"parsing box."

The parsing box check is strict less-than: `col tok < cxPos ctx`.
Content at the same column as the poem does NOT break out — it stays
inside the poem.

## Flat vs Vertical

A poem with only closed children (words, strings, brackets) can be
rendered flat:

    + a b c

Or vertical:

    + a
      b
      c

The printer offers a `PChoice` between these when the poem is
"inlineable." PDoc's layout engine picks flat when it fits within
the page width, vertical otherwise.

A poem is inlineable when all children except possibly the last are
closed, and the last is either closed or itself inlineable. This
recursive check allows chains of nested poems to go flat:

    + a * b c       (poem + with children: a, poem * with children: b c)

## The Staircase Problem

When a poem has multiple children that are themselves poems (open
children), flat rendering is not possible and vertical rendering
requires special care.

Consider a poem `+` with three child poems `| a b`, `| c d`,
`| e f`. A naive vertical layout puts all children at the same
column:

    + | a b
      | c d
      | e f

This is WRONG. The first `|` poem starts at column 2 and its
parsing box captures everything at column > 2. The second `|` at
column 2 is NOT less than 2, so it does not break out — the first
poem consumes it. The tree would re-parse as the first `|` having
children `a`, `b`, `| c d`, `| e f` — completely different from
the original.

## The Staircase Solution

Each earlier sibling must be indented further right than later
siblings, forming a descending staircase:

    +         | a b
          | c d
      | e f

Now the first `|` is at column 10. Its parsing box captures
everything at column > 10. The second `|` at column 6 is less
than 10, so it breaks out. The third `|` at column 2 is less
than 6, so it breaks out of the second. All three remain within
`+`'s box (column > 0).

The staircase pattern: each open sibling is 4 columns further
right than the one below it.

## Why Only Open Children Need Staircases

Closed children (words, strings, bracket forms) have no vertical
extent. A word like `a` sits on one line and cannot capture
anything below it. So closed siblings can safely share a column:

    + a
      b
      c

`a` at column 2 doesn't create a parsing box. `b` at column 2 is
fine. Only rune poems (and blocks, which have their own printing
rules) create parsing boxes that could capture siblings.

This means the staircase is only needed between open siblings.
Mixed sequences work naturally — closed children use `PLine` at
the same column, open children use the staircase:

    + a
          | x y
      | z w

Here `a` is closed (no box). The first open child `| x y` is at
column 6, the second `| z w` at column 2 — a descending staircase
among just the open children.

## PStaircase: The Mechanism

PDoc provides `PStaircase` for rendering consecutive open children
in a descending staircase pattern. Given a list of documents:

    pdocStaircase [doc1, doc2, doc3]

It renders them with doc1 at the deepest indent, doc2 less indented,
and doc3 at the base indent:

            doc1
        doc2
    doc3

The key properties:

1. **Inside-out rendering**: Later items are rendered first to
   determine the overall shape, then earlier items are positioned.

2. **Backstep isolation**: The staircase returns `backstep=0` so
   its internal indentation doesn't leak to surrounding context.
   Multiple staircases compose cleanly without interference.

3. **Step size**: Each level is 4 columns less indented than the
   previous one.

## The Rune's Line

When all children are open, the first child starts on a new line
(from PStaircase's `PLine`), leaving the rune alone:

    +
              | a b
          | c d
      | e f

The rune `+` is on line 1 by itself. This is valid Rex — the poem
still captures everything below at column > 0. When a poem has a
mix of closed and open children, the closed children appear on the
rune's line before the staircase begins:

    + a b
          | x y
      | z w

Here `a` and `b` are closed, rendered inline after `+ `. Then the
open children form a staircase below.

## Inlineability Revisited

A poem is inlineable only when the staircase is unnecessary: all
children except possibly the last are closed. If the last child is
an open poem, it's inlineable only if ITS children are also
inlineable (recursively). This ensures that flat rendering is only
offered when it produces output that re-parses correctly:

    + a * b c       OK: * b c is the last child, inlineable
    + * a b * c d   NOT inlineable: first child is open

When not inlineable, only the vertical form (with staircase) is
produced — no `PChoice`, no chance of incorrect flat output.
