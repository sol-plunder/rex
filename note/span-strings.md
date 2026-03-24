# SPAN Strings (Inline Uglies)

SPAN is the inline form of ugly strings, using `'''` delimiters without a leading newline.

## Limitations

SPAN strings are convenient but fundamentally limited. They cannot represent:

- Content starting with a newline (that would make it a PAGE)
- Content starting with `'` (would be parsed as additional delimiter ticks)
- Content ending with `'` (would be parsed as part of closing delimiter)

For fully general string content, use PAGE instead. PAGE can represent any
string, while SPAN exists as a convenience for the common case of inline
strings containing quotes or other special characters.

## Syntax

### Single-line SPAN
```
'''content here'''
```

The content is taken literally between the delimiters.

### Multi-line SPAN
```
'''first line
   continuation line
   another line'''
```

Continuation lines must be indented past the opening `'''` column. The indent
is stripped to align with the content column (the position after `'''`).

For a SPAN starting at column 1:
- `'''` occupies columns 1-3
- Content starts at column 4
- Continuation lines must start at column 4 or greater
- Columns 1-3 of continuation lines are stripped

## Comparison with PAGE

| Feature | SPAN | PAGE |
|---------|------|------|
| Syntax | `'''content'''` | `'''\ncontent\n'''` |
| Opening | `'''` followed by content | `'''` followed by newline |
| Closing | `'''` on same/continuation line | `'''` on its own line, same column as opening |
| Use case | Short strings with special chars | Multi-line text blocks |

## Examples

### Embedding quotes
```
'''say "hello" and 'goodbye''''
```
Result: `say "hello" and 'goodbye'`

### In expressions
```
+ x '''content'''
(a + '''b''')
x.'''y'''
```

### Multi-line in context
```
+ x '''line one
       line two'''
```
The 7 spaces before "line two" are stripped (column 5 + 2 for `'''`), leaving the content as `line one\nline two`.
