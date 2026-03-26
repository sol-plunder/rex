{-# LANGUAGE BangPatterns #-}
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
    , printRexWith
    , rexDoc
    , prettyRexMain
    , ColorScheme(..)
    , PrintConfig(..)
    , defaultConfig
    , debugConfig
    ) where

import Rex.Rex
import Rex.PDoc
import Rex.Tree2 (parseRex)
import System.IO (hIsTerminalDevice, stdout)


-- Configuration ----------------------------------------------------------------

data ColorScheme = NoColors | BoldColors
  deriving (Eq, Show)

data PrintConfig = PrintConfig
    { cfgColors    :: ColorScheme
    , cfgDebug     :: Bool
    , cfgMaxFlow   :: Int     -- ^ max item width for flow layout in poems
    , cfgMaxInline :: Int     -- ^ max width for inlining open children
    }
  deriving (Eq, Show)

-- | Default config: no colors, no debug, flow items up to 30 chars, inline up to 50
defaultConfig :: PrintConfig
defaultConfig = PrintConfig NoColors False 30 50

-- | Debug config: no colors, debug enabled, flow items up to 30 chars, inline up to 50
debugConfig :: PrintConfig
debugConfig = PrintConfig NoColors True 30 50

-- | Render a Rex to a String, fitting within the given page width.
printRex :: Int -> Rex -> String
printRex width = render width . rexDoc defaultConfig

-- | Render a Rex with colors.
printRexColor :: ColorScheme -> Int -> Rex -> String
printRexColor colors width = render width . rexDoc (PrintConfig colors False 30 50)

-- | Render a Rex with full config.
printRexWith :: PrintConfig -> Int -> Rex -> String
printRexWith cfg width = render width . rexDoc cfg


-- ANSI Color Helpers ----------------------------------------------------------

-- | Create a PText with ANSI coloring. Width counts only the visible text,
-- not the escape sequences.
colorText :: ColorScheme -> String -> String -> PDoc
colorText NoColors   _    s = pdocText s
colorText BoldColors code s = PText (length s) (esc code ++ s ++ esc "0")
  where esc c = "\x1b[" ++ c ++ "m"

-- | Color a rune (yellow, bold for light runes)
cRune :: PrintConfig -> String -> PDoc
cRune cfg r = case cfgColors cfg of
    NoColors   -> pdocText r
    BoldColors
        | isLightRune r -> colorText BoldColors "33;1" r  -- bold yellow
        | otherwise     -> colorText BoldColors "33" r    -- yellow
  where
    isLightRune "-" = True
    isLightRune "`" = True
    isLightRune "." = True
    isLightRune _   = False

-- | Color a bracket (bold magenta)
cBracket :: PrintConfig -> Char -> PDoc
cBracket cfg c = case cfgColors cfg of
    NoColors   -> PChar c
    BoldColors -> PText 1 ("\x1b[35;1m" ++ [c] ++ "\x1b[0m")

-- | Color string content (green)
cString :: PrintConfig -> String -> PDoc
cString cfg s = case cfgColors cfg of
    NoColors   -> pdocText s
    BoldColors -> colorText BoldColors "32" s

-- | Color a single string char (green)
cStringChar :: PrintConfig -> Char -> PDoc
cStringChar cfg c = case cfgColors cfg of
    NoColors   -> PChar c
    BoldColors -> PText 1 ("\x1b[32m" ++ [c] ++ "\x1b[0m")

-- | Color a quip (cyan)
cQuip :: PrintConfig -> String -> PDoc
cQuip cfg s = case cfgColors cfg of
    NoColors   -> pdocText s
    BoldColors -> colorText BoldColors "36" s


-- Top-level Rex Dispatch -------------------------------------------------------

rexDoc :: PrintConfig -> Rex -> PDoc
rexDoc cfg = \case
    LEAF _ sh s     -> leafDoc cfg sh s
    NEST _ c r kids -> nestDoc cfg c r kids
    EXPR _ c kids   -> exprDoc cfg c kids
    PREF _ r child  -> prefDoc cfg r child
    TYTE _ r kids   -> tyteDoc cfg r kids
    JUXT _ kids     -> juxtDoc cfg kids
    OPEN _ r kids   -> openDoc cfg r kids
    HEIR _ kids     -> heirDoc cfg kids
    BLOC _ c r hd items -> blocDoc cfg c r hd items

