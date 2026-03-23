-- Copyright (c) 2026 xoCore Technologies
-- SPDX-License-Identifier: MIT
-- See LICENSE for full terms.
--
-- A pretty-printer document layout system in the vein of Wadler's
-- "A Pretty Printer", extended with PBACKSTEP to handle the
-- indentation requirements of rune poems.
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
    , pdocBackstep
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
    | PLine                     -- ^ newline (renders as newline + indentation)
    | PCat   PDoc PDoc          -- ^ concatenation
    | PDent  PDoc               -- ^ set indent level to current column
    | PChoice PDoc PDoc         -- ^ try left; fall back to right if it doesn't fit
    | PBackstep !Int PDoc PDoc  -- ^ use right's indent to inform left's indent
    deriving (Show)


-- Rendered Document Type ------------------------------------------------------

-- | A fully rendered document, ready to be converted to a string.
data SDoc
    = SEmpty
    | SChar  !Char SDoc
    | SText  !Int String SDoc   -- ^ length, text, rest
    | SLine  !Int SDoc          -- ^ indentation level, rest
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

        PBackstep b x y ->
            let (backstep, ylist) = best n k (DLCons i y ds)
                ip                = i + backstep + b
                (_, xlist)        = best n k (DLSCons ip x backstep ylist)
            in (backstep + b, xlist)

    best n k (DLSCons i d bs ss) = case d of
        PEmpty ->
            (bs, ss)

        PChar c ->
            (bs, SChar c ss)

        PText l s ->
            (bs, SText l s ss)

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

        PBackstep b x y ->
            let (backstep, ylist) = best n k (DLSCons i y bs ss)
                ip                = i + backstep + b
                (_, xlist)        = best n k (DLSCons ip x backstep ylist)
            in (backstep + b, xlist)

-- | Choose the first rendered document if it fits within the page width,
-- otherwise use the second.
pdocRenderNicest :: Int -> Int -> Int -> (Int, SDoc) -> (Int, SDoc) -> (Int, SDoc)
pdocRenderNicest w _n k xr yr =
    if sdocFits (w - k) (snd xr) then xr else yr

-- | Check whether an SDoc fits within the given number of remaining columns.
-- Returns True on newlines (the new line starts fresh).
sdocFits :: Int -> SDoc -> Bool
sdocFits w _            | w < 0     = False
sdocFits _ SEmpty                   = True
sdocFits w (SChar _ x)              = sdocFits (w - 1) x
sdocFits w (SText l _ x)            = sdocFits (w - l) x
sdocFits _ (SLine _ _)              = True

-- | Convert a rendered 'SDoc' to a 'String'.
sdocToString :: SDoc -> String
sdocToString SEmpty        = ""
sdocToString (SChar c x)   = c : sdocToString x
sdocToString (SText _ s x) = s ++ sdocToString x
sdocToString (SLine i x)   = '\n' : replicate i ' ' ++ sdocToString x


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

-- | A single space.
pdocSpace :: PDoc
pdocSpace = PChar ' '

-- | Concatenate two documents, preferring a space between them but
-- falling back to a newline if they don't fit.
pdocSpaceOrLine :: PDoc -> PDoc -> PDoc
pdocSpaceOrLine x y = PCat x (PChoice (PCat pdocSpace y) (PCat PLine y))

-- | The backstep combinator. Renders y first to determine its indentation,
-- then uses that to set the indentation for x. Used to align sibling rune
-- poems correctly.
pdocBackstep :: PDoc -> PDoc -> PDoc
pdocBackstep x y = PBackstep 4 (PCat PLine x) y

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
