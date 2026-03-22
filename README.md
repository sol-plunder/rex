This is a research implementation of the new Rex parsing system.  The main
remaining task is to figure out how to build a good pretty printer for
this, which is somewhat complicated by the nicer features of Rex.

Once this is stabilized, it should be implemented in Reaver Scheme, and
used as the foundation for a new implementation of the Sire language in
Reaver (which will then be fully bootstrapped from Plan Assembly,
instead of implemented in Haskell or loaded from a binary file).

# Rex

Rex (Runic Expressions) is a universal tree notation — a structural normalizer
that sits beneath programming languages the way S-expressions sit beneath Lisp,
but with human-friendly syntax. It is designed to serve as the foundational
syntax layer for the Plunder ecosystem, where every language, configuration
file, and data format shares the same notation and tooling.

Rex is a synthesis of three ideas:

**The uniformity of Lisp notation.** In Lisp, code is data — everything is
an S-expression, and macros operate on the same structure that everything else
uses. This uniformity means a single set of tools works everywhere: one
highlighter, one formatter, one structural editor, one macro system. The
weakness of S-expressions is that the notation is impoverished — everything
looks the same, visual structure is lost, and the syntax is unpleasant to
write at scale.

**The runic notation of Hoon.** Hoon (the language of Urbit) is built almost
entirely from rune poems — symbolic operators that give code visual shape and
structure at a glance. It is more expressive than S-expressions and
mechanically simple. The weakness is that Hoon is not homoiconic in the Lisp
sense, and the notation is alien enough to be a significant barrier to adoption.

**The ergonomics of Haskell/Python/YAML-style syntax.** Familiar infix
operators, indentation-based layout, and juxtaposition for function application
match what programmers already know and expect. The weakness is that each such
language has its own parser, its own tooling, and no shared substrate.

Rex's insight is that these three things are not in tension. The rune system
gives Hoon-style visual expressiveness while remaining mechanically regular
enough to be homoiconic. The layout and infix mechanisms give familiar-looking
syntax as a surface form over the same underlying tree structure. A
Haskell-looking function definition, a Hoon-style rune poem, and an
S-expression prefix form are all just different ways of writing the same kind
of tree — and a macro system operates uniformly across all of them.

## Rex in the Plunder Ecosystem

Plunder is a purely functional, clean-slate operating system — not built on
top of existing OS conventions, but designed from scratch. Within Plunder, Rex
plays the role that S-expressions play in a Lisp machine: it is the universal
notation for everything. Languages, DSLs, configuration, editor buffers,
build scripts — all of it is Rex trees. This means all tooling is written once
and works everywhere: syntax highlighting, structural editing (paredit-style
slurp/barf/raise across any Rex-based language), formatting, diffing, and
metaprogramming all operate on the same substrate.

Because Plunder is a greenfield system, Rex doesn't introduce bootstrapping
problems or require convincing an existing ecosystem to switch. It is simply
the way things are from the ground up, and its uniformity can be assumed at
every layer of the stack.

## What Rex Is Not

Rex is a *structural normalizer*, not a parser in the traditional sense. It
assigns no semantics, no operator precedence beyond grouping, no types, and no
evaluation rules. It transforms text into trees. Meaning is assigned by
downstream consumers.

## Documentation

- [rex-syntax-guide.md](doc/rex-syntax-guide.md) — introduction to the Rex notation for language users and designers
- [parsing.md](doc/parsing.md) — reference guide to the pipeline passes and structural rules
- [printing.md](doc/printing.md) — notes on the pretty-printing design and status
- [rex-syntax-informal.md](doc/rex-syntax-informal.md) — informal grammar and parsing notes
- [syntax.txt](doc/syntax.txt) — concise grammar and lexeme reference

## This Repository

This is a research implementation containing two codebases.

**A Haskell implementation (`src/hs/`)** — the primary implementation,
structured as a sequence of passes each in a separate module:

| Module        | Pass                                              |
|---------------|---------------------------------------------------|
| `Rex.Lex`     | Tokenizer — produces a stream of typed tokens     |
| `Rex.Tree2`   | Structural grouping — produces a parse tree       |
| `Rex.Rex`     | Classification — produces the Rex IR              |
| `Rex.Print`   | Printer — renders Rex IR back to Rex notation     |

Build with `cabal build` and run as:

    echo 'f x = x + 1' | cabal run rex -- lex
    echo 'f x = x + 1' | cabal run rex -- tree
    echo 'f x = x + 1' | cabal run rex -- rex
    echo 'f x = x + 1' | cabal run rex -- print

There is also exploratory Haskell code in `Lib.hs` and `LowLib.hs` — earlier
research into a type-safe clump representation and a Wadler-Lindig-based
pretty-printer. This work is not yet connected to the main pipeline.

**A C implementation (`rex.c`)** — an earlier self-contained implementation.
Somewhat stale relative to the Haskell codebase. Build with `make`:

    echo 'f x = x + 1' | ./o.rex parse
    echo 'f x = x + 1' | ./o.rex lex

## Status

The **lexer and parser** are solid in both implementations. The Haskell
pipeline in particular is clean and well-structured.

The **pretty-printer** is the main unsolved problem and the primary remaining
task for this project. Pretty-printing Rex is harder than pretty-printing most
languages because the printer must invert the parsing rules: every rendering
decision (tight infix vs. spaced infix vs. layout vs. block) must produce
output that parses back to the same tree. Getting this right while also
producing aesthetically good output — respecting line width, choosing natural
forms, handling heirs correctly — is the core research question this project
exists to answer.

The Haskell implementation does not yet have a real pretty-printer. `Rex.Print`
is a simple structural printer that produces valid Rex but makes no aesthetic
decisions. `Lib.hs` contains the most serious attempt at a real layout engine,
using `ansi-wl-pprint` (a Wadler-Lindig implementation) with logic for grouping
children into word-wrapped and boxed flows, but it is disconnected from the
main pipeline. The C printer in `rex.c` has a partial attempt — annotating
nodes with a `wide` size and choosing between wide and tall rendering — but
heir handling, tight infix unwrapping, and juxtaposition wrapping rules are all
incomplete or buggy.

`Rex.Tree2` preserves source position and extent for every node, which was
partly motivated by the idea that the pretty-printer could use the original
source structure as a layout hint — sidestepping parts of the invertibility
problem by anchoring to what the user originally wrote.

## Next Steps

1. Solve the pretty-printer and integrate it into the Haskell pipeline.
2. Port the complete implementation to Reaver Scheme.
3. Use the Reaver Scheme implementation as the foundation for a new
   implementation of the Sire language in Rex, fully bootstrapped from
   Plan Assembly rather than implemented in Haskell or loaded from a
   binary.