-- | Render a Rex in a flat-only context. For NESTs and EXPRs, this renders
-- only the flat form without offering a vertical alternative. This ensures
-- that when we're inside a flat form, nested structures don't unexpectedly
-- go vertical (which would cause the outer flat form to span multiple lines).
--
-- For inherently vertical constructs (OPEN, HEIR, BLOC), we wrap them in
-- pdocNoFit which signals to PChoice that this branch doesn't fit.
rexDocFlat :: PrintConfig -> Rex -> PDoc
rexDocFlat cfg = \case
    LEAF _ sh s     -> leafDoc cfg sh s
    NEST _ c r kids -> nestDocFlat cfg c r kids
    EXPR _ c kids   -> exprDocFlat cfg c kids
    PREF _ r child  -> if cfgDebug cfg
                        then PCat (pdocText "‹") (PCat (cRune cfg r) (PCat (rexDocFlat cfg child) (pdocText "›")))
                        else PCat (cRune cfg r) (rexDocFlat cfg child)
    TYTE _ r kids   -> pdocIntersperseFun (\x y -> PCat x (PCat (cRune cfg r) y)) (map (rexDocFlat cfg) kids)
    JUXT _ kids     -> foldr (PCat . rexDocFlat cfg) PEmpty kids
    -- These are inherently vertical; mark as "no fit" to force vertical layout
    OPEN _ r kids   -> pdocNoFit (openDoc cfg r kids)
    HEIR _ kids     -> pdocNoFit (heirDoc cfg kids)
    BLOC _ c r hd items -> pdocNoFit (blocDoc cfg c r hd items)


-- LEAF: Atomic tokens -------------------------------------------------------------
--
-- Single-line leaves are printed directly. Multi-line leaves need special
-- handling to re-add appropriate prefixes/indentation.
--
-- In debug mode, all string types (CORD, TAPE, SPAN, PAGE) are rendered as
-- slugs to make the extracted content completely unambiguous.

leafDoc :: PrintConfig -> LeafShape -> String -> PDoc
leafDoc cfg shape s
    -- In debug mode, all strings become slugs
    | cfgDebug cfg = case shape of
        WORD    -> pdocText s
        QUIP    -> cQuip cfg s  -- quips in cyan
        SLUG    -> pdocNoFit (formatSlugMulti cfg (lines s))
        BAD _   -> pdocText s
        -- CORD, TAPE, SPAN, PAGE all become slugs in debug mode
        _       -> pdocNoFit (formatSlugMulti cfg (lines s))
    -- Normal mode
    | otherwise = case shape of
        PAGE -> formatPageMulti cfg (lines s)  -- PAGE always uses block form
        TAPE -> formatTapeMulti cfg (lines s)  -- TAPE always uses block form
        -- SLUG never fits inline, always ends with newline
        SLUG | '\n' `elem` s -> pdocNoFit (formatSlugMulti cfg (lines s))
             | otherwise     -> pdocNoFit (formatSlugSingle cfg s)
        _    | '\n' `notElem` s -> formatLeafSingle cfg shape s
             | otherwise        -> formatLeafMulti cfg shape s

-- | Format a single-line leaf with appropriate quoting
formatLeafSingle :: PrintConfig -> LeafShape -> String -> PDoc
formatLeafSingle _   WORD s = pdocText s
formatLeafSingle cfg QUIP s = cQuip cfg s  -- quips in cyan
formatLeafSingle cfg CORD s = PCat (cStringChar cfg '"') (PCat (cString cfg (escapeQuotes s)) (cStringChar cfg '"'))
formatLeafSingle _   TAPE _ = error "TAPE should use formatTapeMulti"
formatLeafSingle _   PAGE _ = error "PAGE should use formatPageMulti"
formatLeafSingle cfg SPAN s = PCat (cString cfg "'''") (PCat (cString cfg s) (cString cfg "'''"))
formatLeafSingle cfg SLUG s = PCat (cString cfg "' ") (cString cfg s)
formatLeafSingle _   (BAD _) s = pdocText s  -- print BAD tokens as-is

