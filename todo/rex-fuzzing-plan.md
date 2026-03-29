# Rex Parser/Printer Fuzzing Plan

This document describes a comprehensive fuzzing strategy for the Rex parser and
printer using QuickCheck and SmallCheck, built on top of the `normalizeRex`
function.

## Overview

The fuzzing strategy has three layers:

1. **Arbitrary Rex Generation** - Generate random Rex trees
2. **Normalization** - Convert to round-trippable form via `normalizeRex`
3. **Property Testing** - Verify round-trip and other invariants

## Dependencies

Add to `rex.cabal`:

```cabal
test-suite rex-fuzz
  type:           exitcode-stdio-1.0
  main-is:        FuzzMain.hs
  hs-source-dirs: hs/test, hs/lib
  other-modules:
      Rex.Lex
      Rex.Tree2
      Rex.Error
      Rex.String
      Rex.Rex
      Rex.Normalize
      Rex.PrintRex
      Rex.Arbitrary
  ghc-options:    -Wall -Wcompat -threaded
  build-depends:
      base             >= 4.7 && < 5
    , QuickCheck       >= 2.14
    , smallcheck       >= 1.2
    , ansi-wl-pprint
    , directory
    , extra
    , filepath
    , optics
    , pretty-show
  default-language: Haskell2010
```

## Module Structure

### Rex.Normalize

The normalizer module (from `rex-normalizer.md`):

```haskell
module Rex.Normalize
    ( normalizeRex
    , isNormalized
    , stripSpans       -- for comparison ignoring source positions
    ) where
```

### Rex.Arbitrary

Generators for Rex and related types:

```haskell
module Rex.Arbitrary
    ( arbitraryRex
    , arbitraryNormalizedRex
    , arbitraryLeafShape
    , arbitraryColor
    , arbitraryRune
    , arbitraryWord
    , arbitraryCord
    -- SmallCheck series
    , seriesRex
    , seriesNormalizedRex
    ) where
```

## Generator Design

### Basic Generators

```haskell
-- Valid rune characters (from Rex.Lex)
runeChars :: String
runeChars = ";,:#$`~@?\\|^&=!<>+-*/%."

-- Generate a valid rune (1-3 chars, all from runeChars)
arbitraryRune :: Gen String
arbitraryRune = do
    len <- choose (1, 3)
    vectorOf len (elements runeChars)

-- Generate a valid word (alphanumeric + underscore, starts with letter/underscore)
arbitraryWord :: Gen String
arbitraryWord = do
    first <- elements $ ['a'..'z'] ++ ['A'..'Z'] ++ ['_']
    rest <- listOf $ elements $ ['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9'] ++ ['_']
    len <- choose (0, 10)
    return $ first : take len rest

-- Generate string content for CORD/TAPE/PAGE/SPAN
-- Avoid problematic characters that break parsing
arbitraryCord :: Gen String
arbitraryCord = listOf $ elements $ ['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9'] ++ " _-"

-- Colors (for NEST/EXPR)
arbitraryColor :: Gen Color
arbitraryColor = elements [PAREN, BRACK, CURLY, CLEAR]

-- Leaf shapes (exclude BAD for valid generation)
arbitraryLeafShape :: Gen LeafShape
arbitraryLeafShape = elements [WORD, QUIP, CORD, TAPE, PAGE, SPAN, SLUG]
```

### Rex Generator (Sized, Recursive)

```haskell
arbitraryRex :: Gen Rex
arbitraryRex = sized arbRex

arbRex :: Int -> Gen Rex
arbRex 0 = arbLeaf  -- base case: only leaves at size 0
arbRex n = oneof
    [ arbLeaf
    , arbNest n
    , arbExpr n
    , arbPref n
    , arbTyte n
    , arbBloc n
    , arbOpen n
    , arbJuxt n
    , arbHeir n
    ]

arbLeaf :: Gen Rex
arbLeaf = do
    shape <- arbitraryLeafShape
    content <- case shape of
        WORD -> arbitraryWord
        QUIP -> arbitraryWord  -- quips are like words
        CORD -> arbitraryCord
        TAPE -> arbitraryCord
        PAGE -> arbitraryCord
        SPAN -> arbitraryCord
        SLUG -> arbitraryCord
        BAD _ -> pure "bad"    -- shouldn't happen
    pure $ LEAF noSpan shape content

