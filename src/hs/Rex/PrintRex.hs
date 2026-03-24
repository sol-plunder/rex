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
    , printRexColor
    , rexDoc
    , prettyRexMain
    , ColorScheme(..)
    ) where

import Rex.Rex
import Rex.PDoc
import Rex.Tree2 (parseRex)
import System.IO (hIsTerminalDevice, stdout)


-- Color Scheme ----------------------------------------------------------------

data ColorScheme = NoColors | BoldColors
  deriving (Eq, Show)

-- | Render a Rex to a String, fitting within the given page width.
printRex :: Int -> Rex -> String
printRex width = render width . rexDoc NoColors

-- | Render a Rex with colors.
printRexColor :: ColorScheme -> Int -> Rex -> String
printRexColor colors width = render width . rexDoc colors


-- ANSI Color Helpers ----------------------------------------------------------

-- | Create a PText with ANSI coloring. Width counts only the visible text,
-- not the escape sequences.
colorText :: ColorScheme -> String -> String -> PDoc
colorText NoColors   _    s = pdocText s
colorText BoldColors code s = PText (length s) (esc code ++ s ++ esc "0")
  where esc c = "\x1b[" ++ c ++ "m"

-- | Color a rune (yellow, bold for light runes)
cRune :: ColorScheme -> String -> PDoc
cRune NoColors   r = pdocText r
cRune BoldColors r
    | isLightRune r = colorText BoldColors "33;1" r  -- bold yellow
    | otherwise     = colorText BoldColors "33" r    -- yellow
  where
    isLightRune "-" = True
    isLightRune "`" = True
    isLightRune "." = True
    isLightRune _   = False

-- | Color a bracket (bold magenta)
cBracket :: ColorScheme -> Char -> PDoc
cBracket NoColors   c = PChar c
cBracket BoldColors c = PText 1 ("\x1b[35;1m" ++ [c] ++ "\x1b[0m")

-- | Color string content (green)
cString :: ColorScheme -> String -> PDoc
cString NoColors   s = pdocText s
cString BoldColors s = colorText BoldColors "32" s

-- | Color a single string char (green)
cStringChar :: ColorScheme -> Char -> PDoc
cStringChar NoColors   c = PChar c
cStringChar BoldColors c = PText 1 ("\x1b[32m" ++ [c] ++ "\x1b[0m")


-- Top-level Rex Dispatch -------------------------------------------------------

rexDoc :: ColorScheme -> Rex -> PDoc
rexDoc cs = \case
    LEAF sh s     -> leafDoc cs sh s
    NEST c r kids -> nestDoc cs c r kids
    EXPR c kids   -> exprDoc cs c kids
    PREF r child  -> prefDoc cs r child
    TYTE r kids   -> tyteDoc cs r kids
    JUXT kids     -> juxtDoc cs kids
    OPEN r kids   -> openDoc cs r kids
    HEIR kids     -> heirDoc cs kids
    BLOC c r hd items -> blocDoc cs c r hd items

-- | Render a Rex in a flat-only context. For NESTs and EXPRs, this renders
-- only the flat form without offering a vertical alternative. This ensures
-- that when we're inside a flat form, nested structures don't unexpectedly
-- go vertical (which would cause the outer flat form to span multiple lines).
--
-- For inherently vertical constructs (OPEN, HEIR, BLOC), we wrap them in
-- pdocNoFit which signals to PChoice that this branch doesn't fit.
rexDocFlat :: ColorScheme -> Rex -> PDoc
rexDocFlat cs = \case
    LEAF sh s     -> leafDoc cs sh s
    NEST c r kids -> nestDocFlat cs c r kids
    EXPR c kids   -> exprDocFlat cs c kids
    PREF r child  -> PCat (cRune cs r) (rexDocFlat cs child)
    TYTE r kids   -> pdocIntersperseFun (\x y -> PCat x (PCat (cRune cs r) y)) (map (rexDocFlat cs) kids)
    JUXT kids     -> foldr (PCat . rexDocFlat cs) PEmpty kids
    -- These are inherently vertical; mark as "no fit" to force vertical layout
    OPEN r kids   -> pdocNoFit (openDoc cs r kids)
    HEIR kids     -> pdocNoFit (heirDoc cs kids)
    BLOC c r hd items -> pdocNoFit (blocDoc cs c r hd items)


