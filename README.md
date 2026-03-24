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
uniformity also enables a powerful approach to language implementation: instead
of writing a dedicated compiler, you write macros that progressively transform
trees. The weakness of S-expressions is that the notation is impoverished
— everything looks the same, visual structure is lost, and the syntax is
unpleasant to write at scale.  It works well enough for Lisp, but once languages introduce a richer range of concepts, like in modern languages like Haskell or Rust, the notation starts to become very cumbersome.

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

## Examples

All of the following are valid Rex. They all parse into the same kind of tree
and are handled by the same parser, formatter, and tooling.

**Runic style** — the primary style of Sire, Rex's bootstrapping language.
Rune poems build up computation vertically, left-aligned, with `|` for
application, `@` for let-binding, `^` for loops, `?` for lambdas:

```rex
= exampleList
   ~   ? (sillyFn x y)
       | sz | weld [5 -4 3]
            | map add-x [1 #(x+4 * y)]
   ~   + user: %sol
       + repo: b"plunder"
       + path: /home/sol/r/plunder
```

**Haskell-like style** — type signatures, function definitions, pattern
matching. Juxtaposition for application, tight infix for cons, spaced infix
for operators, block mode for bodies:

```rex
map : (a -> b) -> [a] -> [b]
map f []     = []
map f (x:xs) = (f x : map f xs)

def quicksort xs:
    match xs:
        []     -> []
        (h:ts) ->
            less    = filter <h ts
            greater = filter >=h ts
            quicksort less ++ [h] ++ quicksort greater
```

**Python-like blocks** — trailing rune opens a block, indented lines become
items:

```rex
def foo(x, y):
    x += y
    return x
```

**Configuration** — Rex handles JSON, TOML, and YAML-style data naturally.
Curly braces for records, tight infix for field access, quips for bare values:

```rex
{
  title: "TOML Example",
  owner: {
    name: "Tom Preston-Werner",
    dob:  '1979-05-27T07:32:00-08:00,
  },
  database: {
    enabled: true,
    ports:   [8000, 8001, 8002],
  }
}
```

**Prefix notation** — the S-expression fallback, always available:

```rex
(:= (/ x y)
 (| if (= y 0) (!! "Error: divide-by-zero")
  (| if (< x y) 0
   (# (+ 1 (/ (- x y) y))))))
```

The same expression in ergonomic Rex using rune poems.

```rex
:= x/y
 | if y=0 !!"divide-by-zero"
 | if x<y 0
 | #(1 + (x-y / y))
```

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
assigns no semantics, no types, and no
evaluation rules. It transforms text into trees. Meaning is assigned by
downstream consumers.

## Documentation

- [rex-syntax-guide.md](doc/rex-syntax-guide.md) — introduction to the Rex notation for language users and designers
- [examples.md](doc/examples.md) — annotated Rex examples covering the full range of the notation
- [hoon-comparison.md](doc/hoon-comparison.md) — Rex compared to Hoon, with side-by-side examples
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

## Next Steps

1. Solve the pretty-printer and integrate it into the Haskell pipeline.
2. Port the complete implementation to Reaver Scheme.
3. Use the Reaver Scheme implementation as the foundation for a new
   implementation of the Sire language in Rex, fully bootstrapped from
   Plan Assembly rather than implemented in Haskell or loaded from a
   binary.
