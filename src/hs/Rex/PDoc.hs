-- Copyright (c) 2026 xoCore Technologies
-- SPDX-License-Identifier: MIT
-- See LICENSE for full terms.
--
-- A pretty-printer document layout system in the vein of Wadler's
-- "A Pretty Printer", extended with PStaircase to handle the
-- reverse-staircase indentation pattern of rune poems.
--
-- Translated from the Sire implementation in the Plunder codebase,
-- which was designed and implemented by Iceman (Elliot Glaysher).

module Rex.PDoc
    ( -- * Document type
      PDoc(..)
      -- * Rendered document type
    , SDoc(..)
      -- * Rendering
    , render
    , pdocRenderSDoc
    , sdocToString
      -- * Primitive constructors
    , pdocChar
    , pdocText
    , pdocLine
    , pdocEmpty
      -- * Combinators
    , pdocEnclose
    , pdocParens
    , pdocBrackets
    , pdocCurlies
    , pdocAngles
    , pdocSquotes
    , pdocDquotes
    , pdocSpace
    , pdocSpaceOrLine
    , pdocStaircase
    , pdocFlow
    , pdocNoFit
    , pdocIntersperse
    , pdocIntersperseFun
    , pdocIntersperseFunList
    , pdocSpaceSep
    ) where


-- Document Type ---------------------------------------------------------------

-- | The document type. Build documents with the combinators below,
-- then render with 'render' or 'pdocRenderSDoc'.
data PDoc
    = PEmpty
    | PChar  !Char
    | PText  !Int String        -- ^ precomputed length, text
    | PSpace                    -- ^ layout space (dropped before newlines)
    | PLine                     -- ^ newline (renders as newline + indentation)
    | PCat   PDoc PDoc          -- ^ concatenation
    | PDent  PDoc               -- ^ set indent level to current column
    | PChoice PDoc PDoc         -- ^ try left; fall back to right if it doesn't fit
    | PNoFit PDoc               -- ^ never fits in PChoice; forces fallback to right
    | PStaircase !Int [PDoc]    -- ^ reverse-staircase layout for open children
                                -- Int = step size (typically 4)
                                -- Items are rendered in reverse-depth order:
                                -- first at deepest indent, last at base indent.
                                -- Each item gets PLine before it.
    | PFlow !Int !Bool [PDoc]   -- ^ flow layout: pack items greedily onto lines
                                -- Int = max item width for flow participation.
                                -- Bool = True if this is the first item (no leading space).
                                -- Small items are packed with spaces between.
                                -- Large items (exceed limit or have newlines)
                                -- get their own line.
    deriving (Show)


-- Rendered Document Type ------------------------------------------------------

-- | A fully rendered document, ready to be converted to a string.
data SDoc
    = SEmpty
    | SChar  !Char SDoc
    | SText  !Int String SDoc   -- ^ length, text, rest
    | SSpace !Int SDoc          -- ^ layout spaces count (dropped before newlines/end)
    | SLine  !Int SDoc          -- ^ indentation level, rest
    | SNoFit SDoc               -- ^ marker that this doesn't fit (for PChoice)
    deriving (Show)


-- Internal Work List ----------------------------------------------------------

data DocList
    = DLNil
    | DLCons  !Int PDoc DocList
    | DLSCons !Int PDoc !Int SDoc  -- ^ indent, doc, backstep, precomputed suffix
    deriving (Show)


-- Rendering -------------------------------------------------------------------

-- | Render a document to a string, fitting within the given page width.
render :: Int -> PDoc -> String
render w = sdocToString . pdocRenderSDoc w

