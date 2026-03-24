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

-- | Render a Rex in a flat-only context. For NESTs and EXPRs, this renders
-- only the flat form without offering a vertical alternative. This ensures
-- that when we're inside a flat form, nested structures don't unexpectedly
-- go vertical (which would cause the outer flat form to span multiple lines).
--
-- For inherently vertical constructs (OPEN, HEIR, BLOC), we wrap them in
-- pdocNoFit which signals to PChoice that this branch doesn't fit.
rexDocFlat :: Rex -> PDoc
rexDocFlat = \case
    LEAF sh s     -> leafDoc sh s
    NEST c r kids -> nestDocFlat c r kids
    EXPR c kids   -> exprDocFlat c kids
    PREF r child  -> PCat (pdocText r) (rexDocFlat child)
    TYTE r kids   -> pdocIntersperseFun (\x y -> PCat x (PCat (pdocText r) y)) (map rexDocFlat kids)
    JUXT kids     -> foldr (PCat . rexDocFlat) PEmpty kids
    -- These are inherently vertical; mark as "no fit" to force vertical layout
    OPEN r kids   -> pdocNoFit (openDoc r kids)
    HEIR kids     -> pdocNoFit (heirDoc kids)
    BLOC c r hd items -> pdocNoFit (blocDoc c r hd items)


-- LEAF: Atomic tokens -------------------------------------------------------------
--
-- Single-line leaves are printed directly. Multi-line leaves need special
-- handling to re-add appropriate prefixes/indentation.

leafDoc :: LeafShape -> String -> PDoc
leafDoc PAGE s = formatPageMulti (lines s)  -- PAGE always uses block form
leafDoc shape s
    | '\n' `notElem` s = pdocText (formatLeafSingle shape s)
    | otherwise        = formatLeafMulti shape s

-- | Format a single-line leaf with appropriate quoting
formatLeafSingle :: LeafShape -> String -> String
formatLeafSingle WORD s = s
formatLeafSingle QUIP s = s  -- quips already have their quote
formatLeafSingle TRAD s = "\"" ++ escapeQuotes s ++ "\""
formatLeafSingle PAGE _ = error "PAGE should use formatPageMulti"
formatLeafSingle SPAN s = "'''" ++ s ++ "'''"
formatLeafSingle SLUG s = "' " ++ s
formatLeafSingle BAD  s = s  -- print BAD tokens as-is

-- | Escape quotes for TRAD strings: " becomes ""
escapeQuotes :: String -> String
escapeQuotes [] = []
escapeQuotes ('"':rest) = '"' : '"' : escapeQuotes rest
escapeQuotes (c:rest) = c : escapeQuotes rest

-- | Format a multi-line leaf as a PDoc
formatLeafMulti :: LeafShape -> String -> PDoc
formatLeafMulti SLUG s = formatSlugMulti (lines s)
formatLeafMulti TRAD s = formatTradMulti (lines s)
formatLeafMulti PAGE s = formatPageMulti (lines s)
formatLeafMulti SPAN s = formatSpanMulti (lines s)
formatLeafMulti WORD s = pdocText s  -- shouldn't have newlines, but handle anyway
formatLeafMulti QUIP s = pdocText s  -- shouldn't have newlines
formatLeafMulti BAD  s = pdocText s  -- print BAD tokens as-is

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

