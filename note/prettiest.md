# A Pretty But Not Greedy Printer (Functional Pearl)

**Jean-Philippe Bernardy**, University of Gothenburg, Department of Philosophy, Linguistics and Theory of Science

*PACM Progr. Lang., Vol. 1, No. 1, Article 6. Publication date: September 2017.*
*DOI: 10.1145/3110250*

---

## Abstract

This paper proposes a new specification of pretty printing which is stronger than the state of the art: we require the output to be the shortest possible, and we also offer the ability to align sub-documents at will. We argue that our specification precludes a greedy implementation. Yet, we provide an implementation which behaves linearly in the size of the output. The derivation of the implementation demonstrates functional programming methodology.

**CCS Concepts:** Software and its engineering → Functional languages; Mathematics of computing → Combinatorial optimization

**Additional Key Words and Phrases:** Pretty Printing

---

## 1 Introduction

A pretty printer is a program that prints data structures in a way which makes them pleasant to read. (The data structures in question often represent programs, but not always.) Pretty printing has historically been used by members of the functional programming community to showcase good style. Prominent examples include the pretty printer of Hughes [1995], which remains an influential example of functional programming design, and that of Wadler [2003] which was published as a chapter in a book dedicated to the "fun of programming".

In addition to their aesthetic and pedagogical value, the pretty printers of Hughes and Wadler are practical implementations. Indeed, they form the basis of industrial-strength pretty-printing packages which remain popular today. Hughes' design has been refined by Peyton Jones, and is available as the Hackage package `pretty`, while Wadler's design has been extended by Leijen and made available as the `wl-print` package. An OCaml implementation of Wadler's design also exists.

While this paper draws much inspiration from the aforementioned landmark pieces of work in the functional programming landscape, my goal is slightly different to that of Hughes and Wadler. Indeed, they aim first and foremost to demonstrate general principles of functional programming development, with an emphasis on the efficiency of the algorithm. Their methodological approach is to derive a *greedy* algorithm from a functional specification. In the process, they give themselves some leeway as to what they accept as pretty outputs (see Sec. 3.1). In contrast, my primary goal is to produce *the prettiest output*, at the cost of efficiency. Yet, the final result is reasonably efficient (Sec. 7).

Let us specify the desired behavior of a pretty printer, first informally, as the following principles:

**Principle 1. Visibility** — A pretty printer shall layout all its output within the width of the page.

**Principle 2. Legibility** — A pretty printer shall make appropriate use of layout, to make it easy for a human to recognize the hierarchical organization of data.

**Principle 3. Frugality** — A pretty printer shall minimize the number of lines used to display the data.

Furthermore, the first principle takes precedence over the second one, which itself takes precedence over the third one. In the rest of the paper, we interpret the above three principles as an optimization problem, and derive a program which solves it efficiently enough for practical purposes.

Before diving into the details, let us pose a couple of methodological points. First, Haskell is used throughout this paper in its quality of *lingua franca* of functional programming pearls — yet, we make no essential use of laziness. Second, the source code for the paper and benchmarks, as well as a fully fledged pretty printing library based on its principles is available online: https://github.com/jyp/prettiest. A Haskell library based on the algorithm developed here is available as well: https://hackage.haskell.org/package/pretty-compact.

---

## 2 Interface (Syntax)

Let us use an example to guide the development of our pretty-printing interface. Assume that we want to pretty print S-Expressions, which can either be an atom or a list of S-Expressions. They can be represented in Haskell as follows:

```haskell
data SExpr = SExpr [SExpr] | Atom String
  deriving Show
```

Using the above representation, the S-Expr `(a b c d)` has the following encoding:

```haskell
abcd :: SExpr
abcd = SExpr [Atom "a", Atom "b", Atom "c", Atom "d"]
```

The goal of the pretty printer is to render a given S-Expr according to the three principles of pretty printing: Visibility, Legibility and Frugality. While it is clear how the first two principles constrain the result, it is less clear how the third principle plays out: we must specify more precisely which layouts are admissible. To this end, we assert that in a pretty display of an S-Expr, the elements should be either concatenated horizontally, or aligned vertically. (Even though there are other possible choices, ours is sufficient for illustrative purposes.) For example, the legible layouts of the abcd S-Expression defined above would be either:

