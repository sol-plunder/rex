# Rex Normalizer

A function to convert arbitrary Rex values into forms that round-trip correctly
through print/parse. This is needed for fuzzing, where we generate random Rex
trees that may not be printable.

## Function Signature

```haskell
normalizeRex :: Rex -> Rex
```

## Invariant

For all `r :: Rex`:
```haskell
parse (print (normalizeRex r)) == normalizeRex r
```

## Normalization Rules

### JUXT: Adjacent same-type elements merge

Any sequence of adjacent elements within a JUXT that would print without
separation and re-parse as a single token must have earlier elements wrapped.

**Conflicting pairs** (elements that merge when adjacent):
- WORD + WORD: `foo bar` with no space → `foobar`
- CORD + CORD: `"a""b"` → single string with escaped quote
- SPAN + SPAN: `'''a''''''b'''` → ambiguous
- QUIP + anything: quip consumes to end of line
- SLUG + anything: slug consumes to end of line

**Fix**: Wrap all but the last element of each conflicting run in `EXPR PAREN`.

```
JUXT [WORD "a", WORD "b"] → JUXT [EXPR PAREN [WORD "a"], WORD "b"]
```

### JUXT: SLUG can only appear at end

A SLUG in a JUXT (except at the end) would consume subsequent elements as part
of its content.

**Fix**: Wrap non-final SLUGs in `EXPR PAREN`.

### JUXT: QUIP can only appear at end

A QUIP in a JUXT (except at the end) would consume subsequent elements.

**Fix**: Wrap non-final QUIPs in `EXPR PAREN`.

### HEIR: Must start with OPEN or SLUG

An HEIR's vertical alignment is based on rune positions. If the first element
is not an OPEN or SLUG, the heir structure is ambiguous.

**Fix**: Prepend `OPEN "+" []` to the beginning.

```
HEIR [WORD "x", OPEN "+" [y]] → HEIR [OPEN "+" [], WORD "x", OPEN "+" [y]]
```

### NEST: Subsequent children cannot be OPEN

In a NEST like `(a + b + c)`, if `b` or `c` is an OPEN, its rune would be
parsed as the infix operator instead.

**Fix**: Wrap OPEN children (except the first) in `EXPR PAREN`.

```
NEST "+" [a, OPEN "-" [x], c] → NEST "+" [a, EXPR PAREN [OPEN "-" [x]], c]
```

### BLOC: Only last item can be OPEN, HEIR, or SLUG

Block items are parsed top-to-bottom. An OPEN, HEIR, or SLUG in a non-final
position would consume subsequent items.

**Fix**: Wrap non-final OPEN/HEIR/SLUG items in `EXPR PAREN`.

```
BLOC "=" head [OPEN "+" [x], y] → BLOC "=" head [EXPR PAREN [OPEN "+" [x]], y]
```

### EXPR CLEAR: Convert to EXPR PAREN

An `EXPR CLEAR` (no brackets) has many edge cases:
- Single child is indistinguishable from the child itself
- Multiple children with runes between them become infix
- Vertical children cause ambiguity

**Fix**: Convert all `EXPR CLEAR` to `EXPR PAREN`.

```
EXPR CLEAR [x, y] → EXPR PAREN [x, y]
```

### TYTE: Must have >= 2 children

Tight infix requires at least two operands.

**Fix**:
- 0 children: invalid, convert to `EXPR PAREN []`
- 1 child: return the child directly (loses the rune, but unavoidable)

```
TYTE "." [x] → x
TYTE "." [] → EXPR PAREN []
```

### NEST: Empty infix NEST is invalid

A NEST with a rune but no children cannot be printed as infix.

**Fix**: Convert to `EXPR` of same color with trailing rune somehow, or
convert to `EXPR PAREN []` if truly empty.

Note: Single-element infix NEST is valid: `(3,)` prints and parses correctly.

### WORD: Must contain valid word characters

A WORD whose content looks like a rune, contains spaces, or matches string
delimiters won't round-trip.

**Fix**: Convert invalid WORDs to CORD.

```
WORD "+" → CORD "+"
WORD "a b" → CORD "a b"
WORD "\"\"" → CORD "\"\""
```

**Valid WORD**: Alphanumeric, starting with letter or underscore, may contain
hyphens. (Check actual lexer rules for precise definition.)

### Runes: Must be valid rune strings

The rune in TYTE, PREF, NEST, OPEN, BLOC must consist only of valid rune
characters (punctuation from `runeSeq`).

**Fix**: If rune is invalid, this is a deeper problem. For now, perhaps
replace with a safe default like `"+"` or signal an error.

## Implementation Notes

- Apply rules recursively (children first, then parent)
- Some rules interact: normalizing a child might change whether the parent
  needs normalization
- Consider adding a `isNormalized :: Rex -> Bool` check for testing

## Testing

Create a QuickCheck/Hedgehog generator for arbitrary Rex, then verify:
```haskell
prop_roundtrip r = parse (print (normalizeRex r)) == normalizeRex r
```
