# Printer Edge Cases

## Under-indented Block Content

The following input is accepted by the parser but would be very difficult for the printer to reproduce:

```rex
= nest ([
   This should probably be rejected by a linter, since it's indented
   less than the opening-nest, but the parser accepts it.
]) ') These match nothing, so are error tokens.
```

The block content is indented less than the opening bracket `[`, which creates an unusual layout that the printer currently cannot produce. A linter should probably reject this as bad style, but since the parser accepts it, ideally the printer would handle it too.

Supporting this would require the printer to track more complex indentation state and potentially emit content at columns less than the current "natural" indent level.

## Records and Tuples with Poems

The printer currently produces output like:

```rex
{name : items , value : ~ 1
                        ~ 2
                        ~ 3}

(+ 3 4 , add 3 4 , ? x | add x x)
```

These work but could be prettier with smarter formatting:

```rex
{ name  : items
, value : ~ 1
          ~ 2
          ~ 3 }

( + 3 4
, add 3 4
, ? x | add x x )
```

## Config/TOML-style Records

The README config example currently prints as:

```rex
{title : "TOML Example" , owner : {name : "Tom Preston-Werner" , dob
                                                                 : '1979-05-27T07:32:00-08:00}
 , database : {enabled : true , ports : [8000 , 8001 , 8002]}}
```

This is quite ugly. Ideally it would format more like the original input with one field per line.
