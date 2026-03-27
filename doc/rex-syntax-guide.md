# Rex: A Universal Tree Notation

## Introduction

Rex is a universal tree notation — a more expressive successor to S-expressions that preserves homoiconicity and macro-extensibility while offering human-friendly syntax. It is designed to serve as the foundational syntax layer for an entire computing environment, where every language, configuration file, and data format shares the same notation.

Like S-expressions, Rex represents code and data as trees of operators applied to arguments. Unlike S-expressions, Rex provides a rich set of composable syntactic mechanisms — operator precedence, infix notation, indentation-based layout, juxtaposition, and multiple string types — so that the surface syntax can look like Haskell, Python, or whatever a language designer prefers, while the underlying representation remains uniform and machine-manipulable.

Before getting into the details: despite the surface variety, Rex collapses
down to three structural forms.

    leaf                    -- an atomic token: word, string, or quoted form
    BRACKET(rune form*)     -- a rune applied to zero or more children,
                            -- tagged with a bracket type: () [] {} or none
    form JUXT form          -- two forms placed immediately adjacent

The bracket type is part of the tree — `{x:3}`, `(x:3)`, and `[x:3]` all
produce different nodes. Downstream languages assign meaning to the
difference: perhaps `()` for grouping, `[]` for lists, `{}` for records.
Rex preserves the distinction but doesn't interpret it.

Everything else — tight infix, tight prefix, spaced infix, layout poems,
blocks — is a different surface encoding of one of these three things.
The syntactic richness is entirely in the encoding layer; the underlying
tree structure is simple and uniform.

The entire lexer, parser, and pretty-printer is compact — orders of magnitude smaller than the parsers of languages like Haskell or Rust — yet it is expressive enough to emulate their syntax.

## Design Philosophy

Rex is built on a principle of regularity: a small number of general mechanisms that compose freely, rather than a growing collection of special cases.

Most programming languages accumulate syntax over time. Haskell added `do` notation, arrow syntax, pattern synonyms, overloaded labels, record dot syntax — each requiring parser changes and new special cases. Rust has lifetimes, turbofish, proc macros, attribute syntax, and a grammar so large it creates context-dependent ambiguities. C++ is famously unparseable without semantic information.

Rex takes the opposite approach. Every syntactic feature is a general mechanism. Operator precedence works the same way for all operators. Brackets are brackets regardless of what they contain. String types follow regular rules. New syntactic patterns are created through macros that transform trees, never by extending the parser.

This regularity has compounding returns. Features that weren't explicitly designed emerge from the system's general rules. Universal tooling — syntax highlighting, structural editing, formatting, diffing — works across every Rex-based language with zero additional effort. And the notation can serve as a shared protocol across an entire OS ecosystem.

## Atoms

Rex has two fundamental atom types: words and runes.

### Words

Words are identifiers composed of alphanumeric characters and underscores. They follow the conventional rules that most programmers expect:

    foo    x    my_var    Point3D    x_3

Numbers are not a separate type. `42`, `3.14`, and `0xFF` all lex as words (or in the case of `3.14`, as tight infix — see below). Whether a word represents a number is a semantic question for the language built on top of Rex, not a syntactic one. This is arguably more homoiconic than Lisp, where numbers are a distinct atom type. In Rex, the representation is more uniform: `1` and `foo` and `+` are all just lexical tokens that become tree nodes.

### Runes

Runes are operators composed of symbolic characters from this set:

    , : # $ ` ~ @ ? \ | ^ & = ! < > + - * / % .

Any contiguous sequence of these characters forms a single rune token: `+`, `->`, `>=`, `,@`, `::`, `|>`, and so on.

The strict separation between word characters and rune characters is important for Rex's simplicity. There is no ambiguity about where a word ends and a rune begins, or vice versa. This is what makes tight forms (like `x+y` or `:foo`) work without spaces.

## Rune Precedence

Runes have precedence determined by their first character, using this fixed ordering from loosest to tightest:

    , : # $ ` ~ @ ? \ | ^ & = ! < > + - * / % .

Operators starting with `,` bind most loosely; operators starting with `.` bind most tightly. This eliminates the need for fixity declarations entirely. In Haskell, you must memorize that `+` is `infixl 6` and `*` is `infixl 7`, and user-defined operators need explicit declarations. In Rex, you just look at the first character.