-- LEAF: Atomic tokens -------------------------------------------------------------
--
-- Single-line leaves are printed directly. Multi-line leaves need special
-- handling to re-add appropriate prefixes/indentation.

leafDoc :: ColorScheme -> LeafShape -> String -> PDoc
leafDoc cs PAGE s = formatPageMulti cs (lines s)  -- PAGE always uses block form
leafDoc cs shape s
    | '\n' `notElem` s = formatLeafSingle cs shape s
    | otherwise        = formatLeafMulti cs shape s

-- | Format a single-line leaf with appropriate quoting
formatLeafSingle :: ColorScheme -> LeafShape -> String -> PDoc
formatLeafSingle _  WORD s = pdocText s
formatLeafSingle _  QUIP s = pdocText s  -- quips already have their quote
formatLeafSingle cs TRAD s = PCat (cStringChar cs '"') (PCat (cString cs (escapeQuotes s)) (cStringChar cs '"'))
formatLeafSingle _  PAGE _ = error "PAGE should use formatPageMulti"
formatLeafSingle cs SPAN s = PCat (cString cs "'''") (PCat (cString cs s) (cString cs "'''"))
formatLeafSingle cs SLUG s = PCat (cString cs "' ") (cString cs s)
formatLeafSingle _  BAD  s = pdocText s  -- print BAD tokens as-is

-- | Escape quotes for TRAD strings: " becomes ""
escapeQuotes :: String -> String
escapeQuotes [] = []
escapeQuotes ('"':rest) = '"' : '"' : escapeQuotes rest
escapeQuotes (c:rest) = c : escapeQuotes rest

-- | Format a multi-line leaf as a PDoc
formatLeafMulti :: ColorScheme -> LeafShape -> String -> PDoc
formatLeafMulti cs SLUG s = formatSlugMulti cs (lines s)
formatLeafMulti cs TRAD s = formatTradMulti cs (lines s)
formatLeafMulti cs PAGE s = formatPageMulti cs (lines s)
formatLeafMulti cs SPAN s = formatSpanMulti cs (lines s)
formatLeafMulti _  WORD s = pdocText s  -- shouldn't have newlines, but handle anyway
formatLeafMulti _  QUIP s = pdocText s  -- shouldn't have newlines
formatLeafMulti _  BAD  s = pdocText s  -- print BAD tokens as-is

-- | Format multi-line SLUG: each line prefixed with "' "
-- Uses PDent to capture the column for alignment
formatSlugMulti :: ColorScheme -> [String] -> PDoc
formatSlugMulti _  [] = PEmpty
formatSlugMulti cs (l:ls) =
    PDent (PCat (cString cs ("' " ++ l)) (slugRest ls))
  where
    slugRest [] = PEmpty
    slugRest (x:xs) = PCat PLine (PCat (cString cs ("' " ++ x)) (slugRest xs))

-- | Format multi-line TRAD: quoted, continuation lines indented
-- Uses PDent after the opening quote to align continuations
formatTradMulti :: ColorScheme -> [String] -> PDoc
formatTradMulti cs [] = cString cs "\"\""
formatTradMulti cs (l:ls) =
    PCat (cStringChar cs '"') (PDent (PCat (cString cs (escapeQuotes l)) (PCat (tradRest ls) (cStringChar cs '"'))))
  where
    tradRest [] = PEmpty
    tradRest (x:xs) = PCat PLine (PCat (cString cs (escapeQuotes x)) (tradRest xs))