```
(a b c d)
```

or

```
(a
 b
 c
 d)
```

And thus, Legibility will interact in non-trivial ways with Frugality and Visibility.

In general, a pretty printing library must provide the means to express the set of legible layouts: it is up to the user to instantiate Legibility on the data structure of interest. The printer will then automatically pick the smallest (Frugality) legible layout which fits the page (Visibility).

Our layout-description API is similar to Hughes': we can concatenate documents either vertically (`$$`) or horizontally (`<>`), as well as embed raw text and choose between layouts (`<|>`) — but we lack a dedicated flexible space insertion operator (`<+>`). We give a formal definition of those operators in Sec. 4, but at this stage we keep the implementation of documents abstract. We do so by using a typeclass (`Doc`) which provides the above combinators, as well as means of rendering a document:

```haskell
text   :: Doc d => String -> d
(<>)   :: Doc d => d -> d -> d
($$)   :: Doc d => d -> d -> d
(<|>)  :: Doc d => d -> d -> d
render :: Doc d => d -> String
```

We can then define a few useful combinators on top of the above: the empty document; horizontal concatenation with a fixed intermediate space (`<+>`); vertical and horizontal concatenation of multiple documents.

```haskell
empty :: Layout d => d
empty = text ""

(<+>) :: Layout d => d -> d -> d
x <+> y = x <> text " " <> y

hsep, vcat :: Doc d => [d] -> d
vcat = foldDoc ($$)
hsep = foldDoc (<+>)

foldDoc :: Doc d => (d -> d -> d) -> [d] -> d
foldDoc _ []       = empty
foldDoc _ [x]      = x
foldDoc f (x : xs) = f x (foldDoc f xs)
```

We can furthermore define the choice between horizontal and vertical concatenation:

```haskell
sep :: Doc d => [d] -> d
sep [] = empty
sep xs = hsep xs <|> vcat xs
```

Turning S-expressions into a Doc is then straightforward:

```haskell
pretty :: Doc d => SExpr -> d
pretty (Atom s)   = text s
pretty (SExpr xs) = text "(" <>
                    (sep $ map pretty xs) <>
                    text ")"
```

---

## 3 Semantics (Informally)

The above API provides a syntax to describe layouts. The next natural question is then: what should its semantics be? In other words, how do we turn the three principles into a formal specification? In particular, how do we turn the above `pretty` function into a pretty printer of S-Expressions?

Let us use an example to pose the question in concrete terms, and outline why neither Wadler's nor Hughes' answer is satisfactory for our purposes. Suppose that we want to pretty-print the following S-Expr (which is specially crafted to demonstrate general shortcomings of both Hughes and Wadler libraries):

```haskell
testData :: SExpr
testData = SExpr [SExpr [Atom "abcde", abcd4],
                  SExpr [Atom "abcdefgh", abcd4]]
  where abcd4 = SExpr [abcd, abcd, abcd, abcd]
```

Remember that by assumption we would like elements inside an S-Expr to be either aligned vertically or concatenated horizontally (for Legibility), and that the second option should be preferred over the first (for Frugality), as long as the text fits within the page width (for Visibility). More precisely, the three principles demand the output with the smallest number of lines which still fits on the page among all the legible outputs described above. Thus on a 80-column-wide page, they demand:

```
12345678901234567890123456789012345678901234567890123456789012345678901234567890

((abcde ((a b c d) (a b c d) (a b c d) (a b c d)))
 (abcdefgh ((a b c d) (a b c d) (a b c d) (a b c d))))
```

And on a 20-column-wide page, they demand the following output:

```
12345678901234567890
((abcde ((a b c d)
         (a b c d)
         (a b c d)
         (a b c d)))
 (abcdefgh
  ((a b c d)
   (a b c d)
   (a b c d)
   (a b c d))))
```

Yet, neither Hughes' nor Wadler's library can deliver those results.

