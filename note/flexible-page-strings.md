# Flexible PAGE Strings

PAGE strings now support flexible indentation where the terminator's column
determines the strip depth, rather than requiring the terminator to align
with the opener.

## Motivation

Previously, PAGE strings required the closing `'''` to be at the same column
as the opening `'''`:

```
x = '''
    content
    '''
```

This meant the content always had to be indented past the opener. The new
flexible syntax allows Nix-style strings where the terminator can be at any
column:

```
x = '''
  content
'''
```

Here the terminator is at column 1, so nothing is stripped from content lines.
The content is literally `  content` (with leading spaces preserved).

## Semantics

1. The lexer produces a single `UGLY` token for any `''`+ delimited string
2. Classification happens during Rex loading:
   - If content starts with a newline: it's a PAGE
   - Otherwise: it's a SPAN
3. For PAGE strings:
   - Count leading spaces on the terminator line
   - Strip that many characters from each content line
   - Blank lines (empty or whitespace-only) pass through as empty
   - Non-blank lines must have at least that many leading spaces, or the
     string is malformed (becomes a BAD leaf)

## Examples

### Traditional style (terminator aligned with content)
```
x = '''
    Line 1
    Line 2
    '''
```
Terminator has 4 leading spaces, so 4 characters are stripped.
Result: `Line 1\nLine 2`

### Nix style (terminator at column 1)
```
x = '''
  Line 1
  Line 2
'''
```
Terminator has 0 leading spaces, so nothing is stripped.
Result: `  Line 1\n  Line 2`

### Partial strip
```
x = '''
    Line 1
    Line 2
  '''
```
Terminator has 2 leading spaces, so 2 characters are stripped.
Result: `  Line 1\n  Line 2`

### Blank lines
```
x = '''
  Line 1

  Line 2
  '''
```
Blank lines are preserved as empty lines regardless of strip depth.
Result: `Line 1\n\nLine 2`

### Invalid (under-indented content)
```
x = '''
  Line 1
 Bad
  '''
```
The line ` Bad` has only 1 leading space but strip depth is 2.
This produces a BAD leaf.

## Backward Compatibility

The traditional PAGE layout remains valid and has the same semantics. A PAGE
where the terminator aligns with the content column strips all leading
indentation, producing bare content lines.

## Printer Behavior

The printer always outputs PAGE strings in the traditional style with
terminator aligned to the opener column. Flexible input formats are
normalized to this canonical form.