-- | Format multi-line PAGE: block form with ''' delimiters
-- Opening and closing ''' must be at the same column
-- Blank lines are emitted without indentation
formatPageMulti :: ColorScheme -> [String] -> PDoc
formatPageMulti cs ls =
    PDent (PCat (cString cs "'''") (PCat PLine (PCat (pageContent ls) (PCat PLine (cString cs "'''")))))
  where
    pageContent [] = PEmpty
    pageContent [x] = cString cs x
    pageContent (x:xs) = PCat (cString cs x) (PCat (pageLine (head' xs)) (pageContent xs))

    -- Use raw newline for blank lines to avoid indentation
    pageLine "" = PText 1 "\n"
    pageLine _  = PLine

    head' [] = ""
    head' (h:_) = h

-- | Format multi-line SPAN: inline form with ''' delimiters
-- PDent is set after ''' so continuation lines align to the content column.
-- This matches the lexer requirement that continuations be indented past the
-- opening ''' position.
formatSpanMulti :: ColorScheme -> [String] -> PDoc
formatSpanMulti cs [] = cString cs "''''''"
formatSpanMulti cs (l:ls) =
    PCat (cString cs "'''") (PDent (PCat (cString cs l) (PCat (spanRest ls) (cString cs "'''"))))
  where
    spanRest [] = PEmpty
    spanRest (x:xs) = PCat PLine (PCat (cString cs x) (spanRest xs))


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

nestDoc :: ColorScheme -> Color -> String -> [Rex] -> PDoc
nestDoc cs c r kids =
    let (open, close) = bracketChars c
    in case c of
        CLEAR -> PDent (nestContentClear cs r kids)  -- CLEAR uses flat separators with normal rexDoc
        _     -> case kids of
            []  -> PCat (cBracket cs open) (cBracket cs close)
            [k] -> -- Single element with trailing rune: (x +)
                   let flat = PCat (cBracket cs open) (PCat (rexDocFlat cs k) (PCat pdocSpace (PCat (cRune cs r) (cBracket cs close))))
                       vert = PDent (PCat (cBracket cs open) (PCat (PChar ' ') (PCat (rexDoc cs k) (PCat pdocSpace (PCat (cRune cs r) (PCat PLine (cBracket cs close)))))))
                   in PChoice flat vert
            _   -> -- Multiple elements
                   let flat = PCat (cBracket cs open) (PCat (nestContentFlat cs r kids) (cBracket cs close))
                       vert = PDent (PCat (cBracket cs open) (PCat (PChar ' ') (PCat (nestContentOutlined cs r kids) (PCat PLine (cBracket cs close)))))
                   in PChoice flat vert

-- | Flat-only version of nestDoc (no PChoice, just flat form)
nestDocFlat :: ColorScheme -> Color -> String -> [Rex] -> PDoc
nestDocFlat cs c r kids =
    let (open, close) = bracketChars c
    in case c of
        CLEAR -> nestContentFlat cs r kids
        _     -> case kids of
            []  -> PCat (cBracket cs open) (cBracket cs close)
            [k] -> PCat (cBracket cs open) (PCat (rexDocFlat cs k) (PCat pdocSpace (PCat (cRune cs r) (cBracket cs close))))
            _   -> PCat (cBracket cs open) (PCat (nestContentFlat cs r kids) (cBracket cs close))

-- | Content for CLEAR nests: separators but no brackets, uses rexDoc
nestContentClear :: ColorScheme -> String -> [Rex] -> PDoc
nestContentClear _  _ []     = PEmpty
nestContentClear cs _ [k]    = rexDoc cs k
nestContentClear cs r (k:ks) = PCat (rexDoc cs k) (PCat (PCat pdocSpace (PCat (cRune cs r) pdocSpace)) (nestContentClear cs r ks))

-- | Flat layout: children separated by " rune " (uses rexDocFlat for children)
nestContentFlat :: ColorScheme -> String -> [Rex] -> PDoc
nestContentFlat _  _ []     = PEmpty
nestContentFlat cs _ [k]    = rexDocFlat cs k
nestContentFlat cs r (k:ks) = PCat (rexDocFlat cs k) (PCat (PCat pdocSpace (PCat (cRune cs r) pdocSpace)) (nestContentFlat cs r ks))

-- | Outlined vertical layout: first child inline, rest on new lines with rune prefix
nestContentOutlined :: ColorScheme -> String -> [Rex] -> PDoc
nestContentOutlined _  _ []     = PEmpty
nestContentOutlined cs _ [k]    = rexDoc cs k
nestContentOutlined cs r (k:ks) = PCat (rexDoc cs k) (nestRestOutlined cs r ks)

-- | Rest of outlined layout: each child on new line prefixed with rune
nestRestOutlined :: ColorScheme -> String -> [Rex] -> PDoc
nestRestOutlined _  _ []     = PEmpty
nestRestOutlined cs r (k:ks) = PCat PLine (PCat (cRune cs r) (PCat (PChar ' ') (PCat (rexDoc cs k) (nestRestOutlined cs r ks))))


-- EXPR: Application forms like (f x), [a, b], {} --------------------------------
--
-- Children are space-separated and enclosed in brackets.
-- Uses PChoice to try flat vs vertical layout.

exprDoc :: ColorScheme -> Color -> [Rex] -> PDoc
exprDoc cs c kids =
    let (open, close) = bracketChars c
        content = case kids of
            [] -> PEmpty
            _  -> PDent (pdocIntersperseFun pdocSpaceOrLine (map (rexDoc cs) kids))
    in case c of
        CLEAR -> content
        _     -> PCat (cBracket cs open) (PCat content (cBracket cs close))

-- | Flat-only version of exprDoc (uses rexDocFlat for children)
exprDocFlat :: ColorScheme -> Color -> [Rex] -> PDoc
exprDocFlat cs c kids =
    let (open, close) = bracketChars c
        content = pdocIntersperse pdocSpace (map (rexDocFlat cs) kids)
    in case c of
        CLEAR -> content
        _     -> PCat (cBracket cs open) (PCat content (cBracket cs close))


-- PREF: Tight prefix like -x, :y ------------------------------------------------
--
-- Rune concatenated directly with child (no space).

prefDoc :: ColorScheme -> String -> Rex -> PDoc
prefDoc cs r child = PCat (cRune cs r) (rexDocTight cs child)


-- TYTE: Tight infix like x.y, a:b:c ---------------------------------------------
--
-- Children concatenated with rune separator (no spaces).

tyteDoc :: ColorScheme -> String -> [Rex] -> PDoc
tyteDoc cs r kids =
    pdocIntersperseFun (\x y -> PCat x (PCat (cRune cs r) y)) (map (rexDocTight cs) kids)


-- JUXT: Tight juxtaposition like f(x), f(x)[1] ----------------------------------
--
-- Children concatenated directly (no spaces). Complex children get wrapped
-- in parens.

juxtDoc :: ColorScheme -> [Rex] -> PDoc
juxtDoc cs = foldr (PCat . rexDocTight cs) PEmpty


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

openDoc :: ColorScheme -> String -> [Rex] -> PDoc
openDoc cs r kids =
    let runeD = cRune cs r
        flat = PCat runeD (PCat pdocSpace (openChildrenFlat cs kids))
        vertical = PCat runeD (PCat pdocSpace (PDent (openChildrenVertical cs kids)))
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

openChildrenFlat :: ColorScheme -> [Rex] -> PDoc
openChildrenFlat cs = pdocIntersperse pdocSpace . map (rexDoc cs)

openChildrenVertical :: ColorScheme -> [Rex] -> PDoc
openChildrenVertical _  []     = PEmpty
openChildrenVertical cs [k]    = rexDoc cs k
openChildrenVertical cs (k:ks)
    | isOpenRex k = pdocBackstep (rexDoc cs k) (openRestAfterOpen cs ks)
    | otherwise   = PCat (rexDoc cs k) (PCat PLine (openChildrenVertical cs ks))

-- After an open sibling, every following child needs PLine before it.
openRestAfterOpen :: ColorScheme -> [Rex] -> PDoc
openRestAfterOpen _  []     = PEmpty
openRestAfterOpen cs [k]    = PCat PLine (rexDoc cs k)
openRestAfterOpen cs (k:ks)
    | isOpenRex k = pdocBackstep (rexDoc cs k) (openRestAfterOpen cs ks)
    | otherwise   = PCat PLine (PCat (rexDoc cs k) (openRestAfterOpen cs ks))


-- HEIR: Vertical siblings at same column ----------------------------------------
--
-- Each element appears aligned by the last character of their runes.
-- E.g., ":= x/y" followed by "| if ..." has "|" aligned with "=" (column 2).
-- But ":| a" followed by ":| b" has both starting at column 1.

heirDoc :: ColorScheme -> [Rex] -> PDoc
heirDoc _  []     = PEmpty
heirDoc cs [k]    = rexDoc cs k
heirDoc cs (k:ks) =
    let firstRuneLen = case k of
            OPEN r _ -> length r
            _        -> 1
    in PDent (PCat (rexDoc cs k) (heirRest cs firstRuneLen ks))

-- | Render remaining heir elements with alignment based on first rune
heirRest :: ColorScheme -> Int -> [Rex] -> PDoc
heirRest _  _            []     = PEmpty
heirRest cs firstRuneLen (k:ks) =
    let currentRuneLen = case k of
            OPEN r _ -> length r
            _        -> 1
        padding = max 0 (firstRuneLen - currentRuneLen)
        pad = if padding > 0 then pdocText (replicate padding ' ') else PEmpty
    in PCat PLine (PCat pad (PCat (rexDoc cs k) (heirRest cs firstRuneLen ks)))


-- BLOC: Block forms like f =\n  a\n  b ------------------------------------------
--
-- Head + rune stays on one line, then items on subsequent lines indented.

blocDoc :: ColorScheme -> Color -> String -> Rex -> [Rex] -> PDoc
blocDoc cs c r hd items =
    let (open, close) = bracketChars c
        headD = rexDoc cs hd
        runeD = cRune cs r
        itemsD = blocItems cs items
        inner = PCat headD (PCat pdocSpace (PCat runeD itemsD))
    in case c of
        CLEAR -> inner
        _     -> PCat (cBracket cs open) (PCat inner (cBracket cs close))

blocItems :: ColorScheme -> [Rex] -> PDoc
blocItems _  []    = PEmpty
blocItems cs items = PCat PLine (PCat (pdocText "    ") (PDent (blocItemsSep cs items)))

blocItemsSep :: ColorScheme -> [Rex] -> PDoc
blocItemsSep _  []     = PEmpty
blocItemsSep cs [k]    = rexDoc cs k
blocItemsSep cs (k:ks) = PCat (rexDoc cs k) (PCat PLine (blocItemsSep cs ks))


-- Helpers -----------------------------------------------------------------------

-- | Render a Rex in a tight context. Complex expressions that would normally
-- span multiple lines get wrapped in parens.
rexDocTight :: ColorScheme -> Rex -> PDoc
rexDocTight cs rex = case rex of
    LEAF _ _      -> rexDoc cs rex
    NEST _ _ _    -> rexDoc cs rex
    EXPR _ _      -> rexDoc cs rex
    PREF _ _      -> rexDoc cs rex
    TYTE _ _      -> rexDoc cs rex
    JUXT _        -> rexDoc cs rex
    -- These need parens when used in tight context
    OPEN _ _      -> pdocParensC cs (rexDoc cs rex)
    HEIR _        -> pdocParensC cs (rexDoc cs rex)
    BLOC _ _ _ _  -> pdocParensC cs (rexDoc cs rex)

-- | Wrap in colored parens
pdocParensC :: ColorScheme -> PDoc -> PDoc
pdocParensC cs d = PCat (cBracket cs '(') (PCat d (cBracket cs ')'))

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
-- Uses colors when stdout is a terminal.
prettyRexMain :: IO ()
prettyRexMain = do
    isTty <- hIsTerminalDevice stdout
    let colors = if isTty then BoldColors else NoColors
    src <- getContents
    let results = parseRex src
    mapM_ (\(slice, tree) ->
        case rexFromBlockTree slice tree of
            Nothing  -> pure ()
            Just rex -> do
                putStrLn (printRexColor colors 80 rex)
                putStrLn ""
        ) results
