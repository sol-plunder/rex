# Prefix Operator Precedence

Basically all programming languages have prefix operators bind more
tightly than infix operators in basically all cases. This is the right
universal rule for a freshly designed language.

## The Main Exception: Complex Leaf Literals

Rational/decimal literals like `3.14` and `6.022e-23` contain
operator-like symbols (`.`, `e`, embedded `-`) that are internal to the
literal and bind more tightly than any prefix applied to the whole. This
is the primary real-world exception to the tight-prefix rule.

Path literals also have prefixes which are logically loosely bound:

    ./foo/bar

## Resolution via Quips

Quips can handle these cases cleanly enough, no need to perfectly
accomidate the standard notational expectations

    3.14
    -3.14
    '-3.14e-23
    '/foo/bar/zaz
    './src/hs/*.exe
