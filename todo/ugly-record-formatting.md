# TODO: Ugly record/config formatting

## Problem

Nested records and configuration-style data produce awkward wrapped layouts
instead of clean vertical formatting.

## Example

Input:
```rex
{
  title: "TOML Example",
  owner: {
    name: "Tom Preston-Werner",
    dob:  '1979-05-27T07:32:00-08:00,
  },
  database: {
    enabled: true,
    ports:   [8000, 8001, 8002],
  }
}
```

Current output:
```rex
{title : "TOML Example" , owner : {name : "Tom Preston-Werner" , dob
                                                                 : '1979-05-27T07:32:00-08:00}
 , database : {enabled : true , ports : [8000 , 8001 , 8002]}}
```

## Desired Output

Something more like:
```rex
{ title    : "TOML Example"
, owner    : { name : "Tom Preston-Werner"
             , dob  : '1979-05-27T07:32:00-08:00 }
, database : { enabled : true
             , ports   : [8000 , 8001 , 8002] } }
```

## Cause

The greedy algorithm in PDoc tries to fit as much as possible on each line,
leading to awkward wrapping mid-field.

## Possible Solutions

1. **Short-term**: Add heuristics to `nestDoc` to prefer vertical layout for
   records (curly braces with `:` or `,` runes) when they contain nested
   structures.

2. **Long-term**: Consider Bernardy's "prettiest" algorithm which uses Pareto
   frontiers to find globally optimal layouts. See `note/prettiest-evaluation.md`.

## Related

- `note/prettiest-evaluation.md` - evaluation of optimal printing algorithm
- `note/printer-edge-cases.md` - documents this issue
