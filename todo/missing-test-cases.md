# Missing Test Cases

Test cases present in `src/c/ex/` but not covered in `src/hs/ex/print-rex/`.

## 1. Empty Block Body

From `bloc0.rex`:
```rex
def foo(x):
```
Block with trailing rune but no items following.

## 2. Blank Lines Inside Blocks

From `bloc.rex`:
```rex
= (this is a big) (

   @ block 'that
   ^ (includes _ _)


   ') lol


   | many
   | blank lines

)
```
Blocks containing multiple blank lines between items.

## 3. Prefix Chains

From `hslex.rex`:
```rex
++-x
```
Multiple consecutive prefix runes applied to an expression.

## 4. Complex Tight Juxt with Trad

From `ifix.rex`, `trad.rex`:
```rex
x"y".a"b"                ') juxt with multiple trads
"one" "two"."strings"    ') trad juxt chain
"1""s"                   ') tight trad (escaped quote vs juxt?)
("1")"s"                 ') trad in parens then juxt
"1"("s")                 ') trad then juxt parens
```

## 5. Quipped Keys in Records

From `ifix.rex`:
```rex
[k1: v1, 'k2(lol): v2]   ') record with quipped keys
```

## 6. Prefix Forms in Curly Brackets

From `node.rex`:
```rex
{ k1:
    (+ (add 1)
     + [ foo,
         .(3*4*(a + b)),
       ])
, k2:
    {+3 +4 +5 +(+5)}
}
```
Prefix runes inside curly brackets creating poems.

## 7. Poem vs Infix vs Tight in Brackets

From `nest.rex`:
```rex
[+ 3 4]    ') poem inside brackets
[3 + 4]    ') infix inside brackets
[3+4]      ') tight infix inside brackets
[3 4]      ') application inside brackets
[3]        ') single item
[]         ') empty
```
Same content with different spacing produces different parses.

## 8. Mixed Juxt with Poems

From `mixed.rex`:
```rex
[x.x, y[0]].(- a
             - b).z
```
Complex expression mixing tight infix, indexing, poems, and juxtaposition.

## 9. Long Trailing Infix Expressions

From `itrail.rex`:
```rex
( ( aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa , aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa )
,
)

( ( aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa ++ aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa )
++
)
```
Deeply nested expressions with trailing runes, testing layout at width boundaries.

## 10. Tight Trailing with Quip/Ugly/Slug

From `twrap.rex`:
```rex
x+'quip
x+''
  ugly
  ''
x+' slug
x+(a,b)
x+(a.b)
x+(ab)
x+(a b)
x+(a . b)
x+(. a b)

word+x
"text"+x
('quip)+x
'quip+'quip
'quip+''
      ugly
      ''
'quip+' slug
(a,b)+c
(a.b)+c
(ab)+c
(a b)+c
(a . b)+c
(. a b)+c
```
Tight infix with various trailing/leading forms.

## 11. Empty Quip

From `quip.rex`:
```rex
(') ') empty quip
```
Quip containing nothing, used as a comment mechanism.

## 12. Quoting Runes with Uglies

From `quip.rex`:
```rex
('x, 'y)      ') uglies do not include trailing runes
('_ , '_____) ') but you can use uglies to quote runes
```
Using ugly strings to quote rune characters.

## 13. Quip Followed by Ugly

From `quip.rex`:
```rex
'Quip''
     Ugly
     ''
```
Quip immediately followed by an ugly string (no space).

## 14. Slug in Parens with Juxt

From `slug.rex`:
```rex
( ' weird
).( ' cases
)
```
Slugs inside parentheses combined with juxtaposition.

## 15. Tight Ugly Chains

From `strip.rex`:
```rex
''
a''b''c
''
```
Multiple ugly strings in sequence (tight).

Also very long quote sequences:
```rex
''''''''''''''''''''''''''''''''''''''''
'''''''''''''''''''''''''''''''''''''''
'''''''''''''''''''''''''''''''''''''''''quip
```

## 16. Poison/Invalid String Tests

From `poison.rex`:
```rex
') Poisoned

ex1 "Poisoned
    Trad"$$$$
ex2 '''
    Poisoned
     Ugly
     '''$$$$
ex3 '''
    Poisoned
     Ugly
   '''$$$$
ex4 ''Poisoned Ugly''$$$$
ex5 'Poisoned(
   Quip)$$$$

') Healthy

ex6 'Quip$$$$
ex7 'Healthy(Quip)$$$$
ex8 'Healthy(
    Quip)$$$$
ex9 "Trad"$$$$
exA "Healthy
      Trad"$$$$
exB '''
      Healthy
      Ugly
    '''$$$$
exC '''
    Healthy
    Ugly
    '''$$$$
```

Invalid strings that should parse as BAD vs valid equivalents.

## 18. Quip Formatting Edge Cases

From `qfmt.rex`:
```rex
|
    - '+
    - '+++
|
    - 'quip.'quip
    - 'quip().'quip()
    - 'quip(
      ).'quip()
|
    'quip(
      quip]
    ).'quipity.quip
```
Various quip formatting patterns with poems and juxtaposition.
