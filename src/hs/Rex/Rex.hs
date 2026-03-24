{-# LANGUAGE LambdaCase #-}
{-# OPTIONS_GHC -Wno-x-partial #-}

module Rex.Rex
    ( Rex(..), LeafShape(..), Color(..), ppRex
    , rexFromTree, rexFromBlockTree
    , rexMain
    )
where

import qualified Rex.Tree2 as Tr

import Rex.Lex    (Span (..))
import Rex.Tree2  (Bracket (..), Leaf (..), Node (..), Shape (..), Tree (..), treePos)
import Data.List  (nubBy, sortBy)


-- Rex Data Model --------------------------------------------------------------

data LeafShape = WORD | QUIP | TRAD | PAGE | SPAN | SLUG | BAD
  deriving (Eq, Show)

data Color = PAREN | BRACK | CURLY | CLEAR
  deriving (Eq, Show)

data Rex
    = LEAF LeafShape String
    | NEST Color String [Rex]           -- (x + y), {a | b}
    | EXPR Color [Rex]                  -- [f x], (x), ()
    | PREF String Rex                   -- :x, -y
    | TYTE String [Rex]                 -- x.y, a:b
    | BLOC Color String Rex [Rex]       -- head rune:\n  a\n  b
    | OPEN String [Rex]                 -- + x y (layout prefix)
    | JUXT [Rex]                        -- f(x), f(x)[1]
    | HEIR [Rex]                        -- + x\n+ y\nz
  deriving (Eq, Show)


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

leafToRex :: Int -> Leaf -> Rex
leafToRex col = \case
    L_WORD s -> LEAF WORD s
    L_TRAD s -> LEAF TRAD (stripTrad col s)
    L_UGLY s -> stripUgly col s
    L_SLUG s -> LEAF SLUG (stripSlug s)
    L_BAD  s -> LEAF BAD s

-- | Strip a TRAD string: remove quotes, strip leading whitespace from
-- continuation lines based on opening quote column.
stripTrad :: Int -> String -> String
stripTrad col s =
    case s of
        '"':rest -> case reverse rest of
            '"':inner -> stripContinuations col (reverse inner)
            _         -> stripContinuations col rest  -- unclosed, just strip open quote
        _ -> s  -- no quotes, leave as is

-- | Process an UGLY string: classify as PAGE or SPAN, then strip accordingly.
-- PAGE: starts with newline after ticks, strip depth determined by terminator indent
-- SPAN: inline content, strip continuation lines based on content column
stripUgly :: Int -> String -> Rex
stripUgly col s =
    let (ticks, afterOpen) = span (== '\'') s
        n = length ticks
    in if n >= 2
       then case afterOpen of
                '\n':rest -> stripPage n rest
                _         -> LEAF SPAN (stripSpan col n afterOpen)
       else LEAF SPAN s  -- shouldn't happen, but fallback
  where
    -- PAGE: strip depth comes from terminator line's indentation
    stripPage :: Int -> String -> Rex
    stripPage n content =
        let contentLines = lines content
        in case reverse contentLines of
            [] -> LEAF PAGE ""
            (lastLine:revRest) ->
                let closeTicks = replicate n '\''
                    (spaces, afterSpaces) = span (== ' ') lastLine
                    stripDepth = length spaces
                    bodyLines = reverse revRest
                in if afterSpaces == closeTicks && all (validPageLine stripDepth) bodyLines
                   then let stripped = map (stripLineForPage stripDepth) bodyLines
                        in LEAF PAGE (unlines' stripped)
                   else LEAF BAD s

    -- Check if a line is valid for PAGE: blank lines are always valid,
    -- non-blank lines must have at least `depth` leading spaces
    validPageLine :: Int -> String -> Bool
    validPageLine depth line
        | all (== ' ') line = True  -- blank lines are always valid
        | otherwise         = all (== ' ') (take depth line) && length line >= depth

    -- SPAN: strip depth is content column (after ticks)
    stripSpan :: Int -> Int -> String -> String
    stripSpan openCol n content =
        let closeTicks = replicate n '\''
            body = removeClosing closeTicks content
            contentCol = openCol + n - 1  -- column where content starts
        in stripContinuations contentCol body

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

quipToRex :: String -> Int -> Tree -> Rex
quipToRex src blockOff tree@(Tree S_QUIP _ _) =
    let qoff = Tr.treeOff tree
        qlen = Tr.treeLen tree
        s = take qlen (drop (qoff - blockOff) src)
    in LEAF QUIP s
quipToRex _ _ t = error $ "quipToRex: not a quip: " ++ show (treeShape t)


-- Top-Level Conversion --------------------------------------------------------
--
-- All conversion functions thread (src, blockOff) for quip extraction.
-- src is the source slice for this block; blockOff is the absolute
-- offset where it starts in the original source.

convertWith :: String -> Int -> Tree -> Rex
convertWith src blockOff tree@(Tree shape _ nodes) = case shape of
    S_NEST bk -> convertNest src blockOff bk nodes
    S_CLUMP   -> convertClump src blockOff nodes
    S_POEM    -> convertPoem src blockOff (treePos tree) nodes
    S_ITEM    -> convertSpaced src blockOff CLEAR nodes
    S_QUIP    -> quipToRex src blockOff tree
    S_BLOCK   -> error "S_BLOCK: should be consumed by enclosing context"


-- Spaced Node Lists -----------------------------------------------------------

convertSpaced :: String -> Int -> Color -> [Node] -> Rex
convertSpaced src blockOff color nodes = case extractBlock nodes of
    Just (headNodes, rune, blockChildren) ->
        let hd    = spacedHead src blockOff headNodes
            items = map (convertWith src blockOff) blockChildren
        in BLOC color rune hd items
    Nothing ->
        spacedGroup src blockOff color nodes

spacedHead :: String -> Int -> [Node] -> Rex
spacedHead _   _        []  = EXPR CLEAR []
spacedHead src blockOff [n] = convertNode src blockOff n
spacedHead src blockOff ns  = spacedGroup src blockOff CLEAR ns

spacedGroup :: String -> Int -> Color -> [Node] -> Rex
spacedGroup src blockOff color nodes =
    let elems = mergeBlocks src blockOff (map (nodeToElem src blockOff) nodes)
        runes = nubBy (==) $ sortBy runeCmp [r | E_RUNE r <- elems]
    in case runes of
         [] -> case [r | E_REX r <- elems] of
                 []  -> EXPR color []
                 [r] -> applyColor color r
                 rs  -> EXPR color rs
         _  -> let rex = infixRecur runes elems
               in applyColor color rex

-- | Merge E_BLOCK elements with their preceding rune and head.
-- Pattern: [E_REX head, E_RUNE rune, E_BLOCK items] -> [E_REX (BLOC CLEAR rune head items)]
mergeBlocks :: String -> Int -> [Elem] -> [Elem]
mergeBlocks src blockOff = go []
  where
    go acc [] = reverse acc
    go acc (E_REX hd : E_RUNE r : E_BLOCK _ items : rest) =
        let bloc = BLOC CLEAR r hd (map (convertWith src blockOff) items)
        in go (E_REX bloc : acc) rest
    go acc (E_RUNE r : E_BLOCK _ items : rest) =
        -- Block with no head - just use empty EXPR as head
        let bloc = BLOC CLEAR r (EXPR CLEAR []) (map (convertWith src blockOff) items)
        in go (E_REX bloc : acc) rest
    go acc (e : rest) = go (e : acc) rest

applyColor :: Color -> Rex -> Rex
applyColor CLEAR rex = rex
applyColor color rex = case rex of
    NEST CLEAR r kids     -> NEST color r kids
    EXPR CLEAR kids       -> EXPR color kids
    BLOC CLEAR r hd items -> BLOC color r hd items
    _                     -> EXPR color [rex]


-- Block Extraction ------------------------------------------------------------

extractBlock :: [Node] -> Maybe ([Node], String, [Tree])
extractBlock nodes =
    case reverse nodes of
      (N_CHILD (Tree S_BLOCK _ blockNodes) : N_RUNE _ rune : revHead) ->
          let items = [t | N_CHILD t <- blockNodes]
          in Just (reverse revHead, rune, items)
      _ -> Nothing


-- Nest Conversion -------------------------------------------------------------

convertNest :: String -> Int -> Bracket -> [Node] -> Rex
convertNest src blockOff bk nodes =
    let color = toColor bk
    in case nodes of
         []  -> EXPR color []
         [n] -> applyColor color (convertNode src blockOff n)
         _   -> convertSpaced src blockOff color nodes

toColor :: Bracket -> Color
toColor Paren = PAREN
toColor Brack = BRACK
toColor Curly = CURLY
toColor Clear = CLEAR


-- Clump Conversion ------------------------------------------------------------

convertClump :: String -> Int -> [Node] -> Rex
convertClump _   _        []    = error "empty clump"
convertClump src blockOff nodes = top (nodeToElem src blockOff <$> nodes)
  where
    top :: [Elem] -> Rex
    top [E_REX r] = r
    top (E_RUNE r : rest) = PREF r (top rest)
    top es = case juxt [] es of [E_REX r] -> r
                                collapsed -> tight collapsed

    tight :: [Elem] -> Rex
    tight elems =
        case nubBy (==) $ sortBy runeCmp [r | E_RUNE r <- elems] of
             [] -> case [r | E_REX r <- elems] of
                     [r] -> r
                     rs  -> EXPR CLEAR rs
             rs -> go rs elems

    go :: [String] -> [Elem] -> Rex
    go _      [E_REX r] = r
    go []     elems     = case [r | E_REX r <- elems] of
                              [r] -> r
                              rs  -> EXPR CLEAR rs
    go (r:rs) elems     = case go rs <$> splitOnRune r elems of
                              [k]  -> k
                              kids -> TYTE r kids

    juxt :: [Rex] -> [Elem] -> [Elem]
    juxt acc []                    = flush acc []
    juxt acc (e@(E_RUNE _) : rest) = flush acc (e : juxt [] rest)
    juxt acc (E_REX r : rest)      = juxt (acc ++ [r]) rest
    juxt acc (E_BLOCK _ _ : rest)  = juxt acc rest  -- shouldn't happen; mergeBlocks handles these

    flush :: [Rex] -> [Elem] -> [Elem]
    flush []  rest = rest
    flush [r] rest = E_REX r : rest
    flush rs  rest = E_REX (JUXT rs) : rest


-- Poem Conversion -------------------------------------------------------------

convertPoem :: String -> Int -> Int -> [Node] -> Rex
convertPoem _   _        _   [] = error "empty poem"
convertPoem src blockOff pos (N_RUNE _ r : rest) =
    let (children, heirNodes) = splitHeir pos rest
        open = OPEN r (map (convertNode src blockOff) children)
    in case heirNodes of
         [] -> open
         _  -> mkHeir (open : concatMap (flattenHeir . convertNode src blockOff) heirNodes)
convertPoem _ _ _ _ = error "poem must start with a rune"

splitHeir :: Int -> [Node] -> ([Node], [Node])
splitHeir pos = go []
  where
    go acc [] = (reverse acc, [])
    go acc rest@(n:_)
      | Tr.nodeCol n <= pos = (reverse acc, rest)
      | otherwise           = go (n : acc) (tail rest)

mkHeir :: [Rex] -> Rex
mkHeir [r] = r
mkHeir rs  = HEIR rs

flattenHeir :: Rex -> [Rex]
flattenHeir (HEIR rs) = rs
flattenHeir r         = [r]


-- Node Conversion -------------------------------------------------------------

convertNode :: String -> Int -> Node -> Rex
convertNode _   _        (N_LEAF sp lf) = leafToRex (spanCol sp) lf
convertNode src blockOff (N_CHILD tree) = convertWith src blockOff tree
convertNode _   _        (N_RUNE _ r)   = error $ "convertNode: bare rune: " ++ r


-- Intermediate Elements -------------------------------------------------------

data Elem = E_RUNE String | E_REX Rex | E_BLOCK String [Tree]

nodeToElem :: String -> Int -> Node -> Elem
nodeToElem _   _        (N_RUNE _ r)   = E_RUNE r
nodeToElem _   _        (N_LEAF sp lf) = E_REX (leafToRex (spanCol sp) lf)
nodeToElem src blockOff (N_CHILD tree) = case tree of
    Tree S_BLOCK _ blockNodes ->
        -- Extract the rune that precedes this block by looking at context
        -- For now, we'll handle this in the grouping phase
        E_BLOCK "" [t | N_CHILD t <- blockNodes]
    _ -> E_REX (convertWith src blockOff tree)


-- Infix Precedence Grouping ---------------------------------------------------

infixRecur :: [String] -> [Elem] -> Rex

infixRecur _ [E_REX r] = r

infixRecur [] elems =
    case [r | E_REX r <- elems] of
        [r] -> r
        rs  -> EXPR CLEAR rs

infixRecur (rune:runes) elems =
    case splitOnRune rune elems of
        [g] -> infixRecur runes g
        gs  -> NEST CLEAR rune $ infixRecur runes <$> filter (not . null) gs


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
    Tree (S_NEST Clear) _ ns -> Just $ convertSpaced src (Tr.treeOff tree) CLEAR ns
    _ -> error "top level tree is always Clear"


-- Pretty Printer --------------------------------------------------------------

ppRex :: Rex -> String
ppRex = go 0
  where
    ind n = replicate n ' '

    go i = \case
        LEAF sh s ->
            ind i ++ show sh ++ " " ++ show s ++ "\n"

        NEST c r kids ->
            ind i ++ "NEST " ++ show c ++ " " ++ show r ++ "\n"
            ++ concatMap (go (i+2)) kids

        EXPR c kids ->
            ind i ++ "EXPR " ++ show c ++ "\n"
            ++ concatMap (go (i+2)) kids

        PREF r child ->
            ind i ++ "PREF " ++ show r ++ "\n"
            ++ go (i+2) child

        TYTE r kids ->
            ind i ++ "TYTE " ++ show r ++ "\n"
            ++ concatMap (go (i+2)) kids

        JUXT kids ->
            ind i ++ "JUXT\n"
            ++ concatMap (go (i+2)) kids

        HEIR kids ->
            ind i ++ "HEIR\n"
            ++ concatMap (go (i+2)) kids

        BLOC c r hd items ->
            ind i ++ "BLOC " ++ show c ++ " " ++ show r ++ "\n"
            ++ go (i+2) hd
            ++ concatMap (go (i+2)) items

        OPEN r kids ->
            ind i ++ "OPEN " ++ show r ++ "\n"
            ++ concatMap (go (i+2)) kids


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
