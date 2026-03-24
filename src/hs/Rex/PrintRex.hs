{-# LANGUAGE LambdaCase #-}

-- Copyright (c) 2026 Benjamin Summers
-- SPDX-License-Identifier: MIT
-- See LICENSE for full terms.
--
-- Pretty printer for Rex, producing Rex source notation.
-- Uses Rex.PDoc for width-aware layout.
--
-- Unlike PrintTree, this module prints directly from the Rex representation,
-- which preserves heir structure via the explicit HEIR constructor.

module Rex.PrintRex
    ( printRex
    , rexDoc
    , prettyRexMain
    ) where

import Rex.Rex
import Rex.PDoc
import Rex.Tree2 (parseRex)


-- | Render a Rex to a String, fitting within the given page width.
printRex :: Int -> Rex -> String
printRex width = render width . rexDoc


-- Top-level Rex Dispatch -------------------------------------------------------

rexDoc :: Rex -> PDoc
rexDoc = \case
    LEAF sh s     -> leafDoc sh s
    NEST c r kids -> nestDoc c r kids
    EXPR c kids   -> exprDoc c kids
    PREF r child  -> prefDoc r child
    TYTE r kids   -> tyteDoc r kids
    JUXT kids     -> juxtDoc kids
    OPEN r kids   -> openDoc r kids
    HEIR kids     -> heirDoc kids
    BLOC c r hd items -> blocDoc c r hd items


-- LEAF: Atomic tokens -------------------------------------------------------------
--
-- Single-line leaves are printed directly. Multi-line leaves need special
-- handling to re-add appropriate prefixes/indentation.

leafDoc :: LeafShape -> String -> PDoc
leafDoc shape s
    | '\n' `notElem` s = pdocText (formatLeafSingle shape s)
    | otherwise        = formatLeafMulti shape s

-- | Format a single-line leaf with appropriate quoting
formatLeafSingle :: LeafShape -> String -> String
formatLeafSingle WORD s = s
formatLeafSingle QUIP s = s  -- quips already have their quote
formatLeafSingle TRAD s = "\"" ++ escapeQuotes s ++ "\""
formatLeafSingle UGLY s = "'''" ++ s ++ "'''"
formatLeafSingle SLUG s = "' " ++ s

-- | Escape quotes for TRAD strings: " becomes ""
escapeQuotes :: String -> String
escapeQuotes [] = []
escapeQuotes ('"':rest) = '"' : '"' : escapeQuotes rest
escapeQuotes (c:rest) = c : escapeQuotes rest

-- | Format a multi-line leaf as a PDoc
formatLeafMulti :: LeafShape -> String -> PDoc
formatLeafMulti SLUG s = formatSlugMulti (lines s)
formatLeafMulti TRAD s = formatTradMulti (lines s)
formatLeafMulti UGLY s = formatUglyMulti (lines s)
formatLeafMulti WORD s = pdocText s  -- shouldn't have newlines, but handle anyway
formatLeafMulti QUIP s = pdocText s  -- shouldn't have newlines

-- | Format multi-line SLUG: each line prefixed with "' "
-- Uses PDent to capture the column for alignment
formatSlugMulti :: [String] -> PDoc
formatSlugMulti [] = PEmpty
formatSlugMulti (l:ls) =
    PDent (PCat (pdocText ("' " ++ l)) (slugRest ls))
  where
    slugRest [] = PEmpty
    slugRest (x:xs) = PCat PLine (PCat (pdocText ("' " ++ x)) (slugRest xs))

-- | Format multi-line TRAD: quoted, continuation lines indented
-- Uses PDent after the opening quote to align continuations
formatTradMulti :: [String] -> PDoc
formatTradMulti [] = pdocText "\"\""
formatTradMulti (l:ls) =
    PCat (PChar '"') (PDent (PCat (pdocText (escapeQuotes l)) (PCat (tradRest ls) (PChar '"'))))
  where
    tradRest [] = PEmpty
    tradRest (x:xs) = PCat PLine (PCat (pdocText (escapeQuotes x)) (tradRest xs))

-- | Format multi-line UGLY: block form with ''' delimiters
-- Opening and closing ''' must be at the same column
formatUglyMulti :: [String] -> PDoc
formatUglyMulti ls =
    PDent (PCat (pdocText "'''") (PCat PLine (PCat (uglyContent ls) (PCat PLine (pdocText "'''")))))
  where
    uglyContent [] = PEmpty
    uglyContent [x] = pdocText x
    uglyContent (x:xs) = PCat (pdocText x) (PCat PLine (uglyContent xs))


-- NEST: Infix bracket forms like (a + b), {a | b} --------------------------------
--
-- Children are separated by " rune " and enclosed in brackets.
-- When children contain HEIR, force newline between them.

nestDoc :: Color -> String -> [Rex] -> PDoc
nestDoc c r kids =
    let (open, close) = bracketChars c
        content = case kids of
            [k] -> PCat (rexDoc k) (PCat pdocSpace (pdocText r))  -- trailing rune for single element
            _   -> nestContent c r kids
    in case c of
        CLEAR -> PDent content
        _     -> PCat (PChar open) (PCat (PDent content) (PChar close))

nestContent :: Color -> String -> [Rex] -> PDoc
nestContent _ _ []     = PEmpty
nestContent _ _ [k]    = rexDoc k
nestContent c r (k:ks)
    -- If current child contains HEIR, force newline after it
    | containsHeir k = PCat (rexDoc k) (PCat PLine (PCat (pdocText (r ++ " ")) (nestContent c r ks)))
    | otherwise      = PCat (rexDoc k) (nestSep c r ks)

-- Separator between non-heir child and rest
nestSep :: Color -> String -> [Rex] -> PDoc
nestSep _ _ []     = PEmpty
nestSep c r (k:ks) =
    let flatSep = pdocText (" " ++ r ++ " ")
        vertSep = PCat PLine (pdocText (r ++ " "))
    in PCat (PChoice flatSep vertSep) (nestContent c r (k:ks))


-- EXPR: Application forms like (f x), [a, b], {} --------------------------------
--
-- Children are space-separated and enclosed in brackets.
-- Uses PChoice to try flat vs vertical layout.

exprDoc :: Color -> [Rex] -> PDoc
exprDoc c kids =
    let (open, close) = bracketChars c
        content = case kids of
            [] -> PEmpty
            _  -> PDent (pdocIntersperseFun pdocSpaceOrLine (map rexDoc kids))
    in case c of
        CLEAR -> content
        _     -> PCat (PChar open) (PCat content (PChar close))


-- PREF: Tight prefix like -x, :y ------------------------------------------------
--
-- Rune concatenated directly with child (no space).

prefDoc :: String -> Rex -> PDoc
prefDoc r child = PCat (pdocText r) (rexDocTight child)


-- TYTE: Tight infix like x.y, a:b:c ---------------------------------------------
--
-- Children concatenated with rune separator (no spaces).

tyteDoc :: String -> [Rex] -> PDoc
tyteDoc r kids =
    pdocIntersperseFun (\x y -> PCat x (PCat (pdocText r) y)) (map rexDocTight kids)


-- JUXT: Tight juxtaposition like f(x), f(x)[1] ----------------------------------
--
-- Children concatenated directly (no spaces). Complex children get wrapped
-- in parens.

juxtDoc :: [Rex] -> PDoc
juxtDoc = foldr (PCat . rexDocTight) PEmpty


-- OPEN: Rune poems like + a b c -------------------------------------------------
--
-- Layout strategy:
--   Flat:     RUNE child1 child2 child3
--   Vertical: RUNE child1
--                  child2
--                  child3
--
-- Children indent 2 past the rune (rune + space = 2 min, typically rune is
-- 1-2 chars). We use PDent after rune+space so children align.
--
-- Sibling open children use backstep for the staircase pattern.

openDoc :: String -> [Rex] -> PDoc
openDoc r kids =
    let runeD = pdocText r
        flat = PCat runeD (PCat pdocSpace (openChildrenFlat kids))
        vertical = PCat runeD (PCat pdocSpace (PDent (openChildrenVertical kids)))
    in PChoice flat vertical

openChildrenFlat :: [Rex] -> PDoc
openChildrenFlat = pdocIntersperse pdocSpace . map rexDoc

openChildrenVertical :: [Rex] -> PDoc
openChildrenVertical []     = PEmpty
openChildrenVertical [k]    = rexDoc k
openChildrenVertical (k:ks)
    | isOpenRex k = pdocBackstep (rexDoc k) (openRestAfterOpen ks)
    | otherwise   = PCat (rexDoc k) (PCat PLine (openChildrenVertical ks))

-- After an open sibling, every following child needs PLine before it.
openRestAfterOpen :: [Rex] -> PDoc
openRestAfterOpen []     = PEmpty
openRestAfterOpen [k]    = PCat PLine (rexDoc k)
openRestAfterOpen (k:ks)
    | isOpenRex k = pdocBackstep (rexDoc k) (openRestAfterOpen ks)
    | otherwise   = PCat PLine (PCat (rexDoc k) (openRestAfterOpen ks))


-- HEIR: Vertical siblings at same column ----------------------------------------
--
-- Each element appears at the exact same column, separated by newlines.
-- For OPEN children, align to the last character of the rune.
-- E.g., ":= x/y" followed by "| if ..." needs the "|" at column 1.
--
-- The alignment is determined by the first child's rune length.

heirDoc :: [Rex] -> PDoc
heirDoc []     = PEmpty
heirDoc [k]    = rexDoc k
heirDoc (k:ks) =
    let runeIndent = case k of
            OPEN r _ -> length r - 1  -- align to last char of rune
            _        -> 0
    in PDent (PCat (heirFirst runeIndent k) (heirRest runeIndent ks))

-- | Render the first heir element
heirFirst :: Int -> Rex -> PDoc
heirFirst _ k = rexDoc k

-- | Render remaining heir elements with proper indentation
heirRest :: Int -> [Rex] -> PDoc
heirRest _      []     = PEmpty
heirRest indent (k:ks) =
    let padding = pdocText (replicate indent ' ')
    in PCat PLine (PCat padding (PCat (rexDoc k) (heirRest indent ks)))


-- BLOC: Block forms like f =\n  a\n  b ------------------------------------------
--
-- Head + rune stays on one line, then items on subsequent lines indented.

blocDoc :: Color -> String -> Rex -> [Rex] -> PDoc
blocDoc c r hd items =
    let (open, close) = bracketChars c
        headD = rexDoc hd
        runeD = pdocText r
        itemsD = blocItems items
        inner = PCat headD (PCat pdocSpace (PCat runeD itemsD))
    in case c of
        CLEAR -> inner
        _     -> PCat (PChar open) (PCat inner (PChar close))

blocItems :: [Rex] -> PDoc
blocItems []    = PEmpty
blocItems items = PCat PLine (PCat (pdocText "    ") (PDent (blocItemsSep items)))

blocItemsSep :: [Rex] -> PDoc
blocItemsSep []     = PEmpty
blocItemsSep [k]    = rexDoc k
blocItemsSep (k:ks) = PCat (rexDoc k) (PCat PLine (blocItemsSep ks))


-- Helpers -----------------------------------------------------------------------

-- | Render a Rex in a tight context. Complex expressions that would normally
-- span multiple lines get wrapped in parens.
rexDocTight :: Rex -> PDoc
rexDocTight rex = case rex of
    LEAF _ _      -> rexDoc rex
    NEST _ _ _    -> rexDoc rex
    EXPR _ _      -> rexDoc rex
    PREF _ _      -> rexDoc rex
    TYTE _ _      -> rexDoc rex
    JUXT _        -> rexDoc rex
    -- These need parens when used in tight context
    OPEN _ _      -> pdocParens (rexDoc rex)
    HEIR _        -> pdocParens (rexDoc rex)
    BLOC _ _ _ _  -> pdocParens (rexDoc rex)

-- | Check if a Rex is an "open" form (may expand vertically).
isOpenRex :: Rex -> Bool
isOpenRex (OPEN _ _)     = True
isOpenRex (BLOC _ _ _ _) = True
isOpenRex (HEIR _)       = True
isOpenRex _              = False

-- | Check if a Rex contains HEIR (directly or nested).
-- Used to force vertical layout when children have heirs.
containsHeir :: Rex -> Bool
containsHeir (HEIR _)          = True
containsHeir (LEAF _ _)        = False
containsHeir (NEST _ _ kids)   = any containsHeir kids
containsHeir (EXPR _ kids)     = any containsHeir kids
containsHeir (PREF _ child)    = containsHeir child
containsHeir (TYTE _ kids)     = any containsHeir kids
containsHeir (JUXT kids)       = any containsHeir kids
containsHeir (OPEN _ kids)     = any containsHeir kids
containsHeir (BLOC _ _ hd its) = containsHeir hd || any containsHeir its

bracketChars :: Color -> (Char, Char)
bracketChars PAREN = ('(', ')')
bracketChars BRACK = ('[', ']')
bracketChars CURLY = ('{', '}')
bracketChars CLEAR = (' ', ' ')  -- unused; CLEAR is handled above


-- Main --------------------------------------------------------------------------

-- | Read Rex source from stdin, parse to Rex, and pretty-print using
-- the PDoc layout engine. Each top-level input is separated by a blank line.
prettyRexMain :: IO ()
prettyRexMain = do
    src <- getContents
    let results = parseRex src
    mapM_ (\(slice, tree) ->
        case rexFromBlockTree slice tree of
            Nothing  -> pure ()
            Just rex -> do
                putStrLn (printRex 80 rex)
                putStrLn ""
        ) results