### 3.1 The limitations of Hughes and Wadler

Let us take a moment to see why. On a 20-column page and using Hughes' library, we would get output that uses much more space than necessary, violating Frugality. Why is that? Hughes states that "it would be unreasonably inefficient for a pretty-printer to decide whether or not to split the first line of a document on the basis of the content of the last." (sec. 7.4 of his paper). Therefore, he chooses a greedy algorithm, which processes the input line by line, trying to fit as much text as possible on the current line, without regard for what comes next. In our example, the algorithm can fit `(abcdefgh ((a` on the sixth line, but then it has committed to a very deep indentation level, which forces to display the remainder of the document in a narrow area, wasting vertical space. Such a waste occurs in many real examples: any optimistic fitting on an early line may waste tremendous amount of space later on.

How does Wadler's library fare on the example? Unfortunately, we cannot answer the question in a strict sense. Indeed, Wadler's API is too restrictive to even *express* the layout that we are after. That is, one can only specify a *constant* amount of indentation, not one that depends on the contents of a document. In other words, Wadler's library lacks the capability to express that a multi-line sub-document b should be laid out to the right of a document a (even if a is single-line). Instead, b must be put below a.

Suppose that we would like to pretty print a ML-style equation composed of a Pattern and the following right-hand-side:

```
expression [listElement x,
            listElement y,
            listElement z,
            listElement w]
```

Quite reasonably, we hope to obtain the following result, which puts the list to the right of the expression, clearly showing that the list is an argument of expression, and thus properly respecting Legibility:

```
Pattern = expression [listElement x,
                      listElement y,
                      listElement z,
                      listElement w]
```

However, using Wadler's library, the indentation of the list can only be constant, so even with the best layout specification we would obtain instead the following output:

```
Pattern = expression
  [listElement x,
   listElement y,
   listElement z,
   listElement w]
```

Aligning the argument of the expression below and to the left of the equal sign is bad, because it needlessly obscures the structure of the program; Legibility is not respected. The lack of a combinator for relative indentation is a serious drawback. In fact, Leijen's implementation of Wadler's design (wl-print), *does* feature an alignment combinator. However, as Hughes' does, Leijen's uses a greedy algorithm, and thus suffers from the same issue as Hughes' library.

In summary, we have to make a choice between either respecting the three principles of pretty printing, or providing a greedy algorithm. Hughes does not fully respect Frugality. Wadler does not fully respect Legibility. Here, I decide to respect both, but I give up on greediness. Yet, the final algorithm that I arrive at is fast enough for common pretty-printing tasks.

---

## 4 Semantics (Formally)

### 4.1 Layouts

We ignore for a moment the choice between possible layouts (`<|>`). As Hughes does, we call a document without choice a *layout*.

Recall that we have inherited from Hughes a draft API for layouts:

```haskell
text :: Layout l => String -> l
(<>) :: Layout l => l -> l -> l
($$) :: Layout l => l -> l -> l
```

At this stage, classic functional pearls would state a number of laws that the above API has to satisfy, then infer a semantics from them. Fortunately, in our case, Hughes and Wadler have already laid out this ground work, so we can take a shortcut and immediately state a compositional semantics. We will later check that the expected laws hold.

Let us interpret a layout as a *non-empty* list of lines to print. As Hughes, I shall simply use the type of lists, trusting the reader to remember the invariant of non-emptiness.

```haskell
type L = [String]
```

Preparing a layout for printing is as easy as inserting a newline character between each string:

```haskell
render :: L -> String
render = intercalate "\n"

intercalate :: String -> [String] -> String
intercalate x []       = []
intercalate x (y : ys) = y ++ x ++ intercalate ys
```

Embedding a string is thus immediate:

```haskell
text :: String -> L
text s = [s]
```

The interpretation of vertical concatenation (`$$`) requires barely more thought: it suffices to concatenate the input lists.

```haskell
($$) :: L -> L -> L
xs $$ ys = xs ++ ys
```

