# Slugs in HEIR forms

I'd like to have slugs be more tightly integrated into HEIR forms,
so that they can be used for notes and docstrings within rune poems.

    ' foo
    ' bar
    x=3

should parse as

    HEIR (SLUG "foo\nbar", TYTE "=" "x" "3")

And similarly, you should be able to write things like this:

    = (f x y)
    ' This does f to x
    ' and also to y,
    ' returning the result
    "the result"

And this:

    ' This is some text before
    ' a definition, what this
    ' means is up to the language.
    = (f x y)
    "the result"
