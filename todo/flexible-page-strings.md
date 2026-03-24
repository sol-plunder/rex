# TODO: Explore the idea of flexible page strings.

In nix, you can write string literals like this:

    foo.bar = ''
      Line1
      Line2
    ''

We could support this with ugly strings (PAGEs) if the prefix stripping
was based on the indentation of terminator, instead of the opener.
This would be strictly more expressive, since the currently mandatory
PAGE layout would retain the exact same meaning.

This would be a bit more mechnically complicated, to implement, and I
want to think through the implications of that first, before committing
to this design.

I propose the following approach:

-   The lexer no longer validates, and it does not distinguish between
    PAGE and SPAN, it just produces UGLY tokens.  It begins a token when
    it sees a string of two-or-more ticks, and it finishes when it finds
    a matching sequence of ticks.

-   The Rex loading logic then converts the UGLY token into a PAGE,
    a SPAN, or a BAD depending on layout of the string.

    1.  If the string begins with a newline, we try to parse it as a PAGE.
        We now know the location of each token, so we have enough
        information to do the validation ourselves.

        Break the input into lines.

        Drop the first line, which will always be empty (since we already
        checked that it begins with a newline).

        Validate that the last line is `/^ *'''$/`.  It's a BAD otherwise.
        Count the number of leading spaces, and then Drop the last line.

        Strip the first n characters from each line, after validating
        that these characters are all spaces.  If we find any non-space
        characters, poision the whole input (it becomes a BAD leaf).

        Combine the lines back together to form the final string.

    2.  If the string begins with something besides a newline, it is
        a SPAN.

        Drop the first 3 characters, and the last three characters to
        eliminate the delimiters.

        Break the input into lines.

        For all lines besides the first one, strip (token_depth+3)
        spaces from the front, poisioning the input if we find any
        non-space characters there.

That's it.  I think this works.  Please review, and give me an analysis
of the viability of this approach.