The only potential difficulty is to figure out the interpretation of horizontal concatenation (`<>`). We follow the advice provided by Hughes [1995]: "translate the second operand [to the right], so that its first character abuts against the last character of the first operand".

Algorithmically, one must handle the last line of the first layout and the first line of the second layout specially, as follows:

```haskell
(<>) :: L -> L -> L
xs <> (y : ys) = xs0 ++ [x ++ y] ++ map (indent ++) ys
  where xs0    = init xs
        x      = last xs
        n      = length x
        indent = replicate n ' '
```

We take a quick detour to refine our API a bit. Indeed, as becomes clear with the above definition, vertical concatenation is (nearly) a special case of horizontal composition. That is, instead of composing vertically, one can add an empty line to the left-hand-side layout and then compose horizontally. The combinator which adds an empty line is called `flush`, and has the following definition:

```haskell
flush :: L -> L
flush xs = xs ++ [""]
```

Vertical concatenation is then:

```haskell
($$) :: L -> L -> L
a $$ b = flush a <> b
```

One might argue that replacing (`$$`) by `flush` does not make the API shorter nor simpler. Yet, we stick this choice, for two reasons:

1. The new API clearly separates the concerns of concatenation and left-flushing documents.
2. The horizontal composition (`<>`) has a nicer algebraic structure than (`$$`). Indeed, the vertical composition (`$$`) has no unit, while (`<>`) has the empty layout as unit. (In Hughes' pretty-printer, not even (`<>`) has a unit, due to more involved semantics.)

To sum up, our API for layouts is the following:

```haskell
class Layout l where
  (<>)   :: l -> l -> l
  text   :: String -> l
  flush  :: l -> l
  render :: l -> String
```

Additionally, as mentioned above, layouts follow a number of algebraic laws:

1. Layouts form a monoid, with operator (`<>`) and unit `empty`:
   - `empty <> a ≡ a`
   - `a <> empty ≡ a`
   - `(a <> b) <> c ≡ a <> (b <> c)`

2. `text` is a monoid homomorphism:
   - `text s <> text t ≡ text (s ++ t)`
   - `empty ≡ text ""`

3. `flush` can be pulled out of concatenation, in this way:
   - `flush a <> flush b ≡ flush (flush a <> b)`

### 4.2 Choice

We proceed to extend the API with choice between layouts, yielding the final API to specify legible documents. The extended API is accessible via a new type class:

```haskell
class Layout d => Doc d where
  (<|>) :: d -> d -> d
  fail  :: d
```

Again, we give the compositional semantics straight away. Documents are interpreted as a set of layouts. We implement sets as lists, and we will take care not to depend on the order and number of occurrences.

The interpretation of disjunction merely appends the list of possible layouts:

```haskell
instance Doc [L] where
  xs <|> ys = (xs ++ ys)
  fail = []
```

Consequently, disjunction is associative.

We simply lift the layout operators idiomatically over sets: elements in sets are treated combinatorially.

```haskell
instance Layout [L] where
  text  = pure . text
  flush = fmap flush
  xs <> ys = (<>) <$> xs <*> ys
```

Consequently, concatenation and flush distribute over disjunction.

### 4.3 Semantics

We can finally define formally what it means to render a document. We wrote above that the prettiest layout is the solution of the optimization problem given by combining all three principles. Namely, to pick a most frugal layout among the visible ones:

```haskell
render = render .
         mostFrugal .
         filter visible
```

Visibility is formalized by the `visible` function, which states that all lines must fit on the page:

```haskell
visible :: L -> Bool
visible xs = maximum (map length xs) <= pageWidth

pageWidth = 80
```

Frugality is formalized by the `mostFrugal` function, which picks a layout with the least number of lines:

```haskell
mostFrugal :: [L] -> L
mostFrugal = minimumBy size
  where size = compare `on` length
```

Legibility is realized by the applications-specific set of layouts, specified by the API of Sec. 2, which comes as an input to `render`.

We have now defined semantics compositionally. Furthermore, this semantics is executable, and thus we can implement the pretty printing of an S-Expr as follows:

```haskell
showSExpr x = render (pretty x :: [L])
```

Running `showSExpr` on our example (`testData`) may eventually yield the output that we demanded in Sec. 3. But one should not expect to see it any time soon. Indeed, while the above semantics provides an executable implementation, it is impracticably slow. Indeed, every possible combination of choices is first constructed, and only then a shortest output is picked. Thus, for an input with n choices, the running time is O(2^n).

---

## 5 A More Efficient Implementation

The next chunk of work is to transform the above, clearly correct but inefficient implementation to a functionally equivalent, but efficient one. To do so we need two insights.

### 5.1 Measures

The first insight is that it is not necessary to fully construct layouts to calculate their size: only some of their parameters are relevant. Let us remember that we want to sift through layouts based on the space that they take. Hence, from an algorithmic point of view, all that matters is a *measure* of that space. Let us define an abstract semantics for layouts, which ignores the text, and captures only the amount of space used.

The only parameters that matter are the maximum width of the layout, the width of its last line and its height (and, because layouts cannot be empty and it is convenient to start counting from zero, we do not count the last line):

```haskell
data M = M { height    :: Int
           , lastWidth :: Int
           , maxWidth  :: Int
           }
  deriving (Show, Eq, Ord)
```

The concatenation operation on measures:

```haskell
instance Layout M where
  a <> b =
    M { maxWidth  = max (maxWidth a) (lastWidth a + maxWidth b)
      , height    = height a + height b
      , lastWidth = lastWidth a + lastWidth b
      }
```

The other layout combinators are easy to implement:

```haskell
  text s = M { height    = 0
             , maxWidth  = length s
             , lastWidth = length s
             }

  flush a = M { maxWidth  = maxWidth a
              , height    = height a + 1
              , lastWidth = 0
              }
```

Using the measure, we can check that a layout is fully visible simply by checking that `maxWidth` is small enough:

```haskell
valid :: M -> Bool
valid x = maxWidth x <= pageWidth
```

### 5.2 Early filtering out invalid results

The first optimization is to filter out invalid results early:

```haskell
text x   = filter valid [text x]
xs <> ys = filter valid [x <> y | x <- xs, y <- ys]
```

We can do so because de-construction preserves validity: the validity of a document implies the validity of its parts.

**Lemma 5.2.** De-construction preserves validity. The following two implications hold:
- `valid (a <> b) => valid a ∧ valid b`
- `valid (flush a) => valid a`

**Theorem 5.3.** Invalid layouts cannot be fixed:
- `not (valid a) => not (valid (a <> b))`
- `not (valid b) => not (valid (a <> b))`
- `not (valid a) => not (valid (flush a))`

### 5.3 Pruning out dominated results

The second optimization relies on the insight that even certain valid results are dominated by others. That is, they can be discarded early.

We write `a ≺ b` when a dominates b. We will arrange our domination relation such that:

1. Layout operators are monotonic with respect to domination. Consequently, for any document context `ctx :: Doc d => d -> d`, if `a ≺ b` then `ctx a ≺ ctx b`

2. If `a ≺ b`, then a is at least as frugal as b.

Together, these properties mean that we can always discard dominated layouts from a set.

**Theorem 5.4.** (Domination) For any context ctx, we have:
`a ≺ b => height (ctx a) <= height (ctx b)`

The order that we use is the intersection of ordering in all dimensions: if layout a is shorter, narrower, and has a narrower last line than layout b, then a dominates b.

```haskell
instance Poset M where
  m1 ≺ m2 = height m1    <= height m2    &&
            maxWidth m1  <= maxWidth m2  &&
            lastWidth m1 <= lastWidth m2
```

### 5.4 Pareto frontier

We know by now that in any set of possible layouts, it is sufficient to consider the subset of non-dominated layouts. This subset is known as the **Pareto frontier** and has the following definition:

**Definition 5.7.** Pareto frontier: `Pareto(X) = {x ∈ X | ¬∃y ∈ X. x ≠ y ∧ y ≺ x}`

When sets are represented as lists without duplicates, the Pareto frontier can be computed as follows:

```haskell
pareto :: Poset a => [a] -> [a]
pareto = loop []
  where loop acc []       = acc
        loop acc (x : xs) = if any (≺ x) acc
                            then loop acc xs
                            else loop (x : filter (not . (x ≺)) acc) xs
```

The implementation of the pretty-printing combinators then becomes:

```haskell
type DM = [M]

instance Layout DM where
  xs <> ys = pareto (concat [filter valid [x <> y | y <- ys] | x <- xs])
  flush xs = pareto (map flush xs)
  text s   = filter valid [text s]
  render   = render . minimum

instance Doc DM where
  fail       = []
  xs <|> ys  = pareto (xs ++ ys)
```

The above is the final, optimized version of the layout-computation algorithm.

---

## 6 Additional Features

### 6.1 Re-pairing with text

Eventually, one might be interested in getting a complete pretty printed output, not just the amount of space that it takes. To do so we can pair measures with full-text layouts, while keeping the measure of space for actual computations:

```haskell
instance Poset (M, L) where
  (a, _) ≺ (b, _) = a ≺ b

instance Layout (M, L) where
  (x, x') <> (y, y') = (x <> y, x' <> y')
  flush (x, x')      = (flush x, flush x')
  text s             = (text s, text s)
  render             = render . snd
```

### 6.2 Hughes-Style nesting

Hughes proposes a `nest` combinator, which indents its argument *unless* it appears on the right-hand-side of a horizontal concatenation. The above semantics are rather involved, and appear difficult to support by a local modification of the framework developed in this paper.

Fortunately, in practice `nest` is used only to implement the `hang` combinator, which offers the choice between horizontal concatenation and vertical concatenation with an indentation:

```haskell
hang :: Doc d => Int -> d -> d -> d
hang n x y = (x <> y) <|> (x $$ nest n y)
```

In this context, nesting occurs on the right-hand-side of vertical concatenation, and thus its semantics can be simplified. In fact, in the context of `hang`, it can be implemented easily in terms of the combinators provided so far:

```haskell
nest :: Layout d => Int -> d -> d
nest n y = spaces n <> y
  where spaces n = text (replicate n ' ')
```

### 6.3 Ribbon length

Another subtle feature of Hughes' library is the ability to limit the amount of text on a single line, ignoring the current indentation. The goal is to avoid long lines mixed with short lines. While such a feature is easily added to Hughes or Wadler's greedy pretty printer, it is harder to support as such on top of the basis we have so far.

An alternative approach to avoid too long lines is to interpret the ribbon length as the maximum size of a self-contained sublayout fitting on a single line. This interpretation can be implemented efficiently, by filtering out intermediate results that do not fit the ribbon:

```haskell
fitRibbon m = height m > 0 || maxWidth m < ribbonLength
valid' m    = valid m && fitRibbon m
```

---

## 7 Performance Tests

Having optimized our algorithm as best we could, we turn to empirical tests to evaluate its performance.

### 7.1 Behaviour at scale

In order to benchmark our pretty printer on large outputs, we have used it to lay out full binary trees and random trees, represented as S-Expressions.

**Full trees.** S-expressions representing full binary trees of increasing depth were generated by the following function:

```haskell
testExpr 0 = Atom "a"
testExpr n = SExpr [testExpr (n - 1), testExpr (n - 1)]
```

Pretty-printing the generated S-expression heavily exercises the disjunction construct. Indeed, for each S-Expressions with two sub-expressions, the printer introduces a choice, therefore the number of choices is equal to the number of nodes in a binary tree of depth n. Thus, for `testExpr n` the pretty printer is offered 2^n - 1 choices, for a total of 2^(2^n-1) possible layouts to consider.

The results show a behavior that tends to become linear when the output is large enough. For such large inputs approximately 1444.27 lines are laid out per second.

We interpret this result as follows. Our pretty-printer essentially considers non-dominated layouts. If the input is sufficiently complex, this means to consider approximately one layout per possible width (80 in our tests) — when the width is given then the length and the width of last line are fixed. Therefore, for sufficiently large outputs the amount of work becomes independent of the number of disjunctions present in the input, and depends only on the amount of text to render.

**Random trees.** The results corroborate those obtained for full trees: the observed running time is proportional to the length of the output. Furthermore the layout speed for random trees is roughly 10 times that of full trees.

### 7.2 Tests for full outputs and typical inputs

| Input    | Ours (ms) | Wadler-Leijen (ms) | Hughes-PJ (ms) |
|----------|-----------|-------------------|----------------|
| JSON 1k  | 9.7       | 1.5               | 3.0            |
| JSON 10k | 145.5     | 14.8              | 30.0           |
| XML 1k   | 20.0      | 3.2               | 11.9           |
| XML 10k  | 245.0     | 36.1              | 192.0          |

We observe that our library is capable of outputting roughly 70,000 lines of pretty-printed JSON per second. Its speed is roughly 40,000 lines per second for XML outputs. This performance is acceptable for many applications, and makes our library about ten times as slow as that of Wadler-Leijen. The Hughes-Peyton Jones library stands in between.

---

## 8 Conclusion

As Bird and de Moor [1997], Wadler [1987], Hughes [1995] and many others have argued, program calculation is a useful tool, and a strength of functional programming languages, with a large body of work showcasing it. Nevertheless, I had often wondered if the problem of pretty-printing had not been contrived to fit the mold of program calculation, before becoming one of its paradigmatic applications. In general, one could wonder if program calculation was only well-suited to derive greedy algorithms.

Thus I have taken the necessary steps to put my doubts to rest. I have taken a critical look at the literature to re-define what pretty-printing means, as three informal principles. I have carefully refined this informal definition to a formal semantics (arguably simpler than that of the state of the art). I avoided cutting any corner and went for the absolute prettiest layout. Doing so I could not obtain a greedy algorithm, but still have derived a reasonably efficient implementation. In the end, the standard methodology worked well: I could use it from start to finish.

---

## 9 Addendum

After this paper settled to a final version, Anton Podkopaev pointed to us that Azero and Swierstra [1998] proposed pretty printing combinators with the same semantics as that presented here (no compromise between greediness and Frugality). However their implementation had exponential behavior. Podkopaev and Boulytchev [2014] took that semantics and proposed a more efficient implementation, which computes for every document its minimal height for every pair of maxWidth and lastWidth. Their strategy is similar to mine, with the following tradeoff. In this paper I do not keep track of every width and lastWidth, but only of those which lie on the Pareto frontier. In return I have to pay a larger constant cost to sieve through intermediate results. Yet I conjecture that for non-pathological inputs the asymptotic complexities for both algorithms are the same.

---

## References

- Pablo R. Azero and S. Doaitse Swierstra. 1998. Optimal Pretty Printing Combinators. Submitted to ICFP 1998.
- Richard Bird and Oege de Moor. 1997. Algebra of programming. Prentice-Hall, Inc.
- Kalyanmoy Deb, Karthik Sindhya, and Jussi Hakanen. 2016. Multi-objective optimization. In Decision Sciences: Theory and Practice. CRC Press, 145–184.
- John Hughes. 1995. The Design of a Pretty-printing Library. In Advanced Functional Programming, First International Spring School on Advanced Functional Programming Techniques-Tutorial Text. Springer-Verlag, 53–96.
- Conor McBride and Ross Paterson. 2007. Applicative programming with effects. Journal of Functional Programming 18, 01, 1–13.
- Anton Podkopaev and Dmitri Boulytchev. 2014. Polynomial-Time Optimal Pretty-Printing Combinators with Choice. In Perspectives of System Informatics - 9th International Ershov Informatics Conference, PSI 2014. 257–265.
- S. Doaitse Swierstra and Olaf Chitil. 2009. Linear, bounded, functional pretty-printing. Journal of Functional Programming 19, 01, 1–16.
- Philip Wadler. 1987. A critique of Abelson and Sussman or why calculating is better than scheming. ACM SIGPLAN Notices 22, 3, 83–94.
- Philip Wadler. 2003. A prettier printer. Palgrave MacMillan, 223–243.