arbNest :: Int -> Gen Rex
arbNest n = do
    color <- arbitraryColor
    rune <- arbitraryRune
    numKids <- choose (0, 4)
    kids <- vectorOf numKids (arbRex (n `div` 2))
    pure $ NEST noSpan color rune kids

arbExpr :: Int -> Gen Rex
arbExpr n = do
    color <- arbitraryColor
    numKids <- choose (0, 4)
    kids <- vectorOf numKids (arbRex (n `div` 2))
    pure $ EXPR noSpan color kids

arbPref :: Int -> Gen Rex
arbPref n = do
    rune <- arbitraryRune
    child <- arbRex (n - 1)
    pure $ PREF noSpan rune child

arbTyte :: Int -> Gen Rex
arbTyte n = do
    rune <- arbitraryRune
    numKids <- choose (0, 4)
    kids <- vectorOf numKids (arbRex (n `div` 2))
    pure $ TYTE noSpan rune kids

arbBloc :: Int -> Gen Rex
arbBloc n = do
    color <- arbitraryColor
    rune <- arbitraryRune
    hd <- arbRex (n `div` 2)
    numItems <- choose (1, 4)
    items <- vectorOf numItems (arbRex (n `div` 2))
    pure $ BLOC noSpan color rune hd items

arbOpen :: Int -> Gen Rex
arbOpen n = do
    rune <- arbitraryRune
    numKids <- choose (0, 4)
    kids <- vectorOf numKids (arbRex (n `div` 2))
    pure $ OPEN noSpan rune kids

arbJuxt :: Int -> Gen Rex
arbJuxt n = do
    numKids <- choose (2, 4)  -- JUXT needs at least 2
    kids <- vectorOf numKids (arbRex (n `div` 2))
    pure $ JUXT noSpan kids

arbHeir :: Int -> Gen Rex
arbHeir n = do
    numKids <- choose (2, 4)  -- HEIR needs at least 2
    kids <- vectorOf numKids (arbRex (n `div` 2))
    pure $ HEIR noSpan kids
```

### Normalized Rex Generator

For efficiency, generate already-normalized Rex:

```haskell
arbitraryNormalizedRex :: Gen Rex
arbitraryNormalizedRex = normalizeRex <$> arbitraryRex
```

Or, generate structurally valid Rex directly (avoiding invalid patterns):

```haskell
-- Generate Rex that is already in normal form
arbNormalizedRex :: Int -> Gen Rex
arbNormalizedRex n = ...  -- similar to arbRex but respects constraints
```

### SmallCheck Series

For exhaustive testing of small cases:

```haskell
instance Serial m LeafShape where
    series = cons0 WORD \/ cons0 QUIP \/ cons0 CORD \/ cons0 TAPE
          \/ cons0 PAGE \/ cons0 SPAN \/ cons0 SLUG

instance Serial m Color where
    series = cons0 PAREN \/ cons0 BRACK \/ cons0 CURLY
    -- Note: exclude CLEAR to avoid edge cases, or include with care

instance Serial m Rex where
    series = cons3 mkLeaf \/ cons4 mkNest \/ cons3 mkExpr
          \/ cons3 mkPref \/ cons3 mkTyte \/ cons5 mkBloc
          \/ cons3 mkOpen \/ cons2 mkJuxt \/ cons2 mkHeir
      where
        mkLeaf sh s = LEAF noSpan sh s
        mkNest c r ks = NEST noSpan c r ks
        mkExpr c ks = EXPR noSpan c ks
        mkPref r x = PREF noSpan r x
        mkTyte r ks = TYTE noSpan r ks
        mkBloc c r h is = BLOC noSpan c r h is
        mkOpen r ks = OPEN noSpan r ks
        mkJuxt ks = JUXT noSpan ks
        mkHeir ks = HEIR noSpan ks
```

## Properties to Test

### Core Round-Trip Property

```haskell
-- The fundamental property: normalized Rex round-trips
prop_roundtrip :: Rex -> Property
prop_roundtrip r =
    let normalized = normalizeRex r
        printed = printRex 80 normalized
        parsed = parseAndConvert printed
    in counterexample ("Printed:\n" ++ printed) $
       counterexample ("Parsed: " ++ show parsed) $
       stripSpans parsed === stripSpans normalized

-- Helper to parse and convert to Rex
parseAndConvert :: String -> Rex
parseAndConvert s = case parseRex s of
    [(slice, tree)] -> case rexFromBlockTree slice tree of
        Just rex -> rex
        Nothing -> error "rexFromBlockTree returned Nothing"
    _ -> error "parseRex returned unexpected result"