Multi-character runes are compared by packing each character into a base-24 representation using the precedence table. This means `->` and `-` have similar precedence (both start with `-`), while `->` and `=>` do not (one starts with `-`, the other with `=`).

The ordering was chosen so that common conventions work naturally. `,` is loosest because commas separate top-level items. `:` is next because type annotations (`map : (a -> b) -> [a] -> [b]`) should bind looser than the arrows they contain. The arithmetic operators `+ - * / %` have their conventional relative ordering. `.` is tightest because field access (`foo.bar.baz`) should bind tighter than anything else.

## Application Forms

Rex provides several ways to apply operators to arguments, all producing tree nodes with the same basic shape: an operator head and zero or more children.

### Juxtaposition (Heir)

Placing expressions next to each other, separated by spaces within the same clump, creates juxtaposition — Rex's equivalent of function application:

    f x          ') f applied to x
    map f xs     ') map applied to f and xs

This is the same convention as Haskell. The internal representation uses "heir" nodes that chain right: `f x y` produces a tree where `f` is applied to `x`, and the result is applied to `y`. When printed back, the backtick operator that marks implicit application is suppressed, so `(map f xs)` prints as `(map f xs)`, not `(` map f xs)`.

### Tight Infix

When a rune appears between tokens with no spaces, it creates a tight infix form:

    x:xs         ') cons
    a.b.c        ') field access chain
    3+4          ') addition

Tight infix was originally designed as an alternative to precedence (to avoid requiring declarations), and it still serves that role for cases where visual tightness is natural. The precedence rules within tight infix follow the same character-based ordering as spaced infix.

### Tight Prefix

A rune immediately followed by a token (no space) creates a tight prefix form:

    -x           ') negation
    :foo         ') keyword or prefix application
    <h           ') operator section (partial application)

This naturally produces operator sections: `filter <h xs` parses as `filter` applied to `(<)h` applied to `xs`. A downstream language can interpret `(<)h` as a partial application, like Haskell's `(< h)`. This feature wasn't explicitly designed — it falls out of how runes and clumping work. Regularity producing emergent features.

### Spaced Infix (Nest Infix)

Inside parentheses or layout blocks, runes separated by spaces from their arguments create nest-level infix forms:

    (3 + 4)
    (a -> b -> c)
    (x = y + z)

The `infix_rex` function collects all runes in the nest, sorts them by precedence, and recursively groups them. Lower-precedence operators split first, creating the correct tree structure. For example:

    map : (a -> b) -> [a] -> [b]

The `:` splits first (lowest precedence), giving `map` on the left and the type on the right. Then `->` splits the type into a chain of arrow types. The result is exactly the tree you want for a type signature.

Multiple tokens between two infix runes are implicitly grouped into a single
child:

    (a + f x + d)  =>  (+ a (f x) d)

The `f x` between the two `+` runes becomes one grouped child rather than two
separate children. This is what makes multi-argument expressions work naturally
inside infix forms without extra parentheses.

### Nest Prefix

Inside parentheses, a rune in the leading position creates a prefix form — the classic S-expression style:

    (+ 3 4)
    (if cond then else)
    (define x 42)

This is always available as a fallback. Any Rex tree can be written in fully parenthesized prefix notation.

## Whitespace Sensitivity

The distinction between tight forms (no spaces) and spaced forms is fundamental to Rex. This means that whitespace around operators is significant:

    a+b          ') tight infix: + applied to a and b
    a + b        ') spaced infix (inside a nest): same tree, different context
    a +b         ') juxtaposition of a with tight prefix +b

This will occasionally surprise programmers who expect whitespace to be insignificant. But the expressiveness payoff is substantial — prefix, infix, and juxtaposition all emerge from one set of rules about spacing and clumping. Languages like Swift already have whitespace-sensitive operator parsing, so there is precedent.

In practice, the conventions that develop around a Rex-based language make the rules intuitive: tight infix for things like `x:xs` and `a.b`, spaced infix for arithmetic and type signatures, tight prefix for operator sections and keywords.

## Brackets

Rex has three bracket types: parentheses `()`, square brackets `[]`, and curly braces `{}`. All three follow the same parsing rules — they create nest contexts where elements are collected and then assembled into trees using infix or prefix rules.

The bracket type is preserved in the tree as a tag. A downstream language assigns meaning: perhaps `()` for grouping, `[]` for lists or indexing, `{}` for blocks or records. Rex doesn't dictate semantics; it just delivers the structure.

Three bracket types is enough for most language designs while avoiding the ambiguity that angle brackets `<>` would create with comparison operators.

## Indentation and Layout

Rex uses indentation to create structure without explicit parentheses, similar to Haskell or Python but applied to general tree-building.

When a rune appears in a "free" position — not clumped tightly with adjacent tokens — it can open a layout context. Subsequent lines indented to at least the rune's column become children of that operator. Dedenting closes the layout.

For example:

    + 3
      4
      5

This parses as `(+ 3 4 5)`. The `+` opens a layout, and `3`, `4`, `5` appear at the right indentation level to be its children.

Layouts nest naturally:

    + * 2 3
      * 4 5

The `*` forms tighter groups within the `+` layout.

### Block Mode

When a line ends with a rune, it enters block mode. Indented lines that follow become semicolon-separated children. This gives Python-style blocks:

    def foo(y):
        x = y
        return x

This parses as something like `(: def foo(y) {(= x y); return x})`.

The mechanism is general — any rune at end of line triggers it, not just `:`. This means multi-line infix works with Haskell-style continuation:

    result = 3 + 4
           + 5 + 6
           + 7 + 8

The `+` at end of line opens a layout, and continuation lines join naturally.

### Block Splitting and REPL Support

At the top level, Rex distinguishes single-line and multi-line expressions for REPL support. A single-line expression (one that starts with a leaf token) is complete after one newline. A multi-line expression (one that starts with a leading rune and a non-leaf) requires a blank line to terminate.

This means interactive use is natural:

    > 3 + 4          ') complete after one newline
    > = foo(x)       ') needs more input...
        x + 1        ') still going...
                      ') blank line, done

No special REPL syntax is needed — the block splitter handles it.

## String Types

Rex provides five string/text literal types, each covering a distinct ergonomic niche. The design philosophy is that different situations call for different quoting mechanisms, and providing the right tool for each case eliminates most escaping.

### TRAD Strings (`"..."`)

Traditional double-quoted strings. The only escape mechanism is doubling the quote character:

    "hello world"
    "she said ""hello"" to me"

No backslash escapes exist at the Rex level. Whether `\n` inside a string means a literal backslash-n or a newline is a semantic question for the downstream language. Different languages can make different choices (C-style escapes, Haskell-style codes, raw interpretation) without the syntax layer imposing one convention.

Multi-line trad strings strip indentation based on the column of the opening quote:

    "first line
     second line
     third line"

This produces `first line\nsecond line\nthird line` — leading spaces up to the opening quote's column are removed from continuation lines. The most common need for embedded newlines — multi-line text — is handled by just using actual newlines.

### QUIP Strings (`'...`)

