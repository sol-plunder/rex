# Block Printing in Rex

## What Is a Block?

A block is Rex's mechanism for multi-line sequences. In source, a block
is triggered when a line ends with exactly one free rune, followed by
indented content on subsequent lines:

    f =
       a
       b
       c

The rune (`=`) opens the block. The indented lines (`a`, `b`, `c`) are
the block's items. Each item is parsed like the inside of a nest.

## Tree Structure

In the parse tree, a block appears as a sibling of the head content and
rune, all inside an enclosing context (a nest, item, or top-level input).
The enclosing node list looks like:

    [head_nodes..., RUNE, BLOCK[ITEM[...], ITEM[...], ...]]

For example, `def foo(x):\n    return x` produces:

    CLEAR
      CLUMP: "def"
      CLUMP: "foo" PAREN("x")
      RUNE: ":"
      BLOCK
        ITEM: CLUMP("return") CLUMP("x")

The block is always the last child. The rune always immediately
precedes it. The head nodes are everything before the rune.

## How Block Printing Should Work

The printer must produce output that re-parses to the same tree. The
critical rules:

1. **The rune stays on the head's line.** The head content and the
   block-opening rune are all on one line. There is no line break
   between the last head node and the rune.

2. **Items start on the next line.** The first item does NOT go on
   the rune's line. All items begin on their own lines, below the
   rune.

3. **Items are indented.** All items must be indented further than
   the first content on the head's line. This is what triggers the
   block during re-parsing. A fixed 2-space indent relative to the
   enclosing context works.

4. **Items are at the same column.** All items in a block share the
   same indentation level. When a new line appears at that level,
   it starts a new item. When a line appears at lesser indentation,
   the block ends.

## Correct Output Examples

Simple block:

    f =
      a
      b

Block with compound head:

    def foo(x) =
      a
      b

Block inside brackets:

    (f =
       a
       b)

Note that inside brackets, the indent is relative to the bracket's
column, not column 0.

Nested block (an item contains its own block):

    f =
      g :
        x
        y
      b

The inner block `g :\n    x\n    y` is one item of the outer block.
The second item `b` returns to the outer block's indentation level.

## Common Mistakes

- **Putting the first item on the rune's line:** `f = a\n    b` looks
  plausible but doesn't re-parse correctly as a block. The parser sees
  `f = a` as a complete line (infix expression), then `b` as a
  separate top-level form.

- **Inlining all items:** `f = a b c` treats the block as a flat
  expression. For a single-item block this might accidentally work
  (as infix), but it changes the tree structure. For multi-item
  blocks it produces the wrong tree entirely.

- **Using `pdocSpaceOrLine` before the block:** This allows the
  layout engine to put the block on the same line as the rune when
  it fits, which is never correct. The block must always start on
  a new line.

## Implementation Notes

In `nodeSep`, a block node must be recognized and handled specially.
When the next node is a block, the current node (the rune) is
concatenated directly (no space after it), and the block's own
rendering handles the line break and indentation.

`blockDoc` emits: `PLine` (newline to enclosing indent), then a
fixed indent (`"  "`), then `PDent` to capture that column, then
items separated by `PLine`. The `PDent` ensures that subsequent
items and any content within items that wraps will align to the
block's indentation column.

For blocks inside brackets, the enclosing `nestContent` uses `PDent`
at the bracket's column. The block's `PLine` returns to that column,
then the `"  "` adds the 2-space offset. This produces correct
bracket-relative indentation automatically.
