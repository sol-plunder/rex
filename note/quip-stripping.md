# Quip Indentation Stripping

Multi-line quips normalize indentation by stripping whitespace up to the
column of the least-indented non-blank continuation line.

## The Rule

For a multi-line quip, find the continuation line with the smallest
leading indent (ignoring blank lines). Strip that many spaces from all
continuation lines.

## Example

Given:

    config = 'yaml{
      name: foo
      value: 123
    }

The continuation lines have indents: 2 (`name`), 2 (`value`), 0 (`}`).
The minimum is 0, so 0 spaces are stripped. The relative indentation (2
spaces for `name` and `value` vs 0 for `}`) is preserved.

## The Jagged Form

This stripping rule enables a convenient "jagged" syntax where you can
type continuation lines starting at column 0:

    config = 'yaml{
      name: foo
      value: 123
    }

Here all lines have indent 0, so min is 0, and nothing is stripped. This
produces the same result as writing everything aligned:

    config = 'yaml{
               name: foo
               value: 123
             }

Here all continuation lines have indent 9, so 9 is stripped from each,
leaving all at relative indent 0.

Both forms are semantically identical.

## Preserving Relative Indentation

Indentation differences within the quip are preserved. Given:

    doc = 'html{
      <body>
        <p>Hello</p>
      </body>
    }

The minimum indent is 0 (from `<body>`, `</body>`, `}`). After stripping
0, `<p>` retains its 2-space relative indent. When printed, this
becomes:

    doc = 'html{
            <body>
              <p>Hello</p>
            </body>
          }

## Blank Lines

Blank lines (empty or whitespace-only) are ignored when computing the
minimum indent and are printed without indentation.