-- | Escape quotes for TRAD strings: " becomes ""
escapeQuotes :: String -> String
escapeQuotes [] = []
escapeQuotes ('"':rest) = '"' : '"' : escapeQuotes rest
escapeQuotes (c:rest) = c : escapeQuotes rest

-- | Format a multi-line leaf as a PDoc
formatLeafMulti :: PrintConfig -> LeafShape -> String -> PDoc
formatLeafMulti cfg SLUG s = formatSlugMulti cfg (lines s)
formatLeafMulti cfg CORD s = formatCordMulti cfg (lines s)
formatLeafMulti cfg TAPE s = formatTapeMulti cfg (lines s)
formatLeafMulti cfg PAGE s = formatPageMulti cfg (lines s)
formatLeafMulti cfg SPAN s = formatSpanMulti cfg (lines s)
formatLeafMulti _   WORD s = pdocText s  -- shouldn't have newlines, but handle anyway
formatLeafMulti cfg QUIP s = formatQuipMulti cfg (lines s)
formatLeafMulti _   (BAD _) s = pdocText s  -- print BAD tokens as-is

-- | Format multi-line QUIP: first line as-is, continuation lines aligned to '
-- Uses PDent to capture the column of ' for alignment
-- Blank lines are emitted without indentation
formatQuipMulti :: PrintConfig -> [String] -> PDoc
formatQuipMulti _   [] = PEmpty
formatQuipMulti cfg (l:ls) =
    PDent (PCat (cQuip cfg l) (quipRest ls))
  where
    quipRest [] = PEmpty
    quipRest (x:xs) = PCat (quipLine x) (PCat (cQuip cfg x) (quipRest xs))

    -- Use raw newline for blank lines to avoid indentation
    quipLine "" = PText 1 "\n"
    quipLine _  = PLine

-- | Format single-line SLUG: "' " prefix
-- Slugs never fit inline, so this is wrapped in pdocNoFit at the call site
formatSlugSingle :: PrintConfig -> String -> PDoc
formatSlugSingle cfg s = PCat (cString cfg "' ") (cString cfg s)

-- | Format multi-line SLUG: each line prefixed with "' "
-- Uses PDent to capture the column for alignment
formatSlugMulti :: PrintConfig -> [String] -> PDoc
formatSlugMulti _   [] = PEmpty
formatSlugMulti cfg (l:ls) =
    PDent (PCat (cString cfg ("' " ++ l)) (slugRest ls))
  where
    slugRest [] = PEmpty
    slugRest (x:xs) = PCat PLine (PCat (cString cfg ("' " ++ x)) (slugRest xs))

-- | Format multi-line CORD: quoted, continuation lines indented (span-style)
-- Uses PDent after the opening quote to align continuations
formatCordMulti :: PrintConfig -> [String] -> PDoc
formatCordMulti cfg [] = cString cfg "\"\""
formatCordMulti cfg (l:ls) =
    PCat (cStringChar cfg '"') (PDent (PCat (cString cfg (escapeQuotes l)) (PCat (cordRest ls) (cStringChar cfg '"'))))
  where
    cordRest [] = PEmpty
    cordRest (x:xs) = PCat PLine (PCat (cString cfg (escapeQuotes x)) (cordRest xs))

