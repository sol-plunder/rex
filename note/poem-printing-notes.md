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
the same column, open children use backstep:

    + a
      | x y
      | z w

Here `a` is closed (no box), so `| x y` at the same column is
safe. But `| x y` IS open, so `| z w` must be at a lesser column.
Wait — in this example they're at the same column, which is wrong.
The correct output would be:

    + a
          | x y
      | z w

The closed child `a` can be at any column. The first open child
must be pushed right by the total backstep of all subsequent open
siblings.

## PBackstep: The Mechanism

PDoc provides `PBackstep` for computing the staircase dynamically.
The key insight: to know how far right the first sibling goes, you
need to know how many open siblings follow it. But the printer
builds the document tree before rendering, so it can't count ahead.
PBackstep solves this by rendering later siblings first during the
layout pass.

    PBackstep b x y

Renders y first to determine its accumulated backstep. Then renders
x at indent `i + backstep(y) + b`. Returns `backstep(y) + b` as
its own backstep for the next level up.

The `pdocBackstep` combinator wraps this:

    pdocBackstep x y = PBackstep 4 (PCat PLine x) y

`PLine` before x ensures x starts on a new line at the computed
indent. `b=4` is the step size — each level adds 4 columns.

For three siblings, the chain is:

    pdocBackstep poem1 (pdocBackstep poem2 (PLine <> poem3))

Rendering works inside-out:
- poem3 at base indent i, backstep = 0
- poem2 at indent i + 0 + 4 = i+4, backstep = 4
- poem1 at indent i + 4 + 4 = i+8, backstep = 8

Result: poem1 at i+8, poem2 at i+4, poem3 at i. Staircase.

## The Last Sibling Needs PLine

There is a subtlety: `pdocBackstep` puts `PLine` before x (the
earlier sibling), and y (the later sibling) is stitched as a
suffix after x's rendered output. If the last sibling in the
chain is just `printNode poem3` with no `PLine`, it gets
concatenated directly onto the previous sibling's last line of
output — producing garbage like `dddd| e f`.

The fix: after the first open child triggers backstep, ALL
subsequent children (including the last) get `PLine` before them.
This is handled by `poemOpenRest`, a separate function used as the
continuation after the first open sibling:

    poemChildrenVertical (n:ns)
        | isOpen n  = pdocBackstep (printNode n) (poemOpenRest ns)
        | otherwise = PCat (printNode n) (PCat PLine (...))

    poemOpenRest [n]    = PCat PLine (printNode n)  -- last gets PLine
    poemOpenRest (n:ns)
        | isOpen n  = pdocBackstep (printNode n) (poemOpenRest ns)
        | otherwise = PCat PLine (PCat (printNode n) (poemOpenRest ns))

## The Rune's Line

With `pdocBackstep`, the first open child has `PLine` before it
(from the `PCat PLine x` inside `pdocBackstep`). This means the
rune appears alone on its line when all children are open:

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

When not inlineable, only the vertical form (with backstep) is
produced — no `PChoice`, no chance of incorrect flat output.
