# Docstrings in Rex

Rex supports docstrings using slugs — line-oriented string literals that begin
with `' ` (tick followed by space). Slugs integrate naturally into Rex's
structure, allowing documentation to flow alongside code without disrupting
visual rhythm.

## Basic Usage

A docstring can precede a definition:

```rex
' Adds two numbers together
= (add x y)
| x+y
```

Or appear inline after a rune:

```rex
= (add x y)
' Adds two numbers together
| x+y
```

## Multi-line Docstrings

Consecutive slug lines at the same column form a single multi-line slug:

```rex
' Compute the factorial of n.
' Returns 1 for n <= 1.
' Uses tail recursion for efficiency.
= (factorial n)
| if n<=1 1
| n*(factorial n-1)
```

## Running Commentary

Slugs work well as running commentary within larger definitions:

```rex
= processUser request
' Extract and validate the user ID
@ userId | validateId request.userId
' Look up the user in the database
@ user | db.findUser userId
' Check permissions before proceeding
| if (not user.isActive)
  | throw "User is inactive"
' Apply the requested changes
| updateUser user request.changes
```

## Documenting Structure Fields

Docstrings naturally attach to fields in record definitions:

```rex
= Config
: struct
' The server hostname (e.g. "localhost")
, host:String
' The port number (default 8080)
, port:Int
' Maximum connections allowed
, maxConns:Int
' Enable verbose logging
, verbose:Bool
```

## Documenting Function Arguments

```rex
= httpRequest
' The HTTP method (GET, POST, etc.)
| method
' Full URL including query parameters
| url
' Request headers as key-value pairs
| headers
' Optional request body
| body
```

## Documenting Alternatives

```rex
= parseValue input
| match input
' Numeric literals become integers
, (Digit d) -> parseNumber d
' Quoted strings preserve their content
, (Quote s) -> parseString s
' Identifiers are looked up in scope
, (Ident i) -> lookupVar i
' Everything else is a syntax error
, _         -> throw "Parse error"
```

## Nested Documentation

Docstrings work at any nesting level, allowing module-level and item-level
documentation to coexist:

```rex
' The networking module handles all HTTP communication.
' It provides both client and server functionality.
: net
' Create an HTTP client with default settings
= mkClient config
  | ...
' Start an HTTP server on the given port
= serve port handler
  | ...
```
