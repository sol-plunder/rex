# Informal Rex Spec

## Lexer

I'll fill this section in later, but for now I'll just talk about what
the tokens are:

    EOL   -- newline
    WYTE  -- non-newline whitespace
    BEGIN -- ( [ { or end-of-block
    END   -- ) ] } or end-of-block
    CLMP  -- a rune with has clump-stuff after it (not space or end)
    FREE  -- a rune which is followed by a wyte/eol/end
    WORD  -- identifier (0, hi, hello)
    TRAD  -- "hello" (normal string)
    TICK  -- ' (quip marker)
    UGLY  -- Block String
    SLUG  -- Light Block String
    BAD   -- some sort of invalid input

In this formalization, we will use END to also indicate the end of
a block.

## Grammar

    leaf   = WORD | TRAD | UGLY | SLUG | BAD
    node   = leaf | nest | quip
    clump  = CLMP? node (CLMP node)*
    quip   = TICK clump | TICK poem
    nest   = BEGIN inner? END
    slot   = clump | poem
    inner  = block | (slot+ (FREE slot+)* FREE?)
    poem   = FREE slot*
    block  = slot+ FREE (EOL WYTE*)+ item+
    item   = inner

Informal Rules:

-   A poem is broken by an END input or any input token which is
    indented less than the poem.

-   In `block`, the first item must be indented more than the slot,
    or the production doesn't match.

-   An item is broken by an END input or by an input token which is
    indented less than the item.  If any input token is indented at
    the *same* level as the item, the item ends and a new item begins.

## Parsing

Parsing generally is concerned with runes, nesting, spacing, and quips.
All of the other things (word, trad, ugly, slug, bad) are treated
uniformly as leaves.

There are seven parsing contexts:

clumps, nests, quips, poems, blocks, items, and inputs

### Clumps

A clump has a concept of a node, which is either a leaf, a quip, or
something enclosed in nesting.

A clump is a non-empty string of runes

    a +a a.b +a.b 
    () [] {} 'x
    a() b[1] ()'x
    +(a) (a)[b]

A clump cannot ever end with a rune, a clump that is immediatly followed
by a rune is not considered to be a clump.  This is not a clump, but a
clump followed by a rune.

   a.b,

This is especially important for inputs where trailing runes are used
as infix operators in nested notation.

    (3, 4, 5)
    (a: 1, b: 2)

A clump can also never have more than one rune in a row, though the
parser doesn't have to care about this case as it is lexically
impossible. (any two runes smashed together would be lexed as one rune).

If we define RC as a rune which is not followed by a space, then clumps
always have the form:

    rc? node_ (rc node_+)*

### Nests

Nests are expression delimited by parenthesis, braces, or curlies.
Their structure is similar to clumps, but more spaced out.

    content = clump+ (rune clump+)* rune?

    gap = (WHYTE | EOL)*

    nest = BEGIN gap content? gap END

These forms can be empty ()

They can be series of clumps (a b c.d)

Or they can be interspersed with runes: (a , b + c.d)

These runes don't need a preceding space: (a, b+ c.d)

But they *do* need a trailing space.  The following input is just read
as three clumps with no infix operators (a ,b +c.d).

In between infix runes, there can be multiple forms: (f x + f y)

Trailing infix runes are also: (3, 4, 5,) (3,)

If two runes apear in a row within a nest, the second one is *not*
treated as an infix rune.  Instead, it is treated as an opening form
for a rune poem.

    (3, + x y) == (3, (+ x y))

A nest form doesn't care about spaces, except that it cares about the
difference between clumped runes and free runes.

If it sees the beginning of a
clump, it lets the clump parser consume it, and the clump parser cares
about spaces.


### Quips

A quip is like a nest, except that it always contains exactly one
thing, and doesn't need a terminator.

Basically, you can use it to quote clumps:

    'x 'foo(x) 'x.y+z

Or to quote poems:

    '+ a b
     + a[b]

Because of the lexical rules, a TICK is never followed by a space or
newline (that would be a slug) or an end (that would be a NOTE), so the
parser doesn't have to care about these cases.

### Poems

A rune poem starts with an unclumped rune (FREE) and this defines a
big square down and to the right which belongs to that poem.  A poem is
only ever escaped when a non-space token appears in the poem which is
indented less than that poem.  Here, z breaks the poem.

    ( + a b
      c d e
      f g h
    z)

Or if an END matches a BEGIN which started before the poem. Here the
closing paren breaks the poem:

    (+ a b) c

Within a poem, each free-rune starts it's own peom, so they can be nested.
This example includes four poems, three nested as siblings within one
outer peom.

    +   ~ a
      + a
    | a


### Blocks and Items

A block is a special light notation for sequences of forms.

A block is started within a NEST (or a INPUT or ITEM, which we will see
are nearly identical) in a situation where we have a series of one-or-more
nodes followed by a rune, followed by a newline, followed by something
which is indented more deeply than the initial node.

    f = 
       item
       item
       item

As soon as we see this pattern, then the first item is the indentation
level of the block. The item is parsed just like a nest, except that,
instead of an explicit terminator, it ends when something happens at
the-same-or-lesser indentation.

Here are some valid blocks.  This has one item:

    f = 
       item

This has two items:

    def f(x) = 
       item
       item

This also has two items:

    def f(x) = 
       print(
         add(x,
           y))
       b + c + d

This also has two items:

    def f(x) = 
       a +
         a + a
       b + c + d

(3 
, + a b
, 4
)

This has only one item, because the first item starts a poem which
eats the rest of the input

    def f(x) = 
       + a
       a + b
       c + d

There is a weird case where you have something like this:

    (def f(x) =
         first
         second
       weird)

In this case, the block is terminated by the weird, and the weird is
just another input to the enclosing nest.

    (paren
      def
      (juxt f (paren x))
      (rune =)
      (block (item first) (item second))
      weird)

Note that the only thing inside of a block is an item and the only place
an item occurs is inside of a block, so they are kinda two states within
the same form.


### Inputs

Top-level inputs are treated as if they were wrapped in parenthesis,
but no terminator is required:

    x += 3