A tick followed by content, running until whitespace or end of expression:

    'hello      ') the string "hello"
    'if         ') the string "if" — useful as a symbol
    '#FF0000    ') a color literal
    'https://example.com

Quips are Rex's most innovative string type. The quip-joining stage merges adjacent tokens into a single quip when brackets are involved:

    'foo(bar)        ') the string "foo(bar)"
    'html{<b>hi</b>} ') the string "html{<b>hi</b>}"
    'date(Sun Feb  8 02:36:08 AM CST 2026)

Balanced brackets are absorbed into the quip — the Rex parser doesn't interpret the contents, it just tracks nesting depth to find the end. This makes quips a general embedding mechanism for domain-specific literals.

Most languages accumulate special syntax for lightweight literals over time: Ruby has `:symbol` and `/regex/`, Haskell has `'c'` for characters and `#label` for overloaded labels, Rust has `b"bytes"` and `r#"raw"#`. Each requires dedicated parser support and creates interactions with the rest of the grammar.

Rex says: stick a tick on it. `'symbol`, `'match([a-z]+)`, `'Jan-15-2025`, `'cmd(ls -la | grep foo)`. The downstream language defines what these mean. The Rex layer delivers them as string atoms. One mechanism for the entire "lightweight domain-specific literal" problem.

