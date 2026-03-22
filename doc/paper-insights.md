# Additional Notes from the Rex Paper

These are ideas from the Rex paper draft not yet captured in the existing
documentation, collected here for review before incorporation.

---

## The Core Conceptual Model

Rex has three and only three structural forms:

    leaf
    (rune form*)
    form JUXT form

A leaf is any atomic token — a word, string, or quoted form. A rune form is a
rune applied to zero or more children. A juxtaposition is two forms placed
immediately adjacent with no whitespace.

Everything else in Rex — tight infix, tight prefix, spaced infix, layout
poems, blocks, bracket types — is a different surface syntax for encoding one
of these three things. Tight infix `a+b` is a rune form with `+` as the rune
and `a`, `b` as children. Tight prefix `+a` is a rune form with one child.
Layout poems are rune forms whose children are gathered by indentation. Blocks
are rune forms whose children are gathered by line boundaries. Heirs are
juxtapositions.

This is the key insight that makes Rex tractable: the structural vocabulary is
minimal, and the syntactic richness is entirely in the encoding layer.

---

## Implicit Grouping in Spaced Infix

Multiple tokens between two infix runes are implicitly grouped into a single
child:

    (a + f x + d)  =>  (+ a (f x) d)

The `f x` between the two `+` runes becomes one grouped child rather than two
separate children. This is what makes multi-argument expressions work naturally
inside infix forms without extra parentheses.

---

## Macros in Both Directions

The standard discussion of Lisp macros focuses on using them to *extend* a
language — adding new syntax via library code. But macros can also be used to
*shrink* a language: taking existing core language features and moving them
into the standard library, making the runtime smaller and more auditable.

TinyScheme — embedded in GIMP — is 5000 lines of C, kept small by this
approach. The point is that homoiconicity gives you a choice about where
complexity lives: in the core, or in libraries. Rex makes the same choice
available to any language built on it.

---

## The Three-Pass Model

Homoiconic languages parse in three stages:

1. Text → uniform tree
2. Uniform tree → macro-expanded tree
3. Expanded tree → internal AST / evaluation

Stage 2 is only possible because stage 1 produces a uniform structure that
user-defined functions can operate on. This is the same architecture Rex
enables — the uniform tree from the Rex parser is what makes the macro
expansion stage possible. Languages that don't share a uniform notation have
to bake all syntax into the parser and lose this capability entirely.