-- | Format multi-line PAGE: block form with ''' delimiters
-- Opening and closing ''' must be at the same column
-- Blank lines are emitted without indentation
formatPageMulti :: [String] -> PDoc
formatPageMulti ls =
    PDent (PCat (pdocText "'''") (PCat PLine (PCat (pageContent ls) (PCat PLine (pdocText "'''")))))
  where
    pageContent [] = PEmpty
    pageContent [x] = pdocText x
    pageContent (x:xs) = PCat (pdocText x) (PCat (pageLine (head' xs)) (pageContent xs))

    -- Use raw newline for blank lines to avoid indentation
    pageLine "" = PText 1 "\n"
    pageLine _  = PLine

    head' [] = ""
    head' (h:_) = h

-- | Format multi-line SPAN: inline form with ''' delimiters
-- PDent is set after ''' so continuation lines align to the content column.
-- This matches the lexer requirement that continuations be indented past the
-- opening ''' position.
formatSpanMulti :: [String] -> PDoc
formatSpanMulti [] = pdocText "''''''"
formatSpanMulti (l:ls) =
    PCat (pdocText "'''") (PDent (PCat (pdocText l) (PCat (spanRest ls) (pdocText "'''"))))
  where
    spanRest [] = PEmpty
    spanRest (x:xs) = PCat PLine (PCat (pdocText x) (spanRest xs))


-- NEST: Infix bracket forms like (a + b), {a | b} --------------------------------
--
-- Children are separated by " rune " and enclosed in brackets.
--
-- Layout options:
--   Flat:     (a + b + c)
--   Outlined: ( a
--            , b
--            , c
--            )
--
-- The outlined form puts the closing bracket on its own line, aligned with
-- the opening bracket. This is the preferred vertical layout for bracketed
-- forms.

nestDoc :: Color -> String -> [Rex] -> PDoc
nestDoc c r kids =
    let (open, close) = bracketChars c
    in case c of
        CLEAR -> PDent (nestContentClear r kids)  -- CLEAR uses flat separators with normal rexDoc
        _     -> case kids of
            []  -> PCat (PChar open) (PChar close)
            [k] -> -- Single element with trailing rune: (x +)
                   let flat = PCat (PChar open) (PCat (rexDocFlat k) (PCat pdocSpace (PCat (pdocText r) (PChar close))))
                       vert = PDent (PCat (PChar open) (PCat (PChar ' ') (PCat (rexDoc k) (PCat pdocSpace (PCat (pdocText r) (PCat PLine (PChar close)))))))
                   in PChoice flat vert
            _   -> -- Multiple elements
                   let flat = PCat (PChar open) (PCat (nestContentFlat r kids) (PChar close))
                       vert = PDent (PCat (PChar open) (PCat (PChar ' ') (PCat (nestContentOutlined r kids) (PCat PLine (PChar close)))))
                   in PChoice flat vert

-- | Flat-only version of nestDoc (no PChoice, just flat form)
nestDocFlat :: Color -> String -> [Rex] -> PDoc
nestDocFlat c r kids =
    let (open, close) = bracketChars c
    in case c of
        CLEAR -> nestContentFlat r kids
        _     -> case kids of
            []  -> PCat (PChar open) (PChar close)
            [k] -> PCat (PChar open) (PCat (rexDocFlat k) (PCat pdocSpace (PCat (pdocText r) (PChar close))))
            _   -> PCat (PChar open) (PCat (nestContentFlat r kids) (PChar close))

-- | Content for CLEAR nests: separators but no brackets, uses rexDoc
nestContentClear :: String -> [Rex] -> PDoc
nestContentClear _ []     = PEmpty
nestContentClear _ [k]    = rexDoc k
nestContentClear r (k:ks) = PCat (rexDoc k) (PCat (pdocText (" " ++ r ++ " ")) (nestContentClear r ks))

-- | Flat layout: children separated by " rune " (uses rexDocFlat for children)
nestContentFlat :: String -> [Rex] -> PDoc
nestContentFlat _ []     = PEmpty
nestContentFlat _ [k]    = rexDocFlat k
nestContentFlat r (k:ks) = PCat (rexDocFlat k) (PCat (pdocText (" " ++ r ++ " ")) (nestContentFlat r ks))

-- | Outlined vertical layout: first child inline, rest on new lines with rune prefix
nestContentOutlined :: String -> [Rex] -> PDoc
nestContentOutlined _ []     = PEmpty
nestContentOutlined _ [k]    = rexDoc k
nestContentOutlined r (k:ks) = PCat (rexDoc k) (nestRestOutlined r ks)

-- | Rest of outlined layout: each child on new line prefixed with rune
nestRestOutlined :: String -> [Rex] -> PDoc
nestRestOutlined _ []     = PEmpty
nestRestOutlined r (k:ks) = PCat PLine (PCat (pdocText (r ++ " ")) (PCat (rexDoc k) (nestRestOutlined r ks)))


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

-- | Flat-only version of exprDoc (uses rexDocFlat for children)
exprDocFlat :: Color -> [Rex] -> PDoc
exprDocFlat c kids =
    let (open, close) = bracketChars c
        content = pdocIntersperse pdocSpace (map rexDocFlat kids)
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
        -- If last child is inherently vertical (HEIR or BLOC), force vertical layout
        hasInherentlyVerticalLast = case kids of
            [] -> False
            _  -> case last kids of
                      HEIR _       -> True
                      BLOC _ _ _ _ -> True
                      _            -> False
    in if hasInherentlyVerticalLast
       then vertical
       else PChoice flat vertical

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
-- Each element appears aligned by the last character of their runes.
-- E.g., ":= x/y" followed by "| if ..." has "|" aligned with "=" (column 2).
-- But ":| a" followed by ":| b" has both starting at column 1.

heirDoc :: [Rex] -> PDoc
heirDoc []     = PEmpty
heirDoc [k]    = rexDoc k
heirDoc (k:ks) =
    let firstRuneLen = case k of
            OPEN r _ -> length r
            _        -> 1
    in PDent (PCat (rexDoc k) (heirRest firstRuneLen ks))

-- | Render remaining heir elements with alignment based on first rune
heirRest :: Int -> [Rex] -> PDoc
heirRest _            []     = PEmpty
heirRest firstRuneLen (k:ks) =
    let currentRuneLen = case k of
            OPEN r _ -> length r
            _        -> 1
        padding = max 0 (firstRuneLen - currentRuneLen)
        pad = if padding > 0 then pdocText (replicate padding ' ') else PEmpty
    in PCat PLine (PCat pad (PCat (rexDoc k) (heirRest firstRuneLen ks)))


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