An empty quip is printed as `(')`.

### SLUG Strings (`' ...`)

A tick followed by a space begins a slug — a line of text:

    ' This is a line of text
    ' This is another line
    ' And a third

Each continuation line is explicitly marked with a tick at the same column. Slugs are ideal for documentation:

    ' map applies a function to each element
    ' of a list, returning a new list.
    '
    ' Examples:
    '   map(inc [1 2 3]) => [2 3 4]
    = map(f []) []
    = map(f x:xs)
      : f(x) map(f xs)

A downstream language can treat slugs preceding a definition as docstrings — like Python docstrings but using existing syntax, with the content available in the tree as data for tooling to extract and process.

### UGLY Strings (`''...''`)

Delimited by two or more tick characters. The content begins after a newline and ends when a matching row of ticks appears at the correct column:

    ''
    Any content here.
    Even 'single quotes' are fine.
    ''

If the content itself contains `''`, use more ticks:

    '''
    This text has '' in it.
    '''

The pretty-printer automatically chooses the minimum delimiter width needed to avoid ambiguity with ticks inside the content. You rarely need ugly strings, but when you do — embedding code, unusual text, content with ticks — nothing else works. They are the escape hatch that guarantees Rex can represent any text.

### The String Spectrum

The five types form a spectrum from lightweight to heavy-duty:

- **WORD**: Identifiers. No quoting at all.
- **QUIP**: Lightweight literals. A tick and you're done.
- **TRAD**: Standard strings. Familiar double-quote syntax.
- **SLUG**: Multi-line text. Line-by-line with ticks.
- **UGLY**: Arbitrary content. Variable-width delimiters.

You almost never need escaping. Trad handles most cases with quote doubling. Quip and slug need no escaping at all. Ugly handles everything else by widening the delimiter. Compare with most languages where you're constantly fighting backslashes inside strings.

## Comments

Comments use the syntax:

    ') This is a line comment
    '] This is also a line comment
    '} And this too

These are tick followed by a closing bracket — sequences that were previously illegal in Rex (a tick starts a quip or slug, but a closing bracket can't be part of that). The design repurposes dead lexical space rather than consuming new syntax.

The rationale for this unconventional choice is that rune characters are a finite, precious resource. Reserving `;` for comments (as in earlier versions) meant no Rex-based language could use `;` as an operator — a significant cost, since semicolons serve as sequencing operators in C, Haskell, OCaml, and many other languages. Keeping all rune characters available for operators and finding an alternative solution for comments is the right tradeoff for a universal syntax layer.

The three variants (`')`, `']`, `'}`) could potentially carry different semantic meaning — regular comments, doc comments, pragmas — though that is a convention for individual languages to define.

Syntax highlighting helps enormously with discoverability. When `') comment` is grayed out in an editor, the notation feels natural almost immediately.

## Homoiconicity and Macros

Rex is homoiconic: code is represented as data structures that the language can manipulate. Every Rex program is a tree of nodes, and the syntax can express arbitrary trees. A macro system operates on Rex trees — it doesn't need to know about syntax, it just transforms trees into other trees.

Homoiconic languages parse in three stages:

1. Text → uniform tree
2. Uniform tree → macro-expanded tree
3. Expanded tree → internal AST / evaluation

Stage 2 is only possible because stage 1 produces a uniform structure that
user-defined functions can operate on. Languages that don't share a uniform
notation have to bake all syntax into the parser and lose this capability
entirely.

Want to add `where` clauses to a language? Pattern guards? Do-notation? Those are macros that rewrite trees. In Haskell, each of those required careful syntax design and parser changes. In Rex, the parser never changes.

This is the same promise that Lisp delivers, but without requiring everything to be written in prefix notation. And unlike Lisp, where reader macros create language-specific syntax extensions that fragment the ecosystem, Rex macros operate on the uniform tree representation. Tooling never breaks because the syntax layer is always the same.

Macros can also work in the other direction: instead of using them to *extend*
a language, you can use them to *shrink* it — moving core language features
into libraries rather than the runtime. This keeps the foundational layer
small and auditable. TinyScheme, embedded in GIMP, is 5000 lines of C kept
small by exactly this approach. Rex makes the same tradeoff available to any
language built on it.

## Putting It Together: Haskell-Like Syntax

Rex's features combine to support Haskell-like notation naturally:

    map : (a -> b) -> [a] -> [b]
    map f []     = []
    map f (x:xs) = (f x : map f xs)

Here, `:` splits loosest for the type annotation. `->` chains the arrow types. `=` separates patterns from bodies. Juxtaposition handles function application (`map f xs`). Tight infix handles cons (`x:xs`). Brackets give list syntax. None of this required special design — it falls out of the general rules.

A more complex example using layout:

    def quicksort xs:
        match xs:
            []     -> []
            (h:ts) ->
                less    = filter <h ts
                greater = filter >=h ts
                quicksort less ++ [h] ++ quicksort greater

This reads like a natural blend of Haskell and Python. Juxtaposition handles application (`filter <h ts`, `quicksort less`). Tight prefix creates operator sections (`<h`, `>=h`). Block mode gives Python-style indented blocks. Spaced infix handles `++`. And the Rex parser handles all of it through general mechanisms.

## HTML-Like DSLs with Quips

Quips enable lightweight domain-specific notations:

    'html{
      'head{}
      'body(bgcolor=red){
        Hello world!
      }
    }

