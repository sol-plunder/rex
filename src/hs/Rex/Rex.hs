{-# LANGUAGE LambdaCase #-}
{-# OPTIONS_GHC -Wno-x-partial #-}

module Rex.Rex
    ( Rex(..), LeafShape(..), Color(..), ppRex
    , rexSpan, noSpan
    , rexFromTree, rexFromBlockTree
    , rexMain, checkMain
    , collectRexErrors
    )
where

import qualified Rex.Tree2 as Tr

import Rex.Lex    (Span (..))
import Rex.Tree2  (Bracket (..), Leaf (..), Node (..), Shape (..), Tree (..), treePos)
import Rex.Error  (BadReason(..), RexError(..))
import Data.List  (nubBy, sortBy)


-- Rex Data Model --------------------------------------------------------------

data LeafShape = WORD | QUIP | CORD | TAPE | PAGE | SPAN | SLUG | BAD BadReason
  deriving (Eq, Show)

data Color = PAREN | BRACK | CURLY | CLEAR
  deriving (Eq, Show)

data Rex
    = LEAF Span LeafShape String
    | NEST Span Color String [Rex]           -- (x + y), {a | b}
    | EXPR Span Color [Rex]                  -- [f x], (x), ()
    | PREF Span String Rex                   -- :x, -y
    | TYTE Span String [Rex]                 -- x.y, a:b
    | BLOC Span Color String Rex [Rex]       -- head rune:\n  a\n  b
    | OPEN Span String [Rex]                 -- + x y (layout prefix)
    | JUXT Span [Rex]                        -- f(x), f(x)[1]
    | HEIR Span [Rex]                        -- + x\n+ y\nz
  deriving (Eq, Show)

-- | Get the span of a Rex node
rexSpan :: Rex -> Span
rexSpan (LEAF sp _ _)     = sp
rexSpan (NEST sp _ _ _)   = sp
rexSpan (EXPR sp _ _)     = sp
rexSpan (PREF sp _ _)     = sp
rexSpan (TYTE sp _ _)     = sp
rexSpan (BLOC sp _ _ _ _) = sp
rexSpan (OPEN sp _ _)     = sp
rexSpan (JUXT sp _)       = sp
rexSpan (HEIR sp _)       = sp

-- | Empty span (for synthetic nodes)
noSpan :: Span
noSpan = Span 0 0 0 0


-- Rune Precedence -------------------------------------------------------------

runeSeq :: String
runeSeq = ";,:#$`~@?\\|^&=!<>+-*/%!."

runePrec :: Char -> Int
runePrec c = go 0 runeSeq
  where
    go n []     = n
    go n (x:xs) = if c == x then n else go (n+1) xs

packRune :: String -> Integer
packRune s =
    let codes = take 13 (map runePrec s ++ repeat 23)
    in foldr (\code acc -> acc * 25 + fromIntegral code) 0 codes

runeCmp :: String -> String -> Ordering
runeCmp a b = compare (packRune a) (packRune b)


-- Leaf Conversion -------------------------------------------------------------

leafToRex :: Span -> Leaf -> Rex
leafToRex sp = \case
    L_WORD s -> LEAF sp WORD s
    L_TRAD s -> stripTrad sp s
    L_UGLY s -> stripUgly sp s
    L_SLUG s -> LEAF sp SLUG (stripSlug s)
    L_BAD  s -> classifyBadLeaf sp s

-- | Classify a BAD leaf from the lexer by examining its content
classifyBadLeaf :: Span -> String -> Rex
classifyBadLeaf sp s = LEAF sp (BAD reason) s
  where
    reason
        | "\"" `isPrefixOf` s && not ("\"" `isSuffixOf` s) = UnclosedTrad
        | "''" `isPrefixOf` s && not ("''" `isSuffixOf` s) = UnclosedUgly
        | otherwise = InvalidChar

    isPrefixOf [] _          = True
    isPrefixOf _  []         = False
    isPrefixOf (x:xs) (y:ys) = x == y && isPrefixOf xs ys

    isSuffixOf xs ys = isPrefixOf (reverse xs) (reverse ys)

-- | Process a TRAD string: classify as TAPE (page-style) or CORD (span-style).
-- TAPE: starts with newline after opening quote, strip depth from closing quote indent
-- CORD: inline content, continuation lines must indent to content column
stripTrad :: Span -> String -> Rex
stripTrad sp s =
    let col = spanCol sp
    in case s of
        '"':afterOpen -> case afterOpen of
            '\n':rest -> stripTape sp s col rest
            _         -> stripCord sp s col afterOpen
        _ -> LEAF sp CORD s  -- no quotes, leave as is (shouldn't happen)
  where
    -- TAPE: strip depth comes from terminator line's indentation
    stripTape :: Span -> String -> Int -> String -> Rex
    stripTape sp' orig _openCol content =
        let contentLines = lines content
        in case reverse contentLines of
            [] -> LEAF sp' TAPE ""
            (lastLine:revRest) ->
                let (spaces, afterSpaces) = span (== ' ') lastLine
                    stripDepth = length spaces
                    bodyLines = reverse revRest
                in if afterSpaces == "\"" && all (validPageLine stripDepth) bodyLines
                   then let stripped = map (unescapeQuotes . stripLineForPage stripDepth) bodyLines
                        in LEAF sp' TAPE (unlines' stripped)
                   else LEAF sp' (BAD InvalidPage) orig

    -- Check if a line is valid for PAGE: blank lines are always valid,
    -- non-blank lines must have at least `depth` leading spaces
    validPageLine :: Int -> String -> Bool
    validPageLine depth line
        | all (== ' ') line = True
        | otherwise         = all (== ' ') (take depth line) && length line >= depth

    -- CORD: strip depth is content column (after opening quote)
    -- Continuation lines must be indented at least to the content column
    stripCord :: Span -> String -> Int -> String -> Rex
    stripCord sp' orig openCol content =
        let body = removeClosingQuote content
            contentCol = openCol  -- column where content starts (right after ")
        in case lines body of
            []     -> LEAF sp' CORD ""
            [single] -> LEAF sp' CORD (unescapeQuotes single)
            (_:rest) ->
                if all (validSpanLine contentCol) rest
                then LEAF sp' CORD (stripContinuations contentCol body)
                else LEAF sp' (BAD InvalidSpan) orig

    -- Check if a continuation line is valid for SPAN
    validSpanLine :: Int -> String -> Bool
    validSpanLine depth line =
        length (takeWhile (== ' ') line) >= depth

    removeClosingQuote str =
        case reverse str of
            '"':inner -> reverse inner
            _         -> str  -- unclosed, return as-is

    -- Strip a line for PAGE: blank lines pass through, others get stripped
    stripLineForPage :: Int -> String -> String
    stripLineForPage depth line
        | all (== ' ') line = ""
        | otherwise         = stripN depth line

    unlines' [] = ""
    unlines' xs = init (unlines xs)

-- | Process an UGLY string: classify as PAGE or SPAN, then strip accordingly.
-- PAGE: starts with newline after ticks, strip depth determined by terminator indent
-- SPAN: inline content, strip continuation lines based on content column
stripUgly :: Span -> String -> Rex
stripUgly sp s =
    let col = spanCol sp
        (ticks, afterOpen) = span (== '\'') s
        n = length ticks
    in if n >= 2
       then case afterOpen of
                '\n':rest -> stripPage n rest
                _         -> stripSpan col n afterOpen
       else LEAF sp SPAN s  -- shouldn't happen, but fallback
  where
    -- PAGE: strip depth comes from terminator line's indentation
    stripPage :: Int -> String -> Rex
    stripPage n content =
        let contentLines = lines content
        in case reverse contentLines of
            [] -> LEAF sp PAGE ""
            (lastLine:revRest) ->
                let closeTicks = replicate n '\''
                    (spaces, afterSpaces) = span (== ' ') lastLine
                    stripDepth = length spaces
                    bodyLines = reverse revRest
                in if afterSpaces == closeTicks && all (validPageLine stripDepth) bodyLines
                   then let stripped = map (stripLineForPage stripDepth) bodyLines
                        in LEAF sp PAGE (unlines' stripped)
                   else LEAF sp (BAD InvalidPage) s

    -- Check if a line is valid for PAGE: blank lines are always valid,
    -- non-blank lines must have at least `depth` leading spaces
    validPageLine :: Int -> String -> Bool
    validPageLine depth line
        | all (== ' ') line = True  -- blank lines are always valid
        | otherwise         = all (== ' ') (take depth line) && length line >= depth

    -- SPAN: strip depth is content column (after ticks)
    -- Continuation lines must be indented at least to the content column
    stripSpan :: Int -> Int -> String -> Rex
    stripSpan openCol n content =
        let closeTicks = replicate n '\''
            body = removeClosing closeTicks content
            contentCol = openCol + n - 1  -- column where content starts
        in case lines body of
            []     -> LEAF sp SPAN ""
            [single] -> LEAF sp SPAN (unescapeQuotes single)
            (first:rest) ->
                if all (validSpanLine contentCol) rest
                then LEAF sp SPAN (stripContinuations contentCol body)
                else LEAF sp (BAD InvalidSpan) s

    -- Check if a continuation line is valid for SPAN:
    -- Must have at least `depth` leading spaces (or be the closing ticks)
    validSpanLine :: Int -> String -> Bool
    validSpanLine depth line =
        length (takeWhile (== ' ') line) >= depth

    removeClosing ticks str =
        let revTicks = reverse ticks
            revStr = reverse str
        in if take (length ticks) revStr == revTicks
           then reverse (drop (length ticks) revStr)
           else str

    -- Strip a line for PAGE: blank lines pass through, others get stripped
    stripLineForPage :: Int -> String -> String
    stripLineForPage depth line
        | all (== ' ') line = ""  -- blank line -> empty
        | otherwise         = stripN depth line

    unlines' [] = ""
    unlines' xs = init (unlines xs)

-- | Strip a SLUG string: remove "' " prefix from each line.
stripSlug :: String -> String
stripSlug = unlines' . map stripSlugLine . lines
  where
    stripSlugLine s = case s of
        '\'':' ':rest -> rest
        '\'':"" -> ""  -- empty slug line
        '\'':rest -> rest  -- slug line with no space after '
        _ -> s  -- shouldn't happen, but leave as is

    unlines' [] = ""
    unlines' xs = init (unlines xs)

-- | Strip leading whitespace from continuation lines.
-- The first line is left as-is, subsequent lines have `col` spaces stripped.
stripContinuations :: Int -> String -> String
stripContinuations col s =
    case lines s of
        [] -> ""
        [single] -> unescapeQuotes single
        (first:rest) -> unlines' (unescapeQuotes first : map (unescapeQuotes . stripN col) rest)
  where
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


-- Quip Conversion -------------------------------------------------------------
--
-- A quip (S_QUIP) is converted by extracting its underlying source
-- text (using treeOff/treeLen relative to the block's source slice)
-- and producing a LEAF QUIP.
--
-- For multi-line quips, we normalize indentation by stripping the minimum
-- indent from all non-empty continuation lines. This allows "jagged" input:
--
--   foo = 'html{
--     <body>
--   }
--
-- to be equivalent to the canonical form:
--
--   foo = 'html{
--         <body>
--         }
--
-- Blank lines are ignored when computing minimum indent.

quipToRex :: String -> Int -> Tree -> Rex
quipToRex src blockOff tree@(Tree S_QUIP sp _) =
    let qoff = Tr.treeOff tree
        qlen = Tr.treeLen tree
        s = take qlen (drop (qoff - blockOff) src)
        s' = normalizeQuipIndent s
    in LEAF sp QUIP s'
quipToRex _ _ t = error $ "quipToRex: not a quip: " ++ show (treeShape t)

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


-- Top-Level Conversion --------------------------------------------------------
--
-- All conversion functions thread (src, blockOff) for quip extraction.
-- src is the source slice for this block; blockOff is the absolute
-- offset where it starts in the original source.

convertWith :: String -> Int -> Tree -> Rex
convertWith src blockOff tree@(Tree shape sp nodes) = case shape of
    S_NEST bk -> convertNest src blockOff sp bk nodes
    S_CLUMP   -> convertClump src blockOff sp nodes
    S_POEM    -> convertPoem src blockOff sp (treePos tree) nodes
    S_ITEM    -> convertSpaced src blockOff sp CLEAR nodes
    S_QUIP    -> quipToRex src blockOff tree
    S_BLOCK   -> error "S_BLOCK: should be consumed by enclosing context"


-- Spaced Node Lists -----------------------------------------------------------

convertSpaced :: String -> Int -> Span -> Color -> [Node] -> Rex
convertSpaced src blockOff sp color nodes = case extractBlock nodes of
    Just (headNodes, rune, blockChildren) ->
        let hd    = spacedHead src blockOff headNodes
            items = map (convertWith src blockOff) blockChildren
        in BLOC sp color rune hd items
    Nothing ->
        spacedGroup src blockOff sp color nodes

spacedHead :: String -> Int -> [Node] -> Rex
spacedHead _   _        []  = EXPR noSpan CLEAR []
spacedHead src blockOff [n] = convertNode src blockOff n
spacedHead src blockOff ns  = spacedGroup src blockOff noSpan CLEAR ns

spacedGroup :: String -> Int -> Span -> Color -> [Node] -> Rex
spacedGroup src blockOff sp color nodes =
    let elems = mergeBlocks src blockOff (map (nodeToElem src blockOff) nodes)
        runes = nubBy (==) $ sortBy runeCmp [r | E_RUNE r <- elems]
    in case runes of
         [] -> case [r | E_REX r <- elems] of
                 []  -> EXPR sp color []
                 [r] -> applyColor sp color r
                 rs  -> EXPR sp color rs
         _  -> let rex = infixRecur sp runes elems
               in applyColor sp color rex

-- | Merge E_BLOCK elements with their preceding rune and head.
-- Pattern: [E_REX head, E_RUNE rune, E_BLOCK items] -> [E_REX (BLOC CLEAR rune head items)]
mergeBlocks :: String -> Int -> [Elem] -> [Elem]
mergeBlocks src blockOff = go []
  where
    go acc [] = reverse acc
    go acc (E_REX hd : E_RUNE r : E_BLOCK _ items : rest) =
        let bloc = BLOC noSpan CLEAR r hd (map (convertWith src blockOff) items)
        in go (E_REX bloc : acc) rest
    go acc (E_RUNE r : E_BLOCK _ items : rest) =
        -- Block with no head - just use empty EXPR as head
        let bloc = BLOC noSpan CLEAR r (EXPR noSpan CLEAR []) (map (convertWith src blockOff) items)
        in go (E_REX bloc : acc) rest
    go acc (e : rest) = go (e : acc) rest

applyColor :: Span -> Color -> Rex -> Rex
applyColor _  CLEAR rex = rex
applyColor sp color rex = case rex of
    NEST _ CLEAR r kids     -> NEST sp color r kids
    EXPR _ CLEAR kids       -> EXPR sp color kids
    BLOC _ CLEAR r hd items -> BLOC sp color r hd items
    _                       -> EXPR sp color [rex]


-- Block Extraction ------------------------------------------------------------

extractBlock :: [Node] -> Maybe ([Node], String, [Tree])
extractBlock nodes =
    case reverse nodes of
      (N_CHILD (Tree S_BLOCK _ blockNodes) : N_RUNE _ rune : revHead) ->
          let items = [t | N_CHILD t <- blockNodes]
          in Just (reverse revHead, rune, items)
      _ -> Nothing


-- Nest Conversion -------------------------------------------------------------

convertNest :: String -> Int -> Span -> Bracket -> [Node] -> Rex
convertNest src blockOff sp bk nodes =
    let color = toColor bk
    in case nodes of
         []  -> EXPR sp color []
         [n] -> applyColor sp color (convertNode src blockOff n)
         _   -> convertSpaced src blockOff sp color nodes

toColor :: Bracket -> Color
toColor Paren = PAREN
toColor Brack = BRACK
toColor Curly = CURLY
toColor Clear = CLEAR


-- Clump Conversion ------------------------------------------------------------

convertClump :: String -> Int -> Span -> [Node] -> Rex
convertClump _   _        _  []    = error "empty clump"
convertClump src blockOff sp nodes = top (nodeToElem src blockOff <$> nodes)
  where
    top :: [Elem] -> Rex
    top [E_REX r] = r
    top (E_RUNE r : rest) = PREF sp r (top rest)
    top es = case juxt [] es of [E_REX r] -> r
                                collapsed -> tight collapsed

    tight :: [Elem] -> Rex
    tight elems =
        case nubBy (==) $ sortBy runeCmp [r | E_RUNE r <- elems] of
             [] -> case [r | E_REX r <- elems] of
                     [r] -> r
                     rs  -> EXPR sp CLEAR rs
             rs -> go rs elems

    go :: [String] -> [Elem] -> Rex
    go _      [E_REX r] = r
    go []     elems     = case [r | E_REX r <- elems] of
                              [r] -> r
                              rs  -> EXPR sp CLEAR rs
    go (r:rs) elems     = case go rs <$> splitOnRune r elems of
                              [k]  -> k
                              kids -> TYTE sp r kids

    juxt :: [Rex] -> [Elem] -> [Elem]
    juxt acc []                    = flush acc []
    juxt acc (e@(E_RUNE _) : rest) = flush acc (e : juxt [] rest)
    juxt acc (E_REX r : rest)      = juxt (acc ++ [r]) rest
    juxt acc (E_BLOCK _ _ : rest)  = juxt acc rest  -- shouldn't happen; mergeBlocks handles these

    flush :: [Rex] -> [Elem] -> [Elem]
    flush []  rest = rest
    flush [r] rest = E_REX r : rest
    flush rs  rest = E_REX (JUXT sp rs) : rest


-- Poem Conversion -------------------------------------------------------------

convertPoem :: String -> Int -> Span -> Int -> [Node] -> Rex
convertPoem _   _        _  _   [] = error "empty poem"
convertPoem src blockOff sp pos (N_RUNE _ r : rest) =
    let (children, heirNodes) = splitHeir pos rest
        open = OPEN sp r (map (convertNode src blockOff) children)
    in case heirNodes of
         [] -> open
         _  -> mkHeir sp (open : concatMap (flattenHeir . convertNode src blockOff) heirNodes)
-- Poem starting with SLUG: flatten everything into a HEIR
convertPoem src blockOff sp pos (N_LEAF leafSp lf : rest) =
    let slug = leafToRex leafSp lf
        -- Flatten all children and heir nodes together
        allNodes = rest
        flattened = concatMap (flattenHeir . convertNode src blockOff) allNodes
    in mkHeir sp (slug : flattened)
convertPoem _ _ _ _ _ = error "poem must start with a rune or leaf"

splitHeir :: Int -> [Node] -> ([Node], [Node])
splitHeir pos = go []
  where
    go acc [] = (reverse acc, [])
    go acc rest@(n:_)
      | Tr.nodeCol n <= pos = (reverse acc, rest)
      | otherwise           = go (n : acc) (tail rest)

mkHeir :: Span -> [Rex] -> Rex
mkHeir _  [r] = r
mkHeir sp rs  = HEIR sp rs

flattenHeir :: Rex -> [Rex]
flattenHeir (HEIR _ rs) = rs
flattenHeir r           = [r]


-- Node Conversion -------------------------------------------------------------

convertNode :: String -> Int -> Node -> Rex
convertNode _   _        (N_LEAF sp lf) = leafToRex sp lf
convertNode src blockOff (N_CHILD tree) = convertWith src blockOff tree
convertNode _   _        (N_RUNE _ r)   = error $ "convertNode: bare rune: " ++ r


-- Intermediate Elements -------------------------------------------------------

data Elem = E_RUNE String | E_REX Rex | E_BLOCK String [Tree]

nodeToElem :: String -> Int -> Node -> Elem
nodeToElem _   _        (N_RUNE _ r)   = E_RUNE r
nodeToElem _   _        (N_LEAF sp lf) = E_REX (leafToRex sp lf)
nodeToElem src blockOff (N_CHILD tree) = case tree of
    Tree S_BLOCK _ blockNodes ->
        -- Extract the rune that precedes this block by looking at context
        -- For now, we'll handle this in the grouping phase
        E_BLOCK "" [t | N_CHILD t <- blockNodes]
    _ -> E_REX (convertWith src blockOff tree)


-- Infix Precedence Grouping ---------------------------------------------------

infixRecur :: Span -> [String] -> [Elem] -> Rex

infixRecur _ _ [E_REX r] = r

infixRecur sp [] elems =
    case [r | E_REX r <- elems] of
        [r] -> r
        rs  -> EXPR sp CLEAR rs

infixRecur sp (rune:runes) elems =
    case splitOnRune rune elems of
        [g] -> infixRecur sp runes g
        gs  -> NEST sp CLEAR rune $ infixRecur sp runes <$> filter (not . null) gs


splitOnRune :: String -> [Elem] -> [[Elem]]
splitOnRune rune = go []
  where
    go acc [] = [reverse acc]
    go acc (E_RUNE r : rest) | r == rune = reverse acc : go [] rest
    go acc (e : rest) = go (e:acc) rest


-- Public API ------------------------------------------------------------------

rexFromTree :: Tree -> Rex
rexFromTree = convertWith "" 0

rexFromBlockTree :: String -> Tree -> Maybe Rex
rexFromBlockTree src tree = case tree of
    Tree (S_NEST Clear) _ [] -> Nothing
    Tree (S_NEST Clear) sp ns -> Just $ convertSpaced src (Tr.treeOff tree) sp CLEAR ns
    _ -> error "top level tree is always Clear"


-- Pretty Printer --------------------------------------------------------------

ppRex :: Rex -> String
ppRex = go 0
  where
    ind n = replicate n ' '
    ppSpan (Span l c o n) = show l ++ ":" ++ show c ++ " [" ++ show o ++ "+" ++ show n ++ "]"

    go i = \case
        LEAF sp sh s ->
            ind i ++ show sh ++ " " ++ ppSpan sp ++ " " ++ show s ++ "\n"

        NEST sp c r kids ->
            ind i ++ "NEST " ++ show c ++ " " ++ show r ++ " " ++ ppSpan sp ++ "\n"
            ++ concatMap (go (i+2)) kids

        EXPR sp c kids ->
            ind i ++ "EXPR " ++ show c ++ " " ++ ppSpan sp ++ "\n"
            ++ concatMap (go (i+2)) kids

        PREF sp r child ->
            ind i ++ "PREF " ++ show r ++ " " ++ ppSpan sp ++ "\n"
            ++ go (i+2) child

        TYTE sp r kids ->
            ind i ++ "TYTE " ++ show r ++ " " ++ ppSpan sp ++ "\n"
            ++ concatMap (go (i+2)) kids

        JUXT sp kids ->
            ind i ++ "JUXT " ++ ppSpan sp ++ "\n"
            ++ concatMap (go (i+2)) kids

        HEIR sp kids ->
            ind i ++ "HEIR " ++ ppSpan sp ++ "\n"
            ++ concatMap (go (i+2)) kids

        BLOC sp c r hd items ->
            ind i ++ "BLOC " ++ show c ++ " " ++ show r ++ " " ++ ppSpan sp ++ "\n"
            ++ go (i+2) hd
            ++ concatMap (go (i+2)) items

        OPEN sp r kids ->
            ind i ++ "OPEN " ++ show r ++ " " ++ ppSpan sp ++ "\n"
            ++ concatMap (go (i+2)) kids


-- Error Collection -------------------------------------------------------------

-- | Collect all errors from a Rex tree
collectRexErrors :: Rex -> [RexError]
collectRexErrors = go
  where
    go = \case
        LEAF sp (BAD reason) s -> [RexError sp reason s]
        LEAF _ _ _             -> []
        NEST _ _ _ kids        -> concatMap go kids
        EXPR _ _ kids          -> concatMap go kids
        PREF _ _ child         -> go child
        TYTE _ _ kids          -> concatMap go kids
        JUXT _ kids            -> concatMap go kids
        HEIR _ kids            -> concatMap go kids
        BLOC _ _ _ hd items    -> go hd ++ concatMap go items
        OPEN _ _ kids          -> concatMap go kids


--- Main -----------------------------------------------------------------------

rexMain :: IO ()
rexMain = do
  src <- getContents
  let results = Tr.parseRex src
  mapM_ (\(slice, tree) ->
    case rexFromBlockTree slice tree of
      Nothing -> pure ()
      Just r  -> putStrLn (ppRex r)
    ) results

checkMain :: IO ()
checkMain = do
    src <- getContents
    let results = Tr.parseRex src
        allErrors = concatMap (\(slice, tree) ->
            case rexFromBlockTree slice tree of
                Nothing -> []
                Just r  -> collectRexErrors r
            ) results
    if null allErrors
       then putStrLn "No errors found."
       else mapM_ (putStrLn . formatError (Just src)) allErrors
  where
    formatError mSrc (RexError sp reason txt) =
        let loc = show (spanLin sp) ++ ":" ++ show (spanCol sp)
            msg = reasonMessage reason
            preview = case mSrc of
                Nothing  -> show txt
                Just s -> showContext s sp
        in loc ++ ": error: " ++ msg ++ "\n" ++ preview

    reasonMessage InvalidChar       = "invalid character"
    reasonMessage UnclosedTrad      = "unclosed string literal"
    reasonMessage UnclosedUgly      = "unclosed multi-line string"
    reasonMessage MismatchedBracket = "mismatched bracket"
    reasonMessage InvalidPage       = "invalid page string indentation"
    reasonMessage InvalidSpan       = "invalid span string indentation"

    showContext src sp =
        let srcLines = lines src
            lineNum = spanLin sp
            colNum = spanCol sp
        in if lineNum > 0 && lineNum <= length srcLines
           then let line = srcLines !! (lineNum - 1)
                    pointer = replicate (colNum - 1) ' ' ++ "^"
                in "  " ++ line ++ "\n  " ++ pointer
           else ""