-- Strip spans for structural comparison
stripSpans :: Rex -> Rex
stripSpans = \case
    LEAF _ sh s -> LEAF noSpan sh s
    NEST _ c r ks -> NEST noSpan c r (map stripSpans ks)
    EXPR _ c ks -> EXPR noSpan c (map stripSpans ks)
    PREF _ r x -> PREF noSpan r (stripSpans x)
    TYTE _ r ks -> TYTE noSpan r (map stripSpans ks)
    BLOC _ c r h is -> BLOC noSpan c r (stripSpans h) (map stripSpans is)
    OPEN _ r ks -> OPEN noSpan r (map stripSpans ks)
    JUXT _ ks -> JUXT noSpan (map stripSpans ks)
    HEIR _ ks -> HEIR noSpan (map stripSpans ks)
```

### Normalizer Idempotence

```haskell
-- Normalizing twice is the same as normalizing once
prop_normalize_idempotent :: Rex -> Property
prop_normalize_idempotent r =
    normalizeRex (normalizeRex r) === normalizeRex r
```

### Normalizer Preserves Valid Rex

```haskell
-- If Rex is already normalized, normalizeRex is identity
prop_normalize_preserves_valid :: Rex -> Property
prop_normalize_preserves_valid r =
    isNormalized r ==> normalizeRex r === r
```

### Print Never Crashes

```haskell
-- Printing any Rex (even non-normalized) should not crash
prop_print_total :: Rex -> Bool
prop_print_total r = length (printRex 80 r) >= 0
```

### Parse Never Crashes

```haskell
-- Parsing any string should not crash (may return errors)
prop_parse_total :: String -> Bool
prop_parse_total s = case parseRex s of
    _ -> True  -- just force evaluation
```

### Width Respect

```haskell
-- Printed output respects width (soft constraint, may exceed for atoms)
prop_width_respected :: Rex -> Property
prop_width_respected r =
    let width = 40
        printed = printRex width (normalizeRex r)
        maxLine = maximum (0 : map length (lines printed))
    in counterexample ("Max line: " ++ show maxLine) $
       counterexample ("Printed:\n" ++ printed) $
       maxLine <= width * 2  -- allow some slack
```

### Structural Properties

```haskell
-- JUXT always has >= 2 children after normalization
prop_juxt_min_children :: Rex -> Property
prop_juxt_min_children r =
    let normalized = normalizeRex r
    in checkJuxtChildren normalized
  where
    checkJuxtChildren (JUXT _ ks) = length ks >= 2 .&&. all checkJuxtChildren ks
    checkJuxtChildren (NEST _ _ _ ks) = all checkJuxtChildren ks
    checkJuxtChildren (EXPR _ _ ks) = all checkJuxtChildren ks
    checkJuxtChildren (PREF _ _ x) = checkJuxtChildren x
    checkJuxtChildren (TYTE _ _ ks) = all checkJuxtChildren ks
    checkJuxtChildren (BLOC _ _ _ h is) = checkJuxtChildren h .&&. all checkJuxtChildren is
    checkJuxtChildren (OPEN _ _ ks) = all checkJuxtChildren ks
    checkJuxtChildren (HEIR _ ks) = all checkJuxtChildren ks
    checkJuxtChildren (LEAF _ _ _) = property True

-- TYTE always has >= 2 children after normalization
prop_tyte_min_children :: Rex -> Property
prop_tyte_min_children r = ...  -- similar

-- No EXPR CLEAR after normalization
prop_no_expr_clear :: Rex -> Property
prop_no_expr_clear r =
    let normalized = normalizeRex r
    in checkNoExprClear normalized
  where
    checkNoExprClear (EXPR _ CLEAR _) = property False
    checkNoExprClear (EXPR _ _ ks) = all checkNoExprClear ks
    checkNoExprClear ...  -- recurse through all constructors
```

## Test Main

```haskell
module Main where

import Test.QuickCheck
import Test.SmallCheck
import Test.SmallCheck.Series

import Rex.Rex
import Rex.Normalize
import Rex.Arbitrary
import Rex.PrintRex
import Rex.Tree2

