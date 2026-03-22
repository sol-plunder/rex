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

The printer is given a Rex tree and a set of alternative representations at
each node. It selects among those alternatives based on line width and ergonomic
considerations — essentially solving a layout problem rather than a semantic
one. This is a well-defined, language-agnostic task.

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

## The Implementation Challenge

A previous version of Rex had a working pretty-printer that performed well.
This version of Rex is more sophisticated — it allows complex expressions inside
tightly nested forms — so the printer logic needs to be correspondingly more
sophisticated.

The main technical challenge is that Rex's layout rules don't map cleanly onto
existing pretty-printing systems (Wadler-Lindig, etc.). Standard combinators
assume particular layout semantics that don't match Rex's poem/block/heir model.
The printer needs its own layout engine that understands Rex's specific rules
about indentation, heir alignment, and the interaction between tight and spaced
forms.

`Lib.hs` contains the most developed attempt at this — a Wadler-Lindig-based
engine with `Flow`/`paragraphs` grouping logic and slug-jogging for adjacent
slugs — but it is not yet connected to the main pipeline and predates the
current Rex IR.

## Status

- The dumb printer (`Rex.Print`) produces valid Rex output but makes no
  aesthetic decisions about line width or layout alternatives.
- `Lib.hs` has a real layout engine but is disconnected from the pipeline.
- The C printer in `rex.c` has partial wide/tall logic but heir handling,
  tight infix unwrapping, and juxtaposition wrapping are incomplete or buggy.

The next step is to build a layout engine that understands Rex's own rules and
can select among the alternative representations each node admits.
