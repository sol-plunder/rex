# Rex: Rune Expressions  
*A reference guide to the Rex front end and its structural rules*

---

## 1. Purpose and scope

Rex (short for **rune expressions**) is a notation whose goal is to capture
**structure**, not meaning.

The Rex front end transforms a stream of characters into a stream of **Rex
trees**, where each tree encodes *what belongs together* according to a small
set of orthogonal grouping mechanisms. No semantic interpretation (operators,
precedence, arity, typing, evaluation) occurs in this process.

The Rex front end should be understood as a **structural normalizer** rather
than a parser in the traditional grammar-based sense.

---

## 2. Core idea (condensed)

Two principles define Rex:

> **Runes are the invariant core. Everything else is just ways of hanging
> structure off them.**

> **Syntax is defined not by a grammar, but by a sequence of structure-refining
> passes, each resolving one class of grouping constraints.**

Each pass:

- operates on the output of the previous pass,
- resolves one kind of ambiguity,
- adds structure monotonically,
- never assigns semantics.

---

## 3. Structural vocabulary

Rex structure is built using **four orthogonal attachment mechanisms**:

1. **Explicit nesting**  
   Absolute grouping via delimiters: `()`, `[]`, `{}`

2. **Juxtaposition (clumps)**  
   Tight, adjacency-based grouping

3. **Rune poems (general layout)**  
   Indentation-based hierarchy introduced by runes  
   (includes heir alignment)

4. **Block layout**  
   Line-terminated, itemized indentation

All Rex trees are composed by combining these four mechanisms.

---

## 4. Dominance and reconciliation rules

When multiple grouping mechanisms apply at the same point, Rex resolves
conflicts using the following dominance order:

1. **Explicit nesting** (absolute)
2. **Layout** (poems and blocks)
3. **Juxtaposition** (local)

Additional reconciliation rules:

- Explicit nesting **suppresses layout** inside it.
- Juxtaposition **cannot cross layout boundaries**.
- Juxtaposition *can* cross line boundaries **only inside explicit nesting**.
- A line ending with exactly one free rune, and no other runes in the current
  context, opens a **block**. A free rune mid-context opens a **poem** if the
  context is empty or the previous token was a rune; otherwise it is treated
  as an infix rune.
- Inside an active layout, free runes open **nested layout**, not infix forms.

These rules ensure predictable behavior and always give users an escape hatch
(explicit nesting).

---

## 5. The Rex pipeline (overview)

The reference implementation maps characters to Rex trees through a sequence of
passes:

1. Lexical analysis (`lexRex`)
2. Line normalization / block splitting (`bsplit`)
3. Structural grouping (`Tree`)
4. Structural classification (`Rex`)

---

## 6. Pass 1: Lexical analysis (`lexRex`)

### Purpose
Identify atomic units and basic spatial information.

### Input

- Raw characters

### Output

- A linear stream of tokens annotated with:
  - token type (rune, word, string, etc.)
  - starting column
  - adjacency ("clump") flag

### Notes

- Runes are identified but not interpreted.
- Whitespace and newlines are preserved as structural signals.
- SLUG and UGLY string forms are fully resolved here, producing atomic leaf
  tokens whose content is determined entirely at lex time.
- Plain quips (`'`) are emitted as a bare single-character QUIP token; the
  extent of the quoted form is determined by the parser.
- No other structure is created at this stage.

---

## 7. Pass 2: Line normalization / block splitting (`bsplit`)

### Purpose
Make line-based structure explicit.

### What this pass does

- Tracks nesting depth and layout state.
- Detects when a line boundary ends a structural unit.
- Inserts explicit **end-of-block (`EOB`) tokens** where appropriate.

### Result
After this pass:

- Block boundaries are explicit.
- End-of-line is no longer implicit control flow.
- The token stream is still linear, but line structure is normalized.

---

## 8. Pass 3: Structural grouping (`Tree`)

### Purpose
Determine **what belongs together**.

This pass consumes the normalized token stream and produces a **purely
structural tree**.

It resolves:

- explicit nesting,
- juxtaposition,
- layout (indentation),
- block structure,
- heir alignment.

It does **not** interpret runes or impose precedence.

---

### 8.1 Explicit nesting

- Opened by `(`, `[`, `{`
- Closed by matching delimiters
- Always dominates other grouping mechanisms
- Layout inside a nest is ignored

Example:

```rex
f(
  x
  y
)
```

---

### 8.2 Juxtaposition (clumps)

- Tokens with no intervening whitespace form a clump.
- Clumps are maximal: whitespace or layout boundaries close them.

Constraints:

- Cannot cross layout boundaries.
- Can cross newlines only inside explicit nesting.

---

### 8.3 Rune poems (general layout)

- A free rune opens a **layout context**.
- The rune establishes an **anchor column**.
- Elements indented to the right become **children**.
- Elements aligned at or left of the anchor become **heirs**.

Example:

```rex
@ x
  y
  z
```

---

### 8.4 Heir alignment

- Lines starting at or left of the anchor column are peers, not children.

Example:

```rex
? cond
| yes
| no
```

---

### 8.5 Block layout

A block opens when:

1. A line ends,
2. The structure ends with **exactly one rune**,
3. That rune is the last element on the line.

Indented lines become block **items**.

Example:

```rex
f x =
  a
  b
```

---

## 9. Pass 4: Structural classification (`Rex`)

### Purpose
Classify structural groupings into canonical Rex forms.

This pass:

- examines Tree shapes,
- identifies prefix, infix, juxtaposition, layout, and block forms,
- still assigns **no semantics**.

The result is a **general-purpose structural IR**.

---

## 10. What the Rex front end deliberately does not do

The Rex front end does **not**:

- assign precedence,
- decide infix vs prefix semantics,
- enforce arity,
- type-check,
- evaluate expressions.

Those responsibilities belong to downstream consumers.

---

## 11. Rex as a generic tree notation

By stopping at structure, Rex generalizes many familiar syntactic forms:

- `a[x]`, `f.x()`, `(x + y * z)`
- indentation-based DSLs
- imperative block syntax
- macro languages

Instead of choosing one interpretation, Rex preserves these forms as
**structure**, allowing later phases to resolve meaning.

---

## 12. Summary

Rex defines syntax as **structure refinement**, not grammar recognition.

Each pass resolves one class of grouping constraints:

- lexical adjacency (SLUG and UGLY fully resolved; plain quips delimited by parser),
- line structure,
- nesting,
- layout,
- blocks.

Runes serve as semantic anchors; grouping is the primary artifact.
Meaning is assigned only downstream.

Rex is therefore best understood as a **universal, rune-centered tree
notation**, designed for extensibility, bootstrapping, and reuse.
