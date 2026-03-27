{-# LANGUAGE LambdaCase #-}

-- | String extraction and processing for Rex leaf nodes.
--
-- This module handles:
-- - String content extraction (strip delimiters, handle escapes)
-- - Quote escaping/unescaping
-- - Multiline string normalization (indent stripping for SPAN/PAGE)
-- - Validation of string literals

module Rex.String
    ( -- * Strip result type
      StripResult(..)
      -- * String stripping
    , stripTrad
    , stripUgly
    , stripSlug
      -- * Quote handling
    , unescapeQuotes
      -- * Quip normalization
    , normalizeQuipIndent
    )
where

import Rex.Lex   (Span(..))
import Rex.Error (BadReason(..))


-- | Result of stripping a string literal
data StripResult
    = StripOK String      -- ^ Successfully extracted content
    | StripBad BadReason  -- ^ Invalid string literal
    deriving (Eq, Show)


-- TRAD String Processing ------------------------------------------------------

-- | Process a TRAD string: classify as TAPE (page-style) or CORD (span-style).
-- Returns (isTape, result) where isTape indicates whether this is page-style.
-- TAPE: starts with newline after opening quote, strip depth from closing quote indent
-- CORD: inline content, continuation lines must indent to content column
stripTrad :: Span -> String -> (Bool, StripResult)
stripTrad sp s =
    let col = spanCol sp
    in case s of
        '"':afterOpen -> case afterOpen of
            '\n':rest -> (True, stripTape s col rest)
            _         -> (False, stripCord s col afterOpen)
        _ -> (False, StripOK s)  -- no quotes, leave as is (shouldn't happen)
  where
    -- TAPE: strip depth comes from terminator line's indentation
    stripTape :: String -> Int -> String -> StripResult
    stripTape _orig _openCol content =
        let contentLines = lines content
        in case reverse contentLines of
            [] -> StripOK ""
            (lastLine:revRest) ->
                let (spaces, afterSpaces) = span (== ' ') lastLine
                    stripDepth = length spaces
                    bodyLines = reverse revRest
                in if afterSpaces == "\"" && all (validPageLine stripDepth) bodyLines
                   then let stripped = map (unescapeQuotes . stripLineForPage stripDepth) bodyLines
                        in StripOK (unlines' stripped)
                   else StripBad InvalidPage

    -- CORD: strip depth is content column (after opening quote)
    -- Continuation lines must be indented at least to the content column
    stripCord :: String -> Int -> String -> StripResult
    stripCord _orig openCol content =
        let body = removeClosingQuote content
            contentCol = openCol  -- column where content starts (right after ")
        in case lines body of
            []     -> StripOK ""
            [single] -> StripOK (unescapeQuotes single)
            (_:rest) ->
                if all (validSpanLine contentCol) rest
                then StripOK (stripContinuations contentCol body)
                else StripBad InvalidSpan

    removeClosingQuote str =
        case reverse str of
            '"':inner -> reverse inner
            _         -> str  -- unclosed, return as-is


-- UGLY String Processing ------------------------------------------------------

-- | Process an UGLY string: classify as PAGE or SPAN, then strip accordingly.
-- Returns (isPage, result) where isPage indicates whether this is page-style.
-- PAGE: starts with newline after ticks, strip depth determined by terminator indent
-- SPAN: inline content, strip continuation lines based on content column
stripUgly :: Span -> String -> (Bool, StripResult)
stripUgly sp s =
    let col = spanCol sp
        (ticks, afterOpen) = span (== '\'') s
        n = length ticks
    in if n >= 2
       then case afterOpen of
                '\n':rest -> (True, stripPage n rest)
                _         -> (False, stripSpan col n afterOpen)
       else (False, StripOK s)  -- shouldn't happen, but fallback
  where
    -- PAGE: strip depth comes from terminator line's indentation
    stripPage :: Int -> String -> StripResult
    stripPage n content =
        let contentLines = lines content
        in case reverse contentLines of
            [] -> StripOK ""
            (lastLine:revRest) ->
                let closeTicks = replicate n '\''
                    (spaces, afterSpaces) = span (== ' ') lastLine
                    stripDepth = length spaces
                    bodyLines = reverse revRest
                in if afterSpaces == closeTicks && all (validPageLine stripDepth) bodyLines
                   then let stripped = map (stripLineForPage stripDepth) bodyLines
                        in StripOK (unlines' stripped)
                   else StripBad InvalidPage

    -- SPAN: strip depth is content column (after ticks)
    -- Continuation lines must be indented at least to the content column
    stripSpan :: Int -> Int -> String -> StripResult
    stripSpan openCol n content =
        let closeTicks = replicate n '\''
            body = removeClosing closeTicks content
            contentCol = openCol + n - 1  -- column where content starts
        in case lines body of
            []     -> StripOK ""
            [single] -> StripOK (unescapeQuotes single)
            (_:rest) ->
                if all (validSpanLine contentCol) rest
                then StripOK (stripContinuations contentCol body)
                else StripBad InvalidSpan

    removeClosing ticks str =
        let revTicks = reverse ticks
            revStr = reverse str
        in if take (length ticks) revStr == revTicks
           then reverse (drop (length ticks) revStr)
           else str


-- SLUG String Processing ------------------------------------------------------

-- | Strip a SLUG string: remove "' " prefix from each line.
stripSlug :: String -> String
stripSlug = unlines' . map stripSlugLine . lines
  where
    stripSlugLine s = case s of
        '\'':' ':rest -> rest
        '\'':"" -> ""  -- empty slug line
        '\'':rest -> rest  -- slug line with no space after '
        _ -> s  -- shouldn't happen, but leave as is


-- Shared Helpers --------------------------------------------------------------

-- | Check if a line is valid for PAGE: blank lines are always valid,
-- non-blank lines must have at least `depth` leading spaces
validPageLine :: Int -> String -> Bool
validPageLine depth line
    | all (== ' ') line = True
    | otherwise         = all (== ' ') (take depth line) && length line >= depth

-- | Check if a continuation line is valid for SPAN
validSpanLine :: Int -> String -> Bool
validSpanLine depth line =
    length (takeWhile (== ' ') line) >= depth

-- | Strip a line for PAGE: blank lines pass through, others get stripped
stripLineForPage :: Int -> String -> String
stripLineForPage depth line
    | all (== ' ') line = ""
    | otherwise         = stripN depth line

-- | Strip leading whitespace from continuation lines.
-- The first line is left as-is, subsequent lines have `col` spaces stripped.
stripContinuations :: Int -> String -> String
stripContinuations col s =
    case lines s of
        [] -> ""
        [single] -> unescapeQuotes single
        (first:rest) -> unlines' (unescapeQuotes first : map (unescapeQuotes . stripN col) rest)

-- | Join lines without trailing newline
unlines' :: [String] -> String
unlines' [] = ""
unlines' xs = init (unlines xs)

-- | Unescape doubled quotes ("") to single quotes (")
unescapeQuotes :: String -> String
unescapeQuotes [] = []
unescapeQuotes ('"':'"':rest) = '"' : unescapeQuotes rest
unescapeQuotes (c:rest) = c : unescapeQuotes rest

-- | Strip up to n leading spaces from a string.
stripN :: Int -> String -> String
stripN 0 s = s
stripN n (' ':rest) = stripN (n-1) rest
stripN _ s = s  -- non-space or end of string


-- Quip Normalization ----------------------------------------------------------

-- | Normalize indentation for multi-line quips.
-- Strips the minimum indent from all non-empty continuation lines, so that
-- the least-indented line ends up at column 0 (relative to the quip start).
-- This allows "jagged" input where lines are typed at column 0 to normalize
-- to the same representation as properly-indented input.
normalizeQuipIndent :: String -> String
normalizeQuipIndent s
    | '\n' `notElem` s = s  -- single-line, no change
    | otherwise =
        let (firstLine, rest) = break (== '\n') s
            contLines = splitLines (drop 1 rest)  -- drop the '\n'
            minIndent = minimum (maxBound : map lineIndent (filter (not . isBlankLine) contLines))
            stripped = map (stripIndent minIndent) contLines
        in firstLine ++ concatMap ('\n':) stripped

-- | Split a string into lines, preserving empty lines
splitLines :: String -> [String]
splitLines "" = []
splitLines s  = let (l, rest) = break (== '\n') s
                in l : case rest of
                         ""     -> []
                         (_:rs) -> splitLines rs

-- | Count leading spaces in a line
lineIndent :: String -> Int
lineIndent = length . takeWhile (== ' ')

-- | Check if a line is blank (empty or only whitespace)
isBlankLine :: String -> Bool
isBlankLine = all (`elem` " \t")

-- | Strip n spaces from the beginning of a line
stripIndent :: Int -> String -> String
stripIndent 0 s = s
stripIndent n s = case s of
    (' ':rest) -> stripIndent (n-1) rest
    _          -> s  -- fewer spaces than expected, or non-space char