main :: IO ()
main = do
    putStrLn "=== QuickCheck Tests ==="

    putStrLn "Round-trip property..."
    quickCheckWith stdArgs{maxSuccess=1000} prop_roundtrip

    putStrLn "Normalizer idempotence..."
    quickCheckWith stdArgs{maxSuccess=1000} prop_normalize_idempotent

    putStrLn "Print totality..."
    quickCheckWith stdArgs{maxSuccess=1000} prop_print_total

    putStrLn "Structural: JUXT children..."
    quickCheckWith stdArgs{maxSuccess=1000} prop_juxt_min_children

    putStrLn "Structural: no EXPR CLEAR..."
    quickCheckWith stdArgs{maxSuccess=1000} prop_no_expr_clear

    putStrLn "\n=== SmallCheck Tests (exhaustive small cases) ==="

    putStrLn "Round-trip (depth 3)..."
    smallCheck 3 prop_roundtrip

    putStrLn "Normalizer idempotence (depth 4)..."
    smallCheck 4 prop_normalize_idempotent

    putStrLn "\nAll tests passed!"
```

## Shrinking

QuickCheck's shrinking helps find minimal counterexamples:

```haskell
instance Arbitrary Rex where
    arbitrary = arbitraryRex

    shrink (LEAF _ sh s) = [LEAF noSpan sh (take n s) | n <- [0..length s - 1]]
    shrink (NEST _ c r ks) =
        ks ++  -- try each child directly
        [NEST noSpan c r ks' | ks' <- shrinkList shrink ks]
    shrink (EXPR _ c ks) =
        ks ++
        [EXPR noSpan c ks' | ks' <- shrinkList shrink ks]
    shrink (PREF _ r x) =
        [x] ++  -- try unwrapping
        [PREF noSpan r x' | x' <- shrink x]
    shrink (TYTE _ r ks) =
        ks ++
        [TYTE noSpan r ks' | ks' <- shrinkList shrink ks]
    shrink (JUXT _ ks) =
        ks ++
        [JUXT noSpan ks' | ks' <- shrinkList shrink ks, length ks' >= 2]
    shrink (HEIR _ ks) =
        ks ++
        [HEIR noSpan ks' | ks' <- shrinkList shrink ks, length ks' >= 2]
    shrink (OPEN _ r ks) =
        ks ++
        [OPEN noSpan r ks' | ks' <- shrinkList shrink ks]
    shrink (BLOC _ c r h is) =
        [h] ++ is ++
        [BLOC noSpan c r h' is | h' <- shrink h] ++
        [BLOC noSpan c r h is' | is' <- shrinkList shrink is, not (null is')]
```

## Debugging Failed Cases

When a test fails, the infrastructure should:

1. Print the generated Rex (pretty-printed structure)
2. Print the printed string
3. Print the re-parsed Rex
4. Show the diff between expected and actual

```haskell
debugRoundtrip :: Rex -> IO ()
debugRoundtrip r = do
    let normalized = normalizeRex r
    putStrLn "=== Original Rex ==="
    putStrLn $ ppRex normalized

    let printed = printRex 80 normalized
    putStrLn "\n=== Printed ==="
    putStrLn printed

    let parsed = parseAndConvert printed
    putStrLn "\n=== Re-parsed Rex ==="
    putStrLn $ ppRex parsed

    putStrLn "\n=== Match ==="
    print $ stripSpans parsed == stripSpans normalized
```

## Implementation Order

1. **Implement `Rex.Normalize`** (from rex-normalizer.md)
   - `normalizeRex :: Rex -> Rex`
   - `isNormalized :: Rex -> Bool`
   - `stripSpans :: Rex -> Rex`

2. **Implement `Rex.Arbitrary`**
   - Basic generators (rune, word, cord, etc.)
   - `Arbitrary Rex` instance with shrinking
   - SmallCheck `Serial Rex` instance

3. **Create test suite**
   - Add test-suite to cabal
   - Implement properties
   - Run and fix discovered issues

4. **Iterate**
   - Failed tests reveal normalizer bugs or missing rules
   - Add new normalization rules as discovered
   - Re-run until all properties pass

## Expected Issues

The fuzzer will likely discover:

1. **Missing normalization rules** - edge cases we didn't anticipate
2. **Printer bugs** - cases where output doesn't parse correctly
3. **Parser ambiguities** - inputs that parse differently than expected
4. **String escaping issues** - special characters in CORD/TAPE/etc.

Each failure is an opportunity to improve the normalizer or fix bugs.
