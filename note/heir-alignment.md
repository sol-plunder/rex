# HEIR Alignment in Rex

## How HEIR Parsing Works

HEIR siblings are forms that appear at the **same column**. The parser groups
them as siblings based on column alignment:

```rex
:= x/y
 | if y=0 !!"error"
 | if x<y 0
 | #(1 + (x-y / y))
```

Here the `|` runes are all at column 1, which aligns with the `=` in `:=`
(the last character of the rune). This makes them HEIR siblings.

**Critical:** The `|` lines must be indented by 1 space to align with the `=`.
Without that indent:

```rex
:= x/y
| if y=0 !!"error"
```

The `|` at column 0 does NOT align with `=` at column 1, so they would not
be parsed as heirs - they'd be separate top-level forms.

## How the Printer Handles This

The printer must output the correct indentation so that HEIR siblings remain
aligned. This is handled in `heirDoc` in PrintRex.hs:

```haskell
heirDoc (k:ks) =
    let runeIndent = case k of
            OPEN r _ -> length r - 1  -- align to last char of rune
            _        -> 0
    in PDent (PCat (heirFirst runeIndent k) (heirRest runeIndent ks))
```

For a first child like `OPEN ":=" ...`:
- Rune length is 2 (`:=`)
- `runeIndent = 2 - 1 = 1`
- Subsequent heirs get 1 space of padding before them

The `heirRest` function applies this padding:

```haskell
heirRest indent (k:ks) =
    let padding = pdocText (replicate indent ' ')
    in PCat PLine (PCat padding (PCat (rexDoc k) (heirRest indent ks)))
```

## Single-Character Runes

For single-character runes like `|`, `+`, `~`:
- Rune length is 1
- `runeIndent = 1 - 1 = 0`
- No extra padding needed; heirs align at column 0

Example:
```rex
| foo
| bar
| baz
```

All `|` are at column 0, no indent needed.

## Multi-Character Runes

For multi-character runes like `:=`, `->`, `=>`:
- `runeIndent = length - 1`
- Subsequent heirs need that many spaces of padding

Example with `:=` (length 2):
```rex
:= x/y
 | continuation
```

The `|` needs 1 space indent to align with the `=`.

Example with `-->` (length 3, hypothetically):
```rex
--> foo
  | bar
```

The `|` would need 2 spaces to align with the last `-`.