The entire `html{...}` is a single quip atom. A downstream macro or tool can parse the internals however it wishes — using Rex itself or a custom parser — while tools that don't understand HTML can still lex, parse, pretty-print, and diff the code because it's just a quip. Compare with Rust's proc macros, where macro invocations contain arbitrary token streams that break every tool that doesn't run the actual macro expander.

Quips also work for small inline fragments: `'foo(x,y)` is just a string. `'date(Sun Feb  8 02:36:08 AM CST 2026)` is just a string. The lexer doesn't care about internal structure; it just tracks bracket nesting to find the end.

## Universal Tooling

Because Rex is a universal notation, tooling built for Rex works across every Rex-based language automatically:

**Syntax highlighting.** The lexer distinguishes words, runes, each string type, and brackets. One highlighter works for every language. A complete syntax highlighter is included in the Rex implementation itself — every Rex-based language gets professional-looking highlighting on day one with zero additional work.

**Structural editing.** Paredit-style editing — where you manipulate the tree directly instead of text — has been one of the most compelling arguments for S-expressions, but it's been trapped in Lisp because no other syntax has a clean enough mapping between text and tree structure. Rex enables paredit for code that looks like Haskell or Python: slurp, barf, raise, wrap, unwrap, transpose — all operating on the tree while the surface syntax stays natural.

**Formatting.** One pretty-printer handles all Rex-based languages. It decides whether expressions fit on one line or need multi-line layout, and applies rules about when parentheses can be safely omitted.

**Diffing and merging.** Tree-based diffs are more meaningful than text diffs. A Rex diff tool could show structural changes rather than line changes.

**Parsing and metaprogramming.** Every program, config file, and data file in the ecosystem is a Rex tree. Generic tools for querying, transforming, and analyzing trees work everywhere.

This is the Unix philosophy applied to structured data. Unix succeeded because everything was plain text and tools composed through pipes. Rex aims for the same composability but with structured trees instead of flat text — `grep` but for trees, `sed` but for tree transformations, pipes that carry structured data.

## Summary

Rex is a universal tree notation that makes a specific bet: that you can have both human-friendly syntax and tree-structured uniformity. It achieves this through a handful of composable mechanisms — rune precedence, tight vs spaced application, layout, juxtaposition, quips — that combine to cover an enormous range of syntactic needs.

The notation is more complex than S-expressions but vastly simpler than the languages people actually use. The learning curve exists, but people generally can use Rex-based languages without understanding Rex for a surprisingly long time, only digging into the actual rules when they encounter an edge case — at which point the rules give them more options for how to write things.

The core insight is that the complexity of syntax is unavoidable — every mature language ends up with thousands of lines of parser code — but it can be factored differently. Instead of each language reinventing syntax from scratch, Rex provides a shared substrate where the complexity is paid once and the returns compound across every language, tool, and data format built on top of it.