-- | Format multi-line TAPE: block form with " delimiters (page-style)
-- Opening and closing " must be at the same column
-- Blank lines are emitted without indentation
formatTapeMulti :: PrintConfig -> [String] -> PDoc
formatTapeMulti cfg ls =
    PDent (PCat (cStringChar cfg '"') (PCat PLine (PCat (tapeContent ls) (PCat PLine (cStringChar cfg '"')))))
  where
    tapeContent [] = PEmpty
    tapeContent [x] = cString cfg (escapeQuotes x)
    tapeContent (x:xs) = PCat (cString cfg (escapeQuotes x)) (PCat (tapeLine (head' xs)) (tapeContent xs))

    -- Use raw newline for blank lines to avoid indentation
    tapeLine "" = PText 1 "\n"
    tapeLine _  = PLine

    head' [] = ""
    head' (h:_) = h

-- | Format multi-line PAGE: block form with ''' delimiters
-- Opening and closing ''' must be at the same column
-- Blank lines are emitted without indentation
formatPageMulti :: PrintConfig -> [String] -> PDoc
formatPageMulti cfg ls =
    PDent (PCat (cString cfg "'''") (PCat PLine (PCat (pageContent ls) (PCat PLine (cString cfg "'''")))))
  where
    pageContent [] = PEmpty
    pageContent [x] = cString cfg x
    pageContent (x:xs) = PCat (cString cfg x) (PCat (pageLine (head' xs)) (pageContent xs))

    -- Use raw newline for blank lines to avoid indentation
    pageLine "" = PText 1 "\n"
    pageLine _  = PLine

    head' [] = ""
    head' (h:_) = h

-- | Format multi-line SPAN: inline form with ''' delimiters
-- PDent is set after ''' so continuation lines align to the content column.
-- This matches the lexer requirement that continuations be indented past the
-- opening ''' position.
formatSpanMulti :: PrintConfig -> [String] -> PDoc
formatSpanMulti cfg [] = cString cfg "''''''"
formatSpanMulti cfg (l:ls) =
    PCat (cString cfg "'''") (PDent (PCat (cString cfg l) (PCat (spanRest ls) (cString cfg "'''"))))
  where
    spanRest [] = PEmpty
    spanRest (x:xs) = PCat PLine (PCat (cString cfg x) (spanRest xs))


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

nestDoc :: PrintConfig -> Color -> String -> [Rex] -> PDoc
nestDoc cfg c r kids =
    let (open, close) = bracketChars c
    in case c of
        CLEAR | cfgDebug cfg -> PCat (pdocText "«") (PCat (PDent (nestContentClear cfg r kids)) (pdocText "»"))
              | otherwise    -> PDent (nestContentClear cfg r kids)
        _     -> case kids of
            []  -> PCat (cBracket cfg open) (cBracket cfg close)
            [k] -> -- Single element with trailing rune: (x +)
                   let flat = PCat (cBracket cfg open) (PCat (rexDocFlat cfg k) (PCat pdocSpace (PCat (cRune cfg r) (cBracket cfg close))))
                       vert = PDent (PCat (cBracket cfg open) (PCat (PChar ' ') (PCat (rexDoc cfg k) (PCat pdocSpace (PCat (cRune cfg r) (PCat PLine (cBracket cfg close)))))))
                   in PChoice flat vert
            _   -> -- Multiple elements
                   let flat = PCat (cBracket cfg open) (PCat (nestContentFlat cfg r kids) (cBracket cfg close))
                       vert = PDent (PCat (cBracket cfg open) (PCat (PChar ' ') (PCat (nestContentOutlined cfg r kids) (PCat PLine (cBracket cfg close)))))
                   in PChoice flat vert

-- | Flat-only version of nestDoc (no PChoice, just flat form)
nestDocFlat :: PrintConfig -> Color -> String -> [Rex] -> PDoc
nestDocFlat cfg c r kids =
    let (open, close) = bracketChars c
    in case c of
        CLEAR | cfgDebug cfg -> PCat (pdocText "«") (PCat (nestContentFlat cfg r kids) (pdocText "»"))
              | otherwise    -> nestContentFlat cfg r kids
        _     -> case kids of
            []  -> PCat (cBracket cfg open) (cBracket cfg close)
            [k] -> PCat (cBracket cfg open) (PCat (rexDocFlat cfg k) (PCat pdocSpace (PCat (cRune cfg r) (cBracket cfg close))))
            _   -> PCat (cBracket cfg open) (PCat (nestContentFlat cfg r kids) (cBracket cfg close))

-- | Content for CLEAR nests: separators but no brackets, uses rexDoc
nestContentClear :: PrintConfig -> String -> [Rex] -> PDoc
nestContentClear _   _ []     = PEmpty
nestContentClear cfg _ [k]    = rexDoc cfg k
nestContentClear cfg r (k:ks) = PCat (rexDoc cfg k) (PCat (PCat pdocSpace (PCat (cRune cfg r) pdocSpace)) (nestContentClear cfg r ks))

-- | Flat layout: children separated by " rune " (uses rexDocFlat for children)
nestContentFlat :: PrintConfig -> String -> [Rex] -> PDoc
nestContentFlat _   _ []     = PEmpty
nestContentFlat cfg _ [k]    = rexDocFlat cfg k
nestContentFlat cfg r (k:ks) = PCat (rexDocFlat cfg k) (PCat (PCat pdocSpace (PCat (cRune cfg r) pdocSpace)) (nestContentFlat cfg r ks))

-- | Outlined vertical layout: first child inline, rest on new lines with rune prefix
nestContentOutlined :: PrintConfig -> String -> [Rex] -> PDoc
nestContentOutlined _   _ []     = PEmpty
nestContentOutlined cfg _ [k]    = rexDoc cfg k
nestContentOutlined cfg r (k:ks) = PCat (rexDoc cfg k) (nestRestOutlined cfg r ks)

-- | Rest of outlined layout: each child on new line prefixed with rune
nestRestOutlined :: PrintConfig -> String -> [Rex] -> PDoc
nestRestOutlined _   _ []     = PEmpty
nestRestOutlined cfg r (k:ks) = PCat PLine (PCat (cRune cfg r) (PCat (PChar ' ') (PCat (rexDoc cfg k) (nestRestOutlined cfg r ks))))


-- EXPR: Application forms like (f x), [a, b], {} --------------------------------
--
-- Children are space-separated and enclosed in brackets.
-- Uses PChoice to try flat vs vertical layout.

exprDoc :: PrintConfig -> Color -> [Rex] -> PDoc
exprDoc cfg c kids =
    let (open, close) = bracketChars c
        content = case kids of
            [] -> PEmpty
            _  -> PDent (pdocIntersperseFun pdocSpaceOrLine (map (rexDoc cfg) kids))
    in case c of
        CLEAR | cfgDebug cfg -> PCat (pdocText "«") (PCat content (pdocText "»"))
              | otherwise    -> content
        _     -> PCat (cBracket cfg open) (PCat content (cBracket cfg close))

-- | Flat-only version of exprDoc (uses rexDocFlat for children)
exprDocFlat :: PrintConfig -> Color -> [Rex] -> PDoc
exprDocFlat cfg c kids =
    let (open, close) = bracketChars c
        content = pdocIntersperse pdocSpace (map (rexDocFlat cfg) kids)
    in case c of
        CLEAR | cfgDebug cfg -> PCat (pdocText "«") (PCat content (pdocText "»"))
              | otherwise    -> content
        _     -> PCat (cBracket cfg open) (PCat content (cBracket cfg close))


-- PREF: Tight prefix like -x, :y ------------------------------------------------
--
-- Rune concatenated directly with child (no space).
-- In debug mode, wrap with ‹› markers.

prefDoc :: PrintConfig -> String -> Rex -> PDoc
prefDoc cfg r child
    | cfgDebug cfg = PCat (pdocText "‹") (PCat (cRune cfg r) (PCat (rexDocTight cfg child) (pdocText "›")))
    | otherwise    = PCat (cRune cfg r) (rexDocTight cfg child)


-- TYTE: Tight infix like x.y, a:b:c ---------------------------------------------
--
-- Children concatenated with rune separator (no spaces).
-- In debug mode, wrap with ⟪⟫ markers.

tyteDoc :: PrintConfig -> String -> [Rex] -> PDoc
tyteDoc cfg r kids =
    let inner = pdocIntersperseFun (\x y -> PCat x (PCat (cRune cfg r) y)) (map (rexDocTight cfg) kids)
    in if cfgDebug cfg
       then PCat (pdocText "⟪") (PCat inner (pdocText "⟫"))
       else inner


-- JUXT: Tight juxtaposition like f(x), f(x)[1] ----------------------------------
--
-- Children concatenated directly (no spaces). Complex children get wrapped
-- in parens.
-- In debug mode, wrap with ⟪⟫ markers and separate children with ·.

juxtDoc :: PrintConfig -> [Rex] -> PDoc
juxtDoc cfg kids =
    if cfgDebug cfg
    then let inner = pdocIntersperse (pdocText "·") (map (rexDocTight cfg) kids)
         in PCat (pdocText "⟪") (PCat inner (pdocText "⟫"))
    else foldr (PCat . rexDocTight cfg) PEmpty kids


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

openDoc :: PrintConfig -> String -> [Rex] -> PDoc
openDoc cfg r kids =
    let runeD = cRune cfg r
        flat = PCat runeD (PCat pdocSpace (openChildrenFlat cfg kids))
        vertical = PCat runeD (PCat pdocSpace (PDent (openChildrenVertical cfg kids)))
        -- Force vertical if:
        -- 1. An open child is followed by more children (heir collision), OR
        -- 2. The last child is open and too big to inline nicely
        hasOpenFollowedByMore = hasOpenThenMore kids
        lastChildTooBig = case lastMay kids of
            Just k | forcesVertical k -> rexMinWidth k > cfgMaxInline cfg
            _ -> False
        inner = if hasOpenFollowedByMore || lastChildTooBig
                then vertical
                else PChoice flat vertical
    in if cfgDebug cfg
       then PCat (pdocText "⟨") (PCat inner (pdocText "⟩"))
       else inner

-- | Safe last element
lastMay :: [a] -> Maybe a
lastMay [] = Nothing
lastMay xs = Just (last xs)

openChildrenFlat :: PrintConfig -> [Rex] -> PDoc
openChildrenFlat cfg = pdocIntersperse pdocSpace . map (rexDoc cfg)

-- | Render children in vertical layout, grouping consecutive open children
-- into staircases that don't leak backstep between groups.
openChildrenVertical :: PrintConfig -> [Rex] -> PDoc
openChildrenVertical _   []   = PEmpty
openChildrenVertical cfg [k]  = rexDoc cfg k  -- single child: no staircase, inline
openChildrenVertical cfg kids = renderGroups (groupChildren kids)
  where
    -- Group children into runs of closed and open
    groupChildren :: [Rex] -> [ChildGroup]
    groupChildren [] = []
    groupChildren xs =
        let (closed, rest1) = span (not . isOpenRex) xs
            (open,   rest2) = span isOpenRex rest1
        in case (closed, open) of
            ([], []) -> []
            (cs, []) -> [ClosedGroup cs]
            ([], os) -> OpenGroup os : groupChildren rest2
            (cs, os) -> ClosedGroup cs : OpenGroup os : groupChildren rest2

    -- Render groups. OpenGroup handles its own newlines.
    -- When OpenGroup has following groups, indent staircase to avoid heir collision.
    renderGroups :: [ChildGroup] -> PDoc
    renderGroups []     = PEmpty
    renderGroups [g]    = renderGroup g
    renderGroups (g:gs) = case (g, gs) of
        (_, OpenGroup _ : _) ->
            -- Next is open group, it handles its own newlines
            PCat (renderGroup g) (renderGroups gs)
        (OpenGroup os, _) ->
            -- Open group with more items after: indent the staircase by 2
            -- to leave room for following items at base indent
            let indentedStaircase = pdocStaircase (map (\o -> PCat (pdocText "  ") (rexDoc cfg o)) os)
            in PCat indentedStaircase (PCat PLine (renderGroups gs))
        _ ->
            PCat (renderGroup g) (PCat PLine (renderGroups gs))

    -- Render a single group
    renderGroup :: ChildGroup -> PDoc
    renderGroup (ClosedGroup cs) =
        pdocFlow (cfgMaxFlow cfg) (map (rexDoc cfg) cs)
    renderGroup (OpenGroup os) =
        pdocStaircase (map (rexDoc cfg) os)

-- | Classification of children for grouping
data ChildGroup
    = ClosedGroup [Rex]  -- consecutive closed children
    | OpenGroup   [Rex]  -- consecutive open children


-- HEIR: Vertical siblings at same column ----------------------------------------
--
-- Each element appears aligned by the last character of their runes.
-- E.g., ":= x/y" followed by "| if ..." has "|" aligned with "=" (column 2).
-- But ":| a" followed by ":| b" has both starting at column 1.

heirDoc :: PrintConfig -> [Rex] -> PDoc
heirDoc _   []     = PEmpty
heirDoc cfg [k]    = rexDoc cfg k
heirDoc cfg (k:ks) =
    let firstRuneLen = case k of
            OPEN _ r _ -> length r
            _          -> 1
        -- Insert ') separator if first two elements are both SLUGs
        firstSep = case (k, ks) of
            (LEAF _ SLUG _, LEAF _ SLUG _ : _) -> PCat PLine (pdocText "')")
            _ -> PEmpty
        inner = PDent (PCat (rexDoc cfg k) (PCat firstSep (heirRest cfg firstRuneLen ks)))
    in if cfgDebug cfg
       then PCat (pdocText "⟨") (PCat inner (pdocText "⟩"))
       else inner

-- | Render remaining heir elements with alignment based on first rune
-- If two consecutive SLUGs appear, insert ') between them to prevent
-- them from being re-parsed as a single multi-line slug.
heirRest :: PrintConfig -> Int -> [Rex] -> PDoc
heirRest _   _            []     = PEmpty
heirRest cfg firstRuneLen (k:ks) =
    let currentRuneLen = case k of
            OPEN _ r _ -> length r
            _          -> 1
        padding = max 0 (firstRuneLen - currentRuneLen)
        pad = if padding > 0 then pdocText (replicate padding ' ') else PEmpty
        -- Insert ') separator if next element is also a SLUG
        sep = case (k, ks) of
            (LEAF _ SLUG _, LEAF _ SLUG _ : _) -> PCat PLine (pdocText "')")
            _ -> PEmpty
    in PCat PLine (PCat pad (PCat (rexDoc cfg k) (PCat sep (heirRest cfg firstRuneLen ks))))


-- BLOC: Block forms like f =\n  a\n  b ------------------------------------------
--
-- Head + rune stays on one line, then items on subsequent lines indented.

blocDoc :: PrintConfig -> Color -> String -> Rex -> [Rex] -> PDoc
blocDoc cfg c r hd items =
    let (open, close) = bracketChars c
        headD = rexDoc cfg hd
        runeD = cRune cfg r
        itemsD = blocItems cfg items
        -- In debug mode, wrap head+rune in ⟦⟧ markers
        headRune = if cfgDebug cfg
                   then PCat (pdocText "⟦") (PCat headD (PCat pdocSpace (PCat runeD (pdocText "⟧"))))
                   else PCat headD (PCat pdocSpace runeD)
        inner = PCat headRune itemsD
    in case c of
        CLEAR -> inner
        _     -> PCat (cBracket cfg open) (PCat inner (cBracket cfg close))

blocItems :: PrintConfig -> [Rex] -> PDoc
blocItems _   []    = PEmpty
blocItems cfg items = PCat PLine (PCat (pdocText "    ") (PDent (blocItemsSep cfg items)))

blocItemsSep :: PrintConfig -> [Rex] -> PDoc
blocItemsSep _   []     = PEmpty
blocItemsSep cfg [k]    = rexDoc cfg k
blocItemsSep cfg (k:ks) = PCat (rexDoc cfg k) (PCat PLine (blocItemsSep cfg ks))


-- Helpers -----------------------------------------------------------------------

-- | Render a Rex in a tight context. Complex expressions that would normally
-- span multiple lines get wrapped in parens.
rexDocTight :: PrintConfig -> Rex -> PDoc
rexDocTight cfg rex = case rex of
    LEAF _ _ _      -> rexDoc cfg rex
    NEST _ _ _ _    -> rexDoc cfg rex
    EXPR _ _ _      -> rexDoc cfg rex
    PREF _ _ _      -> rexDoc cfg rex
    TYTE _ _ _      -> rexDoc cfg rex
    JUXT _ _        -> rexDoc cfg rex
    -- These need parens when used in tight context
    OPEN _ _ _      -> pdocParensC cfg (rexDoc cfg rex)
    HEIR _ _        -> pdocParensC cfg (rexDoc cfg rex)
    BLOC _ _ _ _ _  -> pdocParensC cfg (rexDoc cfg rex)

-- | Wrap in colored parens
pdocParensC :: PrintConfig -> PDoc -> PDoc
pdocParensC cfg d = PCat (cBracket cfg '(') (PCat d (cBracket cfg ')'))

-- | Check if a Rex is an "open" form that needs staircase layout.
-- Used for grouping children in vertical layout.
isOpenRex :: Rex -> Bool
isOpenRex (OPEN _ _ _)     = True
isOpenRex (BLOC _ _ _ _ _) = True
isOpenRex (HEIR _ _)       = True
isOpenRex _                = False

-- | Check if a Rex forces vertical layout but doesn't need staircase.
-- SLUG is always wrapped in pdocNoFit so it can't render flat.
forcesVertical :: Rex -> Bool
forcesVertical (LEAF _ SLUG _) = True
forcesVertical x               = isOpenRex x

-- | Check if the list has a vertical-forcing child followed by more children.
-- This causes heir collision in flat layout, so vertical is required.
hasOpenThenMore :: [Rex] -> Bool
hasOpenThenMore []     = False
hasOpenThenMore [_]    = False  -- last element, no collision possible
hasOpenThenMore (x:xs) = forcesVertical x || hasOpenThenMore xs

-- | Compute the minimum flat width of a Rex (characters if rendered flat).
-- This is a cheap O(n) traversal, no rendering involved.
rexMinWidth :: Rex -> Int
rexMinWidth (LEAF _ shape s) = leafWidth shape s
rexMinWidth (NEST _ _ r kids) = 2 + length r + 1 + childrenWidth kids  -- (rune children)
rexMinWidth (EXPR _ _ kids) = 2 + childrenWidth kids                    -- (children)
rexMinWidth (PREF _ r x) = length r + rexMinWidth x
rexMinWidth (TYTE _ sep kids) = sum (map rexMinWidth kids) + (length kids - 1) * length sep
rexMinWidth (BLOC _ _ r h ks) = length r + 1 + rexMinWidth h + childrenWidth ks
rexMinWidth (OPEN _ r kids) = length r + 1 + childrenWidth kids
rexMinWidth (JUXT _ kids) = sum (map rexMinWidth kids)
rexMinWidth (HEIR _ kids) = childrenWidth kids

-- | Width of leaf content including any quoting overhead
leafWidth :: LeafShape -> String -> Int
leafWidth WORD s = length s
leafWidth QUIP s = 1 + length s                    -- 'x
leafWidth CORD s = 2 + length s + countQuotes s    -- "x" with "" escaping
leafWidth TAPE s = length s + 2                    -- rough estimate for block strings
leafWidth PAGE s = length s + 6                    -- ''' on both sides
leafWidth SPAN s = length s + 6                    -- '''x'''
leafWidth SLUG s = 2 + length s                    -- ' x
leafWidth (BAD _) s = length s

-- | Count quotes that need escaping in CORD strings
countQuotes :: String -> Int
countQuotes = length . filter (== '"')

-- | Total width of children with spaces between
childrenWidth :: [Rex] -> Int
childrenWidth [] = 0
childrenWidth kids = sum (map rexMinWidth kids) + length kids - 1

bracketChars :: Color -> (Char, Char)
bracketChars PAREN = ('(', ')')
bracketChars BRACK = ('[', ']')
bracketChars CURLY = ('{', '}')
bracketChars CLEAR = (' ', ' ')  -- unused; CLEAR is handled above


-- Main --------------------------------------------------------------------------

-- | Read Rex source from stdin, parse to Rex, and pretty-print using
-- the PDoc layout engine. Each top-level input is separated by a blank line.
-- Uses colors when stdout is a terminal.
prettyRexMain :: Bool -> IO ()
prettyRexMain debug = do
    isTty <- hIsTerminalDevice stdout
    let colors = if isTty then BoldColors else NoColors
    let cfg = PrintConfig colors debug 30 50
    src <- getContents
    -- Force full input before parsing (avoid lazy IO issues with interactive input)
    let !_ = length src
    let results = parseRex src
    mapM_ (\(slice, tree) ->
        case rexFromBlockTree slice tree of
            Nothing  -> pure ()
            Just rex -> do
                putStrLn (printRexWith cfg 80 rex)
                putStrLn ""
        ) results
