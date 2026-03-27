# Rex Pretty-Printing

## The Core Advantage Over S-Expressions

S-expression pretty-printers in practice need to know a lot about the input
language to produce reasonable output. A printer for Lisp has to recognize that
`defun` means something, that the argument list goes on the first line, that the
body is indented — none of this is recoverable from the tree structure alone.
Without that baked-in knowledge, output is mechanical and unreadable.

Rex printers work differently. By the time the printer sees a Rex tree, the
decisions about layout intent are already encoded in the tree structure itself.
A language targeting Rex chooses *which Rex form* to emit — block layout, poem
layout, tight infix, spaced infix — and that choice carries most of the
formatting information the printer needs. The printer doesn't have to guess what
the programmer intended; it reads that intent directly from the tree.

The result is much better output with no language-specific assumptions baked
into the printer. A single Rex printer works well across all Rex-based languages
without knowing anything about their semantics or conventions.

## How It Works

The printer is given a Rex tree and renders it based on page width constraints.
It selects among layout alternatives (flat vs vertical) based on whether content
fits within the available width — essentially solving a layout problem rather
than a semantic one. This is a well-defined, language-agnostic task.

The key structural property is that the Rex tree shape determines most of what
you want. A `BLOC` node says "put items on separate indented lines." An `OPEN`
node says "this is a layout-prefix form." A `NEST` node says "this fits in
delimiters." The printer just needs to find a valid textual rendering of that
structure, not rediscover its intent.

## Partiality

Not all instances of the Rex data type can be printed and then read back
correctly. For example, juxtaposing `(WORD "a")` and `(WORD "b")` doesn't
round-trip — it comes back as `(WORD "ab")`. This is expected and acceptable.

The invariant the printer guarantees is: **anything you parse can be printed
back to equivalent input**. Programmatically constructed Rex trees that violate
structural constraints are the caller's responsibility. Rex is a partial data
structure from the printer's perspective — valid in the sense of "produced by
the parser" does not mean the same as "any value of the Rex type."

## Implementation

The printer is implemented in `Rex.PrintRex`, using the `Rex.PDoc` layout engine.

`Rex.PDoc` is a Wadler-style pretty-printing library extended with:

- **PStaircase** for reverse-staircase indentation patterns in rune poems
- **PFlow** for greedy line-packing of closed children
- **PNoFit** for marking inherently vertical constructs

The printer handles all Rex constructs including:

- Flat vs vertical layout choices based on page width
- Heir structures (vertically-aligned sibling poems)
- Staircase layout for consecutive open children
- Flow layout for closed children in poems
- Multi-line strings (PAGE, SPAN, SLUG, TAPE, CORD)
- Tight infix, prefix runes, and juxtaposition
- Block mode with trailing runes

See `note/printer-implementation.md` for detailed documentation of the
printer's architecture and layout algorithms.
