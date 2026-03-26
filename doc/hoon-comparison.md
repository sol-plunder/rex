# Rex and Hoon

Rex syntax is heavily inspired by Hoon, the language used in Urbit. Both use
runes as the primary structural mechanism. This document describes the
relationship between the two notations and the key differences.

## Background

Hoon code is built almost entirely from rune poems — two-character symbolic
operators that each have a fixed arity and visual identity. A fragment of Hoon
from an Urbit networking implementation:

```hoon
|%
++  mess
  |=  [=ship life=@ud =path dat=$@(~ (cask))]
  (jam +<)
::
++  sign  sigh:as:crypto-core.ames-state
::
++  veri-fra
  |=  [=path fra=@ud dat=@ux sig=@]
  (veri sig (jam path fra dat))
::
++  veri
  |=  [sig=@ dat=@]
  ^-  ?
  (safe:as:(com:nu:crub:crypto public-key.peer-state) sig dat)
::
++  meri
  |=  [pax=path sig=@ dat=$@(~ (cask))]
  (veri sig (mess her life.peer-state pax dat))
--
```

The same code in Rex:

```rex
|%
++  mess
  |=  [=ship life='@ud =path dat=($@ '~ |cask)]
   (jam '+<)
++  sign  sigh:as:(crypto_core.ames_state)
 '
++  veri_fra
  |=  [=path fra='@ud dat='@ux sig='@]
   (veri sig (jam path fra dat))
 '
++  veri
  |=  [sig='@ dat='@]
  ^-  ?
   (safe:as:(com:nu:crub:crypto public_key.peer_state) sig dat)
 '
++  meri
  |=  [pax=path sig='@ dat=($@ '~ |cask)]
   (veri sig (mess her life.peer_state pax dat))
```

Most things translate nearly verbatim. The differences are small but systematic.

## Key Differences

**Identifiers.** Hoon uses `-` freely in identifiers (`peer-state`,
`crypto-core`). In Rex, `-` is a rune character, so identifiers use `_`
instead (`peer_state`, `crypto_core`).

**Comments.** Hoon uses `::` for line comments. In Rex, comments use
`')`, `']`, or `'}`, but you can write docstrings inline in rune poems
using slug-strings (`'`), which replace the `::` convention from Hoon.

**Sigil literals.** Hoon has a large family of irregular syntax forms for
literals prefixed with sigils: `@ud`, `~`, `+<`, `$@`. In Rex these become
quips: `'@ud`, `'~`, `'+<`, and the irregular `$@(~ (cask))` becomes
`($@ '~ |cask)` using standard prefix notation with quips for the sigils.

**Dot-access.** Hoon uses `.` in names like `crypto-core.ames-state`. In Rex,
`.` is a rune, so field access becomes a tight infix form:
`crypto_core.ames_state`.

## The Key Advantage

In Hoon, each rune has a fixed, parser-known arity. The parser must know that
`|=` takes exactly two children, `^-` takes exactly two, and so on. This means
the Hoon parser is not truly generic — it encodes semantic information (arity)
about every rune.

In Rex, runes have no fixed arity. Layout and indentation determine grouping,
not rune identity. This makes Rex fully regular: a Rex parser knows nothing
about what any particular rune means. A macro system assigns meaning after the
fact. New runes can be introduced by libraries without touching the parser.

The tradeoff is that Rex is slightly more verbose in some cases — Hoon can
sometimes omit explicit grouping that Rex needs — but the uniformity payoff is
that all Rex-based languages share the same parser, formatter, highlighter, and
structural editor.