-- | Render a 'PDoc' to an 'SDoc', fitting within the given page width.
pdocRenderSDoc :: Int -> PDoc -> SDoc
pdocRenderSDoc w =
    \x -> snd (best 0 0 (DLCons 0 x DLNil))
  where
    best :: Int -> Int -> DocList -> (Int, SDoc)
    best _n _k DLNil = (0, SEmpty)

    best n k (DLCons i d ds) = case d of
        PEmpty ->
            best n k ds

        PChar c ->
            let (bs, rest) = best n (k + 1) ds
            in (bs, SChar c rest)

        PText l s ->
            let (bs, rest) = best n (k + l) ds
            in (bs, SText l s rest)

        PSpace ->
            let (bs, rest) = best n (k + 1) ds
            in (bs, SSpace 1 rest)

        PLine ->
            let (bs, rest) = best i i ds
            in (bs, SLine i rest)

        PCat x y ->
            best n k (DLCons i x (DLCons i y ds))

        PDent x ->
            best n k (DLCons k x ds)

        PChoice x y ->
            pdocRenderNicest w n k
                (best n k (DLCons i x ds))
                (best n k (DLCons i y ds))

        PNoFit x ->
            let (bs, rest) = best n k (DLCons i x ds)
            in (bs, SNoFit rest)

        PStaircase step items ->
            -- Render items in staircase pattern, first item deepest.
            -- ALL items get a newline before them at their computed indent.
            -- Returns backstep=0 to prevent leakage to outer context.
            let totalSteps = (length items - 1) * step
                buildDoc [] _depth = best n k ds
                buildDoc [item] _depth =
                    -- Last item at base indent
                    best n k (DLCons i (PCat PLine item) ds)
                buildDoc (item:rest) depth =
                    let itemIndent = i + depth
                        (_, restSDoc) = buildDoc rest (depth - step)
                        -- Newline at itemIndent, then item, then rest
                    in best n k (DLCons itemIndent (PCat PLine item) (DLSCons i PEmpty 0 restSDoc))
            in (0, snd (buildDoc items totalSteps))

        PFlow _maxW _isFirst [] ->
            best n k ds

        PFlow maxW isFirst (item:rest) ->
            -- Render item speculatively to check its size
            let (_, rendered) = best n k (DLCons i item DLNil)
                isSmall = sdocFitsFlat maxW rendered
                fitsHere = sdocFitsFlat (w - k - 1) rendered  -- room for space + item
                atLineStart = k == i
                needSpace = not isFirst && not atLineStart
            in if isSmall && fitsHere
               then if needSpace
                    then -- append with space between items
                         best n k (DLCons i pdocSpace
                                    (DLCons i item
                                      (DLCons i (PFlow maxW False rest) ds)))
                    else -- first item or at line start, no leading space
                         best n k (DLCons i item (DLCons i (PFlow maxW False rest) ds))
               else if not atLineStart
                    then -- wrap to new line, retry (becomes first on that line)
                         let (bs', r) = best i i (DLCons i (PFlow maxW True (item:rest)) ds)
                         in (bs', SLine i r)
                    else -- at line start, item is big, emit as-is
                         -- only add newline if there are more items
                         case rest of
                             [] -> best n k (DLCons i item ds)
                             _  -> best n k (DLCons i item
                                              (DLCons i PLine
                                                (DLCons i (PFlow maxW True rest) ds)))

    best n k (DLSCons i d bs ss) = case d of
        PEmpty ->
            (bs, ss)

        PChar c ->
            (bs, SChar c ss)

        PText l s ->
            (bs, SText l s ss)

        PSpace ->
            (bs, SSpace 1 ss)

        PLine ->
            (bs, SLine i ss)

        PCat x y ->
            best n k (DLCons i x (DLSCons i y bs ss))

        PDent x ->
            best n k (DLSCons k x bs ss)

        PChoice x y ->
            pdocRenderNicest w n k
                (best n k (DLSCons i x bs ss))
                (best n k (DLSCons i y bs ss))

        PNoFit x ->
            let (_, rest) = best n k (DLSCons i x bs ss)
            in (bs, SNoFit rest)

        PStaircase step items ->
            -- Inside DLSCons: render staircase, then continue with outer context
            -- ALL items get newlines before them
            let totalSteps = (length items - 1) * step
                buildDoc [] _depth = (bs, ss)
                buildDoc [item] _depth =
                    -- Last item at base indent
                    let (_, rest) = best n k (DLSCons i (PCat PLine item) bs ss)
                    in (bs, rest)
                buildDoc (item:rest) depth =
                    let itemIndent = i + depth
                        (_, restSDoc) = buildDoc rest (depth - step)
                    in (bs, snd (best n k (DLCons itemIndent (PCat PLine item) (DLSCons i PEmpty 0 restSDoc))))
            in buildDoc items totalSteps

        PFlow _maxW _isFirst [] ->
            (bs, ss)

        PFlow maxW isFirst (item:rest) ->
            -- Render item speculatively to check its size
            let (_, rendered) = best n k (DLCons i item DLNil)
                isSmall = sdocFitsFlat maxW rendered
                fitsHere = sdocFitsFlat (w - k - 1) rendered  -- room for space + item
                atLineStart = k == i
                needSpace = not isFirst && not atLineStart
            in if isSmall && fitsHere
               then if needSpace
                    then -- append with space between items
                         best n k (DLCons i pdocSpace
                                    (DLCons i item
                                      (DLSCons i (PFlow maxW False rest) bs ss)))
                    else -- first item or at line start, no leading space
                         best n k (DLCons i item (DLSCons i (PFlow maxW False rest) bs ss))
               else if not atLineStart
                    then -- wrap to new line, retry (becomes first on that line)
                         let (_, r) = best i i (DLCons i (PFlow maxW True (item:rest)) (DLSCons i PEmpty bs ss))
                         in (bs, SLine i r)
                    else -- at line start, item is big, emit as-is
                         -- only add newline if there are more items
                         case rest of
                             [] -> best n k (DLCons i item (DLSCons i PEmpty bs ss))
                             _  -> best n k (DLCons i item
                                              (DLCons i PLine
                                                (DLSCons i (PFlow maxW True rest) bs ss)))

-- | Choose the first rendered document if it fits within the page width,
-- otherwise use the second.
pdocRenderNicest :: Int -> Int -> Int -> (Int, SDoc) -> (Int, SDoc) -> (Int, SDoc)
pdocRenderNicest w _n k xr yr =
    if sdocFits (w - k) (snd xr) then xr else yr

-- | Check whether an SDoc fits within the given number of remaining columns.
-- Returns True on newlines (the new line starts fresh).
-- Returns False on SNoFit (explicitly marked as not fitting).
sdocFits :: Int -> SDoc -> Bool
sdocFits w _            | w < 0     = False
sdocFits _ SEmpty                   = True
sdocFits w (SChar _ x)              = sdocFits (w - 1) x
sdocFits w (SText l _ x)            = sdocFits (w - l) x
sdocFits w (SSpace n x)             = sdocFits (w - n) x
sdocFits _ (SLine _ _)              = True
sdocFits _ (SNoFit _)               = False

-- | Stricter variant of sdocFits that rejects newlines.
-- Used by PFlow to check if an item is truly single-line.
sdocFitsFlat :: Int -> SDoc -> Bool
sdocFitsFlat w _ | w < 0       = False
sdocFitsFlat _ SEmpty           = True
sdocFitsFlat w (SChar _ x)      = sdocFitsFlat (w - 1) x
sdocFitsFlat w (SText l _ x)    = sdocFitsFlat (w - l) x
sdocFitsFlat w (SSpace n x)     = sdocFitsFlat (w - n) x
sdocFitsFlat _ (SLine _ _)      = False
sdocFitsFlat _ (SNoFit _)       = False

-- | Convert a rendered 'SDoc' to a 'String'.
-- Layout spaces (SSpace) are dropped before newlines and at end of string.
sdocToString :: SDoc -> String
sdocToString SEmpty        = ""
sdocToString (SChar c x)   = c : sdocToString x
sdocToString (SText _ s x) = s ++ sdocToString x
sdocToString (SSpace n x)  = case skipSpaces x of
    SEmpty     -> ""                                    -- drop at end
    SLine i r  -> '\n' : replicate i ' ' ++ sdocToString r  -- drop before newline
    other      -> replicate n ' ' ++ sdocToString other -- keep otherwise
  where
    -- Skip over any additional SSpace nodes
    skipSpaces (SSpace m y) = case skipSpaces y of
        SEmpty    -> SEmpty
        SLine i r -> SLine i r
        other     -> SSpace (n + m) other  -- accumulate spaces
    skipSpaces y = y
sdocToString (SLine i x)   = '\n' : replicate i ' ' ++ sdocToString x
sdocToString (SNoFit x)    = sdocToString x  -- SNoFit is just a marker, render content


-- Primitive Constructors ------------------------------------------------------

-- | A single character. Newlines become 'PLine'.
pdocChar :: Char -> PDoc
pdocChar '\n' = PLine
pdocChar c    = PChar c

-- | A string. Empty strings become 'PEmpty'.
pdocText :: String -> PDoc
pdocText "" = PEmpty
pdocText s  = PText (length s) s

-- | A newline followed by the current indentation level.
pdocLine :: PDoc
pdocLine = PLine

-- | The empty document.
pdocEmpty :: PDoc
pdocEmpty = PEmpty


-- Combinators -----------------------------------------------------------------

-- | Enclose a document between left and right delimiters.
pdocEnclose :: PDoc -> PDoc -> PDoc -> PDoc
pdocEnclose l r x = PCat l (PCat x r)

pdocParens :: PDoc -> PDoc
pdocParens = pdocEnclose (PChar '(') (PChar ')')

pdocBrackets :: PDoc -> PDoc
pdocBrackets = pdocEnclose (PChar '[') (PChar ']')

pdocCurlies :: PDoc -> PDoc
pdocCurlies = pdocEnclose (PChar '{') (PChar '}')

pdocAngles :: PDoc -> PDoc
pdocAngles = pdocEnclose (PChar '<') (PChar '>')

pdocSquotes :: PDoc -> PDoc
pdocSquotes = pdocEnclose (PChar '\'') (PChar '\'')

pdocDquotes :: PDoc -> PDoc
pdocDquotes = pdocEnclose (PChar '"') (PChar '"')

-- | A single layout space (dropped before newlines and at end).
pdocSpace :: PDoc
pdocSpace = PSpace

-- | Concatenate two documents, preferring a space between them but
-- falling back to a newline if they don't fit.
pdocSpaceOrLine :: PDoc -> PDoc -> PDoc
pdocSpaceOrLine x y = PCat x (PChoice (PCat pdocSpace y) (PCat PLine y))

-- | Create a reverse-staircase layout for a list of open children.
-- First item appears at deepest indent, last at base indent.
-- ALL items get newlines before them (PStaircase handles this).
-- Returns backstep=0, so multiple staircases don't leak into each other.
pdocStaircase :: [PDoc] -> PDoc
pdocStaircase []    = PEmpty
pdocStaircase [x]   = PCat PLine x  -- single item still needs newline
pdocStaircase items = PStaircase 4 items

-- | Create a flow layout that packs items greedily onto lines.
-- Small items (within maxW) are packed with spaces between them.
-- Large items (exceeding maxW or containing newlines) get their own line.
pdocFlow :: Int -> [PDoc] -> PDoc
pdocFlow _    []    = PEmpty
pdocFlow _    [x]   = x
pdocFlow maxW items = PFlow maxW True items  -- True = first item, no leading space

-- | Mark a document as "never fits" for PChoice. When this appears in the
-- left branch of a PChoice, it forces the choice to use the right branch.
-- The document is still rendered normally if the PChoice selects this branch
-- (e.g., if there's no alternative).
pdocNoFit :: PDoc -> PDoc
pdocNoFit = PNoFit

-- | Intersperse a separator between documents in a list, using a
-- combining function.
pdocIntersperseFun :: (PDoc -> PDoc -> PDoc) -> [PDoc] -> PDoc
pdocIntersperseFun _ []     = PEmpty
pdocIntersperseFun _ [x]    = x
pdocIntersperseFun f (x:xs) = f x (pdocIntersperseFun f xs)

-- | Intersperse a separator document between a list of documents.
pdocIntersperse :: PDoc -> [PDoc] -> PDoc
pdocIntersperse sep = pdocIntersperseFun (\x y -> PCat x (PCat sep y))

-- | Like 'pdocIntersperseFun' but for cases where you want to fold over
-- a list with a combining function.
pdocIntersperseFunList :: (PDoc -> PDoc -> PDoc) -> [PDoc] -> PDoc
pdocIntersperseFunList = pdocIntersperseFun

-- | Separate documents with spaces.
pdocSpaceSep :: [PDoc] -> PDoc
pdocSpaceSep = pdocIntersperse pdocSpace
